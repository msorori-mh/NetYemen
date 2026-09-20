-- Platform access grants: an admin pre-authorizes an email to receive one or more
-- platform roles. When that email signs in (via Google) for the first time, a trigger
-- grants the roles automatically. If the user already exists, the create RPC applies
-- the roles immediately. This is how "add a new user" works under Google-only login.

-- ---------------------------------------------------------------------------
-- Table
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.platform_access_grants (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email          text NOT NULL,
  roles          text[] NOT NULL,
  note           text,
  created_by     uuid,
  created_at     timestamptz NOT NULL DEFAULT now(),
  applied_at     timestamptz,
  applied_user_id uuid
);

-- one grant per email (case-insensitive)
CREATE UNIQUE INDEX IF NOT EXISTS platform_access_grants_email_key
  ON public.platform_access_grants (lower(email));

-- Lock the table down: no direct client access; only SECURITY DEFINER RPCs and
-- the service role can read/write it.
ALTER TABLE public.platform_access_grants ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.platform_access_grants FROM anon, authenticated;

-- roles an admin is allowed to pre-grant (never customer / system_* internals)
CREATE OR REPLACE FUNCTION public._grantable_roles()
RETURNS text[] LANGUAGE sql IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT ARRAY['network_owner','network_operator','finance_officer','support_agent','platform_admin']::text[];
$$;

-- ---------------------------------------------------------------------------
-- Apply a grant's roles to a concrete user id (shared helper)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._apply_access_grant(p_grant_id uuid, p_user_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role text;
  v_created_by uuid;
  v_roles text[];
BEGIN
  SELECT roles, created_by INTO v_roles, v_created_by
  FROM public.platform_access_grants WHERE id = p_grant_id AND applied_at IS NULL
  FOR UPDATE;
  IF v_roles IS NULL THEN
    RETURN; -- already applied or missing
  END IF;

  FOREACH v_role IN ARRAY v_roles LOOP
    INSERT INTO public.user_roles (user_id, role, created_by)
    VALUES (p_user_id, v_role, COALESCE(v_created_by, p_user_id))
    ON CONFLICT DO NOTHING;
  END LOOP;

  UPDATE public.platform_access_grants
  SET applied_at = now(), applied_user_id = p_user_id
  WHERE id = p_grant_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- Signup trigger: on new auth user, apply a matching pending grant
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.apply_access_grant_on_signup()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_grant_id uuid;
BEGIN
  IF NEW.email IS NULL THEN
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

DROP TRIGGER IF EXISTS on_auth_user_created_apply_grant ON auth.users;
CREATE TRIGGER on_auth_user_created_apply_grant
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.apply_access_grant_on_signup();

-- ---------------------------------------------------------------------------
-- Admin RPCs (called from the dashboard with a platform_admin JWT)
-- ---------------------------------------------------------------------------
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

  -- if the user already signed in before being invited, apply immediately
  SELECT id INTO v_existing_user FROM auth.users WHERE lower(email) = v_email LIMIT 1;
  IF v_existing_user IS NOT NULL THEN
    PERFORM public._apply_access_grant(v_grant.id, v_existing_user);
    SELECT * INTO v_grant FROM public.platform_access_grants WHERE id = v_grant.id;
  END IF;

  RETURN v_grant;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_list_access_grants()
RETURNS SETOF public.platform_access_grants
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.has_platform_role('platform_admin') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  RETURN QUERY SELECT * FROM public.platform_access_grants ORDER BY created_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_revoke_access_grant(p_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.has_platform_role('platform_admin') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  -- only pending (not yet applied) grants can be revoked
  DELETE FROM public.platform_access_grants WHERE id = p_id AND applied_at IS NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_create_access_grant(text, text[], text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_access_grants() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_revoke_access_grant(uuid) TO authenticated;
