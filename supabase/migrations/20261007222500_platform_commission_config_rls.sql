-- Enable the policy that already protects the singleton commission settings.
-- This migration is intentionally narrow: no data changes and no policy
-- broadening. Direct clients may only SELECT, and only the existing admin or
-- auditor policy can expose the row.

BEGIN;

ALTER TABLE public.platform_commission_config ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.platform_commission_config
FROM PUBLIC, anon, authenticated;

GRANT SELECT ON TABLE public.platform_commission_config TO authenticated;

DROP POLICY IF EXISTS platform_commission_config_admin_select
ON public.platform_commission_config;

CREATE POLICY platform_commission_config_admin_select
ON public.platform_commission_config
FOR SELECT
TO authenticated
USING (
    public.has_platform_role('platform_admin')
    OR public.has_platform_role('system_auditor')
);

COMMIT;
