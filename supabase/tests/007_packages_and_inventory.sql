-- NetYemen Network Packages & Inventory Authorization Test Harness
-- File: supabase/tests/007_packages_and_inventory.sql
-- Task ID: NY-V1-INVENTORY-PACKAGES-001
-- Scope: Package catalog, owner/operator package management, inventory ledger authorization
-- Security: NO card secrets, voucher codes, or access tokens are stored or tested here.

BEGIN;

DO $$
DECLARE
    v_customer_id   UUID := '11111111-1111-4111-a111-111111111111';
    v_owner_a_id    UUID := '22222222-2222-4222-a222-222222222222';
    v_owner_b_id    UUID := '33333333-3333-4333-a333-333333333333';
    v_operator_a_id UUID := '44444444-4444-4444-a444-444444444444';
    v_admin_id      UUID := '55555555-5555-4555-a555-555555555555';
    v_auditor_id    UUID := '66666666-6666-4666-a666-666666666666';

    v_net_a_id      UUID := 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa';
    v_net_b_id      UUID := 'bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb';
    v_pending_net_id UUID := 'cccccccc-cccc-4ccc-cccc-cccccccccccc';

    v_pkg_a_draft_id UUID;
    v_pkg_a_active_id UUID;
    v_pkg_a_public_id UUID;
    v_pkg_b_active_id UUID;
    v_pkg_pending_id UUID;
    v_result JSONB;
    v_status TEXT;
    v_is_public BOOLEAN;
    v_count INT;
    v_err_occurred BOOLEAN;
    v_balance INT;
    v_total INT;
BEGIN
    -- ------------------------------------------------------------------------
    -- FIXTURE SETUP
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE postgres';

    IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth') THEN
        INSERT INTO auth.users (id, email) VALUES
            (v_customer_id, 'customer@netyemen.local'),
            (v_owner_a_id, 'owner_a@netyemen.local'),
            (v_owner_b_id, 'owner_b@netyemen.local'),
            (v_operator_a_id, 'operator_a@netyemen.local'),
            (v_admin_id, 'admin@netyemen.local'),
            (v_auditor_id, 'auditor@netyemen.local')
        ON CONFLICT (id) DO NOTHING;
    END IF;

    INSERT INTO public.profiles (id, full_name, account_status) VALUES
        (v_customer_id, 'Test Customer', 'active'),
        (v_owner_a_id, 'Owner A', 'active'),
        (v_owner_b_id, 'Owner B', 'active'),
        (v_operator_a_id, 'Operator A', 'active'),
        (v_admin_id, 'Test Admin', 'active'),
        (v_auditor_id, 'Test Auditor', 'active')
    ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name;

    INSERT INTO public.user_roles (user_id, role) VALUES
        (v_customer_id, 'customer'),
        (v_owner_a_id, 'network_owner'),
        (v_owner_b_id, 'network_owner'),
        (v_operator_a_id, 'network_operator'),
        (v_admin_id, 'platform_admin'),
        (v_auditor_id, 'system_auditor')
    ON CONFLICT (user_id, role) DO NOTHING;

    -- Approved active network A owned by owner A
    INSERT INTO public.networks (
        id, commercial_name, status, verification_status,
        created_by, approved_by, approved_at
    ) VALUES (
        v_net_a_id, 'Approved Network A', 'active', 'verified',
        v_owner_a_id, v_admin_id, NOW()
    ) ON CONFLICT (id) DO NOTHING;

    -- Approved active network B owned by owner B
    INSERT INTO public.networks (
        id, commercial_name, status, verification_status,
        created_by, approved_by, approved_at
    ) VALUES (
        v_net_b_id, 'Approved Network B', 'active', 'verified',
        v_owner_b_id, v_admin_id, NOW()
    ) ON CONFLICT (id) DO NOTHING;

    -- Pending/unverified network owned by owner A
    INSERT INTO public.networks (
        id, commercial_name, status, verification_status,
        created_by, approved_by, approved_at
    ) VALUES (
        v_pending_net_id, 'Pending Network A', 'pending_approval', 'unverified',
        v_owner_a_id, NULL, NULL
    ) ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.network_memberships (network_id, user_id, membership_role, status, created_by) VALUES
        (v_net_a_id, v_owner_a_id, 'owner', 'active', v_owner_a_id),
        (v_net_a_id, v_operator_a_id, 'operator', 'active', v_owner_a_id),
        (v_net_b_id, v_owner_b_id, 'owner', 'active', v_owner_b_id),
        (v_pending_net_id, v_owner_a_id, 'owner', 'active', v_owner_a_id)
    ON CONFLICT (network_id, user_id) DO NOTHING;

    -- Seed some packages directly for catalog/read tests (creation RPC tested separately)
    INSERT INTO public.network_packages (
        id, network_id, name, description, price, duration_value, duration_unit,
        speed_mbps, package_type, status, is_public, sort_order, created_by
    ) VALUES (
        'd1d1d1d1-d1d1-4d1d-a1d1-d1d1d1d1d1d1', v_net_a_id, 'Draft Package A',
        'Owner-only draft', 500, 1, 'day', 10, 'time', 'draft', FALSE, 1, v_owner_a_id
    ) ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.network_packages (
        id, network_id, name, description, price, duration_value, duration_unit,
        speed_mbps, package_type, status, is_public, sort_order, created_by
    ) VALUES (
        'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1', v_net_a_id, 'Active Public Package A',
        'Public customer-facing package', 1000, 7, 'day', 20, 'time', 'active', TRUE, 2, v_owner_a_id
    ) ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.network_packages (
        id, network_id, name, description, price, duration_value, duration_unit,
        speed_mbps, package_type, status, is_public, sort_order, created_by
    ) VALUES (
        'b1b1b1b1-b1b1-4b1b-b1b1-b1b1b1b1b1b1', v_net_a_id, 'Active Hidden Package A',
        'Active but not public', 1500, 1, 'month', 50, 'volume', 'active', FALSE, 3, v_owner_a_id
    ) ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.network_packages (
        id, network_id, name, description, price, duration_value, duration_unit,
        speed_mbps, package_type, status, is_public, sort_order, created_by
    ) VALUES (
        'c1c1c1c1-c1c1-4c1c-a1c1-c1c1c1c1c1c1', v_net_b_id, 'Active Public Package B',
        'Public package on network B', 800, 1, 'day', 15, 'time', 'active', TRUE, 1, v_owner_b_id
    ) ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.network_packages (
        id, network_id, name, description, price, duration_value, duration_unit,
        speed_mbps, package_type, status, is_public, sort_order, created_by
    ) VALUES (
        'e1e1e1e1-e1e1-4e1e-a1e1-e1e1e1e1e1e1', v_pending_net_id, 'Package on Pending Net',
        'Should not be public', 600, 1, 'day', 10, 'time', 'active', TRUE, 1, v_owner_a_id
    ) ON CONFLICT (id) DO NOTHING;

    -- Initialize balances for seeded packages
    INSERT INTO public.package_inventory_balances (package_id, network_id, total_units, available_units)
    VALUES
        ('d1d1d1d1-d1d1-4d1d-a1d1-d1d1d1d1d1d1', v_net_a_id, 0, 0),
        ('a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1', v_net_a_id, 100, 100),
        ('b1b1b1b1-b1b1-4b1b-b1b1-b1b1b1b1b1b1', v_net_a_id, 50, 50),
        ('c1c1c1c1-c1c1-4c1c-a1c1-c1c1c1c1c1c1', v_net_b_id, 200, 200),
        ('e1e1e1e1-e1e1-4e1e-a1e1-e1e1e1e1e1e1', v_pending_net_id, 10, 10)
    ON CONFLICT (package_id) DO NOTHING;

    -- =======================================================================
    -- POSITIVE TESTS
    -- =======================================================================
    EXECUTE 'SET LOCAL ROLE authenticated';

    -- ------------------------------------------------------------------------
    -- POS-01: Owner A manages packages for owned network A via RPC
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_owner_a_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner_a_id::text, 'role', 'authenticated')::text, true);

    v_pkg_a_draft_id := public.create_network_package(
        v_net_a_id,
        'RPC Created Package',
        'Created via controlled RPC',
        2500,
        'YER',
        30,
        'day',
        100,
        'time'
    );

    IF v_pkg_a_draft_id IS NULL THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-01): create_network_package returned NULL.';
    END IF;

    SELECT status INTO v_status
    FROM public.network_packages
    WHERE id = v_pkg_a_draft_id;

    IF v_status IS NULL OR v_status != 'draft' THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-01): New package was not created in draft status.';
    END IF;

    -- ------------------------------------------------------------------------
    -- POS-02: Owner A updates own package metadata
    -- ------------------------------------------------------------------------
    v_result := public.update_network_package(
        v_pkg_a_draft_id,
        'Updated Package Name',
        'Updated description',
        3000,
        'YER',
        NULL,
        NULL,
        NULL,
        NULL,
        5
    );

    SELECT COUNT(*) INTO v_count
    FROM public.network_packages
    WHERE id = v_pkg_a_draft_id AND name = 'Updated Package Name' AND price = 3000;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-02): Owner could not update package metadata.';
    END IF;

    -- ------------------------------------------------------------------------
    -- POS-03: Owner A publishes a package and it becomes publicly visible
    -- ------------------------------------------------------------------------
    v_result := public.publish_network_package(v_pkg_a_draft_id);
    IF (v_result->>'status') <> 'active' THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-03): publish_network_package did not return active status.';
    END IF;

    SELECT is_public INTO v_is_public
    FROM public.network_packages
    WHERE id = v_pkg_a_draft_id;
    IF v_is_public IS NULL OR v_is_public != TRUE THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-03): Published package is not public.';
    END IF;

    -- ------------------------------------------------------------------------
    -- POS-04: Owner A adjusts inventory for own package
    -- ------------------------------------------------------------------------
    v_result := public.adjust_package_inventory(
        v_pkg_a_draft_id,
        25,
        'Initial stock upload',
        '11111111-1111-4111-b111-111111111111'::UUID
    );

    IF (v_result->>'new_available')::INT <> 25 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-04): Inventory adjustment did not yield expected available stock. Got %.', v_result;
    END IF;

    SELECT total_units, available_units INTO v_total, v_balance
    FROM public.package_inventory_balances
    WHERE package_id = v_pkg_a_draft_id;
    IF v_total <> 25 OR v_balance <> 25 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-04): Balance not updated to 25/25. Got total=%, available=%.', v_total, v_balance;
    END IF;

    -- ------------------------------------------------------------------------
    -- POS-05: Operator A adjusts inventory for assigned network A
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_operator_a_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_operator_a_id::text, 'role', 'authenticated')::text, true);

    v_result := public.adjust_package_inventory(
        v_pkg_a_draft_id,
        10,
        'Operator stock addition',
        '22222222-2222-4222-b222-222222222222'::UUID
    );

    IF (v_result->>'new_available')::INT <> 35 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-05): Operator inventory adjustment did not yield expected stock. Got %.', v_result;
    END IF;

    -- ------------------------------------------------------------------------
    -- POS-06: Public package listing for customer/anonymous shows only public active packages on approved networks
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_customer_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_customer_id::text, 'role', 'authenticated')::text, true);

    SELECT COUNT(*) INTO v_count
    FROM public.network_packages
    WHERE status = 'active' AND is_public = TRUE;
    IF v_count <> 3 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-06): Public catalog expected 3 packages, got %.', v_count;
    END IF;

    -- Verify the pending-network package and hidden package are not visible
    SELECT COUNT(*) INTO v_count
    FROM public.network_packages
    WHERE id IN ('b1b1b1b1-b1b1-4b1b-b1b1-b1b1b1b1b1b1', 'e1e1e1e1-e1e1-4e1e-a1e1-e1e1e1e1e1e1');
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-06): Public catalog leaked hidden or pending-network packages.';
    END IF;

    -- ------------------------------------------------------------------------
    -- POS-07: Owner A can view all packages for owned network including draft
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_owner_a_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner_a_id::text, 'role', 'authenticated')::text, true);

    SELECT COUNT(*) INTO v_count
    FROM public.network_packages
    WHERE network_id = v_net_a_id;
    IF v_count <> 4 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-07): Owner A expected 4 packages on network A, got %.', v_count;
    END IF;

    -- ------------------------------------------------------------------------
    -- POS-08: Owner A can view inventory movements for owned network
    -- ------------------------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM public.package_inventory_movements
    WHERE network_id = v_net_a_id;
    IF v_count <> 2 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-08): Expected 2 inventory movements on network A, got %.', v_count;
    END IF;

    -- ------------------------------------------------------------------------
    -- POS-09: Idempotent replay of adjustment returns same result without double-counting
    -- ------------------------------------------------------------------------
    v_result := public.adjust_package_inventory(
        v_pkg_a_draft_id,
        10,
        'Operator stock addition',
        '22222222-2222-4222-b222-222222222222'::UUID
    );

    IF (v_result->>'replayed')::BOOLEAN IS NOT TRUE THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-09): Idempotent replay did not return replayed=true. Got %.', v_result;
    END IF;

    SELECT total_units, available_units INTO v_total, v_balance
    FROM public.package_inventory_balances
    WHERE package_id = v_pkg_a_draft_id;
    IF v_total <> 35 OR v_balance <> 35 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-09): Idempotent replay double-applied stock. Got total=%, available=%.', v_total, v_balance;
    END IF;

    -- ------------------------------------------------------------------------
    -- POS-10: Distinct UUIDs are independent
    -- ------------------------------------------------------------------------
    v_result := public.adjust_package_inventory(
        v_pkg_a_draft_id,
        5,
        'Distinct key addition',
        '88888888-8888-4888-a888-888888888888'::UUID
    );

    IF (v_result->>'new_available')::INT <> 40 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-10): Distinct UUID was not independent. Got %.', v_result;
    END IF;

    SELECT total_units, available_units INTO v_total, v_balance
    FROM public.package_inventory_balances
    WHERE package_id = v_pkg_a_draft_id;
    IF v_total <> 40 OR v_balance <> 40 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-10): Balance not 40/40 after distinct key. Got total=%, available=%.', v_total, v_balance;
    END IF;

    -- ------------------------------------------------------------------------
    -- POS-11: Auditor can read packages and inventory
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_auditor_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_auditor_id::text, 'role', 'authenticated')::text, true);

    SELECT COUNT(*) INTO v_count FROM public.network_packages;
    IF v_count < 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-11): Auditor could not read packages.';
    END IF;

    SELECT COUNT(*) INTO v_count FROM public.package_inventory_balances;
    IF v_count < 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-11): Auditor could not read inventory balances.';
    END IF;

    SELECT COUNT(*) INTO v_count FROM public.package_inventory_movements;
    IF v_count < 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (POS-11): Auditor could not read inventory movements.';
    END IF;

    -- =======================================================================
    -- NEGATIVE TESTS
    -- =======================================================================

    -- ------------------------------------------------------------------------
    -- NEG-01: Anonymous user cannot create a package
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE anon';
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claims', '{}', true);

    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.create_network_package(v_net_a_id, 'Anon Package');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-01): Anonymous user created a package.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-02: Customer cannot create a package
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_customer_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_customer_id::text, 'role', 'authenticated')::text, true);

    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.create_network_package(v_net_a_id, 'Customer Package');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-02): Customer created a package.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-03: Customer cannot adjust inventory
    -- ------------------------------------------------------------------------
    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.adjust_package_inventory(
            v_pkg_a_draft_id,
            5,
            'Customer adjustment',
            '33333333-3333-4333-c333-333333333333'::UUID
        );
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-03): Customer adjusted inventory.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-04: Owner A cannot manage Owner B network packages
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_owner_a_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner_a_id::text, 'role', 'authenticated')::text, true);

    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.update_network_package('c1c1c1c1-c1c1-4c1c-a1c1-c1c1c1c1c1c1', name := 'Hacked Name');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-04): Owner A updated Owner B package.';
    END IF;

    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.adjust_package_inventory(
            'c1c1c1c1-c1c1-4c1c-a1c1-c1c1c1c1c1c1',
            5,
            'Cross-network adjustment',
            '44444444-4444-4444-c444-444444444444'::UUID
        );
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-04): Owner A adjusted Owner B inventory.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-05: Operator cannot create/update/publish packages
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_operator_a_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_operator_a_id::text, 'role', 'authenticated')::text, true);

    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.create_network_package(v_net_a_id, 'Operator Package');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-05): Operator created a package.';
    END IF;

    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.update_network_package(v_pkg_a_draft_id, name := 'Operator Rename');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-05): Operator updated a package.';
    END IF;

    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.publish_network_package('d1d1d1d1-d1d1-4d1d-a1d1-d1d1d1d1d1d1');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-05): Operator published a package.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-06: Direct DML on network_packages is denied
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_owner_a_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner_a_id::text, 'role', 'authenticated')::text, true);

    v_err_occurred := FALSE;
    BEGIN
        INSERT INTO public.network_packages (network_id, name, price, package_type, status)
        VALUES (v_net_a_id, 'Direct Insert', 100, 'time', 'active');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-06): Direct INSERT into network_packages succeeded.';
    END IF;

    v_err_occurred := FALSE;
    BEGIN
        UPDATE public.network_packages SET name = 'Direct Update' WHERE id = v_pkg_a_draft_id;
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    SELECT COUNT(*) INTO v_count FROM public.network_packages WHERE id = v_pkg_a_draft_id AND name = 'Direct Update';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-06): Direct UPDATE on network_packages succeeded.';
    END IF;

    v_err_occurred := FALSE;
    BEGIN
        DELETE FROM public.network_packages WHERE id = v_pkg_a_draft_id;
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    SELECT COUNT(*) INTO v_count FROM public.network_packages WHERE id = v_pkg_a_draft_id;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-06): Direct DELETE on network_packages succeeded.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-07: Direct DML on inventory balances/movements is denied
    -- ------------------------------------------------------------------------
    v_err_occurred := FALSE;
    BEGIN
        UPDATE public.package_inventory_balances
        SET total_units = 999, available_units = 999
        WHERE package_id = v_pkg_a_draft_id;
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    SELECT total_units INTO v_total FROM public.package_inventory_balances WHERE package_id = v_pkg_a_draft_id;
    IF v_total <> 40 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-07): Direct UPDATE on package_inventory_balances succeeded. Got %.', v_total;
    END IF;

    v_err_occurred := FALSE;
    BEGIN
        INSERT INTO public.package_inventory_movements (
            package_id, network_id, quantity_change,
            previous_total, new_total, previous_available, new_available, reason, idempotency_key
        ) VALUES (
            v_pkg_a_draft_id, v_net_a_id, 100, 35, 135, 35, 135, 'Direct movement',
            '99999999-9999-4999-a999-999999999999'::UUID
        );
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-07): Direct INSERT into package_inventory_movements succeeded.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-08: Inventory cannot go negative
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_owner_a_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner_a_id::text, 'role', 'authenticated')::text, true);

    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.adjust_package_inventory(
            v_pkg_a_draft_id,
            -41,
            'Over-correction',
            '55555555-5555-4555-c555-555555555555'::UUID
        );
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-08): Inventory adjustment to negative was accepted.';
    END IF;

    SELECT available_units INTO v_balance FROM public.package_inventory_balances WHERE package_id = v_pkg_a_draft_id;
    IF v_balance <> 40 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-08): Balance changed despite negative adjustment rejection. Got %.', v_balance;
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-09: Inactive package is not public
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_owner_a_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner_a_id::text, 'role', 'authenticated')::text, true);

    -- Create and publish a package, then deactivate it
    v_pkg_a_active_id := public.create_network_package(v_net_a_id, 'Temp Active Package', 'To be deactivated', 500, 'YER', 1, 'day');
    PERFORM public.publish_network_package(v_pkg_a_active_id);
    v_result := public.deactivate_network_package(v_pkg_a_active_id);
    IF (v_result->>'status') <> 'inactive' THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-09): deactivate_network_package did not return inactive.';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', v_customer_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_customer_id::text, 'role', 'authenticated')::text, true);

    SELECT COUNT(*) INTO v_count
    FROM public.network_packages
    WHERE id = v_pkg_a_active_id AND status = 'active' AND is_public = TRUE;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-09): Inactive package still visible in public catalog.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-10: Package on unapproved/pending network is not public
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_customer_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_customer_id::text, 'role', 'authenticated')::text, true);

    SELECT COUNT(*) INTO v_count
    FROM public.network_packages
    WHERE id = 'e1e1e1e1-e1e1-4e1e-a1e1-e1e1e1e1e1e1';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-10): Package on pending network leaked to public catalog.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-11: Archived package cannot be published or edited
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_owner_a_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner_a_id::text, 'role', 'authenticated')::text, true);

    v_result := public.archive_network_package(v_pkg_a_active_id);
    IF (v_result->>'status') <> 'archived' THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-11): archive_network_package did not return archived.';
    END IF;

    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.publish_network_package(v_pkg_a_active_id);
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-11): Archived package was published.';
    END IF;

    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.update_network_package(v_pkg_a_active_id, name := 'Edit Archived');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-11): Archived package was edited.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-12: Customer cannot view inventory counts
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_customer_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_customer_id::text, 'role', 'authenticated')::text, true);

    SELECT COUNT(*) INTO v_count FROM public.package_inventory_balances;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-12): Customer was able to view % inventory balances.', v_count;
    END IF;

    SELECT COUNT(*) INTO v_count FROM public.package_inventory_movements;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-12): Customer was able to view % inventory movements.', v_count;
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-13: Anonymous user has no inventory visibility
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE anon';
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claims', '{}', true);

    v_err_occurred := FALSE;
    BEGIN
        SELECT COUNT(*) INTO v_count FROM public.package_inventory_balances;
    EXCEPTION WHEN insufficient_privilege THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-13): Anonymous user was able to query package_inventory_balances without privilege error.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-14: Spoofed actor cannot be set on direct movement (direct insert already denied above; extra RPC check)
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_owner_a_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner_a_id::text, 'role', 'authenticated')::text, true);

    -- The RPC always uses auth.uid() as actor; there is no parameter to spoof.
    -- Verified by POS-04/05 reading movements where actor_user_id = auth.uid().
    SELECT COUNT(*) INTO v_count
    FROM public.package_inventory_movements
    WHERE package_id = v_pkg_a_draft_id AND actor_user_id = v_operator_a_id;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-14): Expected exactly one movement attributed to operator A. Got %.', v_count;
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-15: Public catalog does not leak non-public package details
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_customer_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_customer_id::text, 'role', 'authenticated')::text, true);

    SELECT COUNT(*) INTO v_count
    FROM public.network_packages
    WHERE network_id = v_net_a_id;
    IF v_count <> 2 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-15): Public customer saw % packages for network A instead of 2.', v_count;
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-16: Stock-out state returns zero available
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_owner_a_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner_a_id::text, 'role', 'authenticated')::text, true);

    v_pkg_a_public_id := public.create_network_package(
        v_net_a_id, 'Stock Out Test', 'Will be depleted', 100, 'YER', 1, 'hour'
    );
    PERFORM public.publish_network_package(v_pkg_a_public_id);
    PERFORM public.adjust_package_inventory(v_pkg_a_public_id, 5, 'Seed stock', '66666666-6666-4666-d666-666666666666'::UUID);
    PERFORM public.adjust_package_inventory(v_pkg_a_public_id, -5, 'Deplete stock', '77777777-7777-4777-d777-777777777777'::UUID);

    SELECT available_units INTO v_balance
    FROM public.package_inventory_balances
    WHERE package_id = v_pkg_a_public_id;
    IF v_balance <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-16): Stock-out did not result in zero available. Got %.', v_balance;
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-17: NULL idempotency key is rejected
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_owner_a_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner_a_id::text, 'role', 'authenticated')::text, true);

    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.adjust_package_inventory(
            v_pkg_a_draft_id,
            1,
            'Missing key',
            NULL::UUID
        );
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-17): NULL idempotency key was accepted.';
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-18: Same key with different payload raises payload mismatch
    -- ------------------------------------------------------------------------
    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.adjust_package_inventory(
            v_pkg_a_draft_id,
            100,
            'Different reason',
            '22222222-2222-4222-b222-222222222222'::UUID
        );
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-18): Same key with different payload was accepted.';
    END IF;

    -- Balance must remain unchanged after the mismatched replay
    SELECT available_units INTO v_balance FROM public.package_inventory_balances WHERE package_id = v_pkg_a_draft_id;
    IF v_balance <> 40 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-18): Balance changed after payload-mismatch replay. Got %.', v_balance;
    END IF;

    -- ------------------------------------------------------------------------
    -- NEG-19: Cross-user replay with mismatched payload is denied
    -- ------------------------------------------------------------------------
    -- Owner A seeded key '11111111...' on v_pkg_a_draft_id with quantity 25.
    -- Operator A also operates network A; replaying the same UUID with a
    -- different payload must fail closed (the key is bound to the payload).
    PERFORM set_config('request.jwt.claim.sub', v_operator_a_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_operator_a_id::text, 'role', 'authenticated')::text, true);

    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.adjust_package_inventory(
            v_pkg_a_draft_id,
            99,
            'Cross-user replay with different payload',
            '11111111-1111-4111-b111-111111111111'::UUID
        );
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-19): Cross-user replay with mismatched payload was accepted.';
    END IF;

    SELECT available_units INTO v_balance FROM public.package_inventory_balances WHERE package_id = v_pkg_a_draft_id;
    IF v_balance <> 40 THEN
        RAISE EXCEPTION 'TEST_FAIL (NEG-19): Balance changed after cross-user payload-mismatch replay. Got %.', v_balance;
    END IF;

    RAISE NOTICE 'SUCCESS: All Packages & Inventory Authorization Tests Passed.';
END $$;

ROLLBACK;
