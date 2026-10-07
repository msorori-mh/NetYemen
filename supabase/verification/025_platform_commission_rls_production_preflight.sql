-- Read-only production preflight for platform_commission_config RLS repair.
-- No DDL, DML, function calls with side effects, or test data.

WITH target_table AS (
    SELECT
        c.oid,
        n.nspname AS schema_name,
        c.relname AS table_name,
        c.relrowsecurity AS rls_enabled,
        c.relforcerowsecurity AS force_rls_enabled
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'platform_commission_config'
      AND c.relkind IN ('r', 'p')
), public_tables_without_rls AS (
    SELECT n.nspname AS schema_name, c.relname AS table_name
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('r', 'p')
      AND NOT c.relrowsecurity
), target_policies AS (
    SELECT policyname, cmd, roles, qual, with_check
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'platform_commission_config'
), target_grants AS (
    SELECT grantee, privilege_type
    FROM information_schema.role_table_grants
    WHERE table_schema = 'public'
      AND table_name = 'platform_commission_config'
), migration_state AS (
    SELECT version, name, statements
    FROM supabase_migrations.schema_migrations
    ORDER BY version DESC
    LIMIT 20
)
SELECT jsonb_build_object(
    'target_table', COALESCE((SELECT to_jsonb(t) FROM target_table t), 'null'::jsonb),
    'public_tables_without_rls', COALESCE(
        (SELECT jsonb_agg(to_jsonb(t) ORDER BY t.table_name) FROM public_tables_without_rls t),
        '[]'::jsonb
    ),
    'target_policies', COALESCE(
        (SELECT jsonb_agg(to_jsonb(p) ORDER BY p.policyname) FROM target_policies p),
        '[]'::jsonb
    ),
    'target_grants', COALESCE(
        (SELECT jsonb_agg(to_jsonb(g) ORDER BY g.grantee, g.privilege_type) FROM target_grants g),
        '[]'::jsonb
    ),
    'recent_migrations', COALESCE(
        (SELECT jsonb_agg(to_jsonb(m) ORDER BY m.version DESC) FROM migration_state m),
        '[]'::jsonb
    )
) AS platform_commission_rls_preflight;
