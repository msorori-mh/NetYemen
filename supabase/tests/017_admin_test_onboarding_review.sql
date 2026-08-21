-- Administrative review contract for controlled tester onboarding.
-- TEST_ONLY identities and data; transaction is rolled back.
BEGIN;

DO $$
DECLARE
    v_owner_user UUID := 'a6170000-0000-4000-8000-000000000001';
    v_customer_user UUID := 'a6170000-0000-4000-8000-000000000002';
    v_admin_user UUID := 'a6170000-0000-4000-8000-000000000003';
    v_owner_application UUID;
    v_customer_application UUID;
    v_result JSONB;
    v_count INTEGER;
    v_status TEXT;
    v_verification TEXT;
    v_owner_review TEXT;
    v_failed BOOLEAN;
BEGIN
    EXECUTE 'SET LOCAL ROLE postgres';

    INSERT INTO auth.users (id, phone, raw_app_meta_data, raw_user_meta_data)
    VALUES
        (
            v_owner_user,
            '+967770000011',
            '{"onboarding_channel":"test_invite"}'::jsonb,
            '{"full_name":"TEST_ONLY Owner Applicant"}'::jsonb
        ),
        (
            v_customer_user,
            '+967770000012',
            '{"onboarding_channel":"test_invite"}'::jsonb,
            '{"full_name":"TEST_ONLY Customer Applicant"}'::jsonb
        ),
        (
            v_admin_user,
            '+967770000013',
            '{}'::jsonb,
            '{"full_name":"TEST_ONLY Platform Admin"}'::jsonb
        );

    INSERT INTO public.user_roles (user_id, role, created_by)
    VALUES (v_admin_user, 'platform_admin', v_admin_user);

    EXECUTE 'SET LOCAL ROLE service_role';
    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object('role', 'service_role')::text,
        true
    );

    v_result := public.register_test_onboarding(
        v_owner_user,
        'network_owner',
        'مأرب',
        'مدينة مأرب',
        15.470000,
        45.320000,
        5000,
        'TEST_ONLY'
    );
    v_owner_application := (v_result->>'application_id')::UUID;

    v_result := public.register_test_onboarding(
        v_customer_user,
        'customer',
        'مأرب',
        'مدينة مأرب',
        15.480000,
        45.330000,
        NULL,
        'TEST_ONLY'
    );
    v_customer_application := (v_result->>'application_id')::UUID;

    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object('sub', v_customer_user, 'role', 'authenticated')::text,
        true
    );
    v_failed := false;
    BEGIN
        PERFORM public.admin_review_test_onboarding(
            v_owner_application,
            'approve',
            'TEST_ONLY unauthorized attempt'
        );
    EXCEPTION WHEN SQLSTATE '42501' THEN
        v_failed := true;
    END;
    IF NOT v_failed THEN
        RAISE EXCEPTION 'ONBOARD-REVIEW-01 FAIL: non-admin reviewed an application';
    END IF;

    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object('sub', v_admin_user, 'role', 'authenticated')::text,
        true
    );
    v_result := public.admin_review_test_onboarding(
        v_owner_application,
        'approve',
        'TEST_ONLY identity checked by administrator'
    );
    IF v_result->>'verification_state' <> 'test_admin_approved'
       OR v_result->>'owner_review_status' <> 'approved'
       OR v_result->>'account_status' <> 'active' THEN
        RAISE EXCEPTION 'ONBOARD-REVIEW-02 FAIL: unexpected owner approval result %', v_result;
    END IF;

    EXECUTE 'SET LOCAL ROLE postgres';
    SELECT account_status INTO v_status
    FROM public.profiles
    WHERE id = v_owner_user;
    IF v_status IS DISTINCT FROM 'active' THEN
        RAISE EXCEPTION 'ONBOARD-REVIEW-03 FAIL: approved owner profile is not active';
    END IF;

    SELECT verification_state, owner_review_status
    INTO v_verification, v_owner_review
    FROM public.test_onboarding_applications
    WHERE id = v_owner_application;
    IF v_verification IS DISTINCT FROM 'test_admin_approved'
       OR v_owner_review IS DISTINCT FROM 'approved' THEN
        RAISE EXCEPTION 'ONBOARD-REVIEW-04 FAIL: approved owner states are incoherent';
    END IF;

    SELECT count(*) INTO v_count
    FROM public.user_roles
    WHERE user_id = v_owner_user AND role = 'network_owner';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'ONBOARD-REVIEW-05 FAIL: owner role was not granted atomically';
    END IF;

    SELECT count(*) INTO v_count
    FROM public.audit_events
    WHERE action = 'ADMIN_REVIEW_TEST_ONBOARDING'
      AND entity_id = v_owner_application::TEXT
      AND reason_code = 'TEST_ADMIN_APPROVED';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'ONBOARD-REVIEW-06 FAIL: approval audit event missing';
    END IF;

    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object('sub', v_admin_user, 'role', 'authenticated')::text,
        true
    );
    v_result := public.admin_review_test_onboarding(
        v_customer_application,
        'reject',
        'TEST_ONLY identity evidence did not match'
    );
    IF v_result->>'verification_state' <> 'rejected'
       OR v_result->>'owner_review_status' <> 'not_requested'
       OR v_result->>'account_status' <> 'suspended' THEN
        RAISE EXCEPTION 'ONBOARD-REVIEW-07 FAIL: unexpected customer rejection result %', v_result;
    END IF;

    EXECUTE 'SET LOCAL ROLE postgres';
    SELECT count(*) INTO v_count
    FROM public.user_roles
    WHERE user_id = v_customer_user AND role = 'network_owner';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'ONBOARD-REVIEW-08 FAIL: rejected customer received owner role';
    END IF;

    SELECT count(*) INTO v_count
    FROM public.audit_events
    WHERE action = 'ADMIN_REVIEW_TEST_ONBOARDING'
      AND entity_id = v_customer_application::TEXT
      AND reason_code = 'TEST_ADMIN_REJECTED';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'ONBOARD-REVIEW-09 FAIL: rejection audit event missing';
    END IF;

    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object('sub', v_admin_user, 'role', 'authenticated')::text,
        true
    );
    v_failed := false;
    BEGIN
        PERFORM public.admin_review_test_onboarding(
            v_owner_application,
            'reject',
            'TEST_ONLY second decision'
        );
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        v_failed := true;
    END;
    IF NOT v_failed THEN
        RAISE EXCEPTION 'ONBOARD-REVIEW-10 FAIL: terminal application was reviewed twice';
    END IF;

    RAISE NOTICE 'ONBOARD REVIEW PASS: decisions are admin-only, atomic, audited, and terminal';
END;
$$;

ROLLBACK;
