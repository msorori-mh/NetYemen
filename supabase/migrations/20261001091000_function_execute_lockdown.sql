-- Function EXECUTE lockdown (review finding H-1).
--
-- 20260730090000_netyemen_acl_hardening.sql revoked default privileges on
-- TABLES only. PostgreSQL grants EXECUTE on every new function to PUBLIC, and
-- Supabase additionally grants it to anon/authenticated, so SECURITY DEFINER
-- helpers created later without an explicit REVOKE are callable through
-- PostgREST (/rest/v1/rpc/...).
--
-- The most dangerous instance is public._apply_access_grant(grant_id, user_id):
-- it inserts arbitrary platform roles (including platform_admin) for any user
-- and performs no caller check, so anyone who learns a pending grant id could
-- grant those roles to themselves.

-- Internal helpers: no client role may call them. They are only invoked from
-- other SECURITY DEFINER functions or as triggers (firing a trigger does not
-- require EXECUTE on its function).
REVOKE EXECUTE ON FUNCTION public._apply_access_grant(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._grantable_roles() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.apply_access_grant_on_signup() FROM PUBLIC, anon, authenticated;

-- Client RPCs: signed-in users only (each function checks its own role).
REVOKE EXECUTE ON FUNCTION public.admin_create_access_grant(text, text[], text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_list_access_grants() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_revoke_access_grant(uuid) FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.has_account_pin() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.set_account_pin(text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.verify_account_pin(text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.request_pin_reset() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_list_pin_reset_requests() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_resolve_pin_reset(uuid, boolean) FROM PUBLIC, anon;

-- Root cause: functions created from now on are not executable by client
-- roles unless a migration grants it explicitly (fail closed).
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;
