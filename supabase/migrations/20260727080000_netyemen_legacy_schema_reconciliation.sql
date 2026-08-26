-- WASEL NET legacy schema reconciliation
-- Migration: 20260727080000_netyemen_legacy_schema_reconciliation.sql
-- Purpose: preserve and quarantine the pre-V1 prototype tables before the
-- authoritative V1 migrations create their own public schema.
--
-- This migration is intentionally additive and fail-closed:
-- * no rows are deleted or rewritten;
-- * it is a no-op on a fresh/V1 database;
-- * it refuses to overwrite an existing archived table.

CREATE SCHEMA IF NOT EXISTS legacy_netyemen;

COMMENT ON SCHEMA legacy_netyemen IS
    'Read-only quarantine for the pre-V1 NetYemen prototype schema. Not used by the WASEL NET V1 application.';

DO $$
DECLARE
    v_table TEXT;
    v_legacy_tables CONSTANT TEXT[] := ARRAY[
        'cards',
        'network_prices',
        'networks',
        'notifications',
        'purchases',
        'reviews',
        'settlements',
        'users',
        'wallet_deposit_requests',
        'wallet_transactions'
    ];
BEGIN
    -- Detect the legacy catalog by its distinctive networks.name column and
    -- the absence of the V1 networks.commercial_name column.
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'networks'
          AND column_name = 'name'
    ) AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'networks'
          AND column_name = 'commercial_name'
    ) THEN
        FOREACH v_table IN ARRAY v_legacy_tables
        LOOP
            IF to_regclass(format('public.%I', v_table)) IS NOT NULL THEN
                IF to_regclass(format('legacy_netyemen.%I', v_table)) IS NOT NULL THEN
                    RAISE EXCEPTION
                        'LEGACY_RECONCILIATION_CONFLICT: legacy_netyemen.% already exists; refusing to overwrite preserved data.',
                        v_table;
                END IF;

                EXECUTE format(
                    'ALTER TABLE public.%I SET SCHEMA legacy_netyemen',
                    v_table
                );
            END IF;
        END LOOP;
    END IF;
END
$$;

-- Archived prototype data is server-side only. Moving tables preserves their
-- rows, constraints, indexes and foreign-key relationships, while removing
-- them from the client-facing public API.
REVOKE ALL ON SCHEMA legacy_netyemen FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL TABLES IN SCHEMA legacy_netyemen FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA legacy_netyemen FROM PUBLIC, anon, authenticated;

-- Disable the two prototype mutation RPCs if they exist. V1 uses its own
-- fail-closed commerce and wallet RPC contracts.
DO $$
DECLARE
    v_function REGPROCEDURE;
BEGIN
    FOR v_function IN
        SELECT p.oid::regprocedure
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN ('process_deposit', 'purchase_card')
    LOOP
        EXECUTE format(
            'REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated',
            v_function
        );
    END LOOP;
END
$$;
