-- WASEL One RADIUS credential, authorization, idempotency, and accounting tests.
-- Initiative: WASEL-ONE-RADIUS-001

BEGIN;

DO $$
DECLARE
    v_customer_a UUID := '11100000-0000-4000-8000-000000000001';
    v_customer_b UUID := '11100000-0000-4000-8000-000000000002';
    v_owner UUID := '22200000-0000-4000-8000-000000000001';
    v_admin UUID := '33300000-0000-4000-8000-000000000001';
    v_network UUID := '44400000-0000-4000-8000-000000000001';
    v_plan UUID := '55500000-0000-4000-8000-000000000001';
    v_plan_network UUID := '66600000-0000-4000-8000-000000000001';
    v_node UUID := '77700000-0000-4000-8000-000000000001';
    v_entitlement UUID := '88800000-0000-4000-8000-000000000001';
    v_request UUID := '99900000-0000-4000-8000-000000000001';
    v_credential JSONB;
    v_authorization JSONB;
    v_retry JSONB;
    v_accounting JSONB;
    v_username TEXT;
    v_password TEXT;
    v_session UUID;
    v_count INTEGER;
    v_denied BOOLEAN;
    v_base_time TIMESTAMPTZ := NOW();
BEGIN
    EXECUTE 'SET LOCAL ROLE postgres';

    INSERT INTO auth.users (id, email) VALUES
        (v_customer_a, 'radius-customer-a@example.test'),
        (v_customer_b, 'radius-customer-b@example.test'),
        (v_owner, 'radius-owner@example.test'),
        (v_admin, 'radius-admin@example.test')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.profiles (id, full_name, account_status) VALUES
        (v_customer_a, 'RADIUS Customer A', 'active'),
        (v_customer_b, 'RADIUS Customer B', 'active'),
        (v_owner, 'RADIUS Owner', 'active'),
        (v_admin, 'RADIUS Admin', 'active')
    ON CONFLICT (id) DO UPDATE SET account_status = 'active';

    INSERT INTO public.user_roles (user_id, role) VALUES
        (v_customer_a, 'customer'), (v_customer_b, 'customer'),
        (v_owner, 'network_owner'), (v_admin, 'platform_admin')
    ON CONFLICT (user_id, role) DO NOTHING;

    INSERT INTO public.networks (
        id, commercial_name, status, verification_status,
        created_by, approved_by, approved_at
    ) VALUES (
        v_network, 'WASEL RADIUS Partner', 'active', 'verified',
        v_owner, v_admin, NOW()
    );

    INSERT INTO public.federated_access_plans (
        id, name, retail_price, validity_seconds, quota_bytes,
        speed_limit_kbps, status, is_public, created_by
    ) VALUES (
        v_plan, 'WASEL RADIUS Pilot', 1000, 86400, 1073741824,
        4096, 'active', TRUE, v_admin
    );

    INSERT INTO public.federated_plan_networks (
        id, plan_id, network_id, compensation_model,
        compensation_rate_minor, is_active, created_by
    ) VALUES (
        v_plan_network, v_plan, v_network, 'per_gib', 500, TRUE, v_admin
    );

    INSERT INTO public.network_access_nodes (
        id, network_id, display_name, nas_identifier, status, created_by
    ) VALUES (
        v_node, v_network, 'RADIUS Pilot MikroTik', 'wasel-radius-nas-01', 'active', v_admin
    );

    INSERT INTO public.access_entitlements (
        id, user_id, plan_id, status, starts_at, expires_at,
        allowance_bytes, speed_limit_kbps, source_type, idempotency_key
    ) VALUES (
        v_entitlement, v_customer_a, v_plan, 'active', NOW() - INTERVAL '1 minute',
        NOW() + INTERVAL '1 day', 1073741824, 4096, 'pilot',
        'ccc00000-0000-4000-8000-000000000001'
    );

    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_customer_a::TEXT, TRUE);
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_customer_a::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SELECT public.issue_radius_access_credential(v_entitlement) INTO v_credential;
    v_username := v_credential->>'username';
    v_password := v_credential->>'password';
    IF v_username !~ '^w1-[0-9a-f]{24}$' OR length(v_password) < 20 THEN
        RAISE EXCEPTION 'TEST_FAIL (CREDENTIAL-01): malformed issued credential.';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', v_customer_b::TEXT, TRUE);
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_customer_b::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    v_denied := FALSE;
    BEGIN
        PERFORM public.issue_radius_access_credential(v_entitlement);
    EXCEPTION WHEN OTHERS THEN
        v_denied := TRUE;
    END;
    IF NOT v_denied THEN
        RAISE EXCEPTION 'TEST_FAIL (CREDENTIAL-02): cross-customer issuance allowed.';
    END IF;

    v_denied := FALSE;
    BEGIN
        PERFORM public.radius_authorize_access(
            'wasel-radius-nas-01', v_username, v_password, v_request, NULL
        );
    EXCEPTION WHEN OTHERS THEN
        v_denied := TRUE;
    END;
    IF NOT v_denied THEN
        RAISE EXCEPTION 'TEST_FAIL (AUTHZ-01): client executed service-only authorization.';
    END IF;

    EXECUTE 'SET LOCAL ROLE postgres';
    SELECT COUNT(*) INTO v_count FROM public.radius_access_credentials
    WHERE entitlement_id = v_entitlement
      AND secret_hash <> v_password
      AND crypt(v_password, secret_hash) = secret_hash;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (CREDENTIAL-03): credential hash contract failed.';
    END IF;

    EXECUTE 'SET LOCAL ROLE service_role';
    PERFORM set_config('request.jwt.claim.sub', '', TRUE);
    PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', TRUE);

    v_denied := FALSE;
    BEGIN
        PERFORM public.radius_authorize_access(
            'wasel-radius-nas-01', v_username, 'WRONG_TEST_PASSWORD',
            '99900000-0000-4000-8000-000000000099', NULL
        );
    EXCEPTION WHEN OTHERS THEN
        v_denied := TRUE;
    END;
    IF NOT v_denied THEN
        RAISE EXCEPTION 'TEST_FAIL (AUTHZ-02): wrong password accepted.';
    END IF;

    SELECT public.radius_authorize_access(
        'wasel-radius-nas-01', v_username, v_password, v_request, repeat('a', 64)
    ) INTO v_authorization;
    IF NOT (v_authorization->>'accepted')::BOOLEAN THEN
        RAISE EXCEPTION 'TEST_FAIL (AUTHZ-03): valid credential rejected.';
    END IF;
    v_session := (v_authorization->>'session_id')::UUID;

    SELECT public.radius_authorize_access(
        'wasel-radius-nas-01', v_username, v_password, v_request, repeat('a', 64)
    ) INTO v_retry;
    IF (v_retry->>'session_id')::UUID <> v_session THEN
        RAISE EXCEPTION 'TEST_FAIL (AUTHZ-04): retry created a different session.';
    END IF;

    EXECUTE 'SET LOCAL ROLE postgres';
    SELECT COUNT(*) INTO v_count FROM public.access_sessions
    WHERE access_node_id = v_node AND authorization_request_id = v_request;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (AUTHZ-05): authorization retry duplicated session.';
    END IF;

    EXECUTE 'SET LOCAL ROLE service_role';
    SELECT public.radius_record_accounting(
        v_session, 'wasel-radius-nas-01', 'radius-01:start', 'start',
        v_base_time, 0, 0, 0
    ) INTO v_accounting;
    SELECT public.radius_record_accounting(
        v_session, 'wasel-radius-nas-01', 'radius-01:interim:60', 'interim_update',
        v_base_time + INTERVAL '1 second', 1048576, 2097152, 60
    ) INTO v_accounting;
    SELECT public.radius_record_accounting(
        v_session, 'wasel-radius-nas-01', 'radius-01:stop', 'stop',
        v_base_time + INTERVAL '2 seconds', 2097152, 4194304, 120
    ) INTO v_accounting;
    IF (v_accounting->>'delta_bytes')::BIGINT <> 3145728 THEN
        RAISE EXCEPTION 'TEST_FAIL (ACCT-01): final accounting delta is wrong.';
    END IF;

    SELECT public.radius_record_accounting(
        v_session, 'wasel-radius-nas-01', 'radius-01:stop', 'stop',
        v_base_time + INTERVAL '2 seconds', 2097152, 4194304, 120
    ) INTO v_accounting;
    IF NOT (v_accounting->>'replayed')::BOOLEAN THEN
        RAISE EXCEPTION 'TEST_FAIL (ACCT-02): replay was not recognized.';
    END IF;

    EXECUTE 'SET LOCAL ROLE postgres';
    SELECT COUNT(*) INTO v_count FROM public.radius_accounting_events
    WHERE session_id = v_session;
    IF v_count <> 3 THEN
        RAISE EXCEPTION 'TEST_FAIL (ACCT-03): expected exactly three accounting events.';
    END IF;
    SELECT COUNT(*) INTO v_count FROM public.partner_usage_ledger
    WHERE session_id = v_session AND entry_type = 'accrual';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (LEDGER-01): expected exactly one partner accrual.';
    END IF;
    IF (SELECT status FROM public.access_sessions WHERE id = v_session) <> 'closed' THEN
        RAISE EXCEPTION 'TEST_FAIL (ACCT-04): stop did not close the session.';
    END IF;
    IF (SELECT consumed_bytes FROM public.access_entitlements WHERE id = v_entitlement) <> 6291456 THEN
        RAISE EXCEPTION 'TEST_FAIL (ACCT-05): entitlement consumption is wrong.';
    END IF;
END;
$$;

ROLLBACK;
