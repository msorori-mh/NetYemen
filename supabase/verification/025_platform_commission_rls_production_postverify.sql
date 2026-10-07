-- Read-only post-verify. PASS requires RLS, the one scoped SELECT policy,
-- SELECT-only authenticated grant, and no PUBLIC/anon table grants.

SELECT jsonb_build_object(
    'rls_enabled', COALESCE((
        SELECT c.relrowsecurity
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relname = 'platform_commission_config'
          AND c.relkind IN ('r', 'p')
    ), FALSE),
    'policy_ok', EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'platform_commission_config'
          AND policyname = 'platform_commission_config_admin_select'
          AND cmd = 'SELECT'
          AND roles = ARRAY['authenticated']::name[]
    ),
    'authenticated_select_only',
        EXISTS (
            SELECT 1 FROM information_schema.role_table_grants
            WHERE table_schema = 'public'
              AND table_name = 'platform_commission_config'
              AND grantee = 'authenticated'
              AND privilege_type = 'SELECT'
        )
        AND NOT EXISTS (
            SELECT 1 FROM information_schema.role_table_grants
            WHERE table_schema = 'public'
              AND table_name = 'platform_commission_config'
              AND grantee = 'authenticated'
              AND privilege_type <> 'SELECT'
        ),
    'no_public_or_anon_grants', NOT EXISTS (
        SELECT 1 FROM information_schema.role_table_grants
        WHERE table_schema = 'public'
          AND table_name = 'platform_commission_config'
          AND grantee IN ('PUBLIC', 'anon')
    )
) AS platform_commission_rls_postverify;
