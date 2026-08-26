-- WASEL NET production preflight for account-deletion migration 20260822200000.
-- READ ONLY: no schema or data mutations.
BEGIN;
SET TRANSACTION READ ONLY;

DO $$
DECLARE
    v_constraint_definition TEXT;
    v_invalid_statuses BIGINT;
BEGIN
    IF EXISTS (
        SELECT 1
        FROM supabase_migrations.schema_migrations
        WHERE version = '20260822200000'
    ) THEN
        RAISE EXCEPTION
            'HOLD: migration 20260822200000 is already recorded as applied.';
    END IF;

    IF to_regclass('public.account_deletion_requests') IS NOT NULL
       OR to_regprocedure('public.request_my_account_deletion(text)') IS NOT NULL
       OR to_regprocedure('public.cancel_my_account_deletion()') IS NOT NULL THEN
        RAISE EXCEPTION
            'HOLD: account-deletion objects already exist without matching migration history.';
    END IF;

    IF to_regprocedure('public.set_updated_at()') IS NULL
       OR to_regprocedure('public.has_platform_role(text)') IS NULL
       OR to_regprocedure(
            'public.record_audit_event(text,text,text,text,text,jsonb,uuid)'
          ) IS NULL THEN
        RAISE EXCEPTION
            'HOLD: required trigger, authorization, or audit dependency is missing.';
    END IF;

    IF to_regclass('public.device_push_tokens') IS NULL
       OR NOT EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = 'device_push_tokens'
              AND column_name = 'is_active'
       ) THEN
        RAISE EXCEPTION
            'HOLD: device_push_tokens.is_active dependency is missing.';
    END IF;

    SELECT pg_get_constraintdef(c.oid)
    INTO v_constraint_definition
    FROM pg_constraint c
    WHERE c.conrelid = 'public.profiles'::regclass
      AND c.conname = 'chk_profiles_account_status';

    IF v_constraint_definition IS NULL THEN
        RAISE EXCEPTION
            'HOLD: chk_profiles_account_status does not exist.';
    END IF;

    IF v_constraint_definition ~ 'closure_pending' THEN
        RAISE EXCEPTION
            'HOLD: profile status constraint already contains post-migration values.';
    END IF;

    SELECT count(*)
    INTO v_invalid_statuses
    FROM public.profiles
    WHERE account_status NOT IN (
        'active',
        'suspended',
        'pending_verification',
        'anonymized'
    );

    IF v_invalid_statuses <> 0 THEN
        RAISE EXCEPTION
            'HOLD: % profiles have an unsupported pre-migration account status.',
            v_invalid_statuses;
    END IF;

    RAISE NOTICE
        'ACCOUNT DELETION PRODUCTION PREFLIGHT PASS: dependencies, history, constraint, and profile statuses verified.';
END;
$$;

SELECT
    'PASS'::TEXT AS decision,
    '20260822200000'::TEXT AS pending_migration,
    (SELECT count(*) FROM auth.users) AS auth_users,
    (SELECT count(*) FROM public.profiles) AS profiles,
    (SELECT count(*) FROM public.user_roles) AS user_roles,
    (SELECT count(*) FROM public.device_push_tokens) AS device_push_tokens,
    0::BIGINT AS existing_deletion_requests;

ROLLBACK;
