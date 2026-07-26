-- NetYemen Core Schema Contract Test
-- File: supabase/tests/001_core_schema_contract.sql
-- Task ID: NY-GOV-BE-001 / NY-GOV-BE-001B

BEGIN;

-- 1. Test presence of required tables
DO $$
DECLARE
    v_missing_tables TEXT[] := ARRAY[]::TEXT[];
    v_table TEXT;
    v_required_tables TEXT[] := ARRAY[
        'profiles',
        'user_roles',
        'networks',
        'network_memberships',
        'network_ssid_aliases',
        'audit_events'
    ];
BEGIN
    FOREACH v_table IN ARRAY v_required_tables LOOP
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.tables
            WHERE table_schema = 'public' AND table_name = v_table
        ) THEN
            v_missing_tables := array_append(v_missing_tables, v_table);
        END IF;
    END LOOP;

    IF array_length(v_missing_tables, 1) > 0 THEN
        RAISE EXCEPTION 'TEST_FAIL: Missing core tables: %', array_to_string(v_missing_tables, ', ');
    END IF;
END $$;

-- 2. Verify Row-Level Security (RLS) is ENABLED on every core table
DO $$
DECLARE
    v_unprotected_tables TEXT[] := ARRAY[]::TEXT[];
    v_table TEXT;
    v_required_tables TEXT[] := ARRAY[
        'profiles',
        'user_roles',
        'networks',
        'network_memberships',
        'network_ssid_aliases',
        'audit_events'
    ];
BEGIN
    FOREACH v_table IN ARRAY v_required_tables LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public'
              AND c.relname = v_table
              AND c.relrowsecurity = TRUE
        ) THEN
            v_unprotected_tables := array_append(v_unprotected_tables, v_table);
        END IF;
    END LOOP;

    IF array_length(v_unprotected_tables, 1) > 0 THEN
        RAISE EXCEPTION 'TEST_FAIL: RLS not enabled on tables: %', array_to_string(v_unprotected_tables, ', ');
    END IF;
END $$;

-- 3. Verify absence of deferred/forbidden commercial objects
DO $$
DECLARE
    v_forbidden_tables TEXT[] := ARRAY[]::TEXT[];
    v_table TEXT;
    v_prohibited TEXT[] := ARRAY[
        'wallets',
        'wallet_ledger_entries',
        'deposit_requests',
        'cards',
        'card_batches',
        'purchases',
        'card_complaints',
        'settlements',
        'merchants',
        'distributors',
        'telecom_services'
    ];
BEGIN
    FOREACH v_table IN ARRAY v_prohibited LOOP
        IF EXISTS (
            SELECT 1 FROM information_schema.tables
            WHERE table_schema = 'public' AND table_name = v_table
        ) THEN
            v_forbidden_tables := array_append(v_forbidden_tables, v_table);
        END IF;
    END LOOP;

    IF array_length(v_forbidden_tables, 1) > 0 THEN
        RAISE EXCEPTION 'TEST_FAIL: Prohibited deferred objects found in database: %', array_to_string(v_forbidden_tables, ', ');
    END IF;
END $$;

-- 4. Verify user_roles active V1 role constraints (8 roles only)
DO $$
DECLARE
    v_constraint_def TEXT;
BEGIN
    SELECT pg_get_constraintdef(oid) INTO v_constraint_def
    FROM pg_constraint
    WHERE conname = 'chk_user_roles_active_v1_roles';

    IF v_constraint_def IS NULL THEN
        RAISE EXCEPTION 'TEST_FAIL: Constraint chk_user_roles_active_v1_roles is missing.';
    END IF;

    IF v_constraint_def LIKE '%merchant%' OR v_constraint_def LIKE '%distributor%' OR v_constraint_def LIKE '%telecom%' THEN
        RAISE EXCEPTION 'TEST_FAIL: Forbidden deferred roles found in constraint definition: %', v_constraint_def;
    END IF;
END $$;

ROLLBACK;
