-- WASEL NET admin finance read model.
-- Keeps the public/customer active-only projection separate from the privileged
-- administration projection so disabled destinations remain manageable.

CREATE OR REPLACE FUNCTION public.admin_get_payment_destinations()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_result JSONB;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
      USING ERRCODE = '28000';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = v_user_id
      AND account_status = 'active'
  ) THEN
    RAISE EXCEPTION 'INACTIVE_PROFILE: Active account required.'
      USING ERRCODE = '42501';
  END IF;

  IF NOT public.is_finance_or_admin() THEN
    RAISE EXCEPTION 'FORBIDDEN_ROLE: Finance access required.'
      USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(
    jsonb_agg(to_jsonb(d) ORDER BY d.sort_order, d.display_name),
    '[]'::jsonb
  )
  INTO v_result
  FROM (
    SELECT
      id,
      provider_type,
      display_name,
      account_holder_name,
      account_identifier,
      instructions,
      currency,
      is_active,
      sort_order,
      created_at,
      updated_at
    FROM public.payment_destinations
  ) AS d;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_payment_destinations() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_payment_destinations() TO authenticated;

COMMENT ON FUNCTION public.admin_get_payment_destinations() IS
  'Privileged finance/admin projection including inactive payment destinations.';
