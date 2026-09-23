-- WASEL One RADIUS credential, authorization, and accounting control plane.
-- Initiative: WASEL-ONE-RADIUS-001

CREATE TABLE public.radius_access_credentials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entitlement_id UUID NOT NULL,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    username TEXT NOT NULL,
    secret_hash TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    expires_at TIMESTAMPTZ NOT NULL,
    last_authenticated_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_radius_credential_entitlement_user FOREIGN KEY (entitlement_id, user_id)
        REFERENCES public.access_entitlements(id, user_id) ON DELETE RESTRICT,
    CONSTRAINT chk_radius_credential_username CHECK (username ~ '^w1-[0-9a-f]{24}$'),
    CONSTRAINT chk_radius_credential_hash CHECK (secret_hash LIKE '$2%'),
    CONSTRAINT chk_radius_credential_status CHECK (status IN ('active', 'revoked', 'expired')),
    CONSTRAINT chk_radius_credential_expiry CHECK (expires_at > created_at)
);

CREATE UNIQUE INDEX uq_radius_access_credentials_username
    ON public.radius_access_credentials (lower(username));
CREATE INDEX idx_radius_access_credentials_entitlement
    ON public.radius_access_credentials (entitlement_id, status, expires_at);
CREATE TRIGGER trg_radius_access_credentials_updated_at
    BEFORE UPDATE ON public.radius_access_credentials
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.radius_access_credentials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.radius_access_credentials FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.radius_access_credentials FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.radius_access_credentials TO service_role;

ALTER TABLE public.access_sessions ADD COLUMN authorization_request_id UUID;
CREATE UNIQUE INDEX uq_access_sessions_authorization_request
    ON public.access_sessions (access_node_id, authorization_request_id)
    WHERE authorization_request_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.issue_radius_access_credential(p_entitlement_id UUID)
RETURNS JSONB AS $$
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
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions, pg_temp;
REVOKE EXECUTE ON FUNCTION public.issue_radius_access_credential(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.issue_radius_access_credential(UUID) TO authenticated;

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

    UPDATE public.radius_access_credentials SET last_authenticated_at = NOW(), updated_at = NOW()
    WHERE id = v_credential.id;
    v_timeout := GREATEST(1, LEAST(2147483647,
        floor(extract(epoch FROM (v_entitlement.expires_at - NOW())))::INTEGER));
    RETURN jsonb_build_object(
        'accepted', TRUE, 'session_id', v_session_id,
        'session_timeout', v_timeout, 'idle_timeout', 300,
        'speed_limit_kbps', v_entitlement.speed_limit_kbps,
        'remaining_bytes', CASE WHEN v_entitlement.allowance_bytes IS NULL THEN NULL
            ELSE v_entitlement.allowance_bytes - v_entitlement.consumed_bytes END
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions, pg_temp;
REVOKE EXECUTE ON FUNCTION public.radius_authorize_access(TEXT, TEXT, TEXT, UUID, TEXT)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.radius_authorize_access(TEXT, TEXT, TEXT, UUID, TEXT)
    TO service_role;

CREATE OR REPLACE FUNCTION public.radius_record_accounting(
    p_session_id UUID, p_nas_identifier TEXT, p_event_key TEXT,
    p_event_type TEXT, p_event_at TIMESTAMPTZ, p_input_bytes BIGINT,
    p_output_bytes BIGINT, p_session_seconds INTEGER
)
RETURNS JSONB AS $$
DECLARE
    v_session public.access_sessions%ROWTYPE;
    v_entitlement public.access_entitlements%ROWTYPE;
    v_plan_network public.federated_plan_networks%ROWTYPE;
    v_total_bytes BIGINT;
    v_delta_bytes BIGINT;
    v_quantity NUMERIC(20, 6);
    v_amount INTEGER;
BEGIN
    IF p_event_type NOT IN ('start', 'interim_update', 'stop')
       OR p_event_key IS NULL OR length(trim(p_event_key)) = 0
       OR p_event_at IS NULL OR p_event_at > NOW() + INTERVAL '5 minutes'
       OR p_input_bytes < 0 OR p_output_bytes < 0 OR p_session_seconds < 0
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
        v_quantity := CASE v_plan_network.compensation_model
            WHEN 'per_gib' THEN round(v_total_bytes::NUMERIC / 1073741824, 6)
            WHEN 'per_minute' THEN round(p_session_seconds::NUMERIC / 60, 6)
            ELSE 1::NUMERIC END;
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
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions, pg_temp;
REVOKE EXECUTE ON FUNCTION public.radius_record_accounting(
    UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ, BIGINT, BIGINT, INTEGER
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.radius_record_accounting(
    UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ, BIGINT, BIGINT, INTEGER
) TO service_role;
