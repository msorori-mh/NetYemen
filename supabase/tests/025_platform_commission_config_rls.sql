-- Verifies 20261007222500_platform_commission_config_rls.sql.

BEGIN;

DO $$
DECLARE
    v_customer UUID := '12500000-0000-4000-8000-000000000001';
    v_admin UUID := '22500000-0000-4000-8000-000000000001';
    v_auditor UUID := '32500000-0000-4000-8000-000000000001';
    v_count INTEGER;
    v_denied BOOLEAN;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relname = 'platform_commission_config'
          AND c.relrowsecurity
    ) THEN
        RAISE EXCEPTION 'TEST_FAIL (RLS-01): RLS is not enabled.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'platform_commission_config'
          AND policyname = 'platform_commission_config_admin_select'
          AND cmd = 'SELECT'
          AND roles = ARRAY['authenticated']::name[]
    ) THEN
        RAISE EXCEPTION 'TEST_FAIL (RLS-02): scoped authenticated SELECT policy is missing.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.role_table_grants
        WHERE table_schema = 'public'
          AND table_name = 'platform_commission_config'
          AND grantee IN ('PUBLIC', 'anon')
    ) THEN
        RAISE EXCEPTION 'TEST_FAIL (GRANT-01): PUBLIC or anon retains a table grant.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.role_table_grants
        WHERE table_schema = 'public'
          AND table_name = 'platform_commission_config'
          AND grantee = 'authenticated'
          AND privilege_type <> 'SELECT'
    ) OR NOT EXISTS (
        SELECT 1
        FROM information_schema.role_table_grants
        WHERE table_schema = 'public'
          AND table_name = 'platform_commission_config'
          AND grantee = 'authenticated'
          AND privilege_type = 'SELECT'
    ) THEN
        RAISE EXCEPTION 'TEST_FAIL (GRANT-02): authenticated grants are not SELECT-only.';
    END IF;

    INSERT INTO auth.users (id, email) VALUES
        (v_customer, 'rls-customer@example.test'),
        (v_admin, 'rls-admin@example.test'),
        (v_auditor, 'rls-auditor@example.test')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.profiles (id, full_name, account_status) VALUES
        (v_customer, 'RLS Customer', 'active'),
        (v_admin, 'RLS Admin', 'active'),
        (v_auditor, 'RLS Auditor', 'active')
    ON CONFLICT (id) DO UPDATE SET account_status = 'active';

    INSERT INTO public.user_roles (user_id, role) VALUES
        (v_customer, 'customer'),
        (v_admin, 'platform_admin'),
        (v_auditor, 'system_auditor')
    ON CONFLICT (user_id, role) DO NOTHING;

    EXECUTE 'SET LOCAL ROLE anon';
    PERFORM set_config('request.jwt.claim.sub', '', TRUE);
    PERFORM set_config('request.jwt.claims', '{"role":"anon"}', TRUE);
    v_denied := FALSE;
    BEGIN
        PERFORM COUNT(*) FROM public.platform_commission_config;
    EXCEPTION WHEN insufficient_privilege THEN
        v_denied := TRUE;
    END;
    IF NOT v_denied THEN
        RAISE EXCEPTION 'TEST_FAIL (AUTH-01): anon read commission config.';
    END IF;

    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_customer::TEXT, TRUE);
    PERFORM set_config(
        'request.jwt.claims',
        json_build_object('sub', v_customer::TEXT, 'role', 'authenticated')::TEXT,
        TRUE
    );
    SELECT COUNT(*) INTO v_count FROM public.platform_commission_config;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (AUTH-02): customer read commission config.';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', v_admin::TEXT, TRUE);
    PERFORM set_config(
        'request.jwt.claims',
        json_build_object('sub', v_admin::TEXT, 'role', 'authenticated')::TEXT,
        TRUE
    );
    SELECT COUNT(*) INTO v_count FROM public.platform_commission_config;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (AUTH-03): admin could not read commission config.';
    END IF;

    v_denied := FALSE;
    BEGIN
        UPDATE public.platform_commission_config
        SET default_rate = default_rate
        WHERE id = 1;
    EXCEPTION WHEN insufficient_privilege THEN
        v_denied := TRUE;
    END;
    IF NOT v_denied THEN
        RAISE EXCEPTION 'TEST_FAIL (AUTH-04): admin directly mutated commission config.';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', v_auditor::TEXT, TRUE);
    PERFORM set_config(
        'request.jwt.claims',
        json_build_object('sub', v_auditor::TEXT, 'role', 'authenticated')::TEXT,
        TRUE
    );
    SELECT COUNT(*) INTO v_count FROM public.platform_commission_config;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (AUTH-05): auditor could not read commission config.';
    END IF;

    RAISE NOTICE 'SUCCESS: platform commission configuration is protected by RLS.';
END;
$$;

ROLLBACK;
