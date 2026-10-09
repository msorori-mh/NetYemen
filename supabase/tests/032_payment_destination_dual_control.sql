-- Verifies 20261009091000_payment_destination_dual_control.sql: a payment
-- destination reaches customers only after a second, different staff member
-- approves it, approval is pinned to the reviewed content, active destinations
-- cannot be edited in place, and every step is audited.
BEGIN;

DO $$
DECLARE
    v_maker    UUID := gen_random_uuid();
    v_checker  UUID := gen_random_uuid();
    v_customer UUID := gen_random_uuid();
    v_dest     UUID;
    v_req      JSONB;
    v_req2     JSONB;
    v_res      JSONB;
    v_list     JSONB;
    v_msg      TEXT;
BEGIN
    EXECUTE 'SET LOCAL ROLE postgres';
    INSERT INTO auth.users (id, email) VALUES
        (v_maker, 'pd_maker_032@netyemen.local'),
        (v_checker, 'pd_checker_032@netyemen.local'),
        (v_customer, 'pd_customer_032@netyemen.local');
    INSERT INTO public.profiles (id, full_name, account_status) VALUES
        (v_maker, 'TEST_ONLY Maker', 'active'),
        (v_checker, 'TEST_ONLY Checker', 'active'),
        (v_customer, 'TEST_ONLY Customer', 'active')
    ON CONFLICT (id) DO UPDATE SET account_status = 'active';
    INSERT INTO public.user_roles (user_id, role) VALUES
        (v_maker, 'finance_officer'),
        (v_checker, 'platform_admin');

    -- Clients cannot write the table directly.
    IF has_table_privilege('authenticated', 'public.payment_destinations', 'INSERT')
       OR has_table_privilege('authenticated', 'public.payment_destinations', 'UPDATE')
       OR has_table_privilege('authenticated', 'public.payment_destination_activation_requests', 'SELECT') THEN
        RAISE EXCEPTION 'TEST_FAIL: client role can write payment destinations or read requests directly';
    END IF;
    IF has_function_privilege('authenticated', 'public._payment_destination_content(uuid)', 'EXECUTE')
       OR has_function_privilege('authenticated', 'public._require_active_finance_staff()', 'EXECUTE') THEN
        RAISE EXCEPTION 'TEST_FAIL: internal dual-control helper is executable by clients';
    END IF;

    -- ---------------------------------------------------------------------
    -- Maker creates: the destination is inactive and invisible to customers.
    -- ---------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_maker::text, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_maker, 'role', 'authenticated')::text, true);

    v_dest := public.admin_create_payment_destination(
        'bank_account', 'TEST_ONLY S32 Bank', 'TEST_ONLY Holder', 'TEST_ONLY-S32-A', NULL, 'YER', 0);
    IF (SELECT is_active FROM public.payment_destinations WHERE id = v_dest) THEN
        RAISE EXCEPTION 'TEST_FAIL: a new destination was created active';
    END IF;
    IF public.get_active_payment_destinations() @> jsonb_build_array(jsonb_build_object('id', v_dest)) THEN
        RAISE EXCEPTION 'TEST_FAIL: an unapproved destination is visible to customers';
    END IF;

    -- Direct activation is refused.
    BEGIN
        PERFORM public.admin_set_payment_destination_active(v_dest, TRUE);
        RAISE EXCEPTION 'TEST_FAIL: direct activation succeeded';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    IF v_msg NOT LIKE 'APPROVAL_REQUIRED%' THEN
        RAISE EXCEPTION 'TEST_FAIL: expected APPROVAL_REQUIRED, got %', v_msg;
    END IF;

    -- Maker files the request; a second pending request is refused.
    v_req := public.admin_request_payment_destination_activation(v_dest, 'TEST_ONLY new bank');
    BEGIN
        PERFORM public.admin_request_payment_destination_activation(v_dest, NULL);
        RAISE EXCEPTION 'TEST_FAIL: duplicate pending request accepted';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    IF v_msg NOT LIKE 'CHANGE_ALREADY_PENDING%' THEN
        RAISE EXCEPTION 'TEST_FAIL: expected CHANGE_ALREADY_PENDING, got %', v_msg;
    END IF;

    -- The maker cannot approve their own request.
    BEGIN
        PERFORM public.admin_review_payment_destination_activation((v_req ->> 'request_id')::uuid, TRUE, NULL);
        RAISE EXCEPTION 'TEST_FAIL: self approval succeeded';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    IF v_msg NOT LIKE 'SELF_APPROVAL_FORBIDDEN%' THEN
        RAISE EXCEPTION 'TEST_FAIL: expected SELF_APPROVAL_FORBIDDEN, got %', v_msg;
    END IF;

    -- Maker edits the destination after filing: the request goes stale.
    PERFORM public.admin_update_payment_destination(v_dest, NULL, NULL, NULL, 'TEST_ONLY-S32-SWAPPED', NULL, NULL, NULL);

    -- A customer cannot list or review requests.
    PERFORM set_config('request.jwt.claim.sub', v_customer::text, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_customer, 'role', 'authenticated')::text, true);
    BEGIN
        PERFORM public.admin_list_payment_destination_activations('pending');
        RAISE EXCEPTION 'TEST_FAIL: customer listed activation requests';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    IF v_msg NOT LIKE 'FORBIDDEN_ROLE%' THEN
        RAISE EXCEPTION 'TEST_FAIL: expected FORBIDDEN_ROLE for a customer, got %', v_msg;
    END IF;

    -- ---------------------------------------------------------------------
    -- Checker: sees the request flagged stale and cannot approve it.
    -- ---------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_checker::text, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_checker, 'role', 'authenticated')::text, true);

    v_list := public.admin_list_payment_destination_activations('pending');
    IF NOT EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_list) e
        WHERE e ->> 'id' = v_req ->> 'request_id'
          AND (e ->> 'is_stale')::boolean
          AND e -> 'content_snapshot' ->> 'account_identifier' = 'TEST_ONLY-S32-A'
          AND NOT (e ->> 'requested_by_me')::boolean
    ) THEN
        RAISE EXCEPTION 'TEST_FAIL: pending list does not show the stale request: %', v_list;
    END IF;

    BEGIN
        PERFORM public.admin_review_payment_destination_activation((v_req ->> 'request_id')::uuid, TRUE, NULL);
        RAISE EXCEPTION 'TEST_FAIL: stale request approved';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    IF v_msg NOT LIKE 'STALE_CHANGE_REQUEST%' THEN
        RAISE EXCEPTION 'TEST_FAIL: expected STALE_CHANGE_REQUEST, got %', v_msg;
    END IF;

    -- Rejection needs a note.
    BEGIN
        PERFORM public.admin_review_payment_destination_activation((v_req ->> 'request_id')::uuid, FALSE, '  ');
        RAISE EXCEPTION 'TEST_FAIL: rejection without a note accepted';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    IF v_msg NOT LIKE 'REASON_REQUIRED%' THEN
        RAISE EXCEPTION 'TEST_FAIL: expected REASON_REQUIRED, got %', v_msg;
    END IF;
    v_res := public.admin_review_payment_destination_activation((v_req ->> 'request_id')::uuid, FALSE, 'TEST_ONLY changed after request');
    IF v_res ->> 'status' <> 'rejected' THEN
        RAISE EXCEPTION 'TEST_FAIL: rejection returned %', v_res;
    END IF;

    -- ---------------------------------------------------------------------
    -- New request, approved by the checker: the destination goes live.
    -- ---------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_maker::text, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_maker, 'role', 'authenticated')::text, true);
    v_req2 := public.admin_request_payment_destination_activation(v_dest, NULL);

    PERFORM set_config('request.jwt.claim.sub', v_checker::text, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_checker, 'role', 'authenticated')::text, true);
    v_res := public.admin_review_payment_destination_activation((v_req2 ->> 'request_id')::uuid, TRUE, NULL);
    IF v_res ->> 'status' <> 'approved' OR NOT (v_res ->> 'is_active')::boolean THEN
        RAISE EXCEPTION 'TEST_FAIL: approval returned %', v_res;
    END IF;

    -- A resolved request cannot be reviewed again.
    BEGIN
        PERFORM public.admin_review_payment_destination_activation((v_req2 ->> 'request_id')::uuid, FALSE, 'again');
        RAISE EXCEPTION 'TEST_FAIL: a resolved request was reviewed again';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    IF v_msg NOT LIKE 'ALREADY_RESOLVED%' THEN
        RAISE EXCEPTION 'TEST_FAIL: expected ALREADY_RESOLVED, got %', v_msg;
    END IF;

    PERFORM set_config('request.jwt.claim.sub', v_customer::text, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_customer, 'role', 'authenticated')::text, true);
    IF NOT EXISTS (
        SELECT 1 FROM jsonb_array_elements(public.get_active_payment_destinations()) e
        WHERE e ->> 'id' = v_dest::text
    ) THEN
        RAISE EXCEPTION 'TEST_FAIL: approved destination is not visible to customers';
    END IF;

    -- ---------------------------------------------------------------------
    -- Active destinations cannot be edited in place; sort order can change;
    -- deactivation is immediate.
    -- ---------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_maker::text, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_maker, 'role', 'authenticated')::text, true);
    BEGIN
        PERFORM public.admin_update_payment_destination(v_dest, NULL, NULL, NULL, 'TEST_ONLY-S32-HIJACK', NULL, NULL, NULL);
        RAISE EXCEPTION 'TEST_FAIL: active destination account number changed in place';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    IF v_msg NOT LIKE 'DESTINATION_ACTIVE%' THEN
        RAISE EXCEPTION 'TEST_FAIL: expected DESTINATION_ACTIVE, got %', v_msg;
    END IF;
    PERFORM public.admin_update_payment_destination(v_dest, NULL, NULL, NULL, NULL, NULL, NULL, 7);
    PERFORM public.admin_set_payment_destination_active(v_dest, FALSE);

    EXECUTE 'SET LOCAL ROLE postgres';
    IF (SELECT is_active OR sort_order <> 7 OR account_identifier <> 'TEST_ONLY-S32-SWAPPED'
        FROM public.payment_destinations WHERE id = v_dest) THEN
        RAISE EXCEPTION 'TEST_FAIL: final destination state is wrong';
    END IF;

    -- ---------------------------------------------------------------------
    -- Audit trail.
    -- ---------------------------------------------------------------------
    IF (SELECT count(*) FROM public.audit_events
        WHERE entity_id = v_dest::text AND action = 'PAYMENT_DESTINATION_ACTIVATION_REQUESTED'
          AND actor_user_id = v_maker) <> 2 THEN
        RAISE EXCEPTION 'TEST_FAIL: activation requests were not audited';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.audit_events
        WHERE entity_id = v_dest::text AND action = 'PAYMENT_DESTINATION_ACTIVATION_REJECTED'
          AND actor_user_id = v_checker) THEN
        RAISE EXCEPTION 'TEST_FAIL: rejection was not audited';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.audit_events
        WHERE entity_id = v_dest::text AND action = 'PAYMENT_DESTINATION_ACTIVATION_APPROVED'
          AND actor_user_id = v_checker AND (metadata ->> 'requested_by')::uuid = v_maker) THEN
        RAISE EXCEPTION 'TEST_FAIL: approval was not audited with the requester';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.audit_events
        WHERE entity_id = v_dest::text AND action = 'PAYMENT_DESTINATIONS_UPDATE'
          AND actor_user_id = v_checker
          AND (metadata -> 'before' ->> 'is_active')::boolean = FALSE
          AND (metadata -> 'after' ->> 'is_active')::boolean = TRUE) THEN
        RAISE EXCEPTION 'TEST_FAIL: activation row change was not audited with the approver as actor';
    END IF;

    RAISE NOTICE 'SUCCESS: payment destination dual control verified.';
END $$;

ROLLBACK;
