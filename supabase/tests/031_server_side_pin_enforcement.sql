-- Verifies 20261009090000_server_side_pin_enforcement.sql: the RPCs that spend
-- wallet money or return a secret refuse a session that has not verified the
-- account PIN recently, the verification is bound to the auth session, it
-- expires, and an admin-approved reset drops it.
BEGIN;

DO $$
DECLARE
    v_user    UUID := gen_random_uuid();
    v_nopin   UUID := gen_random_uuid();
    v_msg     TEXT;
    v_ok      BOOLEAN;
    v_status  JSONB;
    v_fn      TEXT;
BEGIN
    EXECUTE 'SET LOCAL ROLE postgres';
    INSERT INTO auth.users (id, email) VALUES
        (v_user, 'pin_user_031@netyemen.local'),
        (v_nopin, 'pin_none_031@netyemen.local');

    -- ---------------------------------------------------------------------
    -- Privileges: helpers are internal, the table is RPC-only.
    -- ---------------------------------------------------------------------
    FOREACH v_fn IN ARRAY ARRAY[
        'public._auth_session_key()',
        'public._record_account_pin_verification(uuid)',
        'public.require_recent_account_pin()',
        'public._account_pin_deleted_drop_verifications()'
    ] LOOP
        IF has_function_privilege('anon', v_fn, 'EXECUTE')
           OR has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
            RAISE EXCEPTION 'TEST_FAIL: client role can execute internal helper %', v_fn;
        END IF;
    END LOOP;
    IF NOT has_function_privilege('authenticated', 'public.get_account_pin_verification()', 'EXECUTE')
       OR has_function_privilege('anon', 'public.get_account_pin_verification()', 'EXECUTE') THEN
        RAISE EXCEPTION 'TEST_FAIL: get_account_pin_verification grants are wrong';
    END IF;
    IF has_table_privilege('authenticated', 'public.account_pin_verifications', 'SELECT')
       OR has_table_privilege('authenticated', 'public.account_pin_verifications', 'INSERT')
       OR has_table_privilege('anon', 'public.account_pin_verifications', 'SELECT') THEN
        RAISE EXCEPTION 'TEST_FAIL: client role has a privilege on account_pin_verifications';
    END IF;

    -- ---------------------------------------------------------------------
    -- A user with no PIN: PIN_NOT_SET on every protected RPC.
    -- ---------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_nopin::text, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', v_nopin, 'role', 'authenticated', 'session_id', 'session-nopin')::text, true);

    BEGIN
        PERFORM public.purchase_package(gen_random_uuid(), gen_random_uuid());
        RAISE EXCEPTION 'TEST_FAIL: purchase without a PIN was not refused';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    IF v_msg NOT LIKE 'PIN_NOT_SET%' THEN
        RAISE EXCEPTION 'TEST_FAIL: expected PIN_NOT_SET, got %', v_msg;
    END IF;

    -- ---------------------------------------------------------------------
    -- Enrolled user, session A. Enrollment itself opens the window.
    -- ---------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_user::text, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', v_user, 'role', 'authenticated', 'session_id', 'session-a')::text, true);

    v_status := public.get_account_pin_verification();
    IF (v_status ->> 'has_pin')::boolean OR (v_status ->> 'verified')::boolean THEN
        RAISE EXCEPTION 'TEST_FAIL: status before enrollment is wrong: %', v_status;
    END IF;

    PERFORM public.set_account_pin('482915');
    v_status := public.get_account_pin_verification();
    IF NOT (v_status ->> 'has_pin')::boolean OR NOT (v_status ->> 'verified')::boolean
       OR v_status ->> 'verified_until' IS NULL THEN
        RAISE EXCEPTION 'TEST_FAIL: enrollment did not open the window: %', v_status;
    END IF;

    -- Past the PIN check, purchase_package reaches its own validation.
    BEGIN
        PERFORM public.purchase_package(gen_random_uuid(), gen_random_uuid());
        RAISE EXCEPTION 'TEST_FAIL: purchase of an unknown package succeeded';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    IF v_msg LIKE 'PIN_%' THEN
        RAISE EXCEPTION 'TEST_FAIL: verified session was refused by the PIN check: %', v_msg;
    END IF;

    -- ---------------------------------------------------------------------
    -- Session B (another sign-in with the same account) is not verified.
    -- ---------------------------------------------------------------------
    PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', v_user, 'role', 'authenticated', 'session_id', 'session-b')::text, true);

    FOREACH v_fn IN ARRAY ARRAY[
        'SELECT public.purchase_package(gen_random_uuid(), gen_random_uuid())',
        'SELECT public.purchase_federated_access_plan(gen_random_uuid(), gen_random_uuid())',
        'SELECT public.reveal_purchase_card_secret(gen_random_uuid())',
        'SELECT public.issue_radius_access_credential(gen_random_uuid())'
    ] LOOP
        v_msg := NULL;
        BEGIN
            EXECUTE v_fn;
        EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
        END;
        IF v_msg IS NULL OR v_msg NOT LIKE 'PIN_REQUIRED%' THEN
            RAISE EXCEPTION 'TEST_FAIL: % in an unverified session: expected PIN_REQUIRED, got %', v_fn, v_msg;
        END IF;
    END LOOP;

    -- A wrong PIN does not open the window.
    v_ok := public.verify_account_pin('000000');
    IF v_ok THEN
        RAISE EXCEPTION 'TEST_FAIL: wrong PIN verified';
    END IF;
    IF (public.get_account_pin_verification() ->> 'verified')::boolean THEN
        RAISE EXCEPTION 'TEST_FAIL: wrong PIN opened the window';
    END IF;

    -- The right PIN does.
    v_ok := public.verify_account_pin('482915');
    IF NOT v_ok THEN
        RAISE EXCEPTION 'TEST_FAIL: right PIN did not verify';
    END IF;
    BEGIN
        PERFORM public.reveal_purchase_card_secret(gen_random_uuid());
        RAISE EXCEPTION 'TEST_FAIL: reveal of an unknown purchase succeeded';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    IF v_msg NOT LIKE 'NOT_FOUND%' THEN
        RAISE EXCEPTION 'TEST_FAIL: verified reveal should reach NOT_FOUND, got %', v_msg;
    END IF;

    -- ---------------------------------------------------------------------
    -- The window expires.
    -- ---------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE postgres';
    UPDATE public.account_pin_verifications
    SET verified_at = now() - public.account_pin_verification_window() - interval '1 second'
    WHERE user_id = v_user AND session_key = 'session-b';
    EXECUTE 'SET LOCAL ROLE authenticated';

    BEGIN
        PERFORM public.purchase_package(gen_random_uuid(), gen_random_uuid());
        RAISE EXCEPTION 'TEST_FAIL: purchase with an expired verification succeeded';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    IF v_msg NOT LIKE 'PIN_REQUIRED%' THEN
        RAISE EXCEPTION 'TEST_FAIL: expired verification: expected PIN_REQUIRED, got %', v_msg;
    END IF;

    -- ---------------------------------------------------------------------
    -- An approved PIN reset drops every verification of the user.
    -- ---------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE postgres';
    DELETE FROM public.account_pins WHERE user_id = v_user;
    IF EXISTS (SELECT 1 FROM public.account_pin_verifications WHERE user_id = v_user) THEN
        RAISE EXCEPTION 'TEST_FAIL: PIN reset left verifications behind';
    END IF;

    RAISE NOTICE 'SUCCESS: server-side PIN enforcement verified.';
END $$;

ROLLBACK;
