-- NetYemen V1 Admin Operations Authorization Test Harness
-- File: supabase/tests/008_admin_operations.sql
-- Task ID: NY-V1-ADMIN-OPS-001
-- Scope: Admin dashboard, network approval, SSID alias verification, request review,
--        audit visibility, and role-boundary enforcement.

BEGIN;

DO $$
DECLARE
    v_customer_id      UUID := '01010101-0101-4101-a101-010101010101';
    v_owner_a_id       UUID := '02020202-0202-4202-a202-020202020202';
    v_owner_b_id       UUID := '03030303-0303-4303-a303-030303030303';
    v_operator_id      UUID := '04040404-0404-4404-a404-040404040404';
    v_support_id       UUID := '05050505-0505-4505-a505-050505050505';
    v_auditor_id       UUID := '06060606-0606-4606-a606-060606060606';
    v_admin_id         UUID := '07070707-0707-4707-a707-070707070707';

    v_net_a_id         UUID := '0a0a0a0a-0a0a-4a0a-aa0a-0a0a0a0a0a0a';
    v_net_b_id         UUID := '0b0b0b0b-0b0b-4b0b-ab0b-0b0b0b0b0b0b';
    v_pending_net_id   UUID := '0c0c0c0c-0c0c-4c0c-ac0c-0c0c0c0c0c0c';

    v_alias_id         UUID := '0d0d0d0d-0d0d-4d0d-ad0d-0d0d0d0d0d0d';
    v_request_id       UUID;

    v_result           JSONB;
    v_count            INT;
    v_kpis             JSONB;
    v_err_occurred     BOOLEAN;
BEGIN
    -- ------------------------------------------------------------------------
    -- FIXTURE SETUP
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE postgres';

    IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth') THEN
        INSERT INTO auth.users (id, email) VALUES
            (v_customer_id, 'customer_admin_test@netyemen.local'),
            (v_owner_a_id, 'owner_a_admin_test@netyemen.local'),
            (v_owner_b_id, 'owner_b_admin_test@netyemen.local'),
            (v_operator_id, 'operator_admin_test@netyemen.local'),
            (v_support_id, 'support_admin_test@netyemen.local'),
            (v_auditor_id, 'auditor_admin_test@netyemen.local'),
            (v_admin_id, 'admin_admin_test@netyemen.local')
        ON CONFLICT (id) DO NOTHING;
    END IF;

    INSERT INTO public.profiles (id, full_name, account_status) VALUES
        (v_customer_id, 'Test Customer', 'active'),
        (v_owner_a_id, 'Test Owner A', 'active'),
        (v_owner_b_id, 'Test Owner B', 'active'),
        (v_operator_id, 'Test Operator', 'active'),
        (v_support_id, 'Test Support Agent', 'active'),
        (v_auditor_id, 'Test Auditor', 'active'),
        (v_admin_id, 'Test Platform Admin', 'active')
    ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name;

    INSERT INTO public.user_roles (user_id, role) VALUES
        (v_customer_id, 'customer'),
        (v_owner_a_id, 'network_owner'),
        (v_owner_b_id, 'network_owner'),
        (v_operator_id, 'network_operator'),
        (v_support_id, 'support_agent'),
        (v_auditor_id, 'system_auditor'),
        (v_admin_id, 'platform_admin')
    ON CONFLICT (user_id, role) DO NOTHING;

    -- Approved active network A owned by owner A
    INSERT INTO public.networks (
        id, commercial_name, status, verification_status,
        created_by, approved_by, approved_at
    ) VALUES (
        v_net_a_id, 'Admin Test Network A', 'active', 'verified',
        v_owner_a_id, v_admin_id, NOW()
    ) ON CONFLICT (id) DO NOTHING;

    -- Approved active network B owned by owner B
    INSERT INTO public.networks (
        id, commercial_name, status, verification_status,
        created_by, approved_by, approved_at
    ) VALUES (
        v_net_b_id, 'Admin Test Network B', 'active', 'verified',
        v_owner_b_id, v_admin_id, NOW()
    ) ON CONFLICT (id) DO NOTHING;

    -- Pending network owned by owner A
    INSERT INTO public.networks (
        id, commercial_name, status, verification_status,
        created_by, approved_by, approved_at
    ) VALUES (
        v_pending_net_id, 'Admin Test Pending Network', 'pending_approval', 'unverified',
        v_owner_a_id, NULL, NULL
    ) ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.network_memberships (network_id, user_id, membership_role, status, created_by) VALUES
        (v_net_a_id, v_owner_a_id, 'owner', 'active', v_owner_a_id),
        (v_net_a_id, v_operator_id, 'operator', 'active', v_owner_a_id),
        (v_net_b_id, v_owner_b_id, 'owner', 'active', v_owner_b_id),
        (v_pending_net_id, v_owner_a_id, 'owner', 'active', v_owner_a_id)
    ON CONFLICT (network_id, user_id) DO NOTHING;

    -- Pending SSID alias on pending network
    INSERT INTO public.network_ssid_aliases (id, network_id, ssid_display, status)
    VALUES (v_alias_id, v_pending_net_id, 'AdminPendingSSID', 'pending_verification')
    ON CONFLICT (id) DO NOTHING;

    -- Seed an audit event via service_role to verify auditor read access
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    PERFORM public.record_audit_event('ADMIN_TEST_SETUP', 'system', NULL, 'success', 'SETUP', '{}'::jsonb);

    -- ========================================================================
    -- POSITIVE TESTS
    -- ========================================================================
    EXECUTE 'SET LOCAL ROLE authenticated';

    -- ------------------------------------------------------------------------
    -- POS-01: Platform admin can view dashboard KPIs
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text, 'role', 'authenticated')::text, true);

    v_kpis := public.admin_dashboard_kpis();
    IF v_kpis IS NULL OR (v_kpis->>'active_networks') IS NULL THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-01): admin_dashboard_kpis returned invalid result for admin.';
    END IF;

    -- ------------------------------------------------------------------------
    -- POS-02: Platform admin can approve a pending network
    -- ------------------------------------------------------------------------
    v_result := public.admin_approve_network(v_pending_net_id, 'Approved for pilot.');
    IF (v_result->>'status') <> 'active' THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-02): admin_approve_network did not return active status.';
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM public.networks
    WHERE id = v_pending_net_id AND status = 'active' AND verification_status = 'verified' AND approved_by = v_admin_id;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-02): Pending network was not approved coherently.';
    END IF;

    -- ------------------------------------------------------------------------
    -- POS-03: Platform admin can verify an SSID alias
    -- ------------------------------------------------------------------------
    v_result := public.admin_verify_ssid_alias(v_alias_id);
    IF (v_result->>'status') <> 'active' THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-03): admin_verify_ssid_alias did not return active status.';
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM public.network_ssid_aliases
    WHERE id = v_alias_id AND status = 'active' AND verified_by = v_admin_id;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-03): Alias was not verified coherently.';
    END IF;

    -- ------------------------------------------------------------------------
    -- POS-04: Platform admin can reject an SSID alias
    -- ------------------------------------------------------------------------
    DECLARE
        v_reject_alias_id UUID;
    BEGIN
        INSERT INTO public.network_ssid_aliases (network_id, ssid_display, status)
        VALUES (v_net_a_id, 'RejectMeSSID', 'pending_verification')
        RETURNING id INTO v_reject_alias_id;

        v_result := public.admin_reject_ssid_alias(v_reject_alias_id, 'Invalid alias.');
        IF (v_result->>'status') <> 'rejected' THEN
            RAISE EXCEPTION 'TEST_FAIL (POS-04): admin_reject_ssid_alias did not return rejected status.';
        END IF;
    END;

    -- ------------------------------------------------------------------------
    -- POS-05: Support agent can read all network addition requests
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_customer_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_customer_id::text, 'role', 'authenticated')::text, true);

    v_result := public.submit_network_addition_request(
        '77777777-7777-4777-a777-777777777777'::UUID,
        'AdminTestSSID',
        'Admin Test Proposed Net',
        'Sanaa',
        'Sanaa City',
        'District A',
        'Please review for admin tests'
    );
    v_request_id := (v_result->>'id')::UUID;

    PERFORM set_config('request.jwt.claim.sub', v_support_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_support_id::text, 'role', 'authenticated')::text, true);

    SELECT COUNT(*) INTO v_count
    FROM public.network_addition_requests
    WHERE id = v_request_id;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-05): Support agent could not read network addition request.';
    END IF;

    -- ------------------------------------------------------------------------
    -- POS-06: Support agent can resolve a request via existing resolve RPC
    -- ------------------------------------------------------------------------
    v_result := public.resolve_network_addition_request(
        v_request_id,
        'under_review',
        'Support is reviewing this request.'
    );
    IF (v_result->>'status') <> 'under_review' THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-06): Support agent could not set request to under_review.';
    END IF;

    v_result := public.resolve_network_addition_request(
        v_request_id,
        'matched_existing',
        'Matches existing network.',
        v_net_a_id
    );
    IF (v_result->>'status') <> 'matched_existing' THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-06): Support agent could not resolve request as matched_existing.';
    END IF;

    -- ------------------------------------------------------------------------
    -- POS-07: Auditor can read KPIs
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_auditor_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_auditor_id::text, 'role', 'authenticated')::text, true);

    v_kpis := public.admin_dashboard_kpis();
    IF v_kpis IS NULL THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-07): Auditor could not call admin_dashboard_kpis.';
    END IF;

    -- ------------------------------------------------------------------------
    -- POS-08: Auditor can read audit events
    -- ------------------------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM public.audit_events;
    IF v_count < 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-08): Auditor could not read audit events.';
    END IF;

    RAISE NOTICE 'ROLE_CONTEXT_ADMIN_PASS';

    -- ========================================================================
    -- NEGATIVE TESTS
    -- ========================================================================

    -- ------------------------------------------------------------------------
    -- NEG-01: Anonymous user cannot access admin dashboard KPIs
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE anon';
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claims', '{}', true);

    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.admin_dashboard_kpis();
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-01): Anonymous user accessed admin_dashboard_kpis.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-02: Anonymous user cannot approve a network
    -- ------------------------------------------------------------------------
    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.admin_approve_network(v_net_a_id);
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-02): Anonymous user approved a network.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-03: Customer cannot access admin RPCs
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_customer_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_customer_id::text, 'role', 'authenticated')::text, true);

    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.admin_dashboard_kpis();
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-03): Customer accessed admin_dashboard_kpis.';
    END IF;

    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.admin_approve_network(v_net_a_id);
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-03): Customer approved a network.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-04: Network owner cannot access platform admin operations
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_owner_a_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner_a_id::text, 'role', 'authenticated')::text, true);

    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.admin_dashboard_kpis();
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-04): Network owner accessed admin_dashboard_kpis.';
    END IF;

    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.admin_approve_network(v_net_a_id);
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-04): Network owner approved a network.';
    END IF;

    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.admin_verify_ssid_alias(v_alias_id);
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-04): Network owner verified an alias.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-05: Network operator cannot access platform admin operations
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_operator_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_operator_id::text, 'role', 'authenticated')::text, true);

    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.admin_approve_network(v_net_a_id);
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-05): Network operator approved a network.';
    END IF;

    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.admin_suspend_network(v_net_a_id);
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-05): Network operator suspended a network.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-06: Support agent cannot exceed request-review scope
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_support_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_support_id::text, 'role', 'authenticated')::text, true);

    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.admin_approve_network(v_net_a_id);
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-06): Support agent approved a network.';
    END IF;

    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.admin_suspend_network(v_net_a_id);
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-06): Support agent suspended a network.';
    END IF;

    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.admin_verify_ssid_alias(v_alias_id);
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-06): Support agent verified an SSID alias.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-07: Auditor cannot mutate admin-protected resources
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_auditor_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_auditor_id::text, 'role', 'authenticated')::text, true);

    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.admin_approve_network(v_net_a_id);
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-07): Auditor approved a network.';
    END IF;

    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.admin_verify_ssid_alias(v_alias_id);
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-07): Auditor verified an SSID alias.';
    END IF;

    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.resolve_network_addition_request(v_request_id, 'approved');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-07): Auditor resolved a network addition request.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-08: Cross-network owner/admin boundaries remain correct
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_owner_a_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner_a_id::text, 'role', 'authenticated')::text, true);

    -- Owner A cannot directly mutate network B status
    v_err_occurred := FALSE;
    BEGIN
        UPDATE public.networks SET status = 'suspended' WHERE id = v_net_b_id;
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE id = v_net_b_id AND status = 'suspended';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-08): Owner A suspended network B via direct DML.';
    END IF;

    -- Owner A cannot directly mutate network B membership
    v_err_occurred := FALSE;
    BEGIN
        UPDATE public.network_memberships SET status = 'suspended' WHERE network_id = v_net_b_id;
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    SELECT COUNT(*) INTO v_count FROM public.network_memberships WHERE network_id = v_net_b_id AND status = 'suspended';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-08): Owner A mutated network B membership via direct DML.';
    END IF;

    -- Owner A cannot approve network B via admin RPC
    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.admin_approve_network(v_net_b_id);
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-08): Owner A invoked admin_approve_network for network B.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-09: Direct restricted DML on networks is denied for non-admins
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_customer_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_customer_id::text, 'role', 'authenticated')::text, true);

    v_err_occurred := FALSE;
    BEGIN
        UPDATE public.networks SET status = 'active', verification_status = 'verified' WHERE id = v_net_a_id;
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    -- RLS should prevent customer from seeing the row, but the update will silently affect 0 rows if it passes.
    SELECT COUNT(*) INTO v_count FROM public.networks WHERE id = v_net_a_id AND approved_by = v_customer_id;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-09): Customer mutated network approval metadata.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-10: Direct restricted DML on SSID aliases is denied for non-admins
    -- ------------------------------------------------------------------------
    DECLARE
        v_new_alias_id UUID;
    BEGIN
        -- Create the pending alias as platform admin so we can test customer mutation.
        EXECUTE 'SET LOCAL ROLE postgres';
        PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
        INSERT INTO public.network_ssid_aliases (id, network_id, ssid_display, status)
        VALUES ('f0f0f0f0-f0f0-4f0f-af0f-f0f0f0f0f0f0', v_net_a_id, 'OwnerPendingSSID', 'pending_verification')
        ON CONFLICT (id) DO NOTHING
        RETURNING id INTO v_new_alias_id;
        v_new_alias_id := COALESCE(v_new_alias_id, 'f0f0f0f0-f0f0-4f0f-af0f-f0f0f0f0f0f0'::UUID);

        EXECUTE 'SET LOCAL ROLE authenticated';
        PERFORM set_config('request.jwt.claim.sub', v_customer_id::text, true);
        PERFORM set_config('request.jwt.claims', json_build_object('sub', v_customer_id::text, 'role', 'authenticated')::text, true);

        v_err_occurred := FALSE;
        BEGIN
            UPDATE public.network_ssid_aliases
            SET status = 'active', verified_by = v_customer_id, verified_at = NOW()
            WHERE id = v_new_alias_id;
        EXCEPTION WHEN OTHERS THEN
            v_err_occurred := TRUE;
        END;
        SELECT COUNT(*) INTO v_count FROM public.network_ssid_aliases WHERE id = v_new_alias_id AND status = 'active';
        IF v_count <> 0 THEN
            RAISE EXCEPTION 'TEST_FAIL (NEG-10): Customer self-activated an SSID alias.';
        END IF;
    END;

    RAISE NOTICE 'SUCCESS: All Admin Operations Authorization Tests Passed.';
END $$;

ROLLBACK;
