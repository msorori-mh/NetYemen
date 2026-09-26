-- WASEL One access federation contract and authorization tests.
-- Initiative: WASEL-ONE-PIVOT-001

BEGIN;

DO $$
DECLARE
    v_customer_a UUID := '11000000-0000-4000-8000-000000000001';
    v_customer_b UUID := '11000000-0000-4000-8000-000000000002';
    v_owner_a UUID := '22000000-0000-4000-8000-000000000001';
    v_owner_b UUID := '22000000-0000-4000-8000-000000000002';
    v_admin UUID := '33000000-0000-4000-8000-000000000001';
    v_network_a UUID := '44000000-0000-4000-8000-000000000001';
    v_network_b UUID := '44000000-0000-4000-8000-000000000002';
    v_plan UUID := '55000000-0000-4000-8000-000000000001';
    v_plan_network UUID := '66000000-0000-4000-8000-000000000001';
    v_node UUID := '77000000-0000-4000-8000-000000000001';
    v_entitlement UUID := '88000000-0000-4000-8000-000000000001';
    v_session UUID := '99000000-0000-4000-8000-000000000001';
    v_event UUID := 'aa000000-0000-4000-8000-000000000001';
    v_ledger UUID := 'bb000000-0000-4000-8000-000000000001';
    v_count INTEGER;
    v_denied BOOLEAN;
BEGIN
    EXECUTE 'SET LOCAL ROLE postgres';

    INSERT INTO auth.users (id, email) VALUES
        (v_customer_a, 'wasel-customer-a@example.test'),
        (v_customer_b, 'wasel-customer-b@example.test'),
        (v_owner_a, 'wasel-owner-a@example.test'),
        (v_owner_b, 'wasel-owner-b@example.test'),
        (v_admin, 'wasel-admin@example.test')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.profiles (id, full_name, account_status) VALUES
        (v_customer_a, 'WASEL Customer A', 'active'),
        (v_customer_b, 'WASEL Customer B', 'active'),
        (v_owner_a, 'WASEL Owner A', 'active'),
        (v_owner_b, 'WASEL Owner B', 'active'),
        (v_admin, 'WASEL Admin', 'active')
    ON CONFLICT (id) DO UPDATE SET account_status = 'active';

    INSERT INTO public.user_roles (user_id, role) VALUES
        (v_customer_a, 'customer'),
        (v_customer_b, 'customer'),
        (v_owner_a, 'network_owner'),
        (v_owner_b, 'network_owner'),
        (v_admin, 'platform_admin')
    ON CONFLICT (user_id, role) DO NOTHING;

    INSERT INTO public.networks (
        id, commercial_name, status, verification_status,
        created_by, approved_by, approved_at
    ) VALUES
        (v_network_a, 'WASEL Partner A', 'active', 'verified', v_owner_a, v_admin, NOW()),
        (v_network_b, 'WASEL Partner B', 'active', 'verified', v_owner_b, v_admin, NOW())
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.network_memberships (
        network_id, user_id, membership_role, status, created_by
    ) VALUES
        (v_network_a, v_owner_a, 'owner', 'active', v_admin),
        (v_network_b, v_owner_b, 'owner', 'active', v_admin)
    ON CONFLICT (network_id, user_id) DO NOTHING;

    INSERT INTO public.federated_access_plans (
        id, name, retail_price, validity_seconds, quota_bytes,
        speed_limit_kbps, status, is_public, created_by
    ) VALUES (
        v_plan, 'WASEL One Pilot', 1000, 86400, 1073741824,
        4096, 'active', TRUE, v_admin
    );

    INSERT INTO public.federated_plan_networks (
        id, plan_id, network_id, compensation_model,
        compensation_rate_minor, is_active, created_by
    ) VALUES (
        v_plan_network, v_plan, v_network_a, 'per_gib', 500, TRUE, v_admin
    );

    INSERT INTO public.network_access_nodes (
        id, network_id, display_name, nas_identifier, status, created_by
    ) VALUES (
        v_node, v_network_a, 'Pilot MikroTik', 'wasel-pilot-nas-01', 'active', v_admin
    );

    INSERT INTO public.access_entitlements (
        id, user_id, plan_id, status, starts_at, expires_at,
        allowance_bytes, speed_limit_kbps, source_type, idempotency_key
    ) VALUES (
        v_entitlement, v_customer_a, v_plan, 'active', NOW(), NOW() + INTERVAL '1 day',
        1073741824, 4096, 'pilot', 'cc000000-0000-4000-8000-000000000001'
    );

    INSERT INTO public.access_sessions (
        id, entitlement_id, user_id, network_id, access_node_id,
        external_session_id, status, grant_expires_at, started_at
    ) VALUES (
        v_session, v_entitlement, v_customer_a, v_network_a, v_node,
        'pilot-session-01', 'active', NOW() + INTERVAL '5 minutes', NOW()
    );

    INSERT INTO public.radius_accounting_events (
        id, session_id, access_node_id, network_id, event_key,
        event_type, event_at, input_bytes, output_bytes, session_seconds
    ) VALUES (
        v_event, v_session, v_node, v_network_a, 'pilot-session-01:start',
        'start', NOW(), 0, 0, 0
    );

    INSERT INTO public.partner_usage_ledger (
        id, network_id, session_id, entitlement_id, plan_network_id,
        quantity, unit, rate_minor, amount_minor, idempotency_key
    ) VALUES (
        v_ledger, v_network_a, v_session, v_entitlement, v_plan_network,
        0.5, 'gib', 500, 250, 'dd000000-0000-4000-8000-000000000001'
    );

    -- Public catalog exposes only the active public plan and participation row.
    EXECUTE 'SET LOCAL ROLE anon';
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
    SELECT COUNT(*) INTO v_count FROM public.federated_access_plans WHERE id = v_plan;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (CATALOG-01): public WASEL plan is not visible.';
    END IF;
    SELECT COUNT(*) INTO v_count FROM public.federated_plan_networks WHERE id = v_plan_network;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (CATALOG-02): active partner participation is not visible.';
    END IF;

    -- Customer A can read their entitlement/session but not operational ledgers.
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_customer_a::text, true);
    PERFORM set_config(
        'request.jwt.claims',
        json_build_object('sub', v_customer_a::text, 'role', 'authenticated')::text,
        true
    );
    SELECT COUNT(*) INTO v_count FROM public.access_entitlements WHERE id = v_entitlement;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (CUSTOMER-01): customer cannot read own entitlement.';
    END IF;
    SELECT COUNT(*) INTO v_count FROM public.access_sessions WHERE id = v_session;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (CUSTOMER-02): customer cannot read own session.';
    END IF;
    SELECT COUNT(*) INTO v_count FROM public.radius_accounting_events WHERE id = v_event;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (CUSTOMER-03): raw accounting event leaked to customer.';
    END IF;

    -- Another customer cannot read Customer A state.
    PERFORM set_config('request.jwt.claim.sub', v_customer_b::text, true);
    PERFORM set_config(
        'request.jwt.claims',
        json_build_object('sub', v_customer_b::text, 'role', 'authenticated')::text,
        true
    );
    SELECT COUNT(*) INTO v_count FROM public.access_entitlements WHERE id = v_entitlement;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (CUSTOMER-04): cross-customer entitlement read allowed.';
    END IF;

    -- Client-side writes are denied even to the entitlement owner.
    v_denied := FALSE;
    BEGIN
        UPDATE public.access_entitlements
        SET consumed_bytes = 1
        WHERE id = v_entitlement;
    EXCEPTION WHEN OTHERS THEN
        v_denied := TRUE;
    END;
    IF NOT v_denied THEN
        RAISE EXCEPTION 'TEST_FAIL (WRITE-01): customer directly mutated entitlement.';
    END IF;

    -- Partner A sees its operational and financial records.
    PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
    PERFORM set_config(
        'request.jwt.claims',
        json_build_object('sub', v_owner_a::text, 'role', 'authenticated')::text,
        true
    );
    SELECT COUNT(*) INTO v_count FROM public.network_access_nodes WHERE id = v_node;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (PARTNER-01): owner cannot read own node.';
    END IF;
    SELECT COUNT(*) INTO v_count FROM public.radius_accounting_events WHERE id = v_event;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (PARTNER-02): owner cannot read own accounting.';
    END IF;
    SELECT COUNT(*) INTO v_count FROM public.partner_usage_ledger WHERE id = v_ledger;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (PARTNER-03): owner cannot read own accrual.';
    END IF;

    -- Partner B cannot inspect Partner A's node, sessions, events, or accruals.
    PERFORM set_config('request.jwt.claim.sub', v_owner_b::text, true);
    PERFORM set_config(
        'request.jwt.claims',
        json_build_object('sub', v_owner_b::text, 'role', 'authenticated')::text,
        true
    );
    SELECT
        (SELECT COUNT(*) FROM public.network_access_nodes WHERE id = v_node)
        + (SELECT COUNT(*) FROM public.access_sessions WHERE id = v_session)
        + (SELECT COUNT(*) FROM public.radius_accounting_events WHERE id = v_event)
        + (SELECT COUNT(*) FROM public.partner_usage_ledger WHERE id = v_ledger)
    INTO v_count;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (PARTNER-04): cross-network operational read allowed.';
    END IF;

    -- Append-only protection also applies to privileged database mutation.
    EXECUTE 'SET LOCAL ROLE postgres';
    v_denied := FALSE;
    BEGIN
        UPDATE public.radius_accounting_events
        SET input_bytes = 1
        WHERE id = v_event;
    EXCEPTION WHEN OTHERS THEN
        v_denied := TRUE;
    END;
    IF NOT v_denied THEN
        RAISE EXCEPTION 'TEST_FAIL (IMMUTABLE-01): accounting event was mutable.';
    END IF;

    v_denied := FALSE;
    BEGIN
        DELETE FROM public.partner_usage_ledger WHERE id = v_ledger;
    EXCEPTION WHEN OTHERS THEN
        v_denied := TRUE;
    END;
    IF NOT v_denied THEN
        RAISE EXCEPTION 'TEST_FAIL (IMMUTABLE-02): usage ledger entry was deletable.';
    END IF;

    -- Cross-network foreign keys prevent a session from claiming the wrong NAS.
    v_denied := FALSE;
    BEGIN
        INSERT INTO public.access_sessions (
            entitlement_id, user_id, network_id, access_node_id,
            status, grant_expires_at
        ) VALUES (
            v_entitlement, v_customer_a, v_network_b, v_node,
            'authorized', NOW() + INTERVAL '5 minutes'
        );
    EXCEPTION WHEN OTHERS THEN
        v_denied := TRUE;
    END;
    IF NOT v_denied THEN
        RAISE EXCEPTION 'TEST_FAIL (SCOPE-01): session accepted a node from another network.';
    END IF;

    -- RADIUS cumulative counters cannot move backwards.
    v_denied := FALSE;
    BEGIN
        INSERT INTO public.radius_accounting_events (
            session_id, access_node_id, network_id, event_key,
            event_type, event_at, input_bytes, output_bytes, session_seconds
        ) VALUES (
            v_session, v_node, v_network_a, 'pilot-session-01:regression',
            'interim_update', NOW(), 0, 0, -1
        );
    EXCEPTION WHEN OTHERS THEN
        v_denied := TRUE;
    END;
    IF NOT v_denied THEN
        RAISE EXCEPTION 'TEST_FAIL (ACCOUNTING-01): negative/regressive accounting accepted.';
    END IF;
END $$;

ROLLBACK;
