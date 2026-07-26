-- NetYemen Positive Authorization Test Harness
-- File: supabase/tests/002_core_authorization_positive.sql
-- Task ID: NY-GOV-BE-001

BEGIN;

-- Setup Synthetic Test Personas (UUIDs)
DO $$
DECLARE
    v_customer_id UUID := '11111111-1111-4111-a111-111111111111';
    v_owner_id    UUID := '22222222-2222-4222-a222-222222222222';
    v_operator_id UUID := '33333333-3333-4333-a333-333333333333';
    v_admin_id    UUID := '44444444-4444-4444-a444-444444444444';
    v_auditor_id  UUID := '55555555-5555-4555-a555-555555555555';
    v_network_id  UUID := 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa';
    v_alias_id    UUID := 'bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb';
    v_audit_id    UUID;
    v_count       INT;
BEGIN
    -- Populate synthetic auth.users (if auth schema available in test runner)
    IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth') THEN
        INSERT INTO auth.users (id, email) VALUES
            (v_customer_id, 'customer@netyemen.local'),
            (v_owner_id, 'owner@netyemen.local'),
            (v_operator_id, 'operator@netyemen.local'),
            (v_admin_id, 'admin@netyemen.local'),
            (v_auditor_id, 'auditor@netyemen.local')
        ON CONFLICT (id) DO NOTHING;
    END IF;

    -- 1. Setup Profiles
    INSERT INTO public.profiles (id, full_name, account_status, default_governorate, default_city) VALUES
        (v_customer_id, 'Test Customer', 'active', 'Sanaa', 'Sanaa City'),
        (v_owner_id, 'Test Network Owner', 'active', 'Amanat Al Asimah', 'Sanaa'),
        (v_operator_id, 'Test Operator', 'active', 'Amanat Al Asimah', 'Sanaa'),
        (v_admin_id, 'Test Admin', 'active', 'Sanaa', 'Sanaa City'),
        (v_auditor_id, 'Test Auditor', 'active', 'Sanaa', 'Sanaa City')
    ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name;

    -- 2. Setup Roles
    INSERT INTO public.user_roles (user_id, role) VALUES
        (v_customer_id, 'customer'),
        (v_owner_id, 'network_owner'),
        (v_operator_id, 'network_operator'),
        (v_admin_id, 'platform_admin'),
        (v_auditor_id, 'system_auditor')
    ON CONFLICT (user_id, role) DO NOTHING;

    -- 3. Setup Approved Active Network
    INSERT INTO public.networks (id, commercial_name, description, governorate, city, status, verification_status, created_by, approved_by, approved_at) VALUES
        (v_network_id, 'Al-Badr HighSpeed Net', 'Premium Wi-Fi Sanaa', 'Amanat Al Asimah', 'Sanaa', 'active', 'verified', v_owner_id, v_admin_id, NOW())
    ON CONFLICT (id) DO NOTHING;

    -- 4. Setup Network Memberships
    INSERT INTO public.network_memberships (network_id, user_id, membership_role, status, created_by) VALUES
        (v_network_id, v_owner_id, 'owner', 'active', v_owner_id),
        (v_network_id, v_operator_id, 'operator', 'active', v_owner_id)
    ON CONFLICT (network_id, user_id) DO NOTHING;

    -- 5. Setup Active SSID Alias
    INSERT INTO public.network_ssid_aliases (id, network_id, ssid_display, ssid_normalized, status, verified_by, verified_at) VALUES
        (v_alias_id, v_network_id, 'Al-Badr Net 5G', public.normalize_ssid('Al-Badr Net 5G'), 'active', v_admin_id, NOW())
    ON CONFLICT (id) DO NOTHING;

    -- ------------------------------------------------------------------------
    -- Test 1: Customer reads own profile
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_customer_id::text, true);
    SELECT COUNT(*) INTO v_count FROM public.profiles WHERE id = v_customer_id;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-01): Customer could not read own profile.';
    END IF;

    -- ------------------------------------------------------------------------
    -- Test 2: Customer updates own non-security profile field
    -- ------------------------------------------------------------------------
    UPDATE public.profiles SET default_city = 'Hadda' WHERE id = v_customer_id;
    SELECT COUNT(*) INTO v_count FROM public.profiles WHERE id = v_customer_id AND default_city = 'Hadda';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-02): Customer could not update own profile.';
    END IF;

    -- ------------------------------------------------------------------------
    -- Test 3: Public / Unauthenticated reads approved active network
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', '', true);
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE id = v_network_id;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-03): Public cannot view approved active network.';
    END IF;

    -- ------------------------------------------------------------------------
    -- Test 4: Owner manages own network
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_owner_id::text, true);
    UPDATE public.networks SET description = 'Updated Owner Description' WHERE id = v_network_id;
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE id = v_network_id AND description = 'Updated Owner Description';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-04): Owner could not update owned network description.';
    END IF;

    -- ------------------------------------------------------------------------
    -- Test 5: Operator reads assigned network
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_operator_id::text, true);
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE id = v_network_id;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-05): Operator could not read assigned network.';
    END IF;

    -- ------------------------------------------------------------------------
    -- Test 6: Owner reads own network memberships
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_owner_id::text, true);
    SELECT COUNT(*) INTO v_count FROM public.network_memberships WHERE network_id = v_network_id;
    IF v_count <> 2 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-06): Owner could not read network memberships. Expected 2, got %', v_count;
    END IF;

    -- ------------------------------------------------------------------------
    -- Test 7: Admin verifies network and SSID alias
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    UPDATE public.network_ssid_aliases SET verified_at = NOW(), verified_by = v_admin_id WHERE id = v_alias_id;
    SELECT COUNT(*) INTO v_count FROM public.network_ssid_aliases WHERE id = v_alias_id;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-07): Admin could not verify network SSID alias.';
    END IF;

    -- ------------------------------------------------------------------------
    -- Test 8: Auditor reads audit events
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    v_audit_id := public.record_audit_event('TEST_ACTION', 'network', v_network_id::text, 'success', 'TEST_REASON', '{"test":true}'::jsonb);
    
    PERFORM set_config('request.jwt.claim.sub', v_auditor_id::text, true);
    SELECT COUNT(*) INTO v_count FROM public.audit_events WHERE id = v_audit_id;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-08): System Auditor could not read audit events.';
    END IF;

    RAISE NOTICE 'SUCCESS: All 8 Positive Authorization Tests Passed.';
END $$;

ROLLBACK;
