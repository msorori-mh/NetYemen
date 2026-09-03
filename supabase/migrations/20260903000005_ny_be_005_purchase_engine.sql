-- NY-BE-005: Atomic Card Purchase RPC Execution Engine (Wave 4 core engine gate)
-- Contracts: NETYEMEN-FINANCIAL-OPERATING-CONTRACT-01 §3 (10-step pipeline),
--            NETYEMEN-BUSINESS-RULES-CATALOG-01 (BR-PURCHASE-*, BR-CARD-005/009),
--            NETYEMEN-THREAT-AND-FRAUD-MODEL-01 (THR-04, THR-05, THR-08)
-- Scope: purchases table + purchase_card() RPC + reveal_purchased_card() RPC.

create table purchases (
  id               uuid        primary key default gen_random_uuid(),
  user_id          uuid        not null references users (id) on delete restrict,
  card_id          uuid        not null unique references cards (id) on delete restrict,
  network_id       uuid        not null references networks (id) on delete restrict,
  network_price_id uuid        not null references network_prices (id) on delete restrict,
  price_paid       integer     not null,
  idempotency_key  uuid        not null unique,
  ledger_entry_id  uuid        not null references wallet_ledger_entries (id),
  created_at       timestamptz not null default now(),

  constraint purchases_price_paid_positive check (price_paid > 0)
);

comment on table purchases is 'BR-PURCHASE-001 step 7. card_id is UNIQUE — a card can be sold exactly once, an independent second guard against double-selling on top of cards_enforce_lifecycle and the FOR UPDATE SKIP LOCKED card selection in purchase_card() below. price_paid snapshots network_prices.selling_price at the moment of sale so a later price change never rewrites purchase history.';

create index purchases_network_idx on purchases (network_id, created_at);

alter table purchases enable row level security;

create policy purchases_select_own
  on purchases for select
  to authenticated
  using (user_id = auth.uid());

-- Not in the authorization matrix as its own row, but NY-OWNER-001's sales
-- dashboard has no other data path without it — same judgment call as
-- extending NY-BE-003's owner/operator SELECT policies to cards/card_batches.
create policy purchases_select_owner
  on purchases for select
  to authenticated
  using (exists (
    select 1 from networks n where n.id = purchases.network_id and n.owner_id = auth.uid()
  ));

create policy purchases_select_staff
  on purchases for select
  to authenticated
  using (current_user_role() in ('finance_officer', 'platform_admin', 'system_auditor'));

-- No INSERT/UPDATE/DELETE policy: written exclusively by purchase_card() below.

-- ---------------------------------------------------------------------------
-- purchase_card: the 10-step pipeline from the financial operating contract.
-- ---------------------------------------------------------------------------
-- BR-PURCHASE-004: there is no p_user_id parameter at all — not "accept it and
-- ignore it," simply nothing for a client to spoof. Buyer identity is auth.uid()
-- and nothing else, which is why THR-05's residual risk is rated Zero rather
-- than Low.
-- BR-PURCHASE-003: no price parameter either — selling_price is read from
-- network_prices inside the function, so THR-04 (client price tampering) has
-- no surface to exploit.
-- BR-PURCHASE-005 (post-commit notification) is intentionally out of scope
-- here: it belongs to NY-BE-006's edge functions, triggered off this table's
-- inserts, not embedded in the RPC that must stay purely transactional.

create function purchase_card(
  p_network_id       uuid,
  p_network_price_id uuid,
  p_idempotency_key  uuid
)
returns table (
  purchase_id  uuid,
  card_number  text,
  price_paid   integer,
  purchased_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id         uuid := auth.uid();
  v_existing        record;
  v_price           integer;
  v_wallet_balance  integer;
  v_card_id         uuid;
  v_card_ciphertext bytea;
  v_ledger_id       uuid;
  v_purchase_id     uuid;
  v_created_at      timestamptz;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  -- BR-PURCHASE-002: idempotent replay. Scoped to this caller so one user's
  -- key can never return another user's purchase, and checked before any
  -- lock is taken so a pure replay costs nothing beyond this lookup.
  select p.id, p.price_paid, p.created_at, c.card_number_ciphertext
  into v_existing
  from purchases p
  join cards c on c.id = p.card_id
  where p.idempotency_key = p_idempotency_key and p.user_id = v_user_id;

  if found then
    return query
      select v_existing.id, decrypt_card_number(v_existing.card_number_ciphertext),
             v_existing.price_paid, v_existing.created_at;
    return;
  end if;

  -- Step 1: active user account.
  if not exists (select 1 from users where id = v_user_id and status = 'active') then
    raise exception 'Account is not active' using errcode = '42501';
  end if;

  -- Step 2: active network + its dynamic price tier.
  select np.selling_price into v_price
  from network_prices np
  join networks n on n.id = np.network_id
  where np.id = p_network_price_id
    and np.network_id = p_network_id
    and np.is_active
    and n.is_approved
    and n.is_active;

  if v_price is null then
    raise exception 'Network or price tier is not currently active' using errcode = '22023';
  end if;

  -- Step 3: balance pre-check. Locks the wallet row now so a concurrent
  -- purchase by the same user (e.g. two device tabs) serializes here rather
  -- than both passing this check against a stale balance. This is a
  -- fast-fail for a clean error message — wallet_ledger_apply_entry
  -- (fired by the step-5 insert below) re-locks the same already-locked row
  -- and re-enforces INVARIANT 2 regardless, so this check is not the only guard.
  select cached_balance into v_wallet_balance
  from wallet_accounts
  where user_id = v_user_id
  for update;

  if v_wallet_balance is null or v_wallet_balance < v_price then
    raise exception 'Insufficient wallet balance' using errcode = '23514';
  end if;

  -- Step 4 + BR-CARD-009: lock exactly one available card of this price
  -- tier. A concurrent purchaser's identical query skips this row (SKIP
  -- LOCKED) and, if it was the last one in stock, finds none — clean
  -- out-of-stock rejection below, no double debit (TEST-CONCURRENCY-001/002).
  select id, card_number_ciphertext into v_card_id, v_card_ciphertext
  from cards
  where network_id = p_network_id
    and network_price_id = p_network_price_id
    and status = 'available'
  order by created_at
  for update skip locked
  limit 1;

  if v_card_id is null then
    raise exception 'Card stock unavailable for this network and price tier' using errcode = 'P0003';
  end if;

  -- Step 5: DEBIT entry. wallet_ledger_apply_entry computes balance_after and
  -- updates wallet_accounts.cached_balance (step 8) as part of this insert.
  insert into wallet_ledger_entries (
    user_id, entry_type, amount, reference_type, reference_id,
    idempotency_key, actor_id, reason_code
  )
  values (
    v_user_id, 'DEBIT', v_price, 'PURCHASE', v_card_id,
    p_idempotency_key, v_user_id, 'card_purchase'
  )
  returning id into v_ledger_id;

  -- Step 6.
  update cards
  set status = 'sold', sold_to = v_user_id, sold_at = now()
  where id = v_card_id;

  -- Step 7.
  insert into purchases (
    user_id, card_id, network_id, network_price_id, price_paid,
    idempotency_key, ledger_entry_id
  )
  values (
    v_user_id, v_card_id, p_network_id, p_network_price_id, v_price,
    p_idempotency_key, v_ledger_id
  )
  returning id, created_at into v_purchase_id, v_created_at;

  -- Step 9 (COMMIT) is implicit: this function returning normally lets the
  -- calling transaction commit; any exception raised above rolls back
  -- everything this call has done, including the step-5/6/7 writes.
  -- Step 10.
  return query
    select v_purchase_id, decrypt_card_number(v_card_ciphertext), v_price, v_created_at;
end;
$$;

comment on function purchase_card(uuid, uuid, uuid) is 'Financial operating contract §3.1, 10-step pipeline. No p_user_id or p_price parameter exists on this function at all (BR-PURCHASE-003/004) — there is nothing for a client to spoof or tamper with, only what network and price tier to buy from.';

-- Same named-role caveat documented in the NY-BE-003 fix commit: Supabase
-- grants EXECUTE to anon/authenticated/service_role by name at creation,
-- REVOKE ... FROM PUBLIC alone would not touch that.
revoke execute on function purchase_card(uuid, uuid, uuid) from public, anon, authenticated, service_role;
grant execute on function purchase_card(uuid, uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- reveal_purchased_card: COND-6 re-reveal of an already-purchased card.
-- ---------------------------------------------------------------------------
-- purchase_card already returns the plaintext at the moment of sale (step
-- 10); this is for a customer returning to view a past purchase (e.g. the
-- Purchases screen) rather than a second, separate reveal mechanism.
-- COND-7 (SUPPORT_AGENT reveal, scoped to an actively assigned support
-- ticket) is deferred — there is no support ticket table yet (NY-BE-006
-- territory) to scope that check against.

create function reveal_purchased_card(p_purchase_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ciphertext bytea;
begin
  select c.card_number_ciphertext into v_ciphertext
  from purchases p
  join cards c on c.id = p.card_id
  where p.id = p_purchase_id and p.user_id = auth.uid();

  if v_ciphertext is null then
    raise exception 'Purchase not found' using errcode = 'P0002';
  end if;

  return decrypt_card_number(v_ciphertext);
end;
$$;

revoke execute on function reveal_purchased_card(uuid) from public, anon, authenticated, service_role;
grant execute on function reveal_purchased_card(uuid) to authenticated;
