-- NetYemen V1 Notifications & Engagement Authorization Test Harness
-- File: supabase/tests/009_notifications_engagement.sql
-- Task ID: NY-V1-NOTIFICATIONS-ENGAGEMENT-001
-- Scope: tokens, preferences, transactional/engagement events, outbox,
--        deliveries, opt-out, dedupe, admin composer, targeting, no secrets.

BEGIN;

DO $$
DECLARE
    v_customer_id      UUID := '11010101-0101-4101-a101-010101010111';
    v_customer_b_id    UUID := '11010101-0101-4101-a101-010101010112';
    v_owner_id         UUID := '12020202-0202-4202-a202-020202020212';
    v_operator_id      UUID := '14040404-0404-4404-a404-040404040414';
    v_support_id       UUID := '15050505-0505-4505-a505-050505050515';
    v_auditor_id       UUID := '16060606-0606-4606-a606-060606060616';
    v_admin_id         UUID := '17070707-0707-4707-a707-070707070717';

    v_net_id           UUID := '1a0a0a0a-0a0a-4a0a-aa0a-0a0a0a0a0a1a';
    v_pkg_id           UUID := '1b0b0b0b-0b0b-4b0b-ab0b-0b0b0b0b0b1b';
    v_request_id       UUID;
    v_token_id         UUID;
    v_event_id         UUID;
    v_event_id_2       UUID;
    v_inbox_id         UUID;
    v_result           JSONB;
    v_count            INT;
    v_err_occurred     BOOLEAN;
    v_status           TEXT;
    v_binding          TEXT;
BEGIN
    EXECUTE 'SET LOCAL ROLE postgres';

    IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth') THEN
        INSERT INTO auth.users (id, email) VALUES
            (v_customer_id, 'customer_notif_test@netyemen.local'),
            (v_customer_b_id, 'customer_b_notif_test@netyemen.local'),
            (v_owner_id, 'owner_notif_test@netyemen.local'),
            (v_operator_id, 'operator_notif_test@netyemen.local'),
            (v_support_id, 'support_notif_test@netyemen.local'),
            (v_auditor_id, 'auditor_notif_test@netyemen.local'),
            (v_admin_id, 'admin_notif_test@netyemen.local')
        ON CONFLICT (id) DO NOTHING;
    END IF;

    INSERT INTO public.profiles (id, full_name, account_status, default_governorate, default_city) VALUES
        (v_customer_id, 'Notif Customer A', 'active', 'صنعاء', 'صنعاء'),
        (v_customer_b_id, 'Notif Customer B', 'active', 'عدن', 'عدن'),
        (v_owner_id, 'Notif Owner', 'active', 'صنعاء', 'صنعاء'),
        (v_operator_id, 'Notif Operator', 'active', NULL, NULL),
        (v_support_id, 'Notif Support', 'active', NULL, NULL),
        (v_auditor_id, 'Notif Auditor', 'active', NULL, NULL),
        (v_admin_id, 'Notif Admin', 'active', NULL, NULL)
    ON CONFLICT (id) DO UPDATE SET
        full_name = EXCLUDED.full_name,
        default_governorate = EXCLUDED.default_governorate,
        default_city = EXCLUDED.default_city,
        account_status = 'active';

    INSERT INTO public.user_roles (user_id, role) VALUES
        (v_customer_id, 'customer'),
        (v_customer_b_id, 'customer'),
        (v_owner_id, 'network_owner'),
        (v_operator_id, 'network_operator'),
        (v_support_id, 'support_agent'),
        (v_auditor_id, 'system_auditor'),
        (v_admin_id, 'platform_admin')
    ON CONFLICT (user_id, role) DO NOTHING;

    INSERT INTO public.networks (
        id, commercial_name, governorate, city, status, verification_status,
        created_by, approved_by, approved_at
    ) VALUES (
        v_net_id, 'Notif Test Network', 'صنعاء', 'صنعاء', 'active', 'verified',
        v_owner_id, v_admin_id, NOW()
    ) ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.network_memberships (network_id, user_id, membership_role, status, created_by) VALUES
        (v_net_id, v_owner_id, 'owner', 'active', v_owner_id),
        (v_net_id, v_operator_id, 'operator', 'active', v_owner_id)
    ON CONFLICT (network_id, user_id) DO NOTHING;

    INSERT INTO public.network_packages (
        id, network_id, name, description, price, duration_value, duration_unit,
        speed_mbps, package_type, status, is_public, sort_order, created_by
    ) VALUES (
        v_pkg_id, v_net_id, 'Notif Package', 'test', 500, 1, 'day',
        10, 'time', 'draft', FALSE, 1, v_owner_id
    ) ON CONFLICT (id) DO NOTHING;

    -- Ensure inventory balance exists at zero (trigger may already initialize)
    INSERT INTO public.package_inventory_balances (
        package_id, network_id, total_units, available_units, is_available
    ) VALUES (v_pkg_id, v_net_id, 0, 0, TRUE)
    ON CONFLICT (package_id) DO UPDATE SET
        total_units = 0,
        available_units = 0;

    -- ------------------------------------------------------------------------
    -- External transport binding (OD-NOTIF-01): approved for FCM pilot,
    -- pending Edge Function secret configuration.
    -- ------------------------------------------------------------------------
    SELECT binding_status, provider_key INTO v_binding, v_status FROM public.notification_transport_config WHERE id = 1;
    IF v_binding IS DISTINCT FROM 'approved_pending_secrets' OR v_status IS DISTINCT FROM 'fcm' THEN
        RAISE EXCEPTION 'TEST_FAIL: expected fcm/approved_pending_secrets, got %/%', v_status, v_binding;
    END IF;
    RAISE NOTICE 'TRANSPORT_APPROVED_PENDING_SECRETS_PASS';

    -- ------------------------------------------------------------------------
    -- Token registration: own tokens only
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_customer_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_customer_id::text, 'role', 'authenticated')::text, true);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
    EXECUTE 'SET LOCAL ROLE authenticated';

    v_result := public.register_device_push_token('android', 'device-token-customer-a', 'fp-a', '1.0.0');
    IF v_result->>'user_id' IS DISTINCT FROM v_customer_id::text THEN
        RAISE EXCEPTION 'TEST_FAIL: token registration user mismatch';
    END IF;
    RAISE NOTICE 'TOKEN_REGISTER_OWN_PASS';

    -- Cross-user token read denied via RLS
    v_count := 0;
    SELECT COUNT(*) INTO v_count
    FROM public.device_push_tokens
    WHERE user_id = v_customer_b_id;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL: customer A can see customer B tokens';
    END IF;
    RAISE NOTICE 'CROSS_USER_TOKEN_ACCESS_DENIED_PASS';

    -- Customer B cannot deactivate A's token
    EXECUTE 'SET LOCAL ROLE postgres';
    PERFORM set_config('request.jwt.claim.sub', v_customer_b_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_customer_b_id::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    v_result := public.deactivate_device_push_token('device-token-customer-a');
    IF (v_result->>'deactivated')::boolean = TRUE THEN
        RAISE EXCEPTION 'TEST_FAIL: customer B deactivated customer A token';
    END IF;
    RAISE NOTICE 'CROSS_USER_TOKEN_DEACTIVATE_DENIED_PASS';

    -- Reject secret-looking token
    EXECUTE 'SET LOCAL ROLE postgres';
    PERFORM set_config('request.jwt.claim.sub', v_customer_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_customer_id::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.register_device_push_token('android', 'BEGIN PRIVATE KEY-----secret');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL: secret-like token was accepted';
    END IF;
    RAISE NOTICE 'SECRET_TOKEN_REJECTED_PASS';

    -- Preferences: transactional locked; engagement controllable
    v_result := public.update_notification_preferences(
        FALSE, FALSE, FALSE, FALSE, FALSE
    );
    IF (v_result->>'transactional_enabled')::boolean IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'TEST_FAIL: transactional preference must remain enabled';
    END IF;
    IF (v_result->>'network_added_enabled')::boolean IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'TEST_FAIL: network_added opt-out not applied';
    END IF;
    RAISE NOTICE 'PREFERENCES_OWN_MANAGE_PASS';

    -- ------------------------------------------------------------------------
    -- Transactional: request status notifications
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE postgres';
    INSERT INTO public.network_addition_requests (
        id, requester_user_id, idempotency_key, proposed_network_name,
        observed_ssid_display, observed_ssid_normalized, governorate, city,
        status
    ) VALUES (
        '1c0c0c0c-0c0c-4c0c-ac0c-0c0c0c0c0c1c',
        v_customer_id,
        '1d0d0d0d-0d0d-4d0d-ad0d-0d0d0d0d0d1d',
        'Requested Network',
        'SSID-Test',
        'ssid-test',
        'صنعاء',
        'صنعاء',
        'submitted'
    ) ON CONFLICT (id) DO NOTHING;
    v_request_id := '1c0c0c0c-0c0c-4c0c-ac0c-0c0c0c0c0c1c';

    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.resolve_network_addition_request(v_request_id, 'approved', 'ok', NULL);

    -- Inspect as postgres to bypass recipient RLS for assertions
    EXECUTE 'SET LOCAL ROLE postgres';

    SELECT COUNT(*) INTO v_count
    FROM public.notification_events
    WHERE dedupe_key = 'request_status:' || v_request_id::text || ':approved';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL: expected one transactional request event, got %', v_count;
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM public.notification_inbox
    WHERE user_id = v_customer_id
      AND channel_class = 'request_status'
      AND event_id IN (
          SELECT id FROM public.notification_events
          WHERE dedupe_key = 'request_status:' || v_request_id::text || ':approved'
      );
    IF v_count < 1 THEN
        RAISE EXCEPTION 'TEST_FAIL: transactional inbox row missing for requester';
    END IF;
    RAISE NOTICE 'TRANSACTIONAL_REQUEST_ROUTING_PASS';

    -- Duplicate resolve should not create duplicate business delivery
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.resolve_network_addition_request(v_request_id, 'approved', 'again', NULL);
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    EXECUTE 'SET LOCAL ROLE postgres';
    -- Even if transition fails, re-enqueue with same dedupe must stay unique
    SELECT COUNT(*) INTO v_count
    FROM public.notification_events
    WHERE dedupe_key = 'request_status:' || v_request_id::text || ':approved';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL: duplicate request events created';
    END IF;
    RAISE NOTICE 'DEDUPE_IDEMPOTENCY_PASS';

    -- ------------------------------------------------------------------------
    -- Opt-out respected for engagement; transactional still delivered
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE postgres';
    -- Customer A opted out of network_added earlier. Approve a NEW network to fire event.
    INSERT INTO public.networks (
        id, commercial_name, governorate, city, status, verification_status,
        created_by, approved_by, approved_at
    ) VALUES (
        '1e0e0e0e-0e0e-4e0e-ae0e-0e0e0e0e0e1e',
        'Engagement Network',
        'صنعاء',
        'صنعاء',
        'pending_approval',
        'unverified',
        v_owner_id,
        NULL,
        NULL
    ) ON CONFLICT (id) DO NOTHING;

    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.admin_approve_network('1e0e0e0e-0e0e-4e0e-ae0e-0e0e0e0e0e1e', 'approved for notif');

    EXECUTE 'SET LOCAL ROLE postgres';

    SELECT id INTO v_event_id
    FROM public.notification_events
    WHERE dedupe_key = 'network_added:1e0e0e0e-0e0e-4e0e-ae0e-0e0e0e0e0e1e';

    IF v_event_id IS NULL THEN
        RAISE EXCEPTION 'TEST_FAIL: network_added event missing';
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM public.notification_deliveries
    WHERE event_id = v_event_id
      AND recipient_user_id = v_customer_id
      AND status = 'skipped_opt_out';
    IF v_count < 1 THEN
        RAISE EXCEPTION 'TEST_FAIL: opt-out not respected for customer A';
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM public.notification_inbox
    WHERE user_id = v_customer_id AND event_id = v_event_id;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL: opted-out user received inbox row';
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM public.notification_inbox
    WHERE user_id = v_customer_b_id AND event_id = v_event_id;
    IF v_count < 1 THEN
        RAISE EXCEPTION 'TEST_FAIL: opted-in customer B missing network_added inbox';
    END IF;
    RAISE NOTICE 'OPT_OUT_RESPECTED_PASS';

    -- ------------------------------------------------------------------------
    -- Package-added + stock-restored engagement
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_owner_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner_id::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.publish_network_package(v_pkg_id);

    EXECUTE 'SET LOCAL ROLE postgres';
    SELECT COUNT(*) INTO v_count
    FROM public.notification_events
    WHERE dedupe_key = 'package_added:' || v_pkg_id::text;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL: package_added event missing';
    END IF;
    RAISE NOTICE 'PACKAGE_ADDED_EVENT_PASS';

    -- Restock from 0 → positive
    PERFORM set_config('request.jwt.claim.sub', v_owner_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner_id::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.adjust_package_inventory(v_pkg_id, 5, 'restock for notif test', '1f0f0f0f-0f0f-4f0f-af0f-0f0f0f0f0f1f');

    EXECUTE 'SET LOCAL ROLE postgres';
    SELECT COUNT(*) INTO v_count
    FROM public.notification_events
    WHERE event_type = 'stock_restored'
      AND source_entity_id = v_pkg_id::text;
    IF v_count < 1 THEN
        RAISE EXCEPTION 'TEST_FAIL: stock_restored event missing';
    END IF;
    RAISE NOTICE 'STOCK_RESTORED_EVENT_PASS';

    -- ------------------------------------------------------------------------
    -- Admin composer authorization
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE postgres';
    PERFORM set_config('request.jwt.claim.sub', v_customer_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_customer_id::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.admin_compose_notification(
            'عنوان تجريبي',
            'محتوى تجريبي بدون أسرار',
            'all_active_customers'
        );
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL: non-admin compose should be denied';
    END IF;
    RAISE NOTICE 'NON_ADMIN_SEND_DENIED_PASS';

    EXECUTE 'SET LOCAL ROLE postgres';
    PERFORM set_config('request.jwt.claim.sub', v_support_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_support_id::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.admin_compose_notification(
            'عنوان دعم',
            'محتوى دعم',
            'all_active_customers'
        );
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL: support_agent compose should be denied';
    END IF;

    EXECUTE 'SET LOCAL ROLE postgres';
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    v_result := public.admin_compose_notification(
        'تحديث المنصة',
        'ميزة جديدة متاحة في نت اليمن',
        'governorate',
        jsonb_build_object('governorate', 'صنعاء'),
        'platform_update',
        'notifications',
        NOW(),
        '21010101-0101-4101-a101-010101010201',
        TRUE
    );
    v_event_id := (v_result->>'event_id')::uuid;
    IF v_event_id IS NULL THEN
        RAISE EXCEPTION 'TEST_FAIL: admin compose did not return event_id';
    END IF;
    RAISE NOTICE 'ADMIN_COMPOSER_AUTHORIZED_PASS';

    -- Targeting isolation: only صنعاء profiles (inspect as postgres for cross-user inbox)
    EXECUTE 'SET LOCAL ROLE postgres';
    SELECT COUNT(*) INTO v_count
    FROM public.notification_deliveries
    WHERE event_id = v_event_id
      AND recipient_user_id = v_customer_b_id;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL: Aden customer received Sanaa-targeted announcement';
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM public.notification_inbox
    WHERE event_id = v_event_id AND user_id = v_owner_id;
    IF v_count < 1 THEN
        RAISE EXCEPTION 'TEST_FAIL: Sanaa owner missing targeted announcement';
    END IF;
    RAISE NOTICE 'TARGETING_ISOLATION_PASS';

    -- Idempotent admin compose with same key
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    v_result := public.admin_compose_notification(
        'تحديث المنصة',
        'ميزة جديدة متاحة في نت اليمن',
        'governorate',
        jsonb_build_object('governorate', 'صنعاء'),
        'platform_update',
        'notifications',
        NOW(),
        '21010101-0101-4101-a101-010101010201',
        TRUE
    );
    v_event_id_2 := (v_result->>'event_id')::uuid;
    IF v_event_id_2 IS DISTINCT FROM v_event_id THEN
        RAISE EXCEPTION 'TEST_FAIL: admin compose idempotency broken';
    END IF;
    RAISE NOTICE 'ADMIN_COMPOSE_IDEMPOTENCY_PASS';

    v_result := public.admin_notification_delivery_summary(v_event_id);
    IF v_result->>'event_id' IS DISTINCT FROM v_event_id::text THEN
        RAISE EXCEPTION 'TEST_FAIL: delivery summary missing';
    END IF;
    RAISE NOTICE 'ADMIN_DELIVERY_SUMMARY_PASS';

    -- Auditor can read summary; customer cannot
    EXECUTE 'SET LOCAL ROLE postgres';
    PERFORM set_config('request.jwt.claim.sub', v_auditor_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_auditor_id::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    v_result := public.admin_notification_delivery_summary(v_event_id);

    EXECUTE 'SET LOCAL ROLE postgres';
    PERFORM set_config('request.jwt.claim.sub', v_customer_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_customer_id::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.admin_notification_delivery_summary(v_event_id);
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL: customer should not read admin delivery summary';
    END IF;

    -- ------------------------------------------------------------------------
    -- Secret payload rejected
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE postgres';
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.admin_compose_notification(
            'كلمة المرور للشبكة',
            'password is 12345',
            'all_active_customers'
        );
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL: secret payload was accepted';
    END IF;
    RAISE NOTICE 'NO_SECRET_PAYLOAD_PASS';

    -- ------------------------------------------------------------------------
    -- Inbox mark-read own only + unread count
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE postgres';
    PERFORM set_config('request.jwt.claim.sub', v_customer_b_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_customer_b_id::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT id INTO v_inbox_id
    FROM public.list_my_notifications(10, TRUE)
    LIMIT 1;
    IF v_inbox_id IS NULL THEN
        RAISE EXCEPTION 'TEST_FAIL: expected unread notifications for customer B';
    END IF;
    PERFORM public.mark_notification_read(v_inbox_id);
    RAISE NOTICE 'INBOX_MARK_READ_PASS';

    -- Cross-user mark-read denied
    EXECUTE 'SET LOCAL ROLE postgres';
    INSERT INTO public.notification_inbox (
        id, user_id, event_id, title_ar, body_ar, category, channel_class
    )
    SELECT
        '1a1a1a1a-1a1a-4a1a-aa1a-1a1a1a1a1a1a',
        v_customer_id,
        e.id,
        'x',
        'y',
        'engagement',
        'announcement'
    FROM public.notification_events e
    WHERE e.id = v_event_id
    ON CONFLICT DO NOTHING;

    PERFORM set_config('request.jwt.claim.sub', v_customer_b_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_customer_b_id::text, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.mark_notification_read('1a1a1a1a-1a1a-4a1a-aa1a-1a1a1a1a1a1a');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL: cross-user mark-read should fail';
    END IF;
    RAISE NOTICE 'CROSS_USER_INBOX_DENIED_PASS';

    -- Push deliveries blocked while unbound
    EXECUTE 'SET LOCAL ROLE postgres';
    SELECT COUNT(*) INTO v_count
    FROM public.notification_deliveries
    WHERE delivery_channel = 'push'
      AND status = 'dispatch_blocked_unbound_provider';
    IF v_count < 1 THEN
        RAISE EXCEPTION 'TEST_FAIL: expected unbound-provider blocked push deliveries';
    END IF;
    RAISE NOTICE 'PROVIDER_UNBOUND_BLOCK_PASS';

    -- No provider credentials in transport config
    IF EXISTS (
        SELECT 1 FROM public.notification_transport_config
        WHERE provider_key ILIKE '%firebase%'
           OR notes ~* '(api[_-]?key|private_key)\s*[=:]'
    ) THEN
        RAISE EXCEPTION 'TEST_FAIL: provider secrets leaked into transport config';
    END IF;
    RAISE NOTICE 'NO_PROVIDER_SECRETS_SERVER_PASS';

    RAISE NOTICE 'NY_V1_NOTIFICATIONS_ENGAGEMENT_001_PASS';
END;
$$;

ROLLBACK;
