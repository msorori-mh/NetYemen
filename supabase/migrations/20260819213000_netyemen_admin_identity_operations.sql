-- NetYemen V1 Admin Identity Operations
-- Migration: 20260819213000_netyemen_admin_identity_operations.sql
-- Scope: audited, fail-closed platform-role and account-status administration.

CREATE OR REPLACE FUNCTION public.admin_set_user_platform_role(
    p_user_id UUID,
    p_role TEXT,
    p_enabled BOOLEAN
)
RETURNS JSONB AS $$
DECLARE
    v_actor_id UUID := auth.uid();
    v_allowed_roles CONSTANT TEXT[] := ARRAY[
        'finance_officer',
        'support_agent',
        'platform_admin',
        'system_auditor'
    ];
    v_changed BOOLEAN := FALSE;
    v_row_count INTEGER := 0;
BEGIN
    PERFORM public.admin_require_role_and_profile(ARRAY['platform_admin']);

    IF p_user_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.profiles WHERE id = p_user_id
    ) THEN
        RAISE EXCEPTION 'NOT_FOUND: User profile not found.'
            USING ERRCODE = 'P0002';
    END IF;

    IF p_role IS NULL OR NOT (p_role = ANY(v_allowed_roles)) THEN
        RAISE EXCEPTION 'INVALID_ROLE: Role is not administratively assignable.'
            USING ERRCODE = '22023';
    END IF;

    IF p_role = 'platform_admin' AND p_enabled = FALSE THEN
        IF p_user_id = v_actor_id THEN
            RAISE EXCEPTION 'SELF_LOCKOUT_BLOCKED: An administrator cannot remove their own platform_admin role.'
                USING ERRCODE = '42501';
        END IF;

        IF (
            SELECT COUNT(*)
            FROM public.user_roles ur
            JOIN public.profiles p ON p.id = ur.user_id
            WHERE ur.role = 'platform_admin'
              AND p.account_status = 'active'
        ) <= 1 THEN
            RAISE EXCEPTION 'LAST_ADMIN_BLOCKED: The final active platform administrator cannot be removed.'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    IF p_enabled THEN
        INSERT INTO public.user_roles (user_id, role, created_by)
        VALUES (p_user_id, p_role, v_actor_id)
        ON CONFLICT (user_id, role) DO NOTHING;
        GET DIAGNOSTICS v_row_count = ROW_COUNT;
        v_changed := v_row_count > 0;
    ELSE
        DELETE FROM public.user_roles
        WHERE user_id = p_user_id AND role = p_role;
        GET DIAGNOSTICS v_row_count = ROW_COUNT;
        v_changed := v_row_count > 0;
    END IF;

    PERFORM public.record_audit_event(
        CASE WHEN p_enabled THEN 'ADMIN_GRANT_PLATFORM_ROLE' ELSE 'ADMIN_REVOKE_PLATFORM_ROLE' END,
        'user',
        p_user_id::TEXT,
        'success',
        'ADMIN_IDENTITY',
        jsonb_build_object(
            'role', p_role,
            'enabled', p_enabled,
            'changed', v_changed
        )
    );

    RETURN jsonb_build_object(
        'user_id', p_user_id,
        'role', p_role,
        'enabled', p_enabled,
        'changed', v_changed
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.admin_set_user_platform_role(UUID, TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_user_platform_role(UUID, TEXT, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_user_account_status(
    p_user_id UUID,
    p_status TEXT,
    p_reason TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_actor_id UUID := auth.uid();
    v_previous_status TEXT;
    v_changed BOOLEAN := FALSE;
    v_row_count INTEGER := 0;
BEGIN
    PERFORM public.admin_require_role_and_profile(ARRAY['platform_admin']);

    IF p_status IS NULL OR p_status NOT IN ('active', 'suspended', 'pending_verification') THEN
        RAISE EXCEPTION 'INVALID_STATUS: Unsupported account status.'
            USING ERRCODE = '22023';
    END IF;

    IF p_reason IS NOT NULL AND char_length(trim(p_reason)) > 500 THEN
        RAISE EXCEPTION 'REASON_TOO_LONG: Reason exceeds 500 characters.'
            USING ERRCODE = '22001';
    END IF;

    SELECT account_status
    INTO v_previous_status
    FROM public.profiles
    WHERE id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND: User profile not found.'
            USING ERRCODE = 'P0002';
    END IF;

    IF p_user_id = v_actor_id AND p_status <> 'active' THEN
        RAISE EXCEPTION 'SELF_LOCKOUT_BLOCKED: An administrator cannot deactivate their own account.'
            USING ERRCODE = '42501';
    END IF;

    IF p_status <> 'active'
       AND EXISTS (
           SELECT 1 FROM public.user_roles
           WHERE user_id = p_user_id AND role = 'platform_admin'
       )
       AND (
           SELECT COUNT(*)
           FROM public.user_roles ur
           JOIN public.profiles p ON p.id = ur.user_id
           WHERE ur.role = 'platform_admin'
             AND p.account_status = 'active'
       ) <= 1 THEN
        RAISE EXCEPTION 'LAST_ADMIN_BLOCKED: The final active platform administrator cannot be deactivated.'
            USING ERRCODE = '42501';
    END IF;

    UPDATE public.profiles
    SET account_status = p_status
    WHERE id = p_user_id
      AND account_status IS DISTINCT FROM p_status;
    GET DIAGNOSTICS v_row_count = ROW_COUNT;
        v_changed := v_row_count > 0;

    PERFORM public.record_audit_event(
        'ADMIN_SET_ACCOUNT_STATUS',
        'user',
        p_user_id::TEXT,
        'success',
        'ADMIN_IDENTITY',
        jsonb_build_object(
            'previous_status', v_previous_status,
            'new_status', p_status,
            'reason', NULLIF(trim(p_reason), ''),
            'changed', v_changed
        )
    );

    RETURN jsonb_build_object(
        'user_id', p_user_id,
        'previous_status', v_previous_status,
        'account_status', p_status,
        'changed', v_changed
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.admin_set_user_account_status(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_user_account_status(UUID, TEXT, TEXT) TO authenticated;


CREATE OR REPLACE FUNCTION public.admin_replace_user_platform_roles(
    p_user_id UUID,
    p_roles TEXT[]
)
RETURNS JSONB AS $$
DECLARE
    v_actor_id UUID := auth.uid();
    v_allowed_roles CONSTANT TEXT[] := ARRAY[
        'finance_officer',
        'support_agent',
        'platform_admin',
        'system_auditor'
    ];
    v_requested_roles TEXT[];
    v_had_admin BOOLEAN;
    v_will_have_admin BOOLEAN;
BEGIN
    PERFORM public.admin_require_role_and_profile(ARRAY['platform_admin']);

    IF p_user_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.profiles WHERE id = p_user_id
    ) THEN
        RAISE EXCEPTION 'NOT_FOUND: User profile not found.'
            USING ERRCODE = 'P0002';
    END IF;

    SELECT COALESCE(array_agg(DISTINCT role ORDER BY role), ARRAY[]::TEXT[])
    INTO v_requested_roles
    FROM unnest(COALESCE(p_roles, ARRAY[]::TEXT[])) AS requested(role);

    IF EXISTS (
        SELECT 1
        FROM unnest(v_requested_roles) AS requested(role)
        WHERE NOT (role = ANY(v_allowed_roles))
    ) THEN
        RAISE EXCEPTION 'INVALID_ROLE: One or more roles are not administratively assignable.'
            USING ERRCODE = '22023';
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.user_roles
        WHERE user_id = p_user_id AND role = 'platform_admin'
    ) INTO v_had_admin;
    v_will_have_admin := 'platform_admin' = ANY(v_requested_roles);

    IF v_had_admin AND NOT v_will_have_admin THEN
        IF p_user_id = v_actor_id THEN
            RAISE EXCEPTION 'SELF_LOCKOUT_BLOCKED: An administrator cannot remove their own platform_admin role.'
                USING ERRCODE = '42501';
        END IF;

        IF (
            SELECT COUNT(*)
            FROM public.user_roles ur
            JOIN public.profiles p ON p.id = ur.user_id
            WHERE ur.role = 'platform_admin'
              AND p.account_status = 'active'
        ) <= 1 THEN
            RAISE EXCEPTION 'LAST_ADMIN_BLOCKED: The final active platform administrator cannot be removed.'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    DELETE FROM public.user_roles
    WHERE user_id = p_user_id
      AND role = ANY(v_allowed_roles);

    INSERT INTO public.user_roles (user_id, role, created_by)
    SELECT p_user_id, requested.role, v_actor_id
    FROM unnest(v_requested_roles) AS requested(role);

    PERFORM public.record_audit_event(
        'ADMIN_REPLACE_PLATFORM_ROLES',
        'user',
        p_user_id::TEXT,
        'success',
        'ADMIN_IDENTITY',
        jsonb_build_object('roles', to_jsonb(v_requested_roles))
    );

    RETURN jsonb_build_object(
        'user_id', p_user_id,
        'roles', to_jsonb(v_requested_roles)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.admin_replace_user_platform_roles(UUID, TEXT[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_replace_user_platform_roles(UUID, TEXT[]) TO authenticated;
