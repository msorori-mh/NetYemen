-- NetYemen Negative Authorization Test Harness
-- File: supabase/tests/003_core_authorization_negative.sql
-- Task ID: NY-GOV-BE-001

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

    -- Insert Networks
    INSERT INTO public.networks (id, commercial_name, status, verification_status, created_by) VALUES
        (v_net_1_id, 'Network One', 'active', 'verified', v_owner_1_id),
        (v_net_2_id, 'Network Two', 'active', 'verified', v_owner_2_id),
        (v_suspended_net_id, 'Suspended Net', 'suspended', 'unverified', v_owner_1_id)
    ON CONFLICT (id) DO NOTHING;

    -- Memberships
    INSERT INTO public.network_memberships (network_id, user_id, membership_role, status) VALUES
        (v_net_1_id, v_owner_1_id, 'owner', 'active'),
        (v_net_1_id, v_operator_id, 'operator', 'active'),
        (v_net_2_id, v_owner_2_id, 'owner', 'active')
    ON CONFLICT (network_id, user_id) DO NOTHING;

    -- ------------------------------------------------------------------------
    -- NEG-01: Customer cannot read another user's profile
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_user_a_id::text, true);
    SELECT COUNT(*) INTO v_count FROM public.profiles WHERE id = v_user_b_id;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-01): Customer A was able to read Customer B profile!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-02: Customer cannot self-assign platform roles
    -- ------------------------------------------------------------------------
    v_err_occurred := FALSE;
    BEGIN
        INSERT INTO public.user_roles (user_id, role) VALUES (v_user_a_id, 'platform_admin');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        -- Verify RLS filtered out or rejected insert
        SELECT COUNT(*) INTO v_count FROM public.user_roles WHERE user_id = v_user_a_id AND role = 'platform_admin';
        IF v_count <> 0 THEN
            RAISE EXCEPTION 'TEST_FAIL (NEG-02): Customer self-assigned platform_admin role!';
        END IF;
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-03: Customer cannot change own account_status
    -- ------------------------------------------------------------------------
    v_err_occurred := FALSE;
    BEGIN
        UPDATE public.profiles SET account_status = 'suspended' WHERE id = v_user_a_id;
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    -- Status must remain active (WITH CHECK blocks mutation or update affects 0 rows)
    IF EXISTS (SELECT 1 FROM public.profiles WHERE id = v_user_a_id AND account_status = 'suspended') THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-03): Customer modified account_status!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-04: Owner 1 cannot update Owner 2 network
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_owner_1_id::text, true);
    UPDATE public.networks SET commercial_name = 'Hacked Net Two' WHERE id = v_net_2_id;
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE id = v_net_2_id AND commercial_name = 'Hacked Net Two';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-04): Owner 1 modified Owner 2 network!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-05: Owner cannot self-approve own pending network
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_owner_1_id::text, true);
    UPDATE public.networks SET verification_status = 'verified' WHERE id = v_suspended_net_id;
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE id = v_suspended_net_id AND verification_status = 'verified';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-05): Owner self-approved pending network!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-06: Operator cannot approve or verify a network
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_operator_id::text, true);
    UPDATE public.networks SET verification_status = 'verified' WHERE id = v_suspended_net_id;
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE id = v_suspended_net_id AND verification_status = 'verified';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-06): Operator verified network!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-07: Operator cannot create or remove network memberships
    -- ------------------------------------------------------------------------
    v_err_occurred := FALSE;
    BEGIN
        INSERT INTO public.network_memberships (network_id, user_id, membership_role) VALUES (v_net_1_id, v_user_a_id, 'operator');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    SELECT COUNT(*) INTO v_count FROM public.network_memberships WHERE network_id = v_net_1_id AND user_id = v_user_a_id;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-07): Operator created network membership!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-08: Finance officer receives no general network-management privilege
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_finance_id::text, true);
    UPDATE public.networks SET commercial_name = 'Finance Net' WHERE id = v_net_1_id;
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE id = v_net_1_id AND commercial_name = 'Finance Net';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-08): Finance Officer updated commercial network!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-09: Support agent receives no general network-management privilege
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_support_id::text, true);
    UPDATE public.networks SET commercial_name = 'Support Net' WHERE id = v_net_1_id;
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE id = v_net_1_id AND commercial_name = 'Support Net';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-09): Support Agent updated commercial network!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-10: Auditor cannot mutate operational objects
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_auditor_id::text, true);
    UPDATE public.networks SET commercial_name = 'Auditor Net' WHERE id = v_net_1_id;
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE id = v_net_1_id AND commercial_name = 'Auditor Net';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-10): Auditor mutated operational network!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-11: Anonymous user cannot see suspended networks
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', '', true);
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE id = v_suspended_net_id;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-11): Anonymous user viewed suspended network!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-12: Client cannot direct-write to audit_events table
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_user_a_id::text, true);
    v_err_occurred := FALSE;
    BEGIN
        INSERT INTO public.audit_events (action, entity_type) VALUES ('DIRECT_INSERT', 'test');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    SELECT COUNT(*) INTO v_count FROM public.audit_events WHERE action = 'DIRECT_INSERT';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-12): Client inserted directly into audit_events!';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-13: Client cannot assign system_service role
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    v_err_occurred := FALSE;
    BEGIN
        INSERT INTO public.user_roles (user_id, role) VALUES (v_user_a_id, 'system_service');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    SELECT COUNT(*) INTO v_count FROM public.user_roles WHERE user_id = v_user_a_id AND role = 'system_service';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-13): Client assigned system_service role!';
    END IF;

    RAISE NOTICE 'SUCCESS: All 13 Negative Authorization Tests Passed.';
END $$;

ROLLBACK;
