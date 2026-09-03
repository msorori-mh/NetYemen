-- NY-BE-004: Immutable Append-Only Financial Ledger & Wallet Schema
-- Contracts: NETYEMEN-FINANCIAL-OPERATING-CONTRACT-01, NETYEMEN-BUSINESS-RULES-CATALOG-01 (BR-WALLET-*)
-- Scope: wallet_accounts, wallet_ledger_entries, wallet_deposit_requests.
--
-- Supersedes NY-BE-001's users.wallet_balance placeholder: the financial
-- contract's §1.1 explicitly models the cached balance as its own
-- `wallet_accounts` entity (independent account_status, e.g. a wallet frozen
-- for fraud review while the user's login/profile stays active), separate
-- from `wallet_ledger_entries` (the append-only movement log). Keeping a
-- second cached number on `users` alongside this would be a second source of
-- truth for the same fact — dropped instead of duplicated.

alter table users drop column wallet_balance;

-- ---------------------------------------------------------------------------
-- wallet_accounts
-- ---------------------------------------------------------------------------

create table wallet_accounts (
  user_id        uuid        primary key references users (id) on delete restrict,
  currency       text        not null default 'YER',
  cached_balance integer     not null default 0,
  account_status text        not null default 'active',
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  -- BR-WALLET-006: YER only in V1. A currencies table is not warranted for a
  -- single hard-coded value.
  constraint wallet_accounts_currency_yer check (currency = 'YER'),
  -- INVARIANT 2.
  constraint wallet_accounts_balance_non_negative check (cached_balance >= 0),
  constraint wallet_accounts_status_valid check (account_status in ('active', 'frozen', 'closed'))
);

comment on table wallet_accounts is 'cached_balance is written exclusively by the wallet_ledger_apply_entry trigger below, from wallet_ledger_entries. Never updated by application arithmetic (BR-WALLET-001/002).';

create trigger wallet_accounts_set_updated_at
  before update on wallet_accounts
  for each row execute function set_updated_at();

alter table wallet_accounts enable row level security;

create policy wallet_accounts_select_own
  on wallet_accounts for select
  to authenticated
  using (user_id = auth.uid());

create policy wallet_accounts_select_staff
  on wallet_accounts for select
  to authenticated
  using (current_user_role() in ('finance_officer', 'platform_admin', 'system_auditor'));

-- No INSERT/UPDATE/DELETE policy: rows are created by handle_new_auth_user()
-- (redefined below) and updated exclusively by the ledger trigger, both
-- SECURITY DEFINER / table-owner writes. No client ever touches this table
-- directly, matching BR-WALLET-001/002.

-- Every existing user gets a wallet_accounts row now that wallet_balance no
-- longer lives on `users` (there are none yet in a fresh install, but this
-- keeps the migration correct if it ever runs against a database that already
-- has users — e.g. a re-run against a seeded staging environment).
insert into wallet_accounts (user_id)
select id from users
on conflict (user_id) do nothing;

-- handle_new_auth_user (NY-BE-001) must now also provision the wallet row.
create or replace function handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users (id, phone, role, status)
  values (new.id, new.phone, 'customer', 'active')
  on conflict (id) do nothing;

  insert into public.wallet_accounts (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- wallet_ledger_entries
-- ---------------------------------------------------------------------------

create table wallet_ledger_entries (
  id              uuid        primary key default gen_random_uuid(),
  user_id         uuid        not null references users (id) on delete restrict,
  entry_type      text        not null,
  amount          integer     not null,
  balance_after   integer     not null,
  reference_type  text        not null,
  -- Polymorphic by design (deposit request, purchase, refund, settlement,
  -- or an ad-hoc admin adjustment with no source row at all) — a single real
  -- FK can't target five different tables, so this is deliberately unconstrained.
  reference_id    uuid,
  idempotency_key uuid        not null,
  actor_id        uuid        not null references users (id),
  reason_code     text        not null,
  created_at      timestamptz not null default now(),

  constraint wallet_ledger_entries_type_valid check (entry_type in ('CREDIT', 'DEBIT', 'REVERSAL')),
  -- "amount (Integer YER Amount > 0)" — direction lives in entry_type, never in the sign of amount.
  constraint wallet_ledger_entries_amount_positive check (amount > 0),
  constraint wallet_ledger_entries_balance_after_non_negative check (balance_after >= 0),
  constraint wallet_ledger_entries_reference_type_valid check (
    reference_type in ('DEPOSIT', 'PURCHASE', 'REFUND', 'SETTLEMENT', 'ADJUSTMENT')
  ),
  -- INVARIANT 3: one business event = one financial record.
  constraint wallet_ledger_entries_idempotency_key_unique unique (idempotency_key)
);

comment on table wallet_ledger_entries is 'Append-only (INVARIANT 6 — see the REVOKE below). balance_after and the wallet_accounts.cached_balance update both come from wallet_ledger_apply_entry, never from the caller, so the two can never disagree. REVERSAL direction: this V1 schema treats REVERSAL as always additive (undoing an erroneous/fraudulent DEBIT). Clawing back a wrongful CREDIT is done with a direct DEBIT entry instead, since the financial contract does not specify a bidirectional convention for REVERSAL and BR-WALLET-005 only requires that corrections be new compensating entries, not which direction they run. Flag for an explicit OPEN_DECISION if a wrongful-CREDIT clawback via REVERSAL is actually needed.';

create index wallet_ledger_entries_user_idx on wallet_ledger_entries (user_id, created_at);
create index wallet_ledger_entries_reference_idx on wallet_ledger_entries (reference_type, reference_id);

create function wallet_ledger_apply_entry()
returns trigger
language plpgsql
as $$
declare
  v_current_balance integer;
  v_delta integer;
begin
  -- Row-lock the wallet first so concurrent ledger inserts for the same user
  -- serialize on this row instead of racing on cached_balance — the wallet
  -- equivalent of BR-CARD-009's FOR UPDATE pattern on card stock.
  select cached_balance into v_current_balance
  from wallet_accounts
  where user_id = new.user_id
  for update;

  if v_current_balance is null then
    raise exception 'wallet_accounts row missing for user %', new.user_id using errcode = '23503';
  end if;

  v_delta := case new.entry_type
    when 'CREDIT' then new.amount
    when 'DEBIT' then -new.amount
    when 'REVERSAL' then new.amount
  end;

  new.balance_after := v_current_balance + v_delta;

  -- INVARIANT 2, raised here (rather than only relying on the CHECK
  -- constraint) so the error message names the user and the attempted
  -- transition instead of a bare constraint-violation code.
  if new.balance_after < 0 then
    raise exception 'Ledger entry would drive wallet balance negative for user % (% -> %)',
      new.user_id, v_current_balance, new.balance_after
      using errcode = '23514';
  end if;

  update wallet_accounts
  set cached_balance = new.balance_after
  where user_id = new.user_id;

  return new;
end;
$$;

create trigger wallet_ledger_apply_entry
  before insert on wallet_ledger_entries
  for each row execute function wallet_ledger_apply_entry();

-- INVARIANT 6: immutability. RLS default-deny already blocks anon/authenticated
-- (no UPDATE/DELETE policy exists, or ever will), but Supabase's platform
-- bootstrap grants ALL on every table to anon/authenticated/service_role by
-- name at creation time (see the NY-BE-003 fix commit) — RLS alone doesn't
-- revoke that grant, so the SQL-level privilege must be revoked explicitly
-- too. This is stronger than RLS: even a service_role caller, which bypasses
-- RLS entirely, cannot UPDATE or DELETE a ledger row after this.
revoke update, delete on wallet_ledger_entries from public, anon, authenticated, service_role;

alter table wallet_ledger_entries enable row level security;

create policy wallet_ledger_entries_select_own
  on wallet_ledger_entries for select
  to authenticated
  using (user_id = auth.uid());

create policy wallet_ledger_entries_select_staff
  on wallet_ledger_entries for select
  to authenticated
  using (current_user_role() in ('finance_officer', 'platform_admin', 'system_auditor'));

-- No INSERT policy: every ledger entry is written by a SECURITY DEFINER RPC
-- (deposit approval, purchase_card, refund, settlement — NY-BE-005 onward),
-- never a raw client INSERT, so BR-PURCHASE-002's idempotency_key and
-- BR-PURCHASE-003's server-enforced amount can never be bypassed by a client
-- supplying its own row.

-- ---------------------------------------------------------------------------
-- wallet_deposit_requests (BR-WALLET-003/004/008)
-- ---------------------------------------------------------------------------

create table wallet_deposit_requests (
  id                 uuid        primary key default gen_random_uuid(),
  user_id            uuid        not null references users (id) on delete restrict,
  amount             integer     not null,
  -- Free-text until NY-BE-007 introduces the bank_accounts directory
  -- (OD-FIN-03) — this migration's Database Impact is scoped to exactly the
  -- three tables listed in the backlog, not bank_accounts.
  deposit_channel    text        not null,
  receipt_image_path text        not null,
  status             text        not null default 'pending',
  reviewed_by        uuid        references users (id),
  rejection_reason   text,
  ledger_entry_id    uuid        references wallet_ledger_entries (id),
  created_at         timestamptz not null default now(),
  reviewed_at        timestamptz,

  constraint wallet_deposit_requests_amount_positive check (amount > 0),
  -- BR-WALLET-008 lifecycle.
  constraint wallet_deposit_requests_status_valid check (
    status in ('pending', 'under_review', 'approved', 'rejected')
  ),
  -- BR-WALLET-004: a rejection requires a reason code.
  constraint wallet_deposit_requests_rejection_reason check (
    (status = 'rejected') = (rejection_reason is not null)
  ),
  -- A request only ever links to the ledger entry it produced once approved.
  constraint wallet_deposit_requests_ledger_entry_on_approval check (
    (status = 'approved') = (ledger_entry_id is not null)
  ),
  constraint wallet_deposit_requests_reviewed_fields check (
    (status in ('approved', 'rejected')) = (reviewed_by is not null and reviewed_at is not null)
  )
);

comment on table wallet_deposit_requests is 'BR-WALLET-003: manual receipt verification queue. Approval is a FINANCE_OFFICER action that inserts a CREDIT wallet_ledger_entries row and records it here — enforced by approve_wallet_deposit() below, never by a direct client UPDATE.';

create index wallet_deposit_requests_status_idx on wallet_deposit_requests (status) where status in ('pending', 'under_review');

alter table wallet_deposit_requests enable row level security;

create policy wallet_deposit_requests_select_own
  on wallet_deposit_requests for select
  to authenticated
  using (user_id = auth.uid());

create policy wallet_deposit_requests_select_staff
  on wallet_deposit_requests for select
  to authenticated
  using (current_user_role() in ('finance_officer', 'platform_admin', 'system_auditor'));

-- COND-1: Create Deposit Request — customer only, for themselves.
create policy wallet_deposit_requests_insert_own
  on wallet_deposit_requests for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and current_user_role() = 'customer'
    and status = 'pending'
    and reviewed_by is null
    and ledger_entry_id is null
  );

-- No client-facing UPDATE/DELETE policy: review transitions (pending ->
-- under_review -> approved/rejected) happen exclusively through
-- approve_wallet_deposit() / reject_wallet_deposit() below, so a customer can
-- never edit their own pending request's amount after submission and a
-- finance officer can never approve without going through the ledger-writing
-- function.

create function approve_wallet_deposit(p_deposit_id uuid)
returns wallet_deposit_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deposit    wallet_deposit_requests;
  v_ledger_id  uuid;
begin
  if current_user_role() not in ('finance_officer', 'platform_admin') then
    raise exception 'Only FINANCE_OFFICER or PLATFORM_ADMIN may approve a deposit' using errcode = '42501';
  end if;

  select * into v_deposit
  from wallet_deposit_requests
  where id = p_deposit_id
  for update;

  if not found then
    raise exception 'Deposit request % not found', p_deposit_id using errcode = 'P0002';
  end if;

  if v_deposit.status not in ('pending', 'under_review') then
    raise exception 'Deposit request % is already %, cannot approve', p_deposit_id, v_deposit.status
      using errcode = '22023';
  end if;

  insert into wallet_ledger_entries (
    user_id, entry_type, amount, reference_type, reference_id,
    idempotency_key, actor_id, reason_code
  )
  values (
    v_deposit.user_id, 'CREDIT', v_deposit.amount, 'DEPOSIT', v_deposit.id,
    v_deposit.id, auth.uid(), 'wallet_deposit_approved'
  )
  returning id into v_ledger_id;

  update wallet_deposit_requests
  set status = 'approved',
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      ledger_entry_id = v_ledger_id
  where id = p_deposit_id
  returning * into v_deposit;

  return v_deposit;
end;
$$;

comment on function approve_wallet_deposit(uuid) is 'BR-WALLET-003. idempotency_key = the deposit request''s own id, so a duplicate approve_wallet_deposit call for an already-approved request fails on wallet_ledger_entries_idempotency_key_unique (INVARIANT 3) instead of double-crediting; the status guard above catches the common case earlier with a clearer error.';

create function reject_wallet_deposit(p_deposit_id uuid, p_rejection_reason text)
returns wallet_deposit_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deposit wallet_deposit_requests;
begin
  if current_user_role() not in ('finance_officer', 'platform_admin') then
    raise exception 'Only FINANCE_OFFICER or PLATFORM_ADMIN may reject a deposit' using errcode = '42501';
  end if;

  if p_rejection_reason is null or btrim(p_rejection_reason) = '' then
    raise exception 'A rejection reason is required (BR-WALLET-004)' using errcode = '22023';
  end if;

  update wallet_deposit_requests
  set status = 'rejected',
      rejection_reason = p_rejection_reason,
      reviewed_by = auth.uid(),
      reviewed_at = now()
  where id = p_deposit_id
    and status in ('pending', 'under_review')
  returning * into v_deposit;

  if not found then
    raise exception 'Deposit request % not found or already reviewed', p_deposit_id using errcode = 'P0002';
  end if;

  return v_deposit;
end;
$$;

revoke execute on function approve_wallet_deposit(uuid) from public, anon, authenticated, service_role;
grant execute on function approve_wallet_deposit(uuid) to authenticated;
revoke execute on function reject_wallet_deposit(uuid, text) from public, anon, authenticated, service_role;
grant execute on function reject_wallet_deposit(uuid, text) to authenticated;
