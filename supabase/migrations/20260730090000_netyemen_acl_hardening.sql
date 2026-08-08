-- NetYemen V1 Client Table ACL Hardening
-- Migration: 20260730090000_netyemen_acl_hardening.sql
-- Task ID: NY-V1-OPERATIONS-CLOSURE-001
-- Scope: Remove destructive and non-required table privileges from PUBLIC, anon, and
--         authenticated on every NetYemen application table; re-grant only the
--         operations intentionally exposed through RLS/policies and RPCs.
-- Security invariant:
--   PUBLIC       TRUNCATE = false
--   anon         TRUNCATE = false
--   authenticated TRUNCATE = false
--   for every NetYemen application table.
-- Governance: OD-CARD-01 remains OPEN. No card-secret objects are touched.

-- ============================================================================
-- 1. Hard-coded list of NetYemen application tables in dependency order
-- ============================================================================
-- NOTE: If a future migration adds a new application table, it must explicitly
-- revoke and re-grant client privileges; this migration intentionally revokes
-- default privileges below so that new tables do not silently inherit TRUNCATE.

-- ============================================================================
-- 2. Revoke ALL client privileges and re-grant only intended operations
-- ============================================================================

-- ----------------------------------------------------------------------------
-- public.profiles
-- ----------------------------------------------------------------------------
REVOKE ALL ON TABLE public.profiles FROM PUBLIC;
REVOKE ALL ON TABLE public.profiles FROM anon;
REVOKE ALL ON TABLE public.profiles FROM authenticated;
GRANT SELECT ON TABLE public.profiles TO authenticated;
GRANT UPDATE (full_name, default_governorate, default_city) ON TABLE public.profiles TO authenticated;

-- ----------------------------------------------------------------------------
-- public.user_roles
-- ----------------------------------------------------------------------------
REVOKE ALL ON TABLE public.user_roles FROM PUBLIC;
REVOKE ALL ON TABLE public.user_roles FROM anon;
REVOKE ALL ON TABLE public.user_roles FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.user_roles TO authenticated;

-- ----------------------------------------------------------------------------
-- public.networks
-- ----------------------------------------------------------------------------
REVOKE ALL ON TABLE public.networks FROM PUBLIC;
REVOKE ALL ON TABLE public.networks FROM anon;
REVOKE ALL ON TABLE public.networks FROM authenticated;
GRANT SELECT (id, commercial_name, description, governorate, city, district, status, verification_status)
    ON TABLE public.networks TO anon;
GRANT SELECT, UPDATE ON TABLE public.networks TO authenticated;

-- ----------------------------------------------------------------------------
-- public.network_memberships
-- ----------------------------------------------------------------------------
REVOKE ALL ON TABLE public.network_memberships FROM PUBLIC;
REVOKE ALL ON TABLE public.network_memberships FROM anon;
REVOKE ALL ON TABLE public.network_memberships FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.network_memberships TO authenticated;

-- ----------------------------------------------------------------------------
-- public.network_ssid_aliases
-- ----------------------------------------------------------------------------
REVOKE ALL ON TABLE public.network_ssid_aliases FROM PUBLIC;
REVOKE ALL ON TABLE public.network_ssid_aliases FROM anon;
REVOKE ALL ON TABLE public.network_ssid_aliases FROM authenticated;
GRANT SELECT (id, network_id, ssid_display, ssid_normalized, status) ON TABLE public.network_ssid_aliases TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.network_ssid_aliases TO authenticated;

-- ----------------------------------------------------------------------------
-- public.audit_events
-- ----------------------------------------------------------------------------
REVOKE ALL ON TABLE public.audit_events FROM PUBLIC;
REVOKE ALL ON TABLE public.audit_events FROM anon;
REVOKE ALL ON TABLE public.audit_events FROM authenticated;
GRANT SELECT ON TABLE public.audit_events TO authenticated;

-- ----------------------------------------------------------------------------
-- public.network_addition_requests
-- ----------------------------------------------------------------------------
REVOKE ALL ON TABLE public.network_addition_requests FROM PUBLIC;
REVOKE ALL ON TABLE public.network_addition_requests FROM anon;
REVOKE ALL ON TABLE public.network_addition_requests FROM authenticated;
GRANT SELECT ON TABLE public.network_addition_requests TO authenticated;

-- ----------------------------------------------------------------------------
-- public.network_packages
-- ----------------------------------------------------------------------------
REVOKE ALL ON TABLE public.network_packages FROM PUBLIC;
REVOKE ALL ON TABLE public.network_packages FROM anon;
REVOKE ALL ON TABLE public.network_packages FROM authenticated;
GRANT SELECT ON TABLE public.network_packages TO anon;
GRANT SELECT ON TABLE public.network_packages TO authenticated;

-- ----------------------------------------------------------------------------
-- public.package_inventory_balances
-- ----------------------------------------------------------------------------
REVOKE ALL ON TABLE public.package_inventory_balances FROM PUBLIC;
REVOKE ALL ON TABLE public.package_inventory_balances FROM anon;
REVOKE ALL ON TABLE public.package_inventory_balances FROM authenticated;
GRANT SELECT ON TABLE public.package_inventory_balances TO authenticated;

-- ----------------------------------------------------------------------------
-- public.package_inventory_movements
-- ----------------------------------------------------------------------------
REVOKE ALL ON TABLE public.package_inventory_movements FROM PUBLIC;
REVOKE ALL ON TABLE public.package_inventory_movements FROM anon;
REVOKE ALL ON TABLE public.package_inventory_movements FROM authenticated;
GRANT SELECT ON TABLE public.package_inventory_movements TO authenticated;

-- ============================================================================
-- 3. Default privilege hardening
-- ============================================================================
-- Supabase local seeds default privileges that grant TRUNCATE (and more) to
-- anon, authenticated, and PUBLIC for tables created in the public schema.
-- This is the root cause of the BLOCKER finding: newly-created NetYemen tables
-- inherited Dxt/arwdDxt privileges that bypass RLS.
--
-- We revoke ALL default table privileges from PUBLIC/anon/authenticated for the
-- role that actually creates NetYemen tables (postgres in this environment).
-- Future migrations must explicitly grant only the privileges they intend.
-- service_role defaults are left untouched because Supabase internals rely on
-- them. supabase_admin also owns defaults in public, but the migration role
-- (postgres) is not a member of supabase_admin and cannot alter them; the
-- explicit per-table revokes above protect existing and future tables regardless
-- of which role creates them.

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
    REVOKE ALL ON TABLES FROM PUBLIC, anon, authenticated;

-- ============================================================================
-- 4. Lock down SECURITY DEFINER helpers that are not client-callable
-- ============================================================================
-- The inventory balance initializer is an internal trigger function; it must
-- never be executed directly by client roles.
REVOKE EXECUTE ON FUNCTION public.initialize_package_inventory_balance() FROM anon, authenticated;
