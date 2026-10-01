-- NetYemen V1 Operational Closure Final Contract Test Harness
-- File: supabase/tests/010_operational_closure.sql
-- Task ID: NY-V1-OPERATIONS-CLOSURE-001
-- Scope: Final operational contract checks for inventory idempotency and ACL
--        hardening that are best expressed as standalone assertions.
-- Note: True concurrent replay is enforced by the database unique index on
--       (package_id, idempotency_key) combined with the row-lock-first replay
--       check inside adjust_package_inventory. A live two-session concurrency
--       test was validated manually; this harness verifies the underlying
--       guarantees that make that concurrency property hold.

BEGIN;

DO $$
DECLARE
    v_owner_id         UUID := 'a0a0a0a0-a0a0-4a0a-aa0a-a0a0a0a0a0a0';
    v_net_id           UUID := 'b0b0b0b0-b0b0-4b0b-bb0b-b0b0b0b0b0b0';
    v_pkg_id           UUID := 'c0c0c0c0-c0c0-4c0c-cc0c-c0c0c0c0c0c0';
    v_key              UUID := 'd0d0d0d0-d0d0-4d0d-dd0d-d0d0d0d0d0d0';

    v_count            INT;
    v_balance          INT;
    v_result           JSONB;
    v_err_occurred     BOOLEAN;
BEGIN
    -- ------------------------------------------------------------------------
    -- FIXTURE SETUP
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE postgres';

    IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth') THEN
        INSERT INTO auth.users (id, email) VALUES
            (v_owner_id, 'closure_owner@netyemen.local')
        ON CONFLICT (id) DO NOTHING;
    END IF;

    INSERT INTO public.profiles (id, full_name, account_status) VALUES
        (v_owner_id, 'Closure Owner', 'active')
    ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name;

    INSERT INTO public.user_roles (user_id, role) VALUES
        (v_owner_id, 'network_owner')
    ON CONFLICT (user_id, role) DO NOTHING;

    INSERT INTO public.networks (
        id, commercial_name, status, verification_status,
        created_by, approved_by, approved_at
    ) VALUES (
        v_net_id, 'Closure Network', 'active', 'verified',
        v_owner_id, v_owner_id, NOW()
    ) ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.network_memberships (network_id, user_id, membership_role, status, created_by) VALUES
        (v_net_id, v_owner_id, 'owner', 'active', v_owner_id)
    ON CONFLICT (network_id, user_id) DO NOTHING;

    INSERT INTO public.network_packages (
        id, network_id, name, price, package_type, status, is_public, created_by
    ) VALUES (
        v_pkg_id, v_net_id, 'Closure Package', 100, 'time', 'active', FALSE, v_owner_id
    ) ON CONFLICT (id) DO NOTHING;

    -- ------------------------------------------------------------------------
    -- INV-01: Database unique index prevents duplicate (package_id, key)
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_owner_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner_id::text, 'role', 'authenticated')::text, true);

    PERFORM public.adjust_package_inventory(v_pkg_id, 10, 'Unique index test', v_key);

    -- Test the schema-level guarantee directly as postgres; clients cannot INSERT.
    EXECUTE 'SET LOCAL ROLE postgres';
    v_err_occurred := FALSE;
    BEGIN
        INSERT INTO public.package_inventory_movements (
            package_id, network_id, quantity_change,
            previous_total, new_total, previous_available, new_available,
            reason, actor_user_id, idempotency_key
        ) VALUES (
            v_pkg_id, v_net_id, 10, 0, 10, 0, 10,
            'Duplicate insert', v_owner_id, v_key
        );
    EXCEPTION WHEN unique_violation THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-01): Unique index allowed duplicate (package_id, idempotency_key).';
    END IF;

    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_owner_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner_id::text, 'role', 'authenticated')::text, true);

    -- ------------------------------------------------------------------------
    -- INV-02: RPC replay returns replayed=true without changing balance
    -- ------------------------------------------------------------------------
    v_result := public.adjust_package_inventory(v_pkg_id, 10, 'Unique index test', v_key);
    IF (v_result->>'replayed')::BOOLEAN IS NOT TRUE THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-02): Sequential replay did not return replayed=true.';
    END IF;

    SELECT available_units INTO v_balance
    FROM public.package_inventory_balances
    WHERE package_id = v_pkg_id;
    IF v_balance <> 10 THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-02): Balance changed after replay. Got %.', v_balance;
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM public.package_inventory_movements
    WHERE package_id = v_pkg_id AND idempotency_key = v_key;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-02): Expected exactly 1 movement, got %.', v_count;
    END IF;

    -- ------------------------------------------------------------------------
    -- INV-03: Payload mismatch is rejected even for the owner of the key
    -- ------------------------------------------------------------------------
    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.adjust_package_inventory(v_pkg_id, 99, 'Mismatched payload', v_key);
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-03): Payload mismatch was accepted.';
    END IF;

    SELECT available_units INTO v_balance
    FROM public.package_inventory_balances
    WHERE package_id = v_pkg_id;
    IF v_balance <> 10 THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-03): Balance changed after payload mismatch. Got %.', v_balance;
    END IF;

    -- ------------------------------------------------------------------------
    -- INV-04: Idempotency key column is NOT NULL
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE postgres';
    v_err_occurred := FALSE;
    BEGIN
        INSERT INTO public.package_inventory_movements (
            package_id, network_id, quantity_change,
            previous_total, new_total, previous_available, new_available,
            reason, actor_user_id, idempotency_key
        ) VALUES (
            v_pkg_id, v_net_id, 5, 10, 15, 10, 15,
            'NULL key test', v_owner_id, NULL
        );
    EXCEPTION WHEN not_null_violation THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-04): NULL idempotency_key was accepted.';
    END IF;

    RAISE NOTICE 'SUCCESS: All Operational Closure Contract Tests Passed.';
END $$;

ROLLBACK;
