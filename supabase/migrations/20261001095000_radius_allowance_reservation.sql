-- RADIUS data allowance reservation (follow-up to review finding H-5).
--
-- radius_authorize_access returned the whole remaining allowance to every new
-- session. With max_concurrent_sessions > 1, each concurrent session could
-- therefore spend the full remainder (Mikrotik-Total-Limit caps one session,
-- not their sum). Sessions now reserve their grant: a new session receives
-- only the allowance that is neither consumed nor reserved by other live
-- sessions, so the sum of grants never exceeds the allowance and no
-- server-initiated disconnect (CoA) is needed.

ALTER TABLE public.access_sessions
    ADD COLUMN IF NOT EXISTS granted_bytes BIGINT;
ALTER TABLE public.access_sessions
    DROP CONSTRAINT IF EXISTS chk_access_sessions_granted_bytes_positive;
ALTER TABLE public.access_sessions
    ADD CONSTRAINT chk_access_sessions_granted_bytes_positive
    CHECK (granted_bytes IS NULL OR granted_bytes > 0);
COMMENT ON COLUMN public.access_sessions.granted_bytes IS
    'Data allowance reserved for this session at authorization (Mikrotik-Total-Limit). NULL for unlimited entitlements.';

CREATE OR REPLACE FUNCTION public.radius_authorize_access(
    p_nas_identifier TEXT,
    p_username TEXT,
    p_password TEXT,
    p_authorization_request_id UUID,
    p_device_fingerprint_hash TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
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
        IF (SELECT COUNT(*) FROM public.access_sessions
            WHERE entitlement_id = v_entitlement.id
              AND (status = 'active'
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
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions, pg_temp;
REVOKE EXECUTE ON FUNCTION public.radius_authorize_access(TEXT, TEXT, TEXT, UUID, TEXT)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.radius_authorize_access(TEXT, TEXT, TEXT, UUID, TEXT)
    TO service_role;
