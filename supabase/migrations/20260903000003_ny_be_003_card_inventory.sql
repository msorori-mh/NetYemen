-- NY-BE-003: Card Inventory & Batch Upload Infrastructure
-- Contracts: NETYEMEN-BUSINESS-RULES-CATALOG-01 (BR-CARD-*, BR-NETWORK-004),
--            NETYEMEN-ROLE-AUTHORIZATION-MATRIX-01 (COND-3, COND-4),
--            NETYEMEN-DECISION-REGISTER-01 (OD-CARD-01)
-- Scope: network_operators (COND-4 dependency), pgcrypto card-number encryption
-- infra, card_batches, cards, and the atomic import_card_batch() RPC.

-- ---------------------------------------------------------------------------
-- network_operators (BR-NETWORK-004 / COND-4 dependency)
-- ---------------------------------------------------------------------------

create table network_operators (
  network_id  uuid        not null references networks (id) on delete cascade,
  operator_id uuid        not null references users (id) on delete cascade,
  assigned_by uuid        not null references users (id),
  created_at  timestamptz not null default now(),

  primary key (network_id, operator_id)
);

comment on table network_operators is 'BR-NETWORK-004: up to 5 NETWORK_OPERATOR accounts per network. Row presence is the active-assignment signal referenced by the matrix''s COND-4 — revoking access is a DELETE, not a status flag.';

alter table network_operators enable row level security;

create policy network_operators_select_owner
  on network_operators for select
  to authenticated
  using (exists (
    select 1 from networks n
    where n.id = network_operators.network_id and n.owner_id = auth.uid()
  ));

create policy network_operators_select_self
  on network_operators for select
  to authenticated
  using (operator_id = auth.uid());

create policy network_operators_select_staff
  on network_operators for select
  to authenticated
  using (current_user_role() = 'platform_admin');

-- BR-NETWORK-004: owner-only assignment, capped at 5, target user must actually
-- hold the network_operator role.
create policy network_operators_insert_owner
  on network_operators for insert
  to authenticated
  with check (
    assigned_by = auth.uid()
    and exists (
      select 1 from networks n
      where n.id = network_operators.network_id
        and n.owner_id = auth.uid()
        and current_user_role() = 'network_owner'
    )
    and exists (
      select 1 from users u
      where u.id = network_operators.operator_id and u.role = 'network_operator'
    )
    and (
      select count(*) from network_operators existing
      where existing.network_id = network_operators.network_id
    ) < 5
  );

create policy network_operators_delete_owner
  on network_operators for delete
  to authenticated
  using (exists (
    select 1 from networks n
    where n.id = network_operators.network_id and n.owner_id = auth.uid()
  ));

-- ---------------------------------------------------------------------------
-- Card-number encryption infrastructure (OD-CARD-01: pgcrypto column-level
-- encryption, decrypted exclusively inside a security-definer RPC).
-- ---------------------------------------------------------------------------

create table card_encryption_keys (
  id           uuid        primary key default gen_random_uuid(),
  key_material bytea       not null,
  is_active    boolean     not null default true,
  created_at   timestamptz not null default now()
);

comment on table card_encryption_keys is 'OD-CARD-01 key material for card_number_ciphertext. RLS enabled with zero policies, permanently — not even PLATFORM_ADMIN gets a row here. Reachable only through active_card_encryption_key(), whose EXECUTE is revoked from PUBLIC.';

alter table card_encryption_keys enable row level security;
-- Intentionally no policies of any kind: this table has no legitimate row-level
-- reader at all, staff included. Access is a privileged function call, not a query.

insert into card_encryption_keys (key_material) values (gen_random_bytes(32));

create function active_card_encryption_key()
returns bytea
language sql
stable
security definer
set search_path = public
as $$
  select key_material from card_encryption_keys where is_active order by created_at desc limit 1;
$$;

create function encrypt_card_number(p_card_number text)
returns bytea
language sql
stable
security definer
set search_path = public
as $$
  select encrypt(convert_to(p_card_number, 'utf8'), active_card_encryption_key(), 'aes');
$$;

create function decrypt_card_number(p_ciphertext bytea)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select convert_from(decrypt(p_ciphertext, active_card_encryption_key(), 'aes'), 'utf8');
$$;

-- Supabase/PostgREST exposes every public-schema function as a callable RPC by
-- default. These three touch key material directly and must never be reachable
-- except from another SECURITY DEFINER function owned by the same role (the
-- owner's own privileges are never subject to REVOKE ... FROM PUBLIC).
revoke execute on function active_card_encryption_key() from public;
revoke execute on function encrypt_card_number(text) from public;
revoke execute on function decrypt_card_number(bytea) from public;

-- ---------------------------------------------------------------------------
-- card_batches
-- ---------------------------------------------------------------------------

create table card_batches (
  id                   uuid        primary key default gen_random_uuid(),
  network_id           uuid        not null references networks (id) on delete restrict,
  network_price_id     uuid        not null references network_prices (id) on delete restrict,
  uploaded_by          uuid        not null references users (id) on delete restrict,
  source_filename      text        not null,
  total_lines          integer     not null,
  imported_count       integer     not null,
  duplicate_count      integer     not null,
  invalid_format_count integer     not null,
  created_at           timestamptz not null default now(),

  constraint card_batches_total_lines_positive check (total_lines > 0),
  constraint card_batches_counts_non_negative check (
    imported_count >= 0 and duplicate_count >= 0 and invalid_format_count >= 0
  ),
  constraint card_batches_counts_sum check (
    imported_count + duplicate_count + invalid_format_count = total_lines
  )
);

comment on table card_batches is 'BR-CARD-007: one row per completed import_card_batch() call. A batch that exceeds the 5% error threshold never reaches this table — the whole RPC transaction rolls back before any row is written, so there is no "aborted" status to record.';

alter table card_batches enable row level security;

create policy card_batches_select_owner
  on card_batches for select
  to authenticated
  using (exists (
    select 1 from networks n where n.id = card_batches.network_id and n.owner_id = auth.uid()
  ));

create policy card_batches_select_operator
  on card_batches for select
  to authenticated
  using (exists (
    select 1 from network_operators npo
    where npo.network_id = card_batches.network_id and npo.operator_id = auth.uid()
  ));

create policy card_batches_select_staff
  on card_batches for select
  to authenticated
  using (current_user_role() in ('platform_admin', 'system_auditor'));

-- No INSERT/UPDATE/DELETE policy: rows are written exclusively by
-- import_card_batch() below, which bypasses RLS as the table owner. A batch
-- is an immutable import record, never edited by a client.

-- ---------------------------------------------------------------------------
-- cards
-- ---------------------------------------------------------------------------

-- BR-CARD-003's documented order ("available -> reserved -> sold -> quarantined
-- -> invalid -> cancelled") is also this enum's declaration order, which Postgres
-- uses for <, <=, >, >= comparisons — the lifecycle trigger below relies on that.
create type card_status as enum (
  'available',
  'reserved',
  'sold',
  'quarantined',
  'invalid',
  'cancelled'
);

create table cards (
  id                     uuid        primary key default gen_random_uuid(),
  network_id             uuid        not null references networks (id) on delete restrict,
  batch_id               uuid        not null references card_batches (id) on delete restrict,
  network_price_id       uuid        not null references network_prices (id) on delete restrict,
  card_number_ciphertext bytea       not null,
  card_number_hash       bytea       not null,
  status                 card_status not null default 'available',
  sold_to                uuid        references users (id),
  sold_at                timestamptz,
  created_at             timestamptz not null default now()
);

comment on table cards is 'BR-CARD-004: card_number_ciphertext is pgcrypto AES ciphertext, never plaintext — plaintext is decrypted exclusively inside the purchase_card RPC (NY-BE-005), scoped to the purchasing customer. card_number_hash (sha256) enforces BR-CARD-002 per-network uniqueness without ever reading plaintext back. sold_to/sold_at are set exactly once, together, by purchase_card at the moment status first becomes ''sold'', and are never cleared by any later status change (e.g. a refund-driven move to ''quarantined'' keeps them as the audit record of who bought the card).';

-- BR-CARD-002: unique within a network, across every batch ever imported.
create unique index cards_network_hash_uidx on cards (network_id, card_number_hash);
-- BR-CARD-009: the row purchase_card locks with SELECT ... FOR UPDATE SKIP LOCKED.
create index cards_network_available_idx on cards (network_id, network_price_id) where status = 'available';
create index cards_batch_idx on cards (batch_id);

alter table cards enable row level security;

create policy cards_select_owner
  on cards for select
  to authenticated
  using (exists (
    select 1 from networks n where n.id = cards.network_id and n.owner_id = auth.uid()
  ));

create policy cards_select_operator
  on cards for select
  to authenticated
  using (exists (
    select 1 from network_operators npo
    where npo.network_id = cards.network_id and npo.operator_id = auth.uid()
  ));

create policy cards_select_staff
  on cards for select
  to authenticated
  using (current_user_role() in ('platform_admin', 'system_auditor'));

-- No customer-facing SELECT policy here, deliberately: "View Unsold Card PINs" is
-- DENIED for every role in the authorization matrix, including PLATFORM_ADMIN
-- (BR-ADMIN-002 admin commercial non-bypass). A customer's own purchased card is
-- revealed through the purchase_card RPC's return value and the dedicated COND-6
-- reveal path (both NY-BE-005), never a raw table read. Even the owner/operator/
-- staff policies above only ever expose card_number_ciphertext, which is
-- meaningless without active_card_encryption_key() — so BR-CARD-004's plaintext
-- confidentiality holds regardless of which policy matches.
--
-- No INSERT/UPDATE/DELETE policy: cards are written exclusively by
-- import_card_batch() below and, later, purchase_card() / refund / quarantine
-- RPCs — all SECURITY DEFINER. No client ever mutates a card row directly.

create function cards_enforce_lifecycle()
returns trigger
language plpgsql
as $$
begin
  if new.status < old.status then
    raise exception 'Card % cannot move backward from % to %', old.id, old.status, new.status
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger cards_enforce_lifecycle
  before update of status on cards
  for each row execute function cards_enforce_lifecycle();

-- ---------------------------------------------------------------------------
-- import_card_batch: BR-CARD-002/003/004/007 atomic batch import
-- ---------------------------------------------------------------------------
-- Takes already-parsed, one-card-number-per-element input (CSV/text-file
-- parsing is a client/edge-function concern, out of scope for this RPC) and
-- performs pre-import validation before writing anything, so the 5% error
-- threshold gates the whole transaction rather than requiring a rollback of
-- partially-inserted rows.

create function import_card_batch(
  p_network_id       uuid,
  p_network_price_id uuid,
  p_source_filename  text,
  p_card_numbers     text[]
)
returns table (
  batch_id             uuid,
  total_lines          integer,
  imported_count       integer,
  duplicate_count      integer,
  invalid_format_count integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_authorized      boolean;
  v_total           integer;
  v_raw             text;
  v_normalized      text;
  v_hash            bytea;
  v_invalid_count   integer := 0;
  v_duplicate_count integer := 0;
  v_valid_numbers   text[]  := '{}';
  v_valid_hashes    bytea[] := '{}';
  v_batch_id        uuid;
  v_idx             integer;
begin
  -- COND-3 (owner) or COND-4 (assigned operator).
  select exists (
    select 1 from networks n where n.id = p_network_id and n.owner_id = auth.uid()
  ) or exists (
    select 1 from network_operators npo
    where npo.network_id = p_network_id and npo.operator_id = auth.uid()
  ) into v_authorized;

  if not v_authorized then
    raise exception 'Not authorized to import cards for this network' using errcode = '42501';
  end if;

  if not exists (
    select 1 from network_prices np
    where np.id = p_network_price_id and np.network_id = p_network_id
  ) then
    raise exception 'network_price_id does not belong to network_id' using errcode = '22023';
  end if;

  v_total := coalesce(array_length(p_card_numbers, 1), 0);
  if v_total = 0 then
    raise exception 'Card batch cannot be empty' using errcode = '22023';
  end if;

  foreach v_raw in array p_card_numbers loop
    v_normalized := btrim(v_raw);

    if v_normalized = '' or length(v_normalized) < 4 or length(v_normalized) > 64 then
      v_invalid_count := v_invalid_count + 1;
      continue;
    end if;

    v_hash := digest(v_normalized, 'sha256');

    -- BR-CARD-002: reject duplicates both within this batch and against every
    -- card ever imported for this network.
    if v_hash = any(v_valid_hashes)
       or exists (select 1 from cards c where c.network_id = p_network_id and c.card_number_hash = v_hash) then
      v_duplicate_count := v_duplicate_count + 1;
      continue;
    end if;

    v_valid_numbers := v_valid_numbers || v_normalized;
    v_valid_hashes := v_valid_hashes || v_hash;
  end loop;

  -- BR-CARD-007: >5% invalid+duplicate aborts the entire import. Nothing has
  -- been written yet, so raising here is already a full, clean abort.
  if (v_invalid_count + v_duplicate_count)::numeric / v_total::numeric > 0.05 then
    raise exception 'Batch import aborted: error rate %/% exceeds the 5%% threshold (% invalid, % duplicate)',
      v_invalid_count + v_duplicate_count, v_total, v_invalid_count, v_duplicate_count
      using errcode = 'P0001';
  end if;

  insert into card_batches (
    network_id, network_price_id, uploaded_by, source_filename,
    total_lines, imported_count, duplicate_count, invalid_format_count
  )
  values (
    p_network_id, p_network_price_id, auth.uid(), p_source_filename,
    v_total, coalesce(array_length(v_valid_numbers, 1), 0), v_duplicate_count, v_invalid_count
  )
  returning id into v_batch_id;

  for v_idx in 1 .. coalesce(array_length(v_valid_numbers, 1), 0) loop
    insert into cards (network_id, batch_id, network_price_id, card_number_ciphertext, card_number_hash)
    values (
      p_network_id, v_batch_id, p_network_price_id,
      encrypt_card_number(v_valid_numbers[v_idx]), v_valid_hashes[v_idx]
    );
  end loop;

  return query
    select v_batch_id, v_total, coalesce(array_length(v_valid_numbers, 1), 0), v_duplicate_count, v_invalid_count;
end;
$$;

comment on function import_card_batch(uuid, uuid, text, text[]) is 'BR-CARD-007 atomic batch import. Authorization (COND-3/COND-4) is checked inline rather than relied on at the GRANT level, matching the purchase_card RPC pattern used in NY-BE-005.';

revoke execute on function import_card_batch(uuid, uuid, text, text[]) from public;
grant execute on function import_card_batch(uuid, uuid, text, text[]) to authenticated;
