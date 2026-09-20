-- WASEL NET post-legacy reconciliation lint closure
-- Migration: 20260819193000_netyemen_legacy_rpc_cleanup_and_inventory_lint_fix.sql
--
-- Removes obsolete prototype mutation RPCs after their backing tables were
-- quarantined, and fixes an ambiguous column reference in the V1 inventory RPC.

-- The prototype RPCs are not part of the V1 contract and must not remain
-- callable or lint-invalid. Drop every overload by catalog identity.
DO $$
DECLARE
    v_function REGPROCEDURE;
BEGIN
    FOR v_function IN
        SELECT p.oid::regprocedure
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN ('process_deposit', 'purchase_card')
    LOOP
        EXECUTE format('DROP FUNCTION %s', v_function);
    END LOOP;
END
$$;

CREATE OR REPLACE FUNCTION public.get_owned_networks()
RETURNS TABLE (
    id UUID,
    commercial_name TEXT,
    description TEXT,
    governorate TEXT,
    city TEXT,
    district TEXT,
    status TEXT,
    verification_status TEXT
) AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.profiles AS active_profile
        WHERE active_profile.id = v_user_id
          AND active_profile.account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'INACTIVE_PROFILE: Account is not active.'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        n.id,
        n.commercial_name,
        n.description,
        n.governorate,
        n.city,
        n.district,
        n.status,
        n.verification_status
    FROM public.networks AS n
    JOIN public.network_memberships AS nm ON nm.network_id = n.id
    JOIN public.profiles AS p ON p.id = nm.user_id
    JOIN public.user_roles AS ur
      ON ur.user_id = nm.user_id
     AND ur.role = 'network_owner'
    WHERE nm.user_id = v_user_id
      AND nm.membership_role = 'owner'
      AND nm.status = 'active'
      AND p.account_status = 'active'
    ORDER BY n.commercial_name;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.get_owned_networks() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_owned_networks() TO authenticated;
