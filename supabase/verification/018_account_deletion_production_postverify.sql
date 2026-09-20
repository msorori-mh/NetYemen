-- WASEL NET production post-verify for account-deletion migration 20260822200000.
-- READ ONLY: verifies history, objects, RLS, grants, and zero unexpected rows.
BEGIN;
SET TRANSACTION READ ONLY;

DO $$
DECLARE
    v_rls_enabled BOOLEAN;
    v_rls_forced BOOLEAN;
    v_invalid_statuses BIGINT;
    v_request_count BIGINT;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM supabase_migrations.schema_migrations
        WHERE version = '20260822200000'
    ) THEN
        RAISE EXCEPTION
            'HOLD: migration 20260822200000 is not recorded as applied.';
    END IF;

    IF to_regclass('public.account_deletion_requests') IS NULL
       OR to_regprocedure('public.request_my_account_deletion(text)') IS NULL
       OR to_regprocedure('public.cancel_my_account_deletion()') IS NULL THEN
        RAISE EXCEPTION
            'HOLD: required account-deletion objects are missing.';
    END IF;

    SELECT relrowsecurity, relforcerowsecurity
    INTO v_rls_enabled, v_rls_forced
    FROM pg_class
    WHERE oid = 'public.account_deletion_requests'::regclass;

    IF NOT COALESCE(v_rls_enabled, FALSE)
       OR NOT COALESCE(v_rls_forced, FALSE) THEN
        RAISE EXCEPTION
            'HOLD: account_deletion_requests RLS is not enabled and forced.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'account_deletion_requests'
          AND policyname = 'account_deletion_requests_owner_select'
          AND cmd = 'SELECT'
    ) THEN
        RAISE EXCEPTION
            'HOLD: owner/admin/auditor SELECT policy is missing.';
    END IF;

    IF has_function_privilege(
        'anon',
        'public.request_my_account_deletion(text)',
        'EXECUTE'
    ) OR has_function_privilege(
        'anon',
        'public.cancel_my_account_deletion()',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION
            'HOLD: anon can execute an account-deletion RPC.';
    END IF;

    IF NOT has_function_privilege(
        'authenticated',
        'public.request_my_account_deletion(text)',
        'EXECUTE'
    ) OR NOT has_function_privilege(
        'authenticated',
        'public.cancel_my_account_deletion()',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION
            'HOLD: authenticated users lack an account-deletion RPC grant.';
    END IF;

    IF has_table_privilege(
        'authenticated',
        'public.account_deletion_requests',
        'INSERT'
    ) OR has_table_privilege(
        'authenticated',
        'public.account_deletion_requests',
        'UPDATE'
    ) OR has_table_privilege(
        'authenticated',
        'public.account_deletion_requests',
        'DELETE'
    ) THEN
        RAISE EXCEPTION
            'HOLD: authenticated users have direct mutation privileges.';
    END IF;

    SELECT count(*)
    INTO v_invalid_statuses
    FROM public.profiles
    WHERE account_status NOT IN (
        'active',
        'suspended',
        'pending_verification',
        'closure_pending',
        'anonymized'
    );

    IF v_invalid_statuses <> 0 THEN
        RAISE EXCEPTION
            'HOLD: % profiles have an invalid post-migration account status.',
            v_invalid_statuses;
    END IF;

    SELECT count(*)
    INTO v_request_count
    FROM public.account_deletion_requests;

    IF v_request_count <> 0 THEN
        RAISE EXCEPTION
            'HOLD: migration introduced or encountered % deletion requests.',
            v_request_count;
    END IF;

    RAISE NOTICE
        'ACCOUNT DELETION PRODUCTION POST-VERIFY PASS: history, objects, forced RLS, policies, grants, and zero rows verified.';
END;
$$;

SELECT
    'PASS'::TEXT AS decision,
    '20260822200000'::TEXT AS applied_migration,
    (SELECT count(*) FROM auth.users) AS auth_users,
    (SELECT count(*) FROM public.profiles) AS profiles,
    (SELECT count(*) FROM public.user_roles) AS user_roles,
    (SELECT count(*) FROM public.device_push_tokens) AS device_push_tokens,
    (SELECT count(*) FROM public.account_deletion_requests)
        AS deletion_requests,
    (
        SELECT relrowsecurity AND relforcerowsecurity
        FROM pg_class
        WHERE oid = 'public.account_deletion_requests'::regclass
    ) AS rls_enabled_and_forced;

ROLLBACK;
