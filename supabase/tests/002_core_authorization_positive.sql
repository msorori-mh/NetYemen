-- NetYemen Non-Bypass Positive Authorization Test Harness
-- File: supabase/tests/002_core_authorization_positive.sql
-- Task ID: NY-GOV-BE-001D

BEGIN;

-- ----------------------------------------------------------------------------
-- FIXTURE SETUP & NON-BYPASS AUTHORIZATION ASSERTIONS
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_customer_id UUID := '11111111-1111-4111-a111-111111111111';
    v_owner_id    UUID := '22222222-2222-4222-a222-222222222222';
    v_operator_id UUID := '33333333-3333-4333-a333-333333333333';
    v_admin_id    UUID := '44444444-4444-4444-a444-444444444444';
    v_auditor_id  UUID := '55555555-5555-4555-a555-555555555555';
    v_network_id  UUID := 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa';
    v_alias_id    UUID := 'bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb';
    v_draft_net_id UUID;
    v_new_alias_id UUID;
    v_audit_id    UUID;
    v_count       INT;
BEGIN
    -- Ensure connection role is postgres for initial system fixture creation
    EXECUTE 'SET LOCAL ROLE postgres';

    IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth') THEN
        INSERT INTO auth.users (id, email) VALUES
            (v_customer_id, 'customer@netyemen.local'),
            (v_owner_id, 'owner@netyemen.local'),
            (v_operator_id, 'operator@netyemen.local'),
            (v_admin_id, 'admin@netyemen.local'),
            (v_auditor_id, 'auditor@netyemen.local')
        ON CONFLICT (id) DO NOTHING;
    END IF;

    INSERT INTO public.profiles (id, full_name, account_status, default_governorate, default_city) VALUES
        (v_customer_id, 'Test Customer', 'active', 'Sanaa', 'Sanaa City'),
        (v_owner_id, 'Test Network Owner', 'active', 'Amanat Al Asimah', 'Sanaa'),
        (v_operator_id, 'Test Operator', 'active', 'Amanat Al Asimah', 'Sanaa'),
        (v_admin_id, 'Test Admin', 'active', 'Sanaa', 'Sanaa City'),
        (v_auditor_id, 'Test Auditor', 'active', 'Sanaa', 'Sanaa City')
    ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name;

    INSERT INTO public.user_roles (user_id, role) VALUES
        (v_customer_id, 'customer'),
        (v_owner_id, 'network_owner'),
        (v_operator_id, 'network_operator'),
        (v_admin_id, 'platform_admin'),
        (v_auditor_id, 'system_auditor')
    ON CONFLICT (user_id, role) DO NOTHING;

    INSERT INTO public.networks (id, commercial_name, description, governorate, city, status, verification_status, created_by, approved_by, approved_at) VALUES
        (v_network_id, 'Al-Badr HighSpeed Net', 'Premium Wi-Fi Sanaa', 'Amanat Al Asimah', 'Sanaa', 'active', 'verified', v_owner_id, v_admin_id, NOW())
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.network_memberships (network_id, user_id, membership_role, status, created_by) VALUES
        (v_network_id, v_owner_id, 'owner', 'active', v_owner_id),
        (v_network_id, v_operator_id, 'operator', 'active', v_owner_id)
    ON CONFLICT (network_id, user_id) DO NOTHING;

    -- Set admin JWT claim context for initial setup of active/verified alias fixture
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);

    INSERT INTO public.network_ssid_aliases (id, network_id, ssid_display, status, verified_by, verified_at) VALUES
        (v_alias_id, v_network_id, 'Al-Badr Net 5G', 'active', v_admin_id, NOW())
    ON CONFLICT (id) DO NOTHING;

    -- ========================================================================
    -- SECTION A: AUTHENTICATED NON-BYPASS POSITIVE TESTS
    -- ========================================================================
    EXECUTE 'SET LOCAL ROLE authenticated';
    IF current_user != 'authenticated' THEN
        RAISE EXCEPTION 'TEST_FAIL: Session user is not authenticated!';
    END IF;

    -- Test 1: Customer reads own profile
    PERFORM set_config('request.jwt.claim.sub', v_customer_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_customer_id::text, 'role', 'authenticated')::text, true);
    SELECT COUNT(*) INTO v_count FROM public.profiles WHERE id = v_customer_id;
    IF v_count <> 1 THEN RAISE EXCEPTION 'TEST_FAIL (POS-01): Customer could not read own profile.'; END IF;

    -- Test 2: Customer updates own allowed profile columns
    UPDATE public.profiles SET default_city = 'Hadda' WHERE id = v_customer_id;
    SELECT COUNT(*) INTO v_count FROM public.profiles WHERE id = v_customer_id AND default_city = 'Hadda';
    IF v_count <> 1 THEN RAISE EXCEPTION 'TEST_FAIL (POS-02): Customer could not update own allowed profile columns.'; END IF;

    -- Test 3: Owner reads owned network
    PERFORM set_config('request.jwt.claim.sub', v_owner_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner_id::text, 'role', 'authenticated')::text, true);
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE id = v_network_id;
    IF v_count <> 1 THEN RAISE EXCEPTION 'TEST_FAIL (POS-03): Owner could not read owned network.'; END IF;

    -- Test 4: Owner updates allowed descriptive network fields
    UPDATE public.networks SET description = 'Updated Owner Description' WHERE id = v_network_id;
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE id = v_network_id AND description = 'Updated Owner Description';
    IF v_count <> 1 THEN RAISE EXCEPTION 'TEST_FAIL (POS-04): Owner could not update descriptive network fields.'; END IF;

    -- Test 5: Operator reads assigned network while possessing network_operator role
    PERFORM set_config('request.jwt.claim.sub', v_operator_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_operator_id::text, 'role', 'authenticated')::text, true);
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE id = v_network_id;
    IF v_count <> 1 THEN RAISE EXCEPTION 'TEST_FAIL (POS-05): Operator could not read assigned network.'; END IF;

    -- Test 6: Owner reads memberships for owned network
    PERFORM set_config('request.jwt.claim.sub', v_owner_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner_id::text, 'role', 'authenticated')::text, true);
    SELECT COUNT(*) INTO v_count FROM public.network_memberships WHERE network_id = v_network_id;
    IF v_count <> 2 THEN RAISE EXCEPTION 'TEST_FAIL (POS-06): Owner could not read memberships. Expected 2, got %', v_count; END IF;

    -- Test 7: Active network_owner invokes create_network_draft
    SELECT public.create_network_draft('Pos Draft Network', 'Desc', 'Sanaa', 'Sanaa City', 'District 1') INTO v_draft_net_id;
    IF v_draft_net_id IS NULL THEN RAISE EXCEPTION 'TEST_FAIL (POS-07): create_network_draft returned NULL.'; END IF;

    -- Test 8: create_network_draft atomically creates one owner membership
    SELECT COUNT(*) INTO v_count FROM public.network_memberships WHERE network_id = v_draft_net_id AND user_id = v_owner_id AND membership_role = 'owner';
    IF v_count <> 1 THEN RAISE EXCEPTION 'TEST_FAIL (POS-08): create_network_draft did not create owner membership.'; END IF;

    -- Test 9: Owner adds a valid network_operator membership
    INSERT INTO public.network_memberships (network_id, user_id, membership_role, status)
    VALUES (v_draft_net_id, v_operator_id, 'operator', 'active');
    SELECT COUNT(*) INTO v_count FROM public.network_memberships WHERE network_id = v_draft_net_id AND user_id = v_operator_id AND membership_role = 'operator';
    IF v_count <> 1 THEN RAISE EXCEPTION 'TEST_FAIL (POS-09): Owner could not add valid operator membership.'; END IF;

    -- Test 10: Owner proposes a pending SSID alias
    INSERT INTO public.network_ssid_aliases (network_id, ssid_display, status)
    VALUES (v_draft_net_id, 'Pending Wifi 1', 'pending_verification')
    RETURNING id INTO v_new_alias_id;
    SELECT COUNT(*) INTO v_count FROM public.network_ssid_aliases WHERE id = v_new_alias_id AND status = 'pending_verification';
    IF v_count <> 1 THEN RAISE EXCEPTION 'TEST_FAIL (POS-10): Owner could not propose pending SSID alias.'; END IF;

    -- Test 11: Owner edits a pending SSID display name and normalization is recomputed
    UPDATE public.network_ssid_aliases SET ssid_display = 'Pending Wifi Renamed' WHERE id = v_new_alias_id;
    SELECT COUNT(*) INTO v_count FROM public.network_ssid_aliases WHERE id = v_new_alias_id AND ssid_display = 'Pending Wifi Renamed' AND ssid_normalized = 'pending-wifi-renamed';
    IF v_count <> 1 THEN RAISE EXCEPTION 'TEST_FAIL (POS-11): Pending SSID display update or normalization failed.'; END IF;

    -- Test 12: Platform admin verifies and activates an alias with valid metadata
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text, 'role', 'authenticated')::text, true);

    UPDATE public.networks SET status = 'active', verification_status = 'verified', approved_by = v_admin_id, approved_at = NOW() WHERE id = v_draft_net_id;
    UPDATE public.network_ssid_aliases SET status = 'active', verified_by = v_admin_id, verified_at = NOW() WHERE id = v_new_alias_id;
    SELECT COUNT(*) INTO v_count FROM public.network_ssid_aliases WHERE id = v_new_alias_id AND status = 'active' AND verified_by = v_admin_id;
    IF v_count <> 1 THEN RAISE EXCEPTION 'TEST_FAIL (POS-12): Admin could not verify and activate alias with metadata.'; END IF;

    -- Test 13: Platform admin approves a network with coherent approval metadata
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE id = v_draft_net_id AND status = 'active' AND approved_by = v_admin_id;
    IF v_count <> 1 THEN RAISE EXCEPTION 'TEST_FAIL (POS-13): Admin could not approve network with metadata.'; END IF;

    RAISE NOTICE 'ROLE_CONTEXT_AUTHENTICATED_PASS';

    -- ========================================================================
    -- SECTION B: ANONYMOUS NON-BYPASS POSITIVE TESTS
    -- ========================================================================
    EXECUTE 'SET LOCAL ROLE anon';
    IF current_user != 'anon' THEN
        RAISE EXCEPTION 'TEST_FAIL: Session user is not anon!';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claims', '{}', true);

    -- Anonymous user reads public fields of approved active network
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE id = v_network_id AND status = 'active' AND verification_status = 'verified';
    IF v_count <> 1 THEN RAISE EXCEPTION 'TEST_FAIL (POS-ANON-01): Anonymous user could not view active approved network.'; END IF;

    -- Anonymous user reads public fields of active SSID alias
    SELECT COUNT(*) INTO v_count FROM public.network_ssid_aliases WHERE id = v_alias_id AND status = 'active';
    IF v_count <> 1 THEN RAISE EXCEPTION 'TEST_FAIL (POS-ANON-02): Anonymous user could not view active SSID alias.'; END IF;

    RAISE NOTICE 'ROLE_CONTEXT_ANON_PASS';

    -- ========================================================================
    -- SECTION C: TRUSTED AUDIT SERVICE ROLE TEST
    -- ========================================================================
    EXECUTE 'SET LOCAL ROLE service_role';
    IF current_user != 'service_role' THEN
        RAISE EXCEPTION 'TEST_FAIL: Session user is not service_role!';
    END IF;

    v_audit_id := public.record_audit_event('SYSTEM_TEST', 'network', v_network_id::text, 'success', 'TRUSTED_AUDIT_PASS', '{"test":true}'::jsonb);
    IF v_audit_id IS NULL THEN RAISE EXCEPTION 'TEST_FAIL (POS-SERVICE-01): service_role record_audit_event returned NULL.'; END IF;

    RAISE NOTICE 'ROLE_CONTEXT_SERVICE_ROLE_PASS';

    -- Test 14: System auditor reads audit events
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_auditor_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_auditor_id::text, 'role', 'authenticated')::text, true);

    SELECT COUNT(*) INTO v_count FROM public.audit_events WHERE id = v_audit_id;
    IF v_count <> 1 THEN RAISE EXCEPTION 'TEST_FAIL (POS-14): System Auditor could not read audit event recorded by service_role.'; END IF;

    RAISE NOTICE 'SUCCESS: All 14 Positive Authorization Tests Passed.';
END $$;

ROLLBACK;
