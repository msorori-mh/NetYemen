-- NetYemen V1 Client TRUNCATE ACL Hardening Test Harness
-- File: supabase/tests/009_client_truncate_acl_hardening.sql
-- Task ID: NY-V1-OPERATIONS-CLOSURE-001
-- Scope: Verify that PUBLIC, anon, and authenticated roles cannot TRUNCATE any
--        NetYemen application table, and that intended read access still works.

BEGIN;

DO $$
DECLARE
    v_customer_id      UUID := '90909090-9090-4909-a909-909090909090';
    v_admin_id         UUID := '91919191-9191-4919-a919-919191919191';

    v_table            TEXT;
    v_acl              TEXT;
    v_err_occurred     BOOLEAN;
    v_count            INT;

    -- NetYemen application tables that must be protected from client TRUNCATE.
    v_tables TEXT[] := ARRAY[
        'profiles',
        'user_roles',
        'networks',
        'network_memberships',
        'network_ssid_aliases',
        'audit_events',
        'network_addition_requests',
        'network_packages',
        'package_inventory_balances',
        'package_inventory_movements'
    ];
BEGIN
    -- ------------------------------------------------------------------------
    -- FIXTURE SETUP
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE postgres';

    IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth') THEN
        INSERT INTO auth.users (id, email) VALUES
            (v_customer_id, 'acl_customer@netyemen.local'),
            (v_admin_id, 'acl_admin@netyemen.local')
        ON CONFLICT (id) DO NOTHING;
    END IF;

    INSERT INTO public.profiles (id, full_name, account_status) VALUES
        (v_customer_id, 'ACL Customer', 'active'),
        (v_admin_id, 'ACL Admin', 'active')
    ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name;

    INSERT INTO public.user_roles (user_id, role) VALUES
        (v_customer_id, 'customer'),
        (v_admin_id, 'platform_admin')
    ON CONFLICT (user_id, role) DO NOTHING;

    INSERT INTO public.networks (
        id, commercial_name, status, verification_status,
        created_by, approved_by, approved_at
    ) VALUES (
        'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',
        'ACL Test Network',
        'active',
        'verified',
        v_admin_id,
        v_admin_id,
        NOW()
    ) ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.network_packages (
        id, network_id, name, price, package_type, status, is_public, created_by
    ) VALUES (
        'bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',
        'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',
        'ACL Package',
        100,
        'time',
        'active',
        TRUE,
        v_admin_id
    ) ON CONFLICT (id) DO NOTHING;

    -- ------------------------------------------------------------------------
    -- TEST-01: Effective ACLs contain no TRUNCATE (D) for PUBLIC/anon/authenticated
    -- ------------------------------------------------------------------------
    FOREACH v_table IN ARRAY v_tables
    LOOP
        SELECT array_to_string(relacl, ', ') INTO v_acl
        FROM pg_class
        WHERE relnamespace = 'public'::regnamespace
          AND relname = v_table;

        IF v_acl LIKE '%PUBLIC=%D%' THEN
            RAISE EXCEPTION 'TEST_FAIL (TEST-01): PUBLIC retains TRUNCATE on % (ACL: %).', v_table, v_acl;
        END IF;

        IF v_acl LIKE '%anon=%D%' THEN
            RAISE EXCEPTION 'TEST_FAIL (TEST-01): anon retains TRUNCATE on % (ACL: %).', v_table, v_acl;
        END IF;

        IF v_acl LIKE '%authenticated=%D%' THEN
            RAISE EXCEPTION 'TEST_FAIL (TEST-01): authenticated retains TRUNCATE on % (ACL: %).', v_table, v_acl;
        END IF;
    END LOOP;

    -- ------------------------------------------------------------------------
    -- TEST-02: anon TRUNCATE is denied on every protected table
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE anon';
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claims', '{}', true);

    FOREACH v_table IN ARRAY v_tables
    LOOP
        v_err_occurred := FALSE;
        BEGIN
            EXECUTE format('TRUNCATE TABLE public.%I;', v_table);
        EXCEPTION WHEN insufficient_privilege THEN
            v_err_occurred := TRUE;
        END;
        IF NOT v_err_occurred THEN
            RAISE EXCEPTION 'TEST_FAIL (TEST-02): anon succeeded TRUNCATE on %.', v_table;
        END IF;
    END LOOP;

    -- ------------------------------------------------------------------------
    -- TEST-03: authenticated TRUNCATE is denied on every protected table
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_customer_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_customer_id::text, 'role', 'authenticated')::text, true);

    FOREACH v_table IN ARRAY v_tables
    LOOP
        v_err_occurred := FALSE;
        BEGIN
            EXECUTE format('TRUNCATE TABLE public.%I;', v_table);
        EXCEPTION WHEN insufficient_privilege THEN
            v_err_occurred := TRUE;
        END;
        IF NOT v_err_occurred THEN
            RAISE EXCEPTION 'TEST_FAIL (TEST-03): authenticated succeeded TRUNCATE on %.', v_table;
        END IF;
    END LOOP;

    -- ------------------------------------------------------------------------
    -- TEST-04: Legitimate read access remains for authenticated
    -- ------------------------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM public.networks;
    IF v_count < 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (TEST-04): authenticated lost SELECT on networks.';
    END IF;

    SELECT COUNT(*) INTO v_count FROM public.network_packages;
    IF v_count < 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (TEST-04): authenticated lost SELECT on network_packages.';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST-05: Legitimate public catalog read remains for anon
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE anon';
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claims', '{}', true);

    SELECT COUNT(*) INTO v_count
    FROM public.network_packages
    WHERE status = 'active' AND is_public = TRUE;
    -- The fixture has one public active package, so count should be >= 1.
    IF v_count < 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (TEST-05): anon lost public catalog SELECT. Got %.', v_count;
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST-06: DIRECT destructive DML (DELETE/UPDATE) on audit_events is denied
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_customer_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_customer_id::text, 'role', 'authenticated')::text, true);

    v_err_occurred := FALSE;
    BEGIN
        DELETE FROM public.audit_events;
    EXCEPTION WHEN insufficient_privilege THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (TEST-06): authenticated succeeded DELETE on audit_events.';
    END IF;

    v_err_occurred := FALSE;
    BEGIN
        UPDATE public.audit_events SET result = 'failure';
    EXCEPTION WHEN insufficient_privilege THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (TEST-06): authenticated succeeded UPDATE on audit_events.';
    END IF;

    RAISE NOTICE 'SUCCESS: All Client TRUNCATE ACL Hardening Tests Passed.';
END $$;

ROLLBACK;
