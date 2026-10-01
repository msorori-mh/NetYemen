-- Access grants only for verified Google identities (review finding H-3).
--
-- Pre-provisioned staff grants (platform_admin, finance_officer, ...) were
-- applied to the first auth.users row whose email matched, whatever the sign-in
-- method. Email/password signup is enabled and email confirmations are off in
-- supabase/config.toml, so such signups are auto-confirmed: an attacker could
-- register a pending grantee's address with a password before the real person
-- signs in with Google and receive the staff roles (or at least consume the
-- grant).
--
-- Staff sign in with Google (see 20260913100000_account_pins.sql). Grants are
-- now applied only to users with a confirmed email AND a Google identity, both
-- at signup and when such an identity is later confirmed or linked.

CREATE OR REPLACE FUNCTION public._is_trusted_grant_identity(
  p_email_confirmed_at timestamptz,
  p_app_meta jsonb
) RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT p_email_confirmed_at IS NOT NULL
     AND (
       COALESCE(p_app_meta -> 'providers', '[]'::jsonb) ? 'google'
       OR p_app_meta ->> 'provider' = 'google'
     );
$$;
REVOKE EXECUTE ON FUNCTION public._is_trusted_grant_identity(timestamptz, jsonb) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.apply_access_grant_on_signup()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_grant_id uuid;
BEGIN
  IF NEW.email IS NULL
     OR NOT public._is_trusted_grant_identity(NEW.email_confirmed_at, NEW.raw_app_meta_data) THEN
    RETURN NEW;
  END IF;
  SELECT id INTO v_grant_id
  FROM public.platform_access_grants
  WHERE lower(email) = lower(NEW.email) AND applied_at IS NULL
  LIMIT 1;
  IF v_grant_id IS NOT NULL THEN
    PERFORM public._apply_access_grant(v_grant_id, NEW.id);
  END IF;
  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.apply_access_grant_on_signup() FROM PUBLIC, anon, authenticated;

-- Apply a pending grant once the identity becomes trusted (email confirmed or
-- Google linked after the initial signup).
DROP TRIGGER IF EXISTS on_auth_user_trusted_apply_grant ON auth.users;
CREATE TRIGGER on_auth_user_trusted_apply_grant
  AFTER UPDATE OF email_confirmed_at, raw_app_meta_data ON auth.users
  FOR EACH ROW
  WHEN (OLD.email_confirmed_at IS DISTINCT FROM NEW.email_confirmed_at
        OR OLD.raw_app_meta_data IS DISTINCT FROM NEW.raw_app_meta_data)
  EXECUTE FUNCTION public.apply_access_grant_on_signup();

-- admin_create_access_grant applied a grant immediately to any existing user
-- with that email; restrict it to trusted identities as well.
CREATE OR REPLACE FUNCTION public.admin_create_access_grant(
  p_email text, p_roles text[], p_note text DEFAULT NULL
) RETURNS public.platform_access_grants
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_email text := lower(trim(p_email));
  v_admin uuid := auth.uid();
  v_grant public.platform_access_grants;
  v_existing_user uuid;
BEGIN
  IF NOT public.has_platform_role('platform_admin') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  IF v_email IS NULL OR v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN
    RAISE EXCEPTION 'INVALID_EMAIL';
  END IF;
  IF p_roles IS NULL OR array_length(p_roles,1) IS NULL THEN
    RAISE EXCEPTION 'NO_ROLES';
  END IF;
  IF NOT (p_roles <@ public._grantable_roles()) THEN
    RAISE EXCEPTION 'INVALID_ROLE';
  END IF;

  INSERT INTO public.platform_access_grants (email, roles, note, created_by)
  VALUES (v_email, p_roles, NULLIF(trim(p_note), ''), v_admin)
  ON CONFLICT (lower(email)) DO UPDATE
    SET roles = EXCLUDED.roles,
        note = EXCLUDED.note,
        created_by = EXCLUDED.created_by,
        created_at = now(),
        applied_at = NULL,
        applied_user_id = NULL
  RETURNING * INTO v_grant;

  -- if the user already signed in with a trusted identity, apply immediately
  SELECT id INTO v_existing_user
  FROM auth.users
  WHERE lower(email) = v_email
    AND public._is_trusted_grant_identity(email_confirmed_at, raw_app_meta_data)
  LIMIT 1;
  IF v_existing_user IS NOT NULL THEN
    PERFORM public._apply_access_grant(v_grant.id, v_existing_user);
    SELECT * INTO v_grant FROM public.platform_access_grants WHERE id = v_grant.id;
  END IF;

  RETURN v_grant;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_create_access_grant(text, text[], text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_create_access_grant(text, text[], text) TO authenticated;
