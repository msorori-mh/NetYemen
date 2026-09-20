-- NetYemen V1 Admin Operations Migration
-- Migration: 20260729090000_netyemen_admin_operations.sql
-- Task ID: NY-V1-ADMIN-OPS-001
-- Scope: Controlled admin/support/auditor RPCs for pilot operations.
-- Governance: No card secrets, no payments, no generic authenticated bypass.

-- ============================================================================
-- 1. Helper: enforce active profile and a required platform role
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admin_require_role_and_profile(p_allowed_roles TEXT[])
RETURNS VOID AS $$
DECLARE
    v_user_id UUID;
    v_active BOOLEAN;
    v_has_role BOOLEAN;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    SELECT account_status = 'active' INTO v_active
    FROM public.profiles
    WHERE id = v_user_id;

    IF v_active IS NULL OR v_active = FALSE THEN
        RAISE EXCEPTION 'INACTIVE_PROFILE: Account is not active.'
            USING ERRCODE = '42501';
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM public.user_roles
        WHERE user_id = v_user_id
          AND role = ANY(p_allowed_roles)
    ) INTO v_has_role;

    IF NOT v_has_role THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE: Caller lacks a required platform role (%).', array_to_string(p_allowed_roles, ', ')
            USING ERRCODE = '42501';
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.admin_require_role_and_profile(TEXT[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_require_role_and_profile(TEXT[]) TO authenticated;

-- ============================================================================
-- 2. RPC: Admin dashboard KPIs
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admin_dashboard_kpis()
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_active_networks BIGINT;
    v_pending_requests BIGINT;
    v_approved_requests BIGINT;
    v_rejected_requests BIGINT;
    v_active_packages BIGINT;
    v_out_of_stock_packages BIGINT;
    v_network_owners BIGINT;
    v_network_operators BIGINT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = v_user_id AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'INACTIVE_PROFILE: Account is not active.'
            USING ERRCODE = '42501';
    END IF;

    IF NOT (
        public.has_platform_role('platform_admin')
        OR public.has_platform_role('support_agent')
        OR public.has_platform_role('system_auditor')
    ) THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE: Only platform_admin, support_agent or system_auditor can view admin KPIs.'
            USING ERRCODE = '42501';
    END IF;

    SELECT COUNT(*) INTO v_active_networks
    FROM public.networks
    WHERE status = 'active' AND verification_status = 'verified';

    SELECT COUNT(*) INTO v_pending_requests
    FROM public.network_addition_requests
    WHERE status IN ('submitted', 'under_review');

    SELECT COUNT(*) INTO v_approved_requests
    FROM public.network_addition_requests
    WHERE status = 'approved';

    SELECT COUNT(*) INTO v_rejected_requests
    FROM public.network_addition_requests
    WHERE status = 'rejected';

    SELECT COUNT(*) INTO v_active_packages
    FROM public.network_packages
    WHERE status = 'active';

    SELECT COUNT(*) INTO v_out_of_stock_packages
    FROM public.package_inventory_balances
    WHERE available_units <= 0;

    SELECT COUNT(DISTINCT ur.user_id) INTO v_network_owners
    FROM public.user_roles ur
    JOIN public.profiles p ON p.id = ur.user_id
    WHERE ur.role = 'network_owner' AND p.account_status = 'active';

    SELECT COUNT(DISTINCT ur.user_id) INTO v_network_operators
    FROM public.user_roles ur
    JOIN public.profiles p ON p.id = ur.user_id
    WHERE ur.role = 'network_operator' AND p.account_status = 'active';

    RETURN jsonb_build_object(
        'active_networks', v_active_networks,
        'pending_requests', v_pending_requests,
        'approved_requests', v_approved_requests,
        'rejected_requests', v_rejected_requests,
        'active_packages', v_active_packages,
        'out_of_stock_packages', v_out_of_stock_packages,
        'network_owners', v_network_owners,
        'network_operators', v_network_operators
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.admin_dashboard_kpis() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_dashboard_kpis() TO authenticated;

-- ============================================================================
-- 3. RPC: Approve a pending network
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admin_approve_network(
    p_network_id UUID,
    p_resolution_note TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = v_user_id AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'INACTIVE_PROFILE: Account is not active.'
            USING ERRCODE = '42501';
    END IF;

    IF NOT public.has_platform_role('platform_admin') THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE: Only platform_admin can approve networks.'
            USING ERRCODE = '42501';
    END IF;

    IF p_resolution_note IS NOT NULL AND char_length(p_resolution_note) > 500 THEN
        RAISE EXCEPTION 'NOTE_TOO_LONG: Resolution note exceeds 500 characters.'
            USING ERRCODE = '22000';
    END IF;

    UPDATE public.networks
    SET status = 'active',
        verification_status = 'verified',
        approved_by = v_user_id,
        approved_at = NOW()
    WHERE id = p_network_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND: Network not found.'
            USING ERRCODE = '42501';
    END IF;

    PERFORM public.record_audit_event(
        'ADMIN_APPROVE_NETWORK',
        'network',
        p_network_id::text,
        'success',
        'ADMIN_APPROVE',
        jsonb_build_object('resolution_note', p_resolution_note)
    );

    RETURN jsonb_build_object(
        'id', p_network_id,
        'status', 'active',
        'verification_status', 'verified'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.admin_approve_network(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_approve_network(UUID, TEXT) TO authenticated;

-- ============================================================================
-- 4. RPC: Suspend an active network
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admin_suspend_network(
    p_network_id UUID,
    p_reason TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = v_user_id AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'INACTIVE_PROFILE: Account is not active.'
            USING ERRCODE = '42501';
    END IF;

    IF NOT public.has_platform_role('platform_admin') THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE: Only platform_admin can suspend networks.'
            USING ERRCODE = '42501';
    END IF;

    IF p_reason IS NOT NULL AND char_length(p_reason) > 500 THEN
        RAISE EXCEPTION 'REASON_TOO_LONG: Suspension reason exceeds 500 characters.'
            USING ERRCODE = '22000';
    END IF;

    UPDATE public.networks
    SET status = 'suspended'
    WHERE id = p_network_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND: Network not found.'
            USING ERRCODE = '42501';
    END IF;

    PERFORM public.record_audit_event(
        'ADMIN_SUSPEND_NETWORK',
        'network',
        p_network_id::text,
        'success',
        'ADMIN_SUSPEND',
        jsonb_build_object('reason', p_reason)
    );

    RETURN jsonb_build_object(
        'id', p_network_id,
        'status', 'suspended'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.admin_suspend_network(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_suspend_network(UUID, TEXT) TO authenticated;

-- ============================================================================
-- 5. RPC: Verify an SSID alias
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admin_verify_ssid_alias(
    p_alias_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = v_user_id AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'INACTIVE_PROFILE: Account is not active.'
            USING ERRCODE = '42501';
    END IF;

    IF NOT public.has_platform_role('platform_admin') THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE: Only platform_admin can verify SSID aliases.'
            USING ERRCODE = '42501';
    END IF;

    UPDATE public.network_ssid_aliases
    SET status = 'active',
        verified_by = v_user_id,
        verified_at = NOW()
    WHERE id = p_alias_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND: SSID alias not found.'
            USING ERRCODE = '42501';
    END IF;

    PERFORM public.record_audit_event(
        'ADMIN_VERIFY_SSID_ALIAS',
        'network_ssid_alias',
        p_alias_id::text,
        'success',
        'ADMIN_VERIFY',
        '{}'::jsonb
    );

    RETURN jsonb_build_object(
        'id', p_alias_id,
        'status', 'active'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.admin_verify_ssid_alias(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_verify_ssid_alias(UUID) TO authenticated;

-- ============================================================================
-- 6. RPC: Reject an SSID alias
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admin_reject_ssid_alias(
    p_alias_id UUID,
    p_reason TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = v_user_id AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'INACTIVE_PROFILE: Account is not active.'
            USING ERRCODE = '42501';
    END IF;

    IF NOT public.has_platform_role('platform_admin') THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE: Only platform_admin can reject SSID aliases.'
            USING ERRCODE = '42501';
    END IF;

    IF p_reason IS NOT NULL AND char_length(p_reason) > 500 THEN
        RAISE EXCEPTION 'REASON_TOO_LONG: Rejection reason exceeds 500 characters.'
            USING ERRCODE = '22000';
    END IF;

    UPDATE public.network_ssid_aliases
    SET status = 'rejected'
    WHERE id = p_alias_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND: SSID alias not found.'
            USING ERRCODE = '42501';
    END IF;

    PERFORM public.record_audit_event(
        'ADMIN_REJECT_SSID_ALIAS',
        'network_ssid_alias',
        p_alias_id::text,
        'success',
        'ADMIN_REJECT',
        jsonb_build_object('reason', p_reason)
    );

    RETURN jsonb_build_object(
        'id', p_alias_id,
        'status', 'rejected'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.admin_reject_ssid_alias(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_reject_ssid_alias(UUID, TEXT) TO authenticated;
