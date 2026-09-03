-- NY-BE-007: Multi-SSID Aliases, Bank Directory & Lead Queue Schema (NY-PRODUCT-001E)
-- Contracts: NETYEMEN-BUSINESS-RULES-CATALOG-01 (BR-NETWORK-008/009/011, BR-WALLET-007),
--            NETYEMEN-DATA-CLASSIFICATION-AND-PRIVACY-01, NETYEMEN-DECISION-REGISTER-01 (OD-FIN-03)
-- Scope: network_ssids, bank_accounts, network_addition_leads.

-- ---------------------------------------------------------------------------
-- network_ssids (BR-NETWORK-008)
-- ---------------------------------------------------------------------------
-- Stores the network's own broadcast name(s) — this is PUBLIC data (data
-- classification: "Network Name / SSID / City" = PUBLIC), fetched by clients
-- to do nearby-network matching entirely on-device. It must never be confused
-- with a live Wi-Fi scan result: BR-NETWORK-011 forbids uploading BSSIDs or
-- raw device identifiers, and the classification doc separately marks the
-- customer's own "Wi-Fi SSID Scan Filter" CONFIDENTIAL, never uploaded. This
-- table exists to be downloaded and matched against, not to receive uploads
-- from a scan — there is no bssid column here, deliberately, and there must
-- never be one.

create table network_ssids (
  id         uuid        primary key default gen_random_uuid(),
  network_id uuid        not null references networks (id) on delete cascade,
  ssid       text        not null,
  created_at timestamptz not null default now(),

  -- Not a global UNIQUE: real-world SSIDs collide across unrelated networks
  -- (e.g. two different cafes both named "WiFi"). Only a duplicate alias on
  -- the SAME network is meaningless and rejected.
  constraint network_ssids_network_ssid_unique unique (network_id, ssid)
);

comment on table network_ssids is 'BR-NETWORK-008: card stock is drawn from the unified network inventory regardless of which registered SSID alias matched — this table only maps names to network_id, it has no relationship to cards/pricing.';

alter table network_ssids enable row level security;

create policy network_ssids_select_public
  on network_ssids for select
  to authenticated, anon
  using (exists (
    select 1 from networks n
    where n.id = network_ssids.network_id and n.is_approved and n.is_active
  ));

create policy network_ssids_select_own
  on network_ssids for select
  to authenticated
  using (exists (
    select 1 from networks n where n.id = network_ssids.network_id and n.owner_id = auth.uid()
  ));

create policy network_ssids_select_staff
  on network_ssids for select
  to authenticated
  using (current_user_role() in ('platform_admin', 'system_auditor'));

-- COND-3: "Update Own Network / SSIDs" bundles SSID management with network
-- edits. No cap on alias count is documented, unlike network_operators' 5.
create policy network_ssids_insert_owner
  on network_ssids for insert
  to authenticated
  with check (exists (
    select 1 from networks n
    where n.id = network_ssids.network_id
      and n.owner_id = auth.uid()
      and current_user_role() = 'network_owner'
  ));

create policy network_ssids_delete_owner
  on network_ssids for delete
  to authenticated
  using (exists (
    select 1 from networks n
    where n.id = network_ssids.network_id
      and n.owner_id = auth.uid()
      and current_user_role() = 'network_owner'
  ));

create policy network_ssids_insert_admin
  on network_ssids for insert
  to authenticated
  with check (current_user_role() = 'platform_admin');

create policy network_ssids_delete_admin
  on network_ssids for delete
  to authenticated
  using (current_user_role() = 'platform_admin');

-- No UPDATE policy: an alias is a short string with no other fields to edit —
-- correcting one is a delete-then-insert, not an update.

-- ---------------------------------------------------------------------------
-- bank_accounts (BR-WALLET-007, OD-FIN-03 — Option 1, Configuration-Driven
-- Bank Directory, approved under NY-GOV-001)
-- ---------------------------------------------------------------------------

create table bank_accounts (
  id                  uuid        primary key default gen_random_uuid(),
  provider_name       text        not null,
  account_holder_name text        not null,
  account_number      text        not null,
  branch              text,
  notes               text,
  display_order       integer     not null default 0,
  is_active           boolean     not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

comment on table bank_accounts is 'BR-WALLET-007: illustrative provider entries until real account numbers are configured by FINANCE_OFFICER/PLATFORM_ADMIN — nothing here is a live secret, it is exactly what a customer is shown to make a manual deposit against.';

create trigger bank_accounts_set_updated_at
  before update on bank_accounts
  for each row execute function set_updated_at();

alter table bank_accounts enable row level security;

-- Acceptance criteria: "bank directory RLS public read."
create policy bank_accounts_select_public
  on bank_accounts for select
  to authenticated, anon
  using (is_active);

create policy bank_accounts_select_staff
  on bank_accounts for select
  to authenticated
  using (current_user_role() in ('finance_officer', 'platform_admin', 'system_auditor'));

-- Acceptance criteria (negative test): "unauthenticated insertion of bank
-- account records rejected" — satisfied by having no anon/authenticated
-- INSERT policy at all except this staff-only one.
create policy bank_accounts_insert_staff
  on bank_accounts for insert
  to authenticated
  with check (current_user_role() in ('finance_officer', 'platform_admin'));

create policy bank_accounts_update_staff
  on bank_accounts for update
  to authenticated
  using (current_user_role() in ('finance_officer', 'platform_admin'))
  with check (current_user_role() in ('finance_officer', 'platform_admin'));

-- No DELETE policy: retire a channel with is_active = false — past deposit
-- requests may still reference it by name/notes for their audit trail.

-- ---------------------------------------------------------------------------
-- network_addition_leads (BR-NETWORK-009)
-- ---------------------------------------------------------------------------

create table network_addition_leads (
  id             uuid        primary key default gen_random_uuid(),
  submitted_by   uuid        not null references users (id) on delete restrict,
  suggested_name text        not null,
  governorate    text        not null,
  district       text,
  city           text,
  location_text  text,
  notes          text,
  status         text        not null default 'pending',
  reviewed_by    uuid        references users (id),
  created_at     timestamptz not null default now(),
  reviewed_at    timestamptz,

  constraint network_addition_leads_status_valid check (
    status in ('pending', 'reviewed', 'onboarded', 'rejected')
  ),
  constraint network_addition_leads_reviewed_fields check (
    (status = 'pending') or (reviewed_by is not null and reviewed_at is not null)
  )
);

comment on table network_addition_leads is 'BR-NETWORK-009: leads never grant public listing on their own — onboarding still goes through the normal networks_insert_owner path once PLATFORM_ADMIN acts on a lead. Privacy doc §"Anonymized Lead Suggestions": NETWORK_OWNER gets no SELECT policy on this table at all (not even column-masked), which is what keeps a lead anonymous from owners — only the submitter and staff can read a lead row.';

create index network_addition_leads_status_idx on network_addition_leads (status) where status = 'pending';

alter table network_addition_leads enable row level security;

create policy network_addition_leads_select_own
  on network_addition_leads for select
  to authenticated
  using (submitted_by = auth.uid());

create policy network_addition_leads_select_staff
  on network_addition_leads for select
  to authenticated
  using (current_user_role() in ('platform_admin', 'system_auditor'));

-- Matrix row "Submit Network Addition Lead": CUSTOMER, NETWORK_OWNER and
-- PLATFORM_ADMIN are ALLOWED (no ownership/verification condition attached,
-- unlike "Submit New Network"); every other role is DENIED.
create policy network_addition_leads_insert_allowed_roles
  on network_addition_leads for insert
  to authenticated
  with check (
    submitted_by = auth.uid()
    and current_user_role() in ('customer', 'network_owner', 'platform_admin')
    and status = 'pending'
    and reviewed_by is null
  );

create policy network_addition_leads_update_staff
  on network_addition_leads for update
  to authenticated
  using (current_user_role() = 'platform_admin')
  with check (current_user_role() = 'platform_admin');

-- No DELETE policy: a rejected/onboarded lead stays as the permanent record
-- of what was reviewed and when.
