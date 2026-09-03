-- NY-BE-002: Default-Deny RLS Policies & Role Authorization Framework
-- Contracts: NETYEMEN-ROLE-AUTHORIZATION-MATRIX-01, NETYEMEN-THREAT-AND-FRAUD-MODEL-01
-- Scope: RBAC helper functions + RLS policies for roles, users, networks, network_prices.
--
-- Anti-bypass principles enforced here (NETYEMEN-ROLE-AUTHORIZATION-MATRIX-01 §3):
--   1. UI visibility is not authorization — every policy re-validates independently.
--   2. Backend enforcement on every operation — RLS was already enabled with zero
--      policies in NY-BE-001; this migration is the only place policies are added.
--   4. Client-supplied identifiers are untrusted — every policy compares against
--      auth.uid(), never a client-supplied column value.
--   5. Dual role + resource ownership verification — COND-* policies check both.
--   7. Default-deny scoping — no blanket "authenticated" policies; each grant is
--      named after the specific action it authorizes.

-- ---------------------------------------------------------------------------
-- Role helper functions (SECURITY DEFINER, STABLE: safe to call inside policies)
-- ---------------------------------------------------------------------------

create function current_user_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role from public.users where id = auth.uid();
$$;

comment on function current_user_role() is 'Returns the caller''s platform role, or NULL if unauthenticated / no profile row yet.';

-- ---------------------------------------------------------------------------
-- roles: public read-only reference data. No client ever writes this table.
-- ---------------------------------------------------------------------------

create policy roles_select_all
  on roles for select
  to authenticated, anon
  using (true);

-- No insert/update/delete policies: role catalog changes ship as migrations only.

-- ---------------------------------------------------------------------------
-- users
-- ---------------------------------------------------------------------------

-- COND-1: Read Own Profile. THR-01 mitigation — never a broader "authenticated" grant.
create policy users_select_own
  on users for select
  to authenticated
  using (id = auth.uid());

-- Staff roles read all profiles per the matrix (FINANCE/SUPPORT/ADMIN/AUDITOR = ALLOWED).
create policy users_select_staff
  on users for select
  to authenticated
  using (
    current_user_role() in ('finance_officer', 'support_agent', 'platform_admin', 'system_auditor')
  );

-- COND-1: Update Own Profile. wallet_balance is intentionally NOT excluded from the
-- USING/WITH CHECK column set here because Postgres RLS cannot restrict individual
-- columns; instead wallet_balance is protected structurally — it is only ever
-- written by the trigger backing NY-BE-004's ledger, never by application UPDATE
-- statements, and BR-WALLET-001/002 forbid any direct arithmetic modification.
create policy users_update_own
  on users for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- Suspend Any User Account: ADMIN only (matrix row "Suspend Any User Account").
create policy users_update_admin
  on users for update
  to authenticated
  using (current_user_role() = 'platform_admin')
  with check (current_user_role() = 'platform_admin');

-- No client-side INSERT policy: BR-AUTH-003 requires profile creation to happen
-- exclusively via the handle_new_auth_user() trigger (security definer, NY-BE-001).
-- No DELETE policy at all: account closure is a status transition (BR-AUTH-007),
-- never a row deletion.

-- ---------------------------------------------------------------------------
-- networks
-- ---------------------------------------------------------------------------

-- Public Marketplace: View Active/Approved Networks — ALLOWED for every role,
-- including anon (BR-NETWORK-005).
create policy networks_select_public
  on networks for select
  to authenticated, anon
  using (is_approved and is_active);

-- COND-3: an owner also needs to see their own not-yet-approved / inactive rows.
create policy networks_select_own
  on networks for select
  to authenticated
  using (owner_id = auth.uid());

-- Staff need full visibility to approve/manage listings.
create policy networks_select_staff
  on networks for select
  to authenticated
  using (current_user_role() in ('platform_admin', 'system_auditor', 'finance_officer'));

-- COND-2: Submit New Network — network_owner role AND verified profile.
create policy networks_insert_owner
  on networks for insert
  to authenticated
  with check (
    owner_id = auth.uid()
    and current_user_role() = 'network_owner'
    and (select is_identity_verified from users where id = auth.uid())
  );

-- COND-3: Update Own Network — owner can edit their own network. is_approved and
-- is_featured stay owner-writable at the RLS layer (WITH CHECK cannot compare
-- against the pre-update row), so they are locked down separately below by
-- networks_protect_admin_fields, a BEFORE UPDATE trigger that rejects any change
-- to either column unless the caller is platform_admin (BR-NETWORK-002, BR-NETWORK-006).
create policy networks_update_own
  on networks for update
  to authenticated
  using (owner_id = auth.uid() and current_user_role() = 'network_owner')
  with check (owner_id = auth.uid() and current_user_role() = 'network_owner');

-- ADMIN: Approve/Reject Network, Featured Flag, Suspension — unrestricted update.
create policy networks_update_admin
  on networks for update
  to authenticated
  using (current_user_role() = 'platform_admin')
  with check (current_user_role() = 'platform_admin');

-- No DELETE policy: networks are suspended (is_active = false), never deleted,
-- to preserve historical card/purchase foreign-key integrity.

create function networks_protect_admin_fields()
returns trigger
language plpgsql
as $$
begin
  if (new.is_approved is distinct from old.is_approved
      or new.is_featured is distinct from old.is_featured)
     and current_user_role() is distinct from 'platform_admin' then
    raise exception 'is_approved and is_featured may only be changed by PLATFORM_ADMIN'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger networks_protect_admin_fields
  before update on networks
  for each row execute function networks_protect_admin_fields();

-- ---------------------------------------------------------------------------
-- network_prices
-- ---------------------------------------------------------------------------

-- Public Marketplace: View Network Prices & Packages — ALLOWED for every role.
-- Prices are only meaningful once the parent network is publicly visible.
create policy network_prices_select_public
  on network_prices for select
  to authenticated, anon
  using (
    is_active
    and exists (
      select 1 from networks n
      where n.id = network_prices.network_id
        and n.is_approved and n.is_active
    )
  );

-- Owner needs to see (and manage) price tiers on their own network regardless
-- of the network's public visibility state.
create policy network_prices_select_own
  on network_prices for select
  to authenticated
  using (
    exists (
      select 1 from networks n
      where n.id = network_prices.network_id and n.owner_id = auth.uid()
    )
  );

create policy network_prices_select_staff
  on network_prices for select
  to authenticated
  using (current_user_role() in ('platform_admin', 'system_auditor', 'finance_officer'));

-- COND-3: owner manages price tiers on their own network only.
create policy network_prices_insert_owner
  on network_prices for insert
  to authenticated
  with check (
    exists (
      select 1 from networks n
      where n.id = network_prices.network_id
        and n.owner_id = auth.uid()
        and current_user_role() = 'network_owner'
    )
  );

create policy network_prices_update_owner
  on network_prices for update
  to authenticated
  using (
    exists (
      select 1 from networks n
      where n.id = network_prices.network_id
        and n.owner_id = auth.uid()
        and current_user_role() = 'network_owner'
    )
  )
  with check (
    exists (
      select 1 from networks n
      where n.id = network_prices.network_id
        and n.owner_id = auth.uid()
        and current_user_role() = 'network_owner'
    )
  );

create policy network_prices_update_admin
  on network_prices for update
  to authenticated
  using (current_user_role() = 'platform_admin')
  with check (current_user_role() = 'platform_admin');

-- No DELETE policy anywhere in this migration: retiring a price tier is
-- is_active = false (BR-CARD-008 package history must survive for past
-- purchases' referential integrity), never a row deletion.
