-- End-to-end validation of the production hosted admin-review verifiers.
-- TEST_ONLY identities in the disposable local CI database.
BEGIN;

DO $$
DECLARE
    v_customer_approve UUID := 'a6190000-0000-4000-8000-000000000021';
    v_owner_approve UUID := 'a6190000-0000-4000-8000-000000000022';
    v_customer_reject UUID := 'a6190000-0000-4000-8000-000000000023';
    v_admin UUID := 'a6190000-0000-4000-8000-000000000099';
BEGIN
    INSERT INTO auth.users (
        id,
        phone,
        raw_app_meta_data,
        raw_user_meta_data
    ) VALUES
        (
            v_customer_approve,
            '+967770000021',
            '{"onboarding_channel":"test_invite"}'::jsonb,
            '{"full_name":"TEST_ONLY Hosted Customer Approve"}'::jsonb
        ),
        (
            v_owner_approve,
            '+967770000022',
            '{"onboarding_channel":"test_invite"}'::jsonb,
            '{"full_name":"TEST_ONLY Hosted Owner Approve"}'::jsonb
        ),
        (
            v_customer_reject,
            '+967770000023',
            '{"onboarding_channel":"test_invite"}'::jsonb,
            '{"full_name":"TEST_ONLY Hosted Customer Reject"}'::jsonb
        ),
        (
            v_admin,
            '+967770000099',
            '{}'::jsonb,
            '{"full_name":"TEST_ONLY Hosted Platform Admin"}'::jsonb
        );

    INSERT INTO public.user_roles (user_id, role, created_by)
    VALUES (v_admin, 'platform_admin', v_admin);

    EXECUTE 'SET LOCAL ROLE service_role';
    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object('role', 'service_role')::text,
        true
    );

    PERFORM public.register_test_onboarding(
        v_customer_approve,
        'customer',
        'مأرب',
        'مدينة مأرب',
        15.470000,
        45.320000,
        5000,
        'waselnet-prod-pilot-20260822'
    );
    PERFORM public.register_test_onboarding(
        v_owner_approve,
        'network_owner',
        'مأرب',
        'مدينة مأرب',
        15.480000,
        45.330000,
        5000,
        'waselnet-prod-pilot-20260822'
    );
    PERFORM public.register_test_onboarding(
        v_customer_reject,
        'customer',
        'مأرب',
        'مدينة مأرب',
        15.490000,
        45.340000,
        5000,
        'waselnet-prod-pilot-20260822'
    );
END;
$$;

COMMIT;

\ir ../verification/017_hosted_admin_review_production_preflight.sql

BEGIN;

DO $review$
DECLARE
    v_admin UUID := 'a6190000-0000-4000-8000-000000000099';
    v_customer_approve_application UUID;
    v_owner_approve_application UUID;
    v_customer_reject_application UUID;
BEGIN
    -- Resolve exact immutable references while still in the postgres test
    -- context. The authenticated admin intentionally cannot read auth.users.
    SELECT a.id
    INTO v_customer_approve_application
    FROM public.test_onboarding_applications a
    JOIN auth.users u ON u.id = a.user_id
    WHERE regexp_replace(COALESCE(u.phone, ''), '[^0-9]', '', 'g')
          = '967770000021';

    SELECT a.id
    INTO v_owner_approve_application
    FROM public.test_onboarding_applications a
    JOIN auth.users u ON u.id = a.user_id
    WHERE regexp_replace(COALESCE(u.phone, ''), '[^0-9]', '', 'g')
          = '967770000022';

    SELECT a.id
    INTO v_customer_reject_application
    FROM public.test_onboarding_applications a
    JOIN auth.users u ON u.id = a.user_id
    WHERE regexp_replace(COALESCE(u.phone, ''), '[^0-9]', '', 'g')
          = '967770000023';

    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object('sub', v_admin, 'role', 'authenticated')::text,
        true
    );

    PERFORM public.admin_review_test_onboarding(
        v_customer_approve_application,
        'approve',
        'TEST_ONLY hosted customer review closure'
    );

    PERFORM public.admin_review_test_onboarding(
        v_owner_approve_application,
        'approve',
        'TEST_ONLY hosted owner review closure'
    );

    PERFORM public.admin_review_test_onboarding(
        v_customer_reject_application,
        'reject',
        'TEST_ONLY disposable negative-path closure'
    );
END;
$review$;

COMMIT;

\ir ../verification/017_hosted_admin_review_production_postverify.sql
