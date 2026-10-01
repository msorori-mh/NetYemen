-- Verifies 20261001091000_function_execute_lockdown.sql and
-- 20261001092000_notification_helper_lockdown.sql: internal helpers (role
-- granting, notification fan-out) are not executable by client roles; client
-- RPCs stay available to signed-in users only.
DO $$
DECLARE
    v_fn TEXT;
BEGIN
    FOREACH v_fn IN ARRAY ARRAY[
        'public._apply_access_grant(uuid, uuid)',
        'public._grantable_roles()',
        'public.apply_access_grant_on_signup()',
        'public.enqueue_notification_event(text, text, text, text, text, text, text, jsonb, text, text, text, uuid, uuid, timestamptz, jsonb)',
        'public.resolve_notification_audience(text, jsonb)',
        'public.ensure_notification_preferences(uuid)',
        'public.notification_rate_limit_hit(text, integer, integer)',
        'public.notification_preference_allows(uuid, text, text)',
        'public.notification_assert_no_secrets(text, text, text)',
        'public.process_notification_outbox(integer)'
    ] LOOP
        IF has_function_privilege('anon', v_fn, 'EXECUTE')
           OR has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
            RAISE EXCEPTION 'TEST_FAIL: client role can execute internal helper %', v_fn;
        END IF;
    END LOOP;

    FOREACH v_fn IN ARRAY ARRAY[
        'public.admin_create_access_grant(text, text[], text)',
        'public.admin_list_access_grants()',
        'public.admin_revoke_access_grant(uuid)',
        'public.has_account_pin()',
        'public.set_account_pin(text)',
        'public.verify_account_pin(text)',
        'public.request_pin_reset()',
        'public.admin_list_pin_reset_requests()',
        'public.admin_resolve_pin_reset(uuid, boolean)',
        'public.submit_refund_request(uuid, text)',
        'public.review_refund_request(uuid, text)'
    ] LOOP
        IF has_function_privilege('anon', v_fn, 'EXECUTE') THEN
            RAISE EXCEPTION 'TEST_FAIL: anon can execute %', v_fn;
        END IF;
        IF NOT has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
            RAISE EXCEPTION 'TEST_FAIL: authenticated lost EXECUTE on %', v_fn;
        END IF;
    END LOOP;

    RAISE NOTICE 'SUCCESS: function EXECUTE lockdown verified.';
END $$;
