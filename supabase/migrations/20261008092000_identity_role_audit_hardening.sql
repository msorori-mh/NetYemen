-- Identity, role and audit hardening.

-- 1. Role changes only through the audited RPCs ------------------------------
-- admin_set_user_platform_role / admin_replace_user_platform_roles block
-- self-lockout and removal of the last administrator and write an audit event.
-- The original direct-DML policy bypassed all three, and let one administrator
-- quietly create a second finance account to defeat the two-reviewer rules.
DROP POLICY IF EXISTS user_roles_admin_manage_policy ON public.user_roles;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.user_roles FROM authenticated;

-- 2. Append-only tables really are append-only -------------------------------
CREATE OR REPLACE FUNCTION public.prevent_append_only_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    RAISE EXCEPTION 'MUTATION_FORBIDDEN: % is append-only (% blocked).', TG_TABLE_NAME, TG_OP
        USING ERRCODE = '42501';
END;
$$;
REVOKE EXECUTE ON FUNCTION public.prevent_append_only_mutation() FROM PUBLIC, anon, authenticated;

-- TRUNCATE skips row triggers; block it at statement level for every role.
DROP TRIGGER IF EXISTS trg_audit_events_no_truncate ON public.audit_events;
CREATE TRIGGER trg_audit_events_no_truncate
    BEFORE TRUNCATE ON public.audit_events
    FOR EACH STATEMENT EXECUTE FUNCTION public.prevent_append_only_mutation();

-- The wallet ledger had no protection at all beyond missing client grants.
DROP TRIGGER IF EXISTS trg_customer_wallet_ledger_append_only ON public.customer_wallet_ledger;
CREATE TRIGGER trg_customer_wallet_ledger_append_only
    BEFORE UPDATE OR DELETE ON public.customer_wallet_ledger
    FOR EACH ROW EXECUTE FUNCTION public.prevent_append_only_mutation();

DROP TRIGGER IF EXISTS trg_customer_wallet_ledger_no_truncate ON public.customer_wallet_ledger;
CREATE TRIGGER trg_customer_wallet_ledger_no_truncate
    BEFORE TRUNCATE ON public.customer_wallet_ledger
    FOR EACH STATEMENT EXECUTE FUNCTION public.prevent_append_only_mutation();

REVOKE TRUNCATE ON TABLE public.audit_events, public.customer_wallet_ledger FROM service_role;

-- 3. Cheaper RLS: the role check only reads tables, so it is STABLE ----------
ALTER FUNCTION public.has_platform_role(TEXT) STABLE;

-- 4. A verified network keeps the identity that was verified -----------------
CREATE OR REPLACE FUNCTION public.protect_network_admin_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT public.has_platform_role('platform_admin') THEN
        IF NEW.status IS DISTINCT FROM OLD.status OR
           NEW.verification_status IS DISTINCT FROM OLD.verification_status OR
           NEW.approved_by IS DISTINCT FROM OLD.approved_by OR
           NEW.approved_at IS DISTINCT FROM OLD.approved_at OR
           NEW.created_by IS DISTINCT FROM OLD.created_by THEN
            RAISE EXCEPTION 'MUTATION_FORBIDDEN: Non-admin users cannot modify network administrative fields (status, verification_status, approved_by, approved_at, created_by).'
                USING ERRCODE = '42501';
        END IF;

        -- The public name is what the administrator verified. Renaming a
        -- verified network would let it impersonate another one.
        IF OLD.verification_status = 'verified'
           AND NEW.commercial_name IS DISTINCT FROM OLD.commercial_name THEN
            RAISE EXCEPTION 'REVERIFICATION_REQUIRED: The name of a verified network can only be changed by a platform administrator.'
                USING ERRCODE = '42501';
        END IF;

        IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
            RAISE EXCEPTION 'MUTATION_FORBIDDEN: created_at cannot be modified.' USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

-- 5. Cancel/review race on network addition requests -------------------------
CREATE OR REPLACE FUNCTION public.cancel_network_addition_request(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_user_id UUID;
    v_current_status TEXT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    -- Require active profile
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = v_user_id AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'INACTIVE_PROFILE: Account is not active.'
            USING ERRCODE = '42501';
    END IF;

    -- Only the requester can cancel their own submitted request
    SELECT status INTO v_current_status
    FROM public.network_addition_requests
    WHERE id = p_request_id
      AND requester_user_id = v_user_id;

    IF v_current_status IS NULL THEN
        RAISE EXCEPTION 'NOT_FOUND: Request not found or not owned by caller.'
            USING ERRCODE = '42501';
    END IF;

    IF v_current_status != 'submitted' THEN
        RAISE EXCEPTION 'INVALID_STATE: Only submitted requests can be cancelled.'
            USING ERRCODE = '42501';
    END IF;

    UPDATE public.network_addition_requests
    SET status = 'cancelled',
        updated_at = NOW()
    WHERE id = p_request_id
      AND requester_user_id = v_user_id
      AND status = 'submitted';

    -- A reviewer may have picked the request up between the read and the write.
    IF NOT FOUND THEN
        RAISE EXCEPTION 'INVALID_STATE: Only submitted requests can be cancelled.'
            USING ERRCODE = '42501';
    END IF;

    RETURN jsonb_build_object('id', p_request_id, 'status', 'cancelled');
END;
$function$;

-- 6. Administrator identity changes are serialized ---------------------------
CREATE OR REPLACE FUNCTION public.admin_set_user_platform_role(p_user_id uuid, p_role text, p_enabled boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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

    -- Serialize administrator identity changes so two admins cannot remove
    -- each other at the same moment and leave the platform without one.
    PERFORM pg_advisory_xact_lock(hashtextextended('netyemen.admin_identity_change', 0));

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
$function$;

CREATE OR REPLACE FUNCTION public.admin_replace_user_platform_roles(p_user_id uuid, p_roles text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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

    -- Serialize administrator identity changes so two admins cannot remove
    -- each other at the same moment and leave the platform without one.
    PERFORM pg_advisory_xact_lock(hashtextextended('netyemen.admin_identity_change', 0));

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
$function$;

CREATE OR REPLACE FUNCTION public.admin_set_user_account_status(p_user_id uuid, p_status text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_actor_id UUID := auth.uid();
    v_previous_status TEXT;
    v_changed BOOLEAN := FALSE;
    v_row_count INTEGER := 0;
BEGIN
    PERFORM public.admin_require_role_and_profile(ARRAY['platform_admin']);

    -- Serialize administrator identity changes so two admins cannot remove
    -- each other at the same moment and leave the platform without one.
    PERFORM pg_advisory_xact_lock(hashtextextended('netyemen.admin_identity_change', 0));

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

    -- Deletion is one-way: an anonymized account is never brought back, and
    -- an account that is closing is only reopened by its owner cancelling.
    IF v_previous_status IN ('anonymized', 'closure_pending') THEN
        RAISE EXCEPTION 'INVALID_STATE: Account status % cannot be changed by an administrator.', v_previous_status
            USING ERRCODE = '22000';
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
$function$;

-- 7. Staff grants only for accounts that are purely Google identities --------
-- 20261001094000 applied a pending staff grant as soon as a Google identity was
-- linked. With email confirmations off, anyone could register the invited
-- address with a password first; when the real person later signed in with
-- Google the identities were linked and the grant landed on an account the
-- attacker still had the password for. A grant now only applies while Google
-- is the ONLY sign-in method of the account.
CREATE OR REPLACE FUNCTION public._is_trusted_grant_identity(
  p_email_confirmed_at timestamptz,
  p_app_meta jsonb
) RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT p_email_confirmed_at IS NOT NULL
     AND CASE
           WHEN jsonb_typeof(p_app_meta -> 'providers') = 'array'
             THEN p_app_meta -> 'providers' = '["google"]'::jsonb
           ELSE p_app_meta ->> 'provider' = 'google'
         END;
$$;
REVOKE EXECUTE ON FUNCTION public._is_trusted_grant_identity(timestamptz, jsonb) FROM PUBLIC, anon, authenticated;

-- 8. Stronger PIN hashing (bcrypt cost 10 instead of pgcrypto's default 6) ---
-- Existing hashes keep verifying; they are upgraded the next time a PIN is set.
CREATE OR REPLACE FUNCTION public.set_account_pin(p_pin text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING errcode = '28000';
  END IF;

  IF p_pin IS NULL OR p_pin !~ '^[0-9]{6}$' THEN
    RAISE EXCEPTION 'INVALID_PIN';
  END IF;

  IF EXISTS (SELECT 1 FROM public.account_pins WHERE user_id = v_user) THEN
    RAISE EXCEPTION 'PIN_ALREADY_SET';
  END IF;

  INSERT INTO public.account_pins (user_id, pin_hash)
  VALUES (v_user, crypt(p_pin, gen_salt('bf', 10)));
END;
$function$;

-- 9. Functions that leaked information to signed-out callers -----------------
REVOKE EXECUTE ON FUNCTION public.get_notification_transport_status() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_card_vault_empty() FROM PUBLIC, anon;
