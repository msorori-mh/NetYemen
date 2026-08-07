-- NetYemen Network Discovery & Addition Request Test Harness
-- File: supabase/tests/005_network_discovery_and_requests.sql
-- Task ID: NY-V1-NETWORK-DISCOVERY-001

BEGIN;

DO $$
DECLARE
    v_user_a_id      UUID := 'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1';
    v_user_b_id      UUID := 'b2b2b2b2-b2b2-4b2b-b2b2-b2b2b2b2b2b2';
    v_admin_id       UUID := 'c3c3c3c3-c3c3-4c3c-c3c3-c3c3c3c3c3c3';
    v_support_id     UUID := 'd4d4d4d4-d4d4-4d4d-a4d4-d4d4d4d4d4d4';
    v_suspended_id   UUID := 'e5e5e5e5-e5e5-4e5e-a5e5-e5e5e5e5e5e5';
    v_network_id     UUID := 'f1f1f1f1-f1f1-4f1f-a1f1-f1f1f1f1f1f1';

    v_request_id     UUID;
    v_duplicate_id   UUID;
    v_result         JSONB;
    v_count          INT;
    v_err_occurred   BOOLEAN;
BEGIN
    -- ------------------------------------------------------------------------
    -- FIXTURE SETUP
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE postgres';

    IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth') THEN
        INSERT INTO auth.users (id, email) VALUES
            (v_user_a_id, 'usera@netyemen.local'),
            (v_user_b_id, 'userb@netyemen.local'),
            (v_admin_id, 'admin@netyemen.local'),
            (v_support_id, 'support@netyemen.local'),
            (v_suspended_id, 'suspended@netyemen.local')
        ON CONFLICT (id) DO NOTHING;
    END IF;

    INSERT INTO public.profiles (id, full_name, account_status) VALUES
        (v_user_a_id, 'User A', 'active'),
        (v_user_b_id, 'User B', 'active'),
        (v_admin_id, 'Admin', 'active'),
        (v_support_id, 'Support Agent', 'active'),
        (v_suspended_id, 'Suspended User', 'suspended')
    ON CONFLICT (id) DO NOTHING;

    -- The auth.users trigger auto-provisions an active profile; force suspension.
    UPDATE public.profiles SET account_status = 'suspended' WHERE id = v_suspended_id;

    INSERT INTO public.user_roles (user_id, role) VALUES
        (v_user_a_id, 'customer'),
        (v_user_b_id, 'customer'),
        (v_admin_id, 'platform_admin'),
        (v_support_id, 'support_agent'),
        (v_suspended_id, 'customer')
    ON CONFLICT (user_id, role) DO NOTHING;

    -- Approved public network for matched-existing tests
    INSERT INTO public.networks (
        id, commercial_name, status, verification_status,
        created_by, approved_by, approved_at
    ) VALUES (
        v_network_id, 'Test Approved Net', 'active', 'verified',
        v_admin_id, v_admin_id, NOW()
    ) ON CONFLICT (id) DO NOTHING;

    -- ------------------------------------------------------------------------
    -- POS-01: Authenticated user can submit a network addition request
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_user_a_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_a_id::text, 'role', 'authenticated')::text, true);

    v_result := public.submit_network_addition_request(
        'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1'::UUID,
        'Observed_SSID_1',
        'Proposed Net A',
        'Sanaa',
        'Sanaa City',
        'District A',
        'Please review'
    );
    v_request_id := (v_result->>'id')::UUID;

    IF v_request_id IS NULL THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-01): submit_network_addition_request did not return a request ID.';
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM public.network_addition_requests
    WHERE id = v_request_id AND requester_user_id = v_user_a_id AND status = 'submitted';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-01): Request was not created with expected status.';
    END IF;

    RAISE NOTICE 'ROLE_CONTEXT_AUTHENTICATED_PASS';

    -- ------------------------------------------------------------------------
    -- POS-02: Idempotent replay returns the same request
    -- ------------------------------------------------------------------------
    v_result := public.submit_network_addition_request(
        'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1'::UUID,
        'Different display name',
        'Different name',
        NULL, NULL, NULL, NULL
    );
    IF (v_result->>'id')::UUID <> v_request_id THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-02): Idempotent replay returned a different request ID.';
    END IF;

    -- ------------------------------------------------------------------------
    -- POS-03: Requester can read their own request
    -- ------------------------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM public.network_addition_requests
    WHERE id = v_request_id;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-03): Requester could not read own request.';
    END IF;

    -- ------------------------------------------------------------------------
    -- POS-04: Support agent can read requests for triage
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_support_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_support_id::text, 'role', 'authenticated')::text, true);

    SELECT COUNT(*) INTO v_count
    FROM public.network_addition_requests
    WHERE id = v_request_id;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-04): Support agent could not read request for triage.';
    END IF;

    -- ------------------------------------------------------------------------
    -- POS-05: Platform admin can resolve a request as matched_existing
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text, 'role', 'authenticated')::text, true);

    v_result := public.resolve_network_addition_request(
        v_request_id,
        'matched_existing',
        'Matched existing approved network.',
        v_network_id
    );
    IF (v_result->>'status') <> 'matched_existing' THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-05): Resolve did not return matched_existing status.';
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM public.network_addition_requests
    WHERE id = v_request_id
      AND status = 'matched_existing'
      AND matched_network_id = v_network_id
      AND resolved_at IS NOT NULL
      AND resolved_by = v_admin_id;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-05): Request resolution metadata is incoherent.';
    END IF;

    RAISE NOTICE 'ROLE_CONTEXT_ADMIN_PASS';

    -- ------------------------------------------------------------------------
    -- POS-06: Anonymous user can read the public network catalog
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE anon';
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claims', '{}', true);

    SELECT COUNT(*) INTO v_count
    FROM public.networks
    WHERE id = v_network_id AND status = 'active' AND verification_status = 'verified';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-06): Anonymous user could not read public network catalog.';
    END IF;

    RAISE NOTICE 'ROLE_CONTEXT_ANON_PASS';

    -- ------------------------------------------------------------------------
    -- NEG-01: Unauthenticated user cannot submit a request
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE anon';
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claims', '{}', true);

    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.submit_network_addition_request(
            '99999999-9999-4999-a999-999999999999'::UUID,
            'Hacked_SSID'
        );
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-01): Anonymous user submitted a network addition request.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-02: Suspended user cannot submit a request
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_suspended_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_suspended_id::text, 'role', 'authenticated')::text, true);

    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.submit_network_addition_request(
            'e5e5e5e5-e5e5-4e5e-b5e5-e5e5e5e5e5e5'::UUID,
            'Suspended_SSID'
        );
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-02): Suspended user submitted a network addition request.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-03: Direct INSERT into network_addition_requests is denied
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_user_a_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_a_id::text, 'role', 'authenticated')::text, true);

    v_err_occurred := FALSE;
    BEGIN
        INSERT INTO public.network_addition_requests (
            requester_user_id, idempotency_key, observed_ssid_display, observed_ssid_normalized
        ) VALUES (
            v_user_a_id,
            'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa'::UUID,
            'DirectInsert',
            'directinsert'
        );
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-03): Direct INSERT into network_addition_requests succeeded.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-04: User cannot spoof another requester via RPC
    -- ------------------------------------------------------------------------
    -- The RPC derives requester from auth.uid(); there is no parameter for it.
    -- We verify the request is owned by the authenticated caller.
    v_result := public.submit_network_addition_request(
        'b2b2b2b2-b2b2-4b2b-b2b2-b2b2b2b2b2b2'::UUID,
        'OwnedByA_SSID',
        NULL, NULL, NULL, NULL, NULL
    );
    IF (v_result->>'id') IS NULL THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-04): Request submission failed.';
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM public.network_addition_requests
    WHERE id = (v_result->>'id')::UUID AND requester_user_id = v_user_a_id;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-04): Request was not owned by the authenticated caller.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-05: Cross-user read is denied
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_user_b_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_b_id::text, 'role', 'authenticated')::text, true);

    SELECT COUNT(*) INTO v_count
    FROM public.network_addition_requests
    WHERE requester_user_id = v_user_a_id;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-05): User B could read User A requests.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-06: Cross-user cancel is denied
    -- ------------------------------------------------------------------------
    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.cancel_network_addition_request(v_request_id);
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-06): User B cancelled User A request.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-07: Direct privileged status mutation is denied
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_user_a_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_a_id::text, 'role', 'authenticated')::text, true);

    v_err_occurred := FALSE;
    BEGIN
        UPDATE public.network_addition_requests
        SET status = 'approved'
        WHERE id = v_request_id;
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-07): Customer directly mutated request status.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-08: Only submitted requests can be cancelled
    -- ------------------------------------------------------------------------
    -- v_request_id is already matched_existing from POS-05.
    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.cancel_network_addition_request(v_request_id);
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-08): Non-submitted request was cancelled.';
    END IF;

    -- ------------------------------------------------------------------------
    -- POS-07: User can cancel their own submitted request
    -- ------------------------------------------------------------------------
    v_result := public.submit_network_addition_request(
        'c3c3c3c3-c3c3-4c3c-c3c3-c3c3c3c3c3c3'::UUID,
        'ToCancel_SSID'
    );
    DECLARE
        v_cancel_id UUID := (v_result->>'id')::UUID;
    BEGIN
        v_result := public.cancel_network_addition_request(v_cancel_id);
        IF (v_result->>'status') <> 'cancelled' THEN
            RAISE EXCEPTION 'TEST_FAIL (POS-07): Cancel did not return cancelled status.';
        END IF;

        SELECT COUNT(*) INTO v_count
        FROM public.network_addition_requests
        WHERE id = v_cancel_id AND status = 'cancelled';
        IF v_count <> 1 THEN
            RAISE EXCEPTION 'TEST_FAIL (POS-07): Request was not cancelled.';
        END IF;
    END;

    -- ------------------------------------------------------------------------
    -- POS-08: Duplicate open request detection links duplicate_of
    -- ------------------------------------------------------------------------
    v_result := public.submit_network_addition_request(
        'd4d4d4d4-d4d4-4d4d-b4d4-d4d4d4d4d4d4'::UUID,
        'Duplicate SSID'
    );
    v_duplicate_id := (v_result->>'id')::UUID;

    v_result := public.submit_network_addition_request(
        'e5e5e5e5-e5e5-4e5e-b5e5-e5e5e5e5e5e5'::UUID,
        '  duplicate ssid  '
    );

    SELECT duplicate_of INTO v_duplicate_id
    FROM public.network_addition_requests
    WHERE id = (v_result->>'id')::UUID;
    IF v_duplicate_id IS NULL THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-08): Duplicate request was not linked to existing open request.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-09: Non-admin/support cannot resolve requests
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_user_a_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_a_id::text, 'role', 'authenticated')::text, true);

    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.resolve_network_addition_request(
            v_duplicate_id,
            'approved'
        );
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-09): Customer resolved a network addition request.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-10: Existing core authorization remains intact
    -- ------------------------------------------------------------------------
    -- Customer cannot read another user's profile
    SELECT COUNT(*) INTO v_count
    FROM public.profiles
    WHERE id = v_user_b_id;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-10): Customer could read another user profile.';
    END IF;

    -- Customer cannot self-assign platform_admin role
    v_err_occurred := FALSE;
    BEGIN
        INSERT INTO public.user_roles (user_id, role) VALUES (v_user_a_id, 'platform_admin');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    SELECT COUNT(*) INTO v_count FROM public.user_roles WHERE user_id = v_user_a_id AND role = 'platform_admin';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-10): Customer self-assigned platform_admin role.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-11: Anonymous user cannot read network addition requests
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE anon';
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claims', '{}', true);

    v_err_occurred := FALSE;
    BEGIN
        SELECT COUNT(*) INTO v_count
        FROM public.network_addition_requests;
    EXCEPTION WHEN insufficient_privilege THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-11): Anonymous user was able to SELECT network_addition_requests.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-12: Terminal-to-terminal resolution rewrite is denied
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text, 'role', 'authenticated')::text, true);

    v_result := public.resolve_network_addition_request(v_request_id, 'approved');
    IF (v_result->>'status') <> 'approved' THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-12 setup): Could not approve request for terminal transition test.';
    END IF;

    v_err_occurred := FALSE;
    BEGIN
        v_result := public.resolve_network_addition_request(v_request_id, 'rejected');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-12): Terminal-to-terminal resolution rewrite succeeded.';
    END IF;

    v_err_occurred := FALSE;
    BEGIN
        v_result := public.resolve_network_addition_request(v_request_id, 'under_review');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-12): Terminal-to-under_review reopening succeeded.';
    END IF;

    RAISE NOTICE 'SUCCESS: All Network Discovery & Request Tests Passed.';
END $$;

ROLLBACK;
