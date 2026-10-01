-- NetYemen Negative Authorization Test Harness
-- File: supabase/tests/003_core_authorization_negative.sql
-- Task ID: NY-GOV-BE-001 / NY-GOV-BE-001B

BEGIN;

DO $$
DECLARE
    v_user_a_id   UUID := '11111111-1111-4111-a111-111111111111';
    v_user_b_id   UUID := '22222222-2222-4222-a222-222222222222';
    v_owner_1_id  UUID := '33333333-3333-4333-a333-333333333333';
    v_owner_2_id  UUID := '44444444-4444-4444-a444-444444444444';
    v_operator_id UUID := '55555555-5555-4555-a555-555555555555';
    v_finance_id  UUID := '66666666-6666-4666-a666-666666666666';
    v_support_id  UUID := '77777777-7777-4777-a777-777777777777';
    v_admin_id    UUID := '88888888-8888-4888-a888-888888888888';
    v_auditor_id  UUID := '99999999-9999-4999-a999-999999999999';

    v_net_1_id    UUID := 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa';
    v_net_2_id    UUID := 'bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb';
    v_suspended_net_id UUID := 'cccccccc-cccc-4ccc-cccc-cccccccccccc';
    v_alias_id    UUID;

    v_count INT;
    v_err_occurred BOOLEAN;
BEGIN
    -- Setup auth.users if auth schema present
    IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth') THEN
        INSERT INTO auth.users (id, email) VALUES
            (v_user_a_id, 'usera@netyemen.local'),
            (v_user_b_id, 'userb@netyemen.local'),
            (v_owner_1_id, 'owner1@netyemen.local'),
            (v_owner_2_id, 'owner2@netyemen.local'),
            (v_operator_id, 'operator@netyemen.local'),
            (v_finance_id, 'finance@netyemen.local'),
            (v_support_id, 'support@netyemen.local'),
            (v_admin_id, 'admin@netyemen.local'),
            (v_auditor_id, 'auditor@netyemen.local')
        ON CONFLICT (id) DO NOTHING;
    END IF;

    -- Insert Profiles
    INSERT INTO public.profiles (id, full_name, account_status) VALUES
        (v_user_a_id, 'User A', 'active'),
        (v_user_b_id, 'User B', 'active'),
        (v_owner_1_id, 'Owner 1', 'active'),
        (v_owner_2_id, 'Owner 2', 'active'),
        (v_operator_id, 'Operator 1', 'active'),
        (v_finance_id, 'Finance Officer', 'active'),
        (v_support_id, 'Support Agent', 'active'),
        (v_admin_id, 'Platform Admin', 'active'),
        (v_auditor_id, 'System Auditor', 'active')
    ON CONFLICT (id) DO NOTHING;

    -- Insert Roles
    INSERT INTO public.user_roles (user_id, role) VALUES
        (v_user_a_id, 'customer'),
        (v_user_b_id, 'customer'),
        (v_owner_1_id, 'network_owner'),
        (v_owner_2_id, 'network_owner'),
        (v_operator_id, 'network_operator'),
        (v_finance_id, 'finance_officer'),
        (v_support_id, 'support_agent'),
        (v_admin_id, 'platform_admin'),
        (v_auditor_id, 'system_auditor')
    ON CONFLICT (user_id, role) DO NOTHING;

    -- Set Admin context for initial setup of active/verified test fixtures
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);

    -- Insert Networks
    INSERT INTO public.networks (id, commercial_name, status, verification_status, created_by, approved_by, approved_at) VALUES
        (v_net_1_id, 'Network One', 'active', 'verified', v_owner_1_id, v_admin_id, NOW()),
        (v_net_2_id, 'Network Two', 'active', 'verified', v_owner_2_id, v_admin_id, NOW()),
        (v_suspended_net_id, 'Suspended Net', 'suspended', 'unverified', v_owner_1_id, NULL, NULL)
    ON CONFLICT (id) DO NOTHING;

    -- Memberships
    INSERT INTO public.network_memberships (network_id, user_id, membership_role, status) VALUES
        (v_net_1_id, v_owner_1_id, 'owner', 'active'),
        (v_net_1_id, v_operator_id, 'operator', 'active'),
        (v_net_2_id, v_owner_2_id, 'owner', 'active')
    ON CONFLICT (network_id, user_id) DO NOTHING;

    -- Switch connection to authenticated role to enforce table & column privileges (prevent superuser bypass)
    EXECUTE 'SET LOCAL ROLE authenticated';

    -- ------------------------------------------------------------------------
    -- NEG-01: Customer network creation via create_network_draft RPC fails
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_user_a_id::text, true);
    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.create_network_draft('Customer Illegal Net');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-01): Customer created network draft!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-02: Operator network creation via create_network_draft RPC fails
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_operator_id::text, true);
    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.create_network_draft('Operator Illegal Net');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-02): Operator created network draft!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-03: Direct network INSERT table attempt by authenticated caller fails
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_owner_1_id::text, true);
    v_err_occurred := FALSE;
    BEGIN
        INSERT INTO public.networks (commercial_name) VALUES ('Bypass Net');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE commercial_name = 'Bypass Net';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-03): Direct table INSERT created network!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-04: Customer cannot read another user profile
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_user_a_id::text, true);
    SELECT COUNT(*) INTO v_count FROM public.profiles WHERE id = v_user_b_id;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-04): Customer A read Customer B profile!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-05: Customer cannot self-assign platform roles
    -- ------------------------------------------------------------------------
    v_err_occurred := FALSE;
    BEGIN
        INSERT INTO public.user_roles (user_id, role) VALUES (v_user_a_id, 'platform_admin');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    SELECT COUNT(*) INTO v_count FROM public.user_roles WHERE user_id = v_user_a_id AND role = 'platform_admin';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-05): Customer self-assigned platform_admin role!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-06: Customer cannot change own account_status
    -- ------------------------------------------------------------------------
    v_err_occurred := FALSE;
    BEGIN
        UPDATE public.profiles SET account_status = 'suspended' WHERE id = v_user_a_id;
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    SELECT COUNT(*) INTO v_count FROM public.profiles WHERE id = v_user_a_id AND account_status = 'suspended';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-06): Customer modified account_status!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-07: Owner adds owner membership fails (only operator allowed for owners)
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_owner_1_id::text, true);
    v_err_occurred := FALSE;
    BEGIN
        INSERT INTO public.network_memberships (network_id, user_id, membership_role) VALUES (v_net_1_id, v_owner_2_id, 'owner');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    SELECT COUNT(*) INTO v_count FROM public.network_memberships WHERE network_id = v_net_1_id AND user_id = v_owner_2_id;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-07): Owner added owner membership!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-08: Owner deletes owner membership fails
    -- ------------------------------------------------------------------------
    v_err_occurred := FALSE;
    BEGIN
        DELETE FROM public.network_memberships WHERE network_id = v_net_1_id AND user_id = v_owner_1_id;
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    SELECT COUNT(*) INTO v_count FROM public.network_memberships WHERE network_id = v_net_1_id AND user_id = v_owner_1_id;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-08): Owner deleted owner membership!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-09: Owner removes final owner fails (FINAL_OWNER_PROTECTION trigger)
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    v_err_occurred := FALSE;
    BEGIN
        DELETE FROM public.network_memberships WHERE network_id = v_net_1_id AND user_id = v_owner_1_id;
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-09): Final owner was removed without exception!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-10: Owner adds operator without network_operator platform role fails
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_owner_1_id::text, true);
    v_err_occurred := FALSE;
    BEGIN
        INSERT INTO public.network_memberships (network_id, user_id, membership_role) VALUES (v_net_1_id, v_user_a_id, 'operator');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    SELECT COUNT(*) INTO v_count FROM public.network_memberships WHERE network_id = v_net_1_id AND user_id = v_user_a_id;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-10): Operator without network_operator platform role was added!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-11: Owner self-activates SSID fails
    -- ------------------------------------------------------------------------
    v_err_occurred := FALSE;
    BEGIN
        INSERT INTO public.network_ssid_aliases (network_id, ssid_display, status) VALUES (v_net_1_id, 'Self Active SSID', 'active');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    SELECT COUNT(*) INTO v_count FROM public.network_ssid_aliases WHERE network_id = v_net_1_id AND ssid_display = 'Self Active SSID';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-11): Owner self-activated SSID alias!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-12: Owner forges verified_by / verified_at fails
    -- ------------------------------------------------------------------------
    v_err_occurred := FALSE;
    BEGIN
        INSERT INTO public.network_ssid_aliases (network_id, ssid_display, status, verified_by, verified_at) VALUES (v_net_1_id, 'Forged SSID', 'pending_verification', v_owner_1_id, NOW());
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    SELECT COUNT(*) INTO v_count FROM public.network_ssid_aliases WHERE network_id = v_net_1_id AND ssid_display = 'Forged SSID';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-12): Owner forged verified_by/verified_at metadata!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-13: Client overrides normalized SSID (Trigger overwrites client value)
    -- ------------------------------------------------------------------------
    INSERT INTO public.network_ssid_aliases (network_id, ssid_display, ssid_normalized, status) VALUES (v_net_1_id, 'Real SSID Name', 'FORGED_NORMALIZED_VALUE', 'pending_verification')
    RETURNING id INTO v_alias_id;
    SELECT COUNT(*) INTO v_count FROM public.network_ssid_aliases WHERE id = v_alias_id AND ssid_normalized = 'real-ssid-name';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-13): Client forged normalized SSID was not overwritten by trigger!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-14: Authenticated client invokes audit-write RPC record_audit_event fails (Permission Denied)
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_user_a_id::text, true);
    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.record_audit_event('FORGED_CLIENT_EVENT', 'system');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-14): Authenticated client invoked record_audit_event RPC!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-15: Owner changes approved_by / approved_at fails
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_owner_1_id::text, true);
    v_err_occurred := FALSE;
    BEGIN
        UPDATE public.networks SET approved_by = v_owner_1_id, approved_at = NOW() WHERE id = v_net_1_id;
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE id = v_net_1_id AND approved_by = v_owner_1_id;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-15): Owner modified network approved_by/approved_at!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-16: Owner changes network status or verification_status fails
    -- ------------------------------------------------------------------------
    v_err_occurred := FALSE;
    BEGIN
        UPDATE public.networks SET status = 'active', verification_status = 'verified' WHERE id = v_suspended_net_id;
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE id = v_suspended_net_id AND status = 'active';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-16): Owner modified network status/verification_status!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-17: Anonymous user cannot see suspended networks
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', '', true);
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE id = v_suspended_net_id;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-17): Anonymous user viewed suspended network!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-18: Direct profile INSERT by authenticated client fails
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_user_a_id::text, true);
    v_err_occurred := FALSE;
    BEGIN
        INSERT INTO public.profiles (id, full_name) VALUES ('99999999-9999-4999-a999-999999999999', 'Fake Profile');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    SELECT COUNT(*) INTO v_count FROM public.profiles WHERE id = '99999999-9999-4999-a999-999999999999';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-18): Authenticated client directly inserted profile!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-19: Suspended network owner cannot create network draft
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE postgres';
    UPDATE public.profiles SET account_status = 'suspended' WHERE id = v_owner_1_id;
    EXECUTE 'SET LOCAL ROLE authenticated';

    PERFORM set_config('request.jwt.claim.sub', v_owner_1_id::text, true);
    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.create_network_draft('Suspended Owner Net Draft');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;

    EXECUTE 'SET LOCAL ROLE postgres';
    UPDATE public.profiles SET account_status = 'active' WHERE id = v_owner_1_id;
    EXECUTE 'SET LOCAL ROLE authenticated';

    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-19): Suspended network owner created draft network!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-20: Suspended owner cannot manage network
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE postgres';
    UPDATE public.profiles SET account_status = 'suspended' WHERE id = v_owner_1_id;
    EXECUTE 'SET LOCAL ROLE authenticated';

    PERFORM set_config('request.jwt.claim.sub', v_owner_1_id::text, true);
    UPDATE public.networks SET commercial_name = 'Illegal Rename' WHERE id = v_net_1_id;

    EXECUTE 'SET LOCAL ROLE postgres';
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE id = v_net_1_id AND commercial_name = 'Illegal Rename';
    UPDATE public.profiles SET account_status = 'active' WHERE id = v_owner_1_id;
    EXECUTE 'SET LOCAL ROLE authenticated';

    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-20): Suspended owner managed network!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-21: User whose network_owner role was removed cannot use owner membership
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE postgres';
    DELETE FROM public.user_roles WHERE user_id = v_owner_1_id AND role = 'network_owner';
    EXECUTE 'SET LOCAL ROLE authenticated';

    PERFORM set_config('request.jwt.claim.sub', v_owner_1_id::text, true);
    UPDATE public.networks SET commercial_name = 'No Role Rename' WHERE id = v_net_1_id;

    EXECUTE 'SET LOCAL ROLE postgres';
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE id = v_net_1_id AND commercial_name = 'No Role Rename';
    INSERT INTO public.user_roles (user_id, role) VALUES (v_owner_1_id, 'network_owner') ON CONFLICT DO NOTHING;
    EXECUTE 'SET LOCAL ROLE authenticated';

    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-21): User without network_owner platform role managed network!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-22: Owner cannot rename display name of active, verified SSID alias
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE postgres';
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    INSERT INTO public.network_ssid_aliases (id, network_id, ssid_display, ssid_normalized, status, verified_by, verified_at)
    VALUES ('e1e1e1e1-e1e1-4e1e-a1e1-e1e1e1e1e1e1', v_net_1_id, 'Verified SSID', 'verified-ssid', 'active', v_admin_id, NOW())
    ON CONFLICT (id) DO NOTHING;
    EXECUTE 'SET LOCAL ROLE authenticated';

    -- Owner attempts rename
    PERFORM set_config('request.jwt.claim.sub', v_owner_1_id::text, true);
    v_err_occurred := FALSE;
    BEGIN
        UPDATE public.network_ssid_aliases SET ssid_display = 'Renamed Active SSID' WHERE id = 'e1e1e1e1-e1e1-4e1e-a1e1-e1e1e1e1e1e1';
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-22): Owner renamed display name of active verified SSID alias!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-23: Owner cannot reactivate suspended SSID alias
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE postgres';
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    INSERT INTO public.network_ssid_aliases (id, network_id, ssid_display, ssid_normalized, status)
    VALUES ('e2e2e2e2-e2e2-4e2e-a2e2-e2e2e2e2e2e2', v_net_1_id, 'Suspended Alias', 'suspended-alias', 'suspended')
    ON CONFLICT (id) DO NOTHING;
    EXECUTE 'SET LOCAL ROLE authenticated';

    PERFORM set_config('request.jwt.claim.sub', v_owner_1_id::text, true);
    v_err_occurred := FALSE;
    BEGIN
        UPDATE public.network_ssid_aliases SET status = 'pending_verification' WHERE id = 'e2e2e2e2-e2e2-4e2e-a2e2-e2e2e2e2e2e2';
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-23): Owner reactivated suspended SSID alias!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-24: Admin cannot set alias status=active without verified_by / verified_at
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    v_err_occurred := FALSE;
    BEGIN
        INSERT INTO public.network_ssid_aliases (network_id, ssid_display, status, verified_by, verified_at)
        VALUES (v_net_1_id, 'Unverified Active', 'active', NULL, NULL);
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-24): Alias status active was committed without verification metadata!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-25: Inconsistent network state (active status with unverified verification_status) fails
    -- ------------------------------------------------------------------------
    v_err_occurred := FALSE;
    BEGIN
        INSERT INTO public.networks (commercial_name, status, verification_status, approved_by, approved_at)
        VALUES ('Incoherent Net', 'active', 'unverified', v_admin_id, NOW());
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-25): Incoherent network status/verification combination was committed!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-26: Finance officer and support agent cannot enumerate all profiles
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_finance_id::text, true);
    SELECT COUNT(*) INTO v_count FROM public.profiles WHERE id = v_user_a_id;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-26): Finance officer enumerated arbitrary profile!';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', v_support_id::text, true);
    SELECT COUNT(*) INTO v_count FROM public.profiles WHERE id = v_user_a_id;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-26): Support agent enumerated arbitrary profile!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-27: Owner cannot promote operator membership to owner membership
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_owner_1_id::text, true);
    v_err_occurred := FALSE;
    BEGIN
        UPDATE public.network_memberships SET membership_role = 'owner' WHERE network_id = v_net_1_id AND user_id = v_operator_id;
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-27): Owner promoted operator membership to owner!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-28: Platform role revocation renders owner membership inactive (G3)
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE postgres';
    INSERT INTO public.networks (id, commercial_name, description, governorate, city, status, verification_status, created_by)
    VALUES ('f1f1f1f1-f1f1-4f1f-a1f1-f1f1f1f1f1f1', 'Private Pending Net', 'Private', 'Sanaa', 'Sanaa', 'pending_approval', 'unverified', v_owner_1_id)
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.network_memberships (network_id, user_id, membership_role, status, created_by)
    VALUES ('f1f1f1f1-f1f1-4f1f-a1f1-f1f1f1f1f1f1', v_owner_1_id, 'owner', 'active', v_owner_1_id)
    ON CONFLICT (network_id, user_id) DO NOTHING;
    EXECUTE 'SET LOCAL ROLE authenticated';

    -- Confirm owner can read pending network initially
    PERFORM set_config('request.jwt.claim.sub', v_owner_1_id::text, true);
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE id = 'f1f1f1f1-f1f1-4f1f-a1f1-f1f1f1f1f1f1';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-28): Owner could not read pending network initially.';
    END IF;

    -- Revoke network_owner platform role
    EXECUTE 'SET LOCAL ROLE postgres';
    DELETE FROM public.user_roles WHERE user_id = v_owner_1_id AND role = 'network_owner';
    EXECUTE 'SET LOCAL ROLE authenticated';

    -- Verify owner membership alone without platform role denies access
    PERFORM set_config('request.jwt.claim.sub', v_owner_1_id::text, true);
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE id = 'f1f1f1f1-f1f1-4f1f-a1f1-f1f1f1f1f1f1';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-28): Revoked owner platform role still allowed reading pending network!';
    END IF;

    IF public.is_network_member('f1f1f1f1-f1f1-4f1f-a1f1-f1f1f1f1f1f1') THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-28): is_network_member returned true for user with revoked owner platform role!';
    END IF;

    -- Restore network_owner platform role
    EXECUTE 'SET LOCAL ROLE postgres';
    INSERT INTO public.user_roles (user_id, role) VALUES (v_owner_1_id, 'network_owner') ON CONFLICT (user_id, role) DO NOTHING;
    EXECUTE 'SET LOCAL ROLE authenticated';

    PERFORM set_config('request.jwt.claim.sub', v_owner_1_id::text, true);
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE id = 'f1f1f1f1-f1f1-4f1f-a1f1-f1f1f1f1f1f1';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-28): Restoring owner platform role did not restore network access.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-29: Platform role revocation renders operator membership inactive (G3)
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE postgres';
    INSERT INTO public.network_memberships (network_id, user_id, membership_role, status, created_by)
    VALUES ('f1f1f1f1-f1f1-4f1f-a1f1-f1f1f1f1f1f1', v_operator_id, 'operator', 'active', v_owner_1_id)
    ON CONFLICT (network_id, user_id) DO NOTHING;
    EXECUTE 'SET LOCAL ROLE authenticated';

    PERFORM set_config('request.jwt.claim.sub', v_operator_id::text, true);
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE id = 'f1f1f1f1-f1f1-4f1f-a1f1-f1f1f1f1f1f1';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-29): Operator could not read assigned network initially.';
    END IF;

    -- Revoke network_operator platform role
    EXECUTE 'SET LOCAL ROLE postgres';
    DELETE FROM public.user_roles WHERE user_id = v_operator_id AND role = 'network_operator';
    EXECUTE 'SET LOCAL ROLE authenticated';

    PERFORM set_config('request.jwt.claim.sub', v_operator_id::text, true);
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE id = 'f1f1f1f1-f1f1-4f1f-a1f1-f1f1f1f1f1f1';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-29): Revoked operator platform role still allowed reading assigned network!';
    END IF;

    -- Restore network_operator platform role
    EXECUTE 'SET LOCAL ROLE postgres';
    INSERT INTO public.user_roles (user_id, role) VALUES (v_operator_id, 'network_operator') ON CONFLICT (user_id, role) DO NOTHING;
    EXECUTE 'SET LOCAL ROLE authenticated';

    PERFORM set_config('request.jwt.claim.sub', v_operator_id::text, true);
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE id = 'f1f1f1f1-f1f1-4f1f-a1f1-f1f1f1f1f1f1';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-29): Restoring operator platform role did not restore network access.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-30: Real anonymous column privilege & visibility enforcement (G6)
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE anon';
    IF current_user != 'anon' THEN
        RAISE EXCEPTION 'TEST_FAIL: Session role is %, expected anon.', current_user;
    END IF;
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claims', '{}', true);

    -- Anonymous user selecting restricted created_by column on networks raises 42501
    v_err_occurred := FALSE;
    BEGIN
        EXECUTE 'SELECT created_by FROM public.networks WHERE id = ''f1f1f1f1-f1f1-4f1f-a1f1-f1f1f1f1f1f1''';
    EXCEPTION WHEN insufficient_privilege THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-30): Anonymous user was able to SELECT created_by column on networks!';
    END IF;

    -- Anonymous user selecting restricted approved_by column on networks raises 42501
    v_err_occurred := FALSE;
    BEGIN
        EXECUTE 'SELECT approved_by FROM public.networks WHERE id = ''f1f1f1f1-f1f1-4f1f-a1f1-f1f1f1f1f1f1''';
    EXCEPTION WHEN insufficient_privilege THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-30): Anonymous user was able to SELECT approved_by column on networks!';
    END IF;

    -- Anonymous user selecting restricted verified_by column on network_ssid_aliases raises 42501
    v_err_occurred := FALSE;
    BEGIN
        EXECUTE 'SELECT verified_by FROM public.network_ssid_aliases WHERE id = ''e1e1e1e1-e1e1-4e1e-a1e1-e1e1e1e1e1e1''';
    EXCEPTION WHEN insufficient_privilege THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-30): Anonymous user was able to SELECT verified_by column on network_ssid_aliases!';
    END IF;

    -- Anonymous user cannot see pending/unverified networks
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE id = 'f1f1f1f1-f1f1-4f1f-a1f1-f1f1f1f1f1f1';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-30): Anonymous user saw pending/unverified network!';
    END IF;

    RAISE NOTICE 'SUCCESS: All 30 Negative Authorization Tests Passed.';
END $$;

ROLLBACK;
