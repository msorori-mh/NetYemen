-- Account deletion request contract. TEST_ONLY rows; always rolled back.
BEGIN;

DO $$
DECLARE
    v_user UUID := 'a6180000-0000-4000-8000-000000000001';
    v_admin UUID := 'a6180000-0000-4000-8000-000000000002';
    v_result JSONB;
    v_request_id UUID;
    v_count INTEGER;
    v_status TEXT;
    v_failed BOOLEAN;
BEGIN
    EXECUTE 'SET LOCAL ROLE postgres';

    INSERT INTO auth.users (id, phone, raw_app_meta_data, raw_user_meta_data)
    VALUES
        (
            v_user,
            '+967770000031',
            '{}'::jsonb,
            '{"full_name":"TEST_ONLY Deletion Customer"}'::jsonb
        ),
        (
            v_admin,
            '+967770000032',
            '{}'::jsonb,
            '{"full_name":"TEST_ONLY Deletion Admin"}'::jsonb
        );

    INSERT INTO public.user_roles (user_id, role, created_by)
    VALUES (v_admin, 'platform_admin', v_admin);

    INSERT INTO public.device_push_tokens (
        user_id, platform, token, is_active
    ) VALUES (
        v_user, 'android', 'TEST_ONLY_ACCOUNT_DELETION_TOKEN', TRUE
    );

    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object('sub', v_user, 'role', 'authenticated')::text,
        true
    );

    v_result := public.request_my_account_deletion('TEST_ONLY user request');
    v_request_id := (v_result->>'request_id')::UUID;

    IF v_result->>'status' <> 'pending'
       OR (v_result->>'idempotent')::BOOLEAN THEN
        RAISE EXCEPTION 'ACCOUNT-DELETE-01 FAIL: unexpected first response %', v_result;
    END IF;

    EXECUTE 'SET LOCAL ROLE postgres';

    SELECT account_status INTO v_status
    FROM public.profiles
    WHERE id = v_user;
    IF v_status IS DISTINCT FROM 'closure_pending' THEN
        RAISE EXCEPTION 'ACCOUNT-DELETE-02 FAIL: profile was not closed immediately';
    END IF;

    SELECT count(*) INTO v_count
    FROM public.device_push_tokens
    WHERE user_id = v_user AND is_active;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'ACCOUNT-DELETE-03 FAIL: active push token remained';
    END IF;

    SELECT count(*) INTO v_count
    FROM public.audit_events
    WHERE action = 'ACCOUNT_DELETION_REQUESTED'
      AND entity_id = v_request_id::TEXT;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'ACCOUNT-DELETE-04 FAIL: request audit missing';
    END IF;

    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object('sub', v_user, 'role', 'authenticated')::text,
        true
    );
    v_result := public.request_my_account_deletion('TEST_ONLY duplicate');
    IF NOT (v_result->>'idempotent')::BOOLEAN
       OR (v_result->>'request_id')::UUID <> v_request_id THEN
        RAISE EXCEPTION 'ACCOUNT-DELETE-05 FAIL: duplicate request was not idempotent';
    END IF;

    EXECUTE 'SET LOCAL ROLE postgres';
    SELECT count(*) INTO v_count
    FROM public.audit_events
    WHERE action = 'ACCOUNT_DELETION_REQUESTED'
      AND entity_id = v_request_id::TEXT;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'ACCOUNT-DELETE-06 FAIL: duplicate request added an audit';
    END IF;

    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object('sub', v_user, 'role', 'authenticated')::text,
        true
    );
    v_result := public.cancel_my_account_deletion();
    IF v_result->>'status' <> 'cancelled' THEN
        RAISE EXCEPTION 'ACCOUNT-DELETE-07 FAIL: cancellation failed %', v_result;
    END IF;

    EXECUTE 'SET LOCAL ROLE postgres';
    SELECT account_status INTO v_status
    FROM public.profiles
    WHERE id = v_user;
    IF v_status IS DISTINCT FROM 'active' THEN
        RAISE EXCEPTION 'ACCOUNT-DELETE-08 FAIL: cancellation did not restore profile';
    END IF;

    SELECT count(*) INTO v_count
    FROM public.audit_events
    WHERE action = 'ACCOUNT_DELETION_CANCELLED'
      AND entity_id = v_request_id::TEXT;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'ACCOUNT-DELETE-09 FAIL: cancellation audit missing';
    END IF;

    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object('sub', v_admin, 'role', 'authenticated')::text,
        true
    );
    v_failed := FALSE;
    BEGIN
        PERFORM public.request_my_account_deletion('TEST_ONLY admin attempt');
    EXCEPTION WHEN SQLSTATE '42501' THEN
        v_failed := TRUE;
    END;
    IF NOT v_failed THEN
        RAISE EXCEPTION 'ACCOUNT-DELETE-10 FAIL: privileged account bypassed handoff';
    END IF;

    RAISE NOTICE 'ACCOUNT DELETION PASS: request, idempotency, token shutdown, cancellation, audit, and admin handoff verified';
END;
$$;

ROLLBACK;
