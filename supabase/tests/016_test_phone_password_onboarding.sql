-- Controlled phone/password test onboarding security contract.
-- TEST_ONLY identities and data; transaction is rolled back.
BEGIN;

DO $$
DECLARE
    v_test_user UUID := 'a6100000-0000-4000-8000-000000000001';
    v_other_user UUID := 'a6100000-0000-4000-8000-000000000002';
    v_result JSONB;
    v_count INTEGER;
    v_status TEXT;
    v_failed BOOLEAN;
BEGIN
    EXECUTE 'SET LOCAL ROLE postgres';
    INSERT INTO auth.users (
        id,
        phone,
        raw_app_meta_data,
        raw_user_meta_data
    ) VALUES (
        v_test_user,
        '+967770000001',
        '{"onboarding_channel":"test_invite"}'::jsonb,
        '{"full_name":"TEST_ONLY Invited Owner"}'::jsonb
    );
    INSERT INTO auth.users (id, phone, raw_app_meta_data, raw_user_meta_data)
    VALUES (
        v_other_user,
        '+967770000002',
        '{}'::jsonb,
        '{"full_name":"TEST_ONLY Other User"}'::jsonb
    );

    SELECT account_status INTO v_status
    FROM public.profiles
    WHERE id = v_test_user;
    IF v_status IS DISTINCT FROM 'pending_verification' THEN
        RAISE EXCEPTION 'ONBOARD-01 FAIL: invite user was not pending from auth trigger';
    END IF;

    SELECT count(*) INTO v_count
    FROM public.user_roles
    WHERE user_id = v_test_user AND role = 'customer';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'ONBOARD-02 FAIL: baseline customer role missing';
    END IF;

    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object('sub', v_test_user, 'role', 'authenticated')::text,
        true
    );
    v_failed := false;
    BEGIN
        PERFORM public.register_test_onboarding(
            v_test_user,
            'network_owner',
            'مأرب',
            'مدينة مأرب',
            15.470000,
            45.320000,
            NULL,
            'TEST_ONLY'
        );
    EXCEPTION WHEN SQLSTATE '42501' THEN
        v_failed := true;
    END;
    IF NOT v_failed THEN
        RAISE EXCEPTION 'ONBOARD-03 FAIL: authenticated caller reached service-only RPC';
    END IF;

    EXECUTE 'SET LOCAL ROLE service_role';
    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object('role', 'service_role')::text,
        true
    );
    v_result := public.register_test_onboarding(
        v_test_user,
        'network_owner',
        'مأرب',
        'مدينة مأرب',
        15.470000,
        45.320000,
        5000,
        'TEST_ONLY'
    );
    IF v_result->>'verification_state' <> 'test_only_pending'
       OR v_result->>'owner_review_status' <> 'pending' THEN
        RAISE EXCEPTION 'ONBOARD-04 FAIL: unexpected application state %', v_result;
    END IF;

    -- Inspect privileged role/audit tables as the test harness, not service_role.
    EXECUTE 'SET LOCAL ROLE postgres';
    SELECT count(*) INTO v_count
    FROM public.user_roles
    WHERE user_id = v_test_user AND role = 'network_owner';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'ONBOARD-05 FAIL: signup escalated to network_owner';
    END IF;

    SELECT count(*) INTO v_count
    FROM public.audit_events
    WHERE action = 'test_onboarding.created'
      AND entity_id = v_result->>'application_id';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'ONBOARD-06 FAIL: creation audit event missing';
    END IF;

    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object('sub', v_other_user, 'role', 'authenticated')::text,
        true
    );
    SELECT count(*) INTO v_count
    FROM public.test_onboarding_applications
    WHERE user_id = v_test_user;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'ONBOARD-07 FAIL: another user read private onboarding/location data';
    END IF;

    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object('sub', v_test_user, 'role', 'authenticated')::text,
        true
    );
    SELECT count(*) INTO v_count
    FROM public.test_onboarding_applications
    WHERE user_id = v_test_user;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'ONBOARD-08 FAIL: user cannot read own onboarding state';
    END IF;

    v_failed := false;
    BEGIN
        UPDATE public.test_onboarding_applications
        SET verification_state = 'phone_verified'
        WHERE user_id = v_test_user;
    EXCEPTION WHEN SQLSTATE '42501' THEN
        v_failed := true;
    END;
    IF NOT v_failed THEN
        RAISE EXCEPTION 'ONBOARD-09 FAIL: user self-verified onboarding state';
    END IF;

    RAISE NOTICE 'ONBOARD PASS: invite accounts are pending, private, service-created, and non-escalating';
END;
$$;

ROLLBACK;
