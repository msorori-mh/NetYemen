-- NY-BE-001: Database Schema Definition & Core Profile Tables Migration
-- Contracts: NETYEMEN-BUSINESS-RULES-CATALOG-01, NETYEMEN-ROLE-AUTHORIZATION-MATRIX-01
-- Scope: roles, users, networks, network_prices.
-- RLS policies are deliberately NOT defined here; NY-BE-002 owns them. Every table
-- enables RLS with zero policies so the default-deny posture holds between the two
-- migrations rather than leaving a window where the tables are world-readable.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Enumerations
-- ---------------------------------------------------------------------------

create type account_status as enum (
  'pending_verification',
  'active',
  'suspended',
  'closure_pending',
  'closed'
);

-- ---------------------------------------------------------------------------
-- roles: catalog of the 8 active V1 platform roles
-- ---------------------------------------------------------------------------

create table roles (
  code          text primary key,
  display_name  text        not null,
  description   text        not null,
  is_staff_role boolean     not null default false,
  created_at    timestamptz not null default now()
);

comment on table roles is 'Active V1 platform roles. Deferred roles (merchant/sub-distributor) are out of V1 scope per BR-AUTH-008.';

insert into roles (code, display_name, description, is_staff_role) values
  ('customer',         'Customer',         'Authenticated retail card purchaser.',                       false),
  ('network_owner',    'Network Owner',    'Verified proprietor of one or more Wi-Fi networks.',         false),
  ('network_operator', 'Network Operator', 'Staff member delegated by a network owner.',                 false),
  ('finance_officer',  'Finance Officer',  'Internal financial reviewer and deposit approver.',          true),
  ('support_agent',    'Support Agent',    'Customer care and dispute resolution specialist.',           true),
  ('platform_admin',   'Platform Admin',   'System superadmin and role authority.',                      true),
  ('system_auditor',   'System Auditor',   'Read-only compliance and forensic auditor.',                 true);

-- ---------------------------------------------------------------------------
-- Yemen phone normalization (BR-AUTH-001)
-- ---------------------------------------------------------------------------

create function normalize_yemen_phone(raw text)
returns text
language plpgsql
immutable
as $$
declare
  digits text;
begin
  if raw is null then
    return null;
  end if;

  digits := regexp_replace(raw, '[^0-9]', '', 'g');

  -- Strip the country code in whichever form it arrived (+967, 00967, 967).
  if left(digits, 3) = '967' then
    digits := substr(digits, 4);
  end if;

  if digits !~ '^7[01378][0-9]{7}$' then
    raise exception 'Invalid Yemen mobile number: %. Expected 9 digits starting with 70, 71, 73, 77 or 78.', raw
      using errcode = '22023';
  end if;

  return '+967' || digits;
end;
$$;

comment on function normalize_yemen_phone(text) is 'BR-AUTH-001: normalizes any Yemeni mobile input to E.164 (+9677XXXXXXXX) or raises.';

-- ---------------------------------------------------------------------------
-- users: profile mirror of auth.users
-- ---------------------------------------------------------------------------

create table users (
  id                   uuid primary key references auth.users (id) on delete cascade,
  phone                text           not null unique,
  full_name            text,
  role                 text           not null default 'customer' references roles (code),
  status               account_status not null default 'active',
  wallet_balance       integer        not null default 0,
  is_identity_verified boolean        not null default false,
  closure_requested_at timestamptz,
  created_at           timestamptz    not null default now(),
  updated_at           timestamptz    not null default now(),

  -- BR-AUTH-001: storage format is E.164, enforced independently of the trigger
  -- so a direct SQL insert cannot smuggle in an unnormalized number.
  constraint users_phone_e164 check (phone ~ '^\+9677[01378][0-9]{7}$'),
  -- BR-WALLET-001 / INVARIANT 2
  constraint users_wallet_balance_non_negative check (wallet_balance >= 0),
  -- BR-AUTH-007: a closure_pending account must carry the grace-period start.
  constraint users_closure_timestamp check (
    (status = 'closure_pending') = (closure_requested_at is not null)
  )
);

comment on column users.wallet_balance is 'OD-WALLET-01: cached balance maintained by trigger from wallet_ledger_entries (NY-BE-004). Never updated by application arithmetic.';

create index users_role_idx on users (role);
create index users_status_idx on users (status);

-- ---------------------------------------------------------------------------
-- networks
-- ---------------------------------------------------------------------------

create table networks (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid        not null references users (id) on delete restrict,
  name           text        not null,
  description    text,
  governorate    text        not null,
  district       text,
  city           text,
  location_text  text,
  lat            double precision,
  lng            double precision,
  is_approved    boolean     not null default false,
  is_active      boolean     not null default false,
  is_featured    boolean     not null default false,
  verified_badge boolean     not null default false,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  -- BR-NETWORK-002: a network cannot be live before an admin approves it.
  constraint networks_active_requires_approval check (not is_active or is_approved),
  constraint networks_lat_range check (lat is null or lat between -90 and 90),
  constraint networks_lng_range check (lng is null or lng between -180 and 180)
);

comment on table networks is 'BR-NETWORK-003: a network belongs to exactly one owner; transfer requires multi-signature approval handled outside this schema.';
comment on column networks.is_featured is 'BR-NETWORK-006: settable only by PLATFORM_ADMIN. Enforced by the NY-BE-002 RLS policy, not by this column.';

create index networks_owner_idx on networks (owner_id);
-- BR-NETWORK-005: the customer discovery query filters on exactly these two flags.
create index networks_discovery_idx on networks (governorate) where is_approved and is_active;

-- ---------------------------------------------------------------------------
-- network_prices (BR-CARD-008: every package attribute is mandatory)
-- ---------------------------------------------------------------------------

create table network_prices (
  id                uuid primary key default gen_random_uuid(),
  network_id        uuid        not null references networks (id) on delete cascade,
  denomination      integer     not null,
  selling_price     integer     not null,
  data_quota_mb     integer     not null,
  validity_minutes  integer     not null,
  speed_limit_mbps  numeric(6,2) not null,
  is_active         boolean     not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  -- BR-WALLET-006: whole YER only, so both money columns are integers > 0.
  constraint network_prices_denomination_positive check (denomination > 0),
  constraint network_prices_selling_price_positive check (selling_price > 0),
  constraint network_prices_quota_positive check (data_quota_mb > 0),
  constraint network_prices_validity_positive check (validity_minutes > 0),
  constraint network_prices_speed_positive check (speed_limit_mbps > 0)
);

comment on table network_prices is 'BR-PURCHASE-003: the purchase_card RPC reads price from this table. Client-supplied prices are ignored.';

-- One live tier per denomination per network; retired tiers stay for ledger history.
create unique index network_prices_active_denomination_idx
  on network_prices (network_id, denomination)
  where is_active;

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

create function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger users_set_updated_at
  before update on users
  for each row execute function set_updated_at();

create trigger networks_set_updated_at
  before update on networks
  for each row execute function set_updated_at();

create trigger network_prices_set_updated_at
  before update on network_prices
  for each row execute function set_updated_at();

create function users_normalize_phone()
returns trigger
language plpgsql
as $$
begin
  new.phone := normalize_yemen_phone(new.phone);
  return new;
end;
$$;

create trigger users_normalize_phone
  before insert or update of phone on users
  for each row execute function users_normalize_phone();

-- BR-AUTH-003: profile provisioning is a database concern. Client-side inserts
-- into users are forbidden, so the row must exist before the app ever queries it.
create function handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users (id, phone, wallet_balance, role, status)
  values (new.id, new.phone, 0, 'customer', 'active')
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_auth_user();

-- ---------------------------------------------------------------------------
-- Default-deny posture (anti-bypass principle 2). Policies land in NY-BE-002.
-- ---------------------------------------------------------------------------

alter table roles           enable row level security;
alter table users           enable row level security;
alter table networks        enable row level security;
alter table network_prices  enable row level security;
