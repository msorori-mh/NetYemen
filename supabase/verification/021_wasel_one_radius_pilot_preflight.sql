-- Read-only WASEL One RADIUS pilot preflight. Safe after migrations, before traffic.
\set ON_ERROR_STOP on

DO $$
DECLARE
    v_missing TEXT[] := ARRAY[]::TEXT[];
    v_force_rls BOOLEAN;
BEGIN
    IF to_regclass('public.radius_access_credentials') IS NULL THEN
        v_missing := array_append(v_missing, 'table:radius_access_credentials');
    END IF;
    IF to_regprocedure('public.issue_radius_access_credential(uuid)') IS NULL THEN
        v_missing := array_append(v_missing, 'function:issue_radius_access_credential');
    END IF;
    IF to_regprocedure('public.radius_authorize_access(text,text,text,uuid,text)') IS NULL THEN
        v_missing := array_append(v_missing, 'function:radius_authorize_access');
    END IF;
    IF to_regprocedure('public.radius_record_accounting(uuid,text,text,text,timestamptz,bigint,bigint,integer)') IS NULL THEN
        v_missing := array_append(v_missing, 'function:radius_record_accounting');
    END IF;
    IF cardinality(v_missing) > 0 THEN
        RAISE EXCEPTION 'WASEL_RADIUS_PREFLIGHT_MISSING: %', array_to_string(v_missing, ', ');
    END IF;

    SELECT relforcerowsecurity INTO v_force_rls
    FROM pg_class WHERE oid = 'public.radius_access_credentials'::regclass;
    IF NOT v_force_rls THEN
        RAISE EXCEPTION 'WASEL_RADIUS_PREFLIGHT_RLS: credential table must FORCE RLS.';
    END IF;

    IF NOT has_function_privilege(
        'authenticated', 'public.issue_radius_access_credential(uuid)', 'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'WASEL_RADIUS_PREFLIGHT_GRANT: authenticated cannot issue credential.';
    END IF;
    IF has_function_privilege(
        'authenticated', 'public.radius_authorize_access(text,text,text,uuid,text)', 'EXECUTE'
    ) OR has_function_privilege(
        'authenticated',
        'public.radius_record_accounting(uuid,text,text,text,timestamptz,bigint,bigint,integer)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'WASEL_RADIUS_PREFLIGHT_GRANT: service-only RPC leaked to authenticated.';
    END IF;
    IF NOT has_function_privilege(
        'service_role', 'public.radius_authorize_access(text,text,text,uuid,text)', 'EXECUTE'
    ) OR NOT has_function_privilege(
        'service_role',
        'public.radius_record_accounting(uuid,text,text,text,timestamptz,bigint,bigint,integer)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'WASEL_RADIUS_PREFLIGHT_GRANT: service role is missing RADIUS RPC access.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name IN (
            'radius_access_credentials', 'radius_accounting_events',
            'access_sessions', 'partner_usage_ledger'
        ) AND column_name IN ('password', 'plaintext_password', 'shared_secret', 'raw_packet')
    ) THEN
        RAISE EXCEPTION 'WASEL_RADIUS_PREFLIGHT_SECRET_COLUMN: forbidden plaintext/raw column exists.';
    END IF;
END;
$$;

SELECT jsonb_build_object(
    'result', 'PASS',
    'credential_table_force_rls', TRUE,
    'customer_issue_rpc', TRUE,
    'service_only_authorize_accounting', TRUE,
    'plaintext_secret_columns', 0
) AS wasel_radius_preflight;
