-- WASEL One: session and accounting hardening.
--
--  * A session that lost its Accounting-Stop held its concurrency slot forever
--    and locked the customer out. Stale sessions no longer count and are closed
--    by radius_close_stale_sessions().
--  * Partner accruals were computed from whatever the partner's own router
--    reported, without any bound. They are now capped by what the platform
--    granted and by wall-clock time.
--  * Suspended, closing and deleted accounts could still issue credentials and
--    authenticate.
--  * Partner compensation terms were readable by anyone, signed in or not.

CREATE OR REPLACE FUNCTION public.radius_authorize_access(p_nas_identifier text, p_username text, p_password text, p_authorization_request_id uuid, p_device_fingerprint_hash text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
    v_node public.network_access_nodes%ROWTYPE;
    v_credential public.radius_access_credentials%ROWTYPE;
    v_entitlement public.access_entitlements%ROWTYPE;
    v_session_id UUID;
    v_timeout INTEGER;
    v_session_grant BIGINT;
    v_session_used BIGINT;
    v_reserved BIGINT;
    v_grant BIGINT;
BEGIN
    IF p_nas_identifier IS NULL OR p_username IS NULL OR p_password IS NULL
       OR p_authorization_request_id IS NULL THEN
        RAISE EXCEPTION 'INVALID_RADIUS_REQUEST' USING ERRCODE = '22023';
    END IF;
    IF p_device_fingerprint_hash IS NOT NULL
       AND p_device_fingerprint_hash !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'INVALID_DEVICE_HASH' USING ERRCODE = '22023';
    END IF;

    SELECT n.* INTO v_node FROM public.network_access_nodes n
    JOIN public.networks network ON network.id = n.network_id
    WHERE lower(n.nas_identifier) = lower(p_nas_identifier)
      AND n.status = 'active' AND network.status = 'active'
      AND network.verification_status = 'verified';
    IF v_node.id IS NULL THEN
        RAISE EXCEPTION 'ACCESS_NODE_NOT_ACTIVE' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_credential FROM public.radius_access_credentials
    WHERE lower(username) = lower(p_username) FOR UPDATE;
    IF v_credential.id IS NULL OR v_credential.status <> 'active'
       OR v_credential.expires_at <= NOW()
       OR crypt(p_password, v_credential.secret_hash) <> v_credential.secret_hash THEN
        RAISE EXCEPTION 'INVALID_RADIUS_CREDENTIAL' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_entitlement FROM public.access_entitlements
    WHERE id = v_credential.entitlement_id FOR UPDATE;
    IF v_entitlement.status <> 'active' OR v_entitlement.starts_at > NOW()
       OR v_entitlement.expires_at <= NOW()
       OR (v_entitlement.allowance_bytes IS NOT NULL
           AND v_entitlement.consumed_bytes >= v_entitlement.allowance_bytes) THEN
        RAISE EXCEPTION 'ENTITLEMENT_NOT_ACTIVE' USING ERRCODE = '42501';
    END IF;
    -- A suspended, closing or deleted account does not get on the network.
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = v_entitlement.user_id AND p.account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'ACCOUNT_NOT_ACTIVE' USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.federated_plan_networks pn
        WHERE pn.plan_id = v_entitlement.plan_id AND pn.network_id = v_node.network_id
          AND pn.is_active AND pn.effective_from <= NOW()
          AND (pn.effective_until IS NULL OR pn.effective_until > NOW())
    ) THEN
        RAISE EXCEPTION 'PLAN_NOT_ACCEPTED_BY_NETWORK' USING ERRCODE = '42501';
    END IF;

    SELECT id INTO v_session_id FROM public.access_sessions
    WHERE access_node_id = v_node.id
      AND authorization_request_id = p_authorization_request_id;
    IF v_session_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.access_sessions
        WHERE id = v_session_id
          AND (status = 'active'
               OR (status = 'authorized' AND grant_expires_at > NOW()))
    ) THEN
        RAISE EXCEPTION 'AUTHORIZATION_REQUEST_CLOSED' USING ERRCODE = '42501';
    END IF;
    IF v_session_id IS NULL THEN
        -- A session whose router went silent for 10 minutes (lost Stop, power
        -- cut, reboot) no longer holds a concurrency slot. Without this a single
        -- lost Stop locked the customer out until the plan expired.
        IF (SELECT COUNT(*) FROM public.access_sessions
            WHERE entitlement_id = v_entitlement.id
              AND ((status = 'active'
                    AND COALESCE(last_accounting_at, started_at, authorized_at)
                        > NOW() - INTERVAL '10 minutes')
                   OR (status = 'authorized' AND grant_expires_at > NOW())))
           >= v_entitlement.max_concurrent_sessions THEN
            RAISE EXCEPTION 'CONCURRENCY_LIMIT_REACHED' USING ERRCODE = '42501';
        END IF;
        INSERT INTO public.access_sessions (
            entitlement_id, user_id, network_id, access_node_id, status,
            device_fingerprint_hash, grant_expires_at, authorization_request_id
        ) VALUES (
            v_entitlement.id, v_entitlement.user_id, v_node.network_id, v_node.id,
            'authorized', p_device_fingerprint_hash, NOW() + INTERVAL '5 minutes',
            p_authorization_request_id
        ) RETURNING id INTO v_session_id;
    END IF;

    -- Data allowance reservation. The entitlement row is locked above, so
    -- concurrent authorizations for one entitlement serialize here. Each
    -- session is granted at most the allowance not yet consumed and not still
    -- reserved by other live sessions; MikroTik enforces the grant through
    -- Mikrotik-Total-Limit. Reservations of sessions silent for 10 minutes
    -- (lost Stop, NAS reboot) are released so they cannot lock the user out.
    IF v_entitlement.allowance_bytes IS NOT NULL THEN
        SELECT granted_bytes, input_bytes + output_bytes
        INTO v_session_grant, v_session_used
        FROM public.access_sessions WHERE id = v_session_id;

        IF v_session_grant IS NOT NULL THEN
            -- Retry of an authorization already granted: same reservation.
            v_grant := v_session_grant - v_session_used;
        ELSE
            SELECT COALESCE(SUM(GREATEST(s.granted_bytes - (s.input_bytes + s.output_bytes), 0)), 0)
            INTO v_reserved
            FROM public.access_sessions s
            WHERE s.entitlement_id = v_entitlement.id
              AND s.id <> v_session_id
              AND s.granted_bytes IS NOT NULL
              AND ((s.status = 'active'
                    AND COALESCE(s.last_accounting_at, s.started_at, s.authorized_at)
                        > NOW() - INTERVAL '10 minutes')
                   OR (s.status = 'authorized' AND s.grant_expires_at > NOW()));

            v_grant := v_entitlement.allowance_bytes - v_entitlement.consumed_bytes - v_reserved;
            IF v_grant > 0 THEN
                UPDATE public.access_sessions SET granted_bytes = v_grant, updated_at = NOW()
                WHERE id = v_session_id;
            END IF;
        END IF;

        IF v_grant IS NULL OR v_grant <= 0 THEN
            RAISE EXCEPTION 'ALLOWANCE_RESERVED_BY_OTHER_SESSIONS' USING ERRCODE = '42501';
        END IF;
    END IF;

    UPDATE public.radius_access_credentials SET last_authenticated_at = NOW(), updated_at = NOW()
    WHERE id = v_credential.id;
    v_timeout := GREATEST(1, LEAST(2147483647,
        floor(extract(epoch FROM (v_entitlement.expires_at - NOW())))::INTEGER));
    RETURN jsonb_build_object(
        'accepted', TRUE, 'session_id', v_session_id,
        'session_timeout', v_timeout, 'idle_timeout', 300,
        'speed_limit_kbps', v_entitlement.speed_limit_kbps,
        'remaining_bytes', v_grant
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.issue_radius_access_credential(p_entitlement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
    v_user_id UUID := auth.uid();
    v_entitlement public.access_entitlements%ROWTYPE;
    v_username TEXT;
    v_password TEXT;
    v_expires_at TIMESTAMPTZ;
    v_credential_id UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = '28000';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles WHERE id = v_user_id AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'INACTIVE_PROFILE: Account is not active.' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_entitlement FROM public.access_entitlements
    WHERE id = p_entitlement_id AND user_id = v_user_id FOR UPDATE;
    IF v_entitlement.id IS NULL THEN
        RAISE EXCEPTION 'ENTITLEMENT_NOT_FOUND' USING ERRCODE = '42501';
    END IF;
    IF v_entitlement.status <> 'active' OR v_entitlement.starts_at > NOW()
       OR v_entitlement.expires_at <= NOW()
       OR (v_entitlement.allowance_bytes IS NOT NULL
           AND v_entitlement.consumed_bytes >= v_entitlement.allowance_bytes) THEN
        RAISE EXCEPTION 'ENTITLEMENT_NOT_ACTIVE' USING ERRCODE = '42501';
    END IF;

    UPDATE public.radius_access_credentials SET status = 'revoked', updated_at = NOW()
    WHERE entitlement_id = p_entitlement_id AND status = 'active';
    v_username := 'w1-' || substr(encode(gen_random_bytes(16), 'hex'), 1, 24);
    v_password := encode(gen_random_bytes(18), 'base64');
    v_expires_at := LEAST(v_entitlement.expires_at, NOW() + INTERVAL '24 hours');
    INSERT INTO public.radius_access_credentials (
        entitlement_id, user_id, username, secret_hash, expires_at
    ) VALUES (
        p_entitlement_id, v_user_id, v_username,
        crypt(v_password, gen_salt('bf', 10)), v_expires_at
    ) RETURNING id INTO v_credential_id;
    RETURN jsonb_build_object(
        'credential_id', v_credential_id, 'username', v_username,
        'password', v_password, 'expires_at', v_expires_at
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.radius_record_accounting(p_session_id uuid, p_nas_identifier text, p_event_key text, p_event_type text, p_event_at timestamp with time zone, p_input_bytes bigint, p_output_bytes bigint, p_session_seconds integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
    v_session public.access_sessions%ROWTYPE;
    v_entitlement public.access_entitlements%ROWTYPE;
    v_plan_network public.federated_plan_networks%ROWTYPE;
    v_total_bytes BIGINT;
    v_delta_bytes BIGINT;
    v_quantity NUMERIC(20, 6);
    v_amount INTEGER;
    v_billable_bytes BIGINT;
    v_billable_seconds BIGINT;
    v_elapsed_seconds BIGINT;
BEGIN
    IF p_event_type NOT IN ('start', 'interim_update', 'stop')
       OR p_event_key IS NULL OR length(trim(p_event_key)) = 0
       OR p_event_at IS NULL OR p_event_at > NOW() + INTERVAL '5 minutes'
       OR p_input_bytes < 0 OR p_output_bytes < 0 OR p_session_seconds < 0
       -- secret-scan: allow-numeric-limit (BIGINT accounting overflow guard)
       OR p_input_bytes > 9000000000000000 OR p_output_bytes > 9000000000000000 THEN
        RAISE EXCEPTION 'INVALID_ACCOUNTING_REQUEST' USING ERRCODE = '22023';
    END IF;
    SELECT s.* INTO v_session FROM public.access_sessions s
    JOIN public.network_access_nodes n ON n.id = s.access_node_id
    WHERE s.id = p_session_id AND lower(n.nas_identifier) = lower(p_nas_identifier)
      AND n.status IN ('active', 'degraded') FOR UPDATE OF s;
    IF v_session.id IS NULL THEN
        RAISE EXCEPTION 'SESSION_NOT_FOUND_FOR_NODE' USING ERRCODE = '42501';
    END IF;
    IF EXISTS (SELECT 1 FROM public.radius_accounting_events
        WHERE access_node_id = v_session.access_node_id AND event_key = p_event_key) THEN
        RETURN jsonb_build_object('accepted', TRUE, 'replayed', TRUE, 'session_id', v_session.id);
    END IF;

    INSERT INTO public.radius_accounting_events (
        session_id, access_node_id, network_id, event_key, event_type,
        event_at, input_bytes, output_bytes, session_seconds
    ) VALUES (
        v_session.id, v_session.access_node_id, v_session.network_id,
        trim(p_event_key), p_event_type, p_event_at,
        p_input_bytes, p_output_bytes, p_session_seconds
    );
    v_total_bytes := p_input_bytes + p_output_bytes;
    v_delta_bytes := GREATEST(0, v_total_bytes - (v_session.input_bytes + v_session.output_bytes));
    UPDATE public.access_sessions SET
        status = CASE WHEN p_event_type = 'stop' THEN 'closed' ELSE 'active' END,
        external_session_id = COALESCE(external_session_id, p_session_id::TEXT),
        started_at = CASE WHEN p_event_type = 'start' THEN COALESCE(started_at, p_event_at)
            ELSE COALESCE(started_at, authorized_at) END,
        last_accounting_at = p_event_at,
        ended_at = CASE WHEN p_event_type = 'stop' THEN p_event_at ELSE ended_at END,
        input_bytes = p_input_bytes, output_bytes = p_output_bytes,
        session_seconds = p_session_seconds,
        close_reason = CASE WHEN p_event_type = 'stop' THEN 'radius_stop' ELSE close_reason END,
        updated_at = NOW()
    WHERE id = v_session.id;

    SELECT * INTO v_entitlement FROM public.access_entitlements
    WHERE id = v_session.entitlement_id FOR UPDATE;
    UPDATE public.access_entitlements SET
        consumed_bytes = CASE WHEN allowance_bytes IS NULL THEN consumed_bytes + v_delta_bytes
            ELSE LEAST(allowance_bytes, consumed_bytes + v_delta_bytes) END,
        status = CASE WHEN allowance_bytes IS NOT NULL
            AND consumed_bytes + v_delta_bytes >= allowance_bytes THEN 'exhausted'
            WHEN expires_at <= NOW() THEN 'expired' ELSE status END,
        updated_at = NOW()
    WHERE id = v_entitlement.id;

    IF p_event_type = 'stop' THEN
        SELECT pn.* INTO v_plan_network FROM public.federated_plan_networks pn
        WHERE pn.plan_id = v_entitlement.plan_id AND pn.network_id = v_session.network_id;
        -- The router reports its own usage, and the partner who owns the
        -- router is paid on it, so a report is never trusted beyond what the
        -- platform itself granted: bytes are capped at the session grant and
        -- time at the wall-clock time since authorization (plus five minutes of
        -- clock skew). A session that carried no traffic and lasted under a
        -- minute earns nothing, so logins cannot be looped to farm per-session
        -- fees.
        v_billable_bytes := LEAST(v_total_bytes, COALESCE(v_session.granted_bytes, v_total_bytes));
        v_elapsed_seconds := GREATEST(0, ceil(extract(epoch FROM (
            LEAST(p_event_at, NOW()) - COALESCE(v_session.started_at, v_session.authorized_at)
        )))::BIGINT) + 300;
        v_billable_seconds := LEAST(p_session_seconds::BIGINT, v_elapsed_seconds);
        v_quantity := CASE v_plan_network.compensation_model
            WHEN 'per_gib' THEN round(v_billable_bytes::NUMERIC / 1073741824, 6)
            WHEN 'per_minute' THEN round(v_billable_seconds::NUMERIC / 60, 6)
            ELSE CASE WHEN v_billable_bytes > 0 OR v_billable_seconds >= 60
                THEN 1::NUMERIC ELSE 0::NUMERIC END
            END;
        v_amount := round(v_quantity * v_plan_network.compensation_rate_minor)::INTEGER;
        INSERT INTO public.partner_usage_ledger (
            network_id, session_id, entitlement_id, plan_network_id,
            quantity, unit, rate_minor, amount_minor, idempotency_key
        ) VALUES (
            v_session.network_id, v_session.id, v_entitlement.id, v_plan_network.id,
            v_quantity, CASE v_plan_network.compensation_model
                WHEN 'per_gib' THEN 'gib' WHEN 'per_minute' THEN 'minute'
                ELSE 'session' END,
            v_plan_network.compensation_rate_minor, v_amount, gen_random_uuid()
        ) ON CONFLICT (session_id, entry_type) DO NOTHING;
    END IF;
    RETURN jsonb_build_object('accepted', TRUE, 'replayed', FALSE,
        'session_id', v_session.id, 'delta_bytes', v_delta_bytes);
END;
$function$;

-- Close sessions whose router stopped reporting. Safe to run at any time and
-- from a scheduler; a later Stop for a closed session is still recorded.
CREATE OR REPLACE FUNCTION public.radius_close_stale_sessions(
    p_idle INTERVAL DEFAULT INTERVAL '30 minutes'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_closed INTEGER;
    v_expired INTEGER;
BEGIN
    IF p_idle IS NULL OR p_idle < INTERVAL '10 minutes' THEN
        RAISE EXCEPTION 'INVALID_IDLE_INTERVAL: Idle interval must be at least 10 minutes.' USING ERRCODE = '22023';
    END IF;

    UPDATE public.access_sessions
    SET status = 'closed',
        ended_at = GREATEST(
            COALESCE(last_accounting_at, started_at, authorized_at),
            COALESCE(started_at, authorized_at)
        ),
        close_reason = 'stale_timeout',
        updated_at = NOW()
    WHERE status = 'active'
      AND COALESCE(last_accounting_at, started_at, authorized_at) < NOW() - p_idle;
    GET DIAGNOSTICS v_closed = ROW_COUNT;

    -- Authorizations the router never followed up with an Accounting-Start.
    UPDATE public.access_sessions
    SET status = 'rejected',
        close_reason = 'authorization_expired',
        updated_at = NOW()
    WHERE status = 'authorized'
      AND grant_expires_at < NOW() - p_idle;
    GET DIAGNOSTICS v_expired = ROW_COUNT;

    RETURN jsonb_build_object('closed_stale', v_closed, 'expired_authorizations', v_expired);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.radius_close_stale_sessions(INTERVAL) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.radius_close_stale_sessions(INTERVAL) TO service_role;

-- Partner compensation terms are commercial terms between the platform and a
-- network. Customers and signed-out visitors only need to know which networks
-- accept a plan. Staff read the terms through service tooling.
REVOKE SELECT ON TABLE public.federated_plan_networks FROM anon, authenticated;
GRANT SELECT (id, plan_id, network_id, is_active, effective_from, effective_until, created_at, updated_at)
    ON TABLE public.federated_plan_networks TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_network_compensation_terms(p_network_id UUID)
RETURNS TABLE (
    plan_id UUID,
    compensation_model TEXT,
    compensation_rate_minor INTEGER,
    is_active BOOLEAN,
    effective_from TIMESTAMPTZ,
    effective_until TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.' USING ERRCODE = '28000';
    END IF;
    IF NOT (public.is_finance_or_admin() OR public.can_manage_network(p_network_id)) THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE: Only the network owner or platform staff can read compensation terms.'
            USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
        SELECT pn.plan_id, pn.compensation_model, pn.compensation_rate_minor,
               pn.is_active, pn.effective_from, pn.effective_until
        FROM public.federated_plan_networks pn
        WHERE pn.network_id = p_network_id
        ORDER BY pn.effective_from DESC;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_network_compensation_terms(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_network_compensation_terms(UUID) TO authenticated;
