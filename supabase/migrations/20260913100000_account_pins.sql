-- App-level 6-digit PIN lock, on top of Google auth.
--
-- Model: a PIN is set once (first login on a device, or right after an admin
-- clears it for a reset). It never changes on its own. A new device prompts
-- for the PIN; owner/operator 15-minute inactivity auto-lock is a frontend
-- concern — this migration only provides verification + brute-force
-- rate-limiting. Forgot-PIN has no self-service change path: the user files
-- a reset request, a platform_admin approves it (which clears the stored
-- PIN so the user re-enrolls), or rejects it (no change). Tables are
-- RPC-only — same posture as platform_access_grants: RLS enabled, ALL
-- revoked from anon/authenticated, SECURITY DEFINER functions are the only
-- door in.
--
-- pgcrypto's crypt()/gen_salt() live in the `extensions` schema on this
-- project (not `public`) — every function below that touches a PIN hash
-- sets search_path to `public, extensions, pg_temp` accordingly. This is
-- the same search_path bug that previously broke card reveal
-- (20260908120000_card_pgcrypto.sql) — do not repeat it here.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.account_pins (
  user_id        uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  pin_hash       text NOT NULL,
  failed_attempts int NOT NULL DEFAULT 0,
  locked_until   timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.account_pins ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_pins FROM anon, authenticated;

CREATE TABLE IF NOT EXISTS public.pin_reset_requests (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  status        text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  requested_at  timestamptz DEFAULT now(),
  resolved_by   uuid,
  resolved_at   timestamptz
);

-- at most one pending request per user at a time
CREATE UNIQUE INDEX IF NOT EXISTS pin_reset_requests_one_pending_per_user
  ON public.pin_reset_requests (user_id)
  WHERE status = 'pending';

ALTER TABLE public.pin_reset_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pin_reset_requests FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- has_account_pin() — does the caller already have a PIN enrolled?
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.has_account_pin()
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, extensions, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING errcode = '28000';
  END IF;

  RETURN EXISTS (SELECT 1 FROM public.account_pins WHERE user_id = auth.uid());
END;
$$;

-- ---------------------------------------------------------------------------
-- set_account_pin(p_pin) — first-time enrollment, or re-enrollment right
-- after an admin-approved reset cleared the row. Refuses to overwrite an
-- existing PIN (there is no "change PIN" path — only reset-via-admin).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_account_pin(p_pin text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING errcode = '28000';
  END IF;

  IF p_pin IS NULL OR p_pin !~ '^[0-9]{6}$' THEN
    RAISE EXCEPTION 'INVALID_PIN';
  END IF;

  IF EXISTS (SELECT 1 FROM public.account_pins WHERE user_id = v_user) THEN
    RAISE EXCEPTION 'PIN_ALREADY_SET';
  END IF;

  INSERT INTO public.account_pins (user_id, pin_hash)
  VALUES (v_user, crypt(p_pin, gen_salt('bf')));
END;
$$;

-- ---------------------------------------------------------------------------
-- verify_account_pin(p_pin) — check the PIN on this device. 5 wrong
-- attempts locks verification for 15 minutes (counter resets on lock and on
-- success). Never returns or logs the hash or the plaintext PIN.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.verify_account_pin(p_pin text)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_row public.account_pins%ROWTYPE;
  v_ok boolean;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING errcode = '28000';
  END IF;

  SELECT * INTO v_row FROM public.account_pins WHERE user_id = v_user FOR UPDATE;
  IF v_row.user_id IS NULL THEN
    RAISE EXCEPTION 'PIN_NOT_SET';
  END IF;

  -- Custom (non-standard) SQLSTATE: only used so this condition is
  -- distinguishable in DB-side logs/tooling. The frontend keys off the
  -- message text 'PIN_LOCKED' itself, same as every other RPC in this repo.
  IF v_row.locked_until IS NOT NULL AND v_row.locked_until > now() THEN
    RAISE EXCEPTION 'PIN_LOCKED' USING errcode = 'PLK01';
  END IF;

  v_ok := (crypt(p_pin, v_row.pin_hash) = v_row.pin_hash);

  IF v_ok THEN
    UPDATE public.account_pins
    SET failed_attempts = 0, locked_until = NULL, updated_at = now()
    WHERE user_id = v_user;
  ELSIF v_row.failed_attempts + 1 >= 5 THEN
    UPDATE public.account_pins
    SET failed_attempts = 0, locked_until = now() + interval '15 minutes', updated_at = now()
    WHERE user_id = v_user;
  ELSE
    UPDATE public.account_pins
    SET failed_attempts = failed_attempts + 1, updated_at = now()
    WHERE user_id = v_user;
  END IF;

  RETURN v_ok;
END;
$$;

-- ---------------------------------------------------------------------------
-- request_pin_reset() — the only forgot-PIN path: file a request for a
-- platform_admin to review. Idempotent while one is already pending.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.request_pin_reset()
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_id uuid;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING errcode = '28000';
  END IF;

  SELECT id INTO v_id
  FROM public.pin_reset_requests
  WHERE user_id = v_user AND status = 'pending'
  LIMIT 1;

  IF v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;

  INSERT INTO public.pin_reset_requests (user_id)
  VALUES (v_user)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- Admin RPCs (dashboard, platform_admin JWT)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_list_pin_reset_requests()
RETURNS TABLE (
  id uuid,
  user_id uuid,
  email text,
  full_name text,
  status text,
  requested_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, extensions, pg_temp
AS $$
BEGIN
  IF NOT public.has_platform_role('platform_admin') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;

  RETURN QUERY
  SELECT
    r.id,
    r.user_id,
    u.email,
    p.full_name,
    r.status,
    r.requested_at
  FROM public.pin_reset_requests r
  JOIN auth.users u ON u.id = r.user_id
  LEFT JOIN public.profiles p ON p.id = r.user_id
  ORDER BY (r.status = 'pending') DESC, r.requested_at DESC;
END;
$$;

-- approve: clears the stored PIN so the user is prompted to set a fresh one
-- on next launch (that's the entire "reset"). reject: leaves it untouched.
CREATE OR REPLACE FUNCTION public.admin_resolve_pin_reset(p_request_id uuid, p_approve boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_admin uuid := auth.uid();
  v_request public.pin_reset_requests%ROWTYPE;
BEGIN
  IF NOT public.has_platform_role('platform_admin') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;

  SELECT * INTO v_request FROM public.pin_reset_requests WHERE id = p_request_id FOR UPDATE;
  IF v_request.id IS NULL THEN
    RAISE EXCEPTION 'NOT_FOUND';
  END IF;
  IF v_request.status <> 'pending' THEN
    RAISE EXCEPTION 'ALREADY_RESOLVED';
  END IF;

  IF p_approve THEN
    DELETE FROM public.account_pins WHERE user_id = v_request.user_id;
    UPDATE public.pin_reset_requests
    SET status = 'approved', resolved_by = v_admin, resolved_at = now()
    WHERE id = p_request_id;
  ELSE
    UPDATE public.pin_reset_requests
    SET status = 'rejected', resolved_by = v_admin, resolved_at = now()
    WHERE id = p_request_id;
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION public.has_account_pin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_account_pin(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.verify_account_pin(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.request_pin_reset() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_pin_reset_requests() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_resolve_pin_reset(uuid, boolean) TO authenticated;
