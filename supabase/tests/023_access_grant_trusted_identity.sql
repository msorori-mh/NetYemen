-- Verifies 20261001094000_access_grant_trusted_identity.sql: pending staff
-- grants are applied only to confirmed Google identities.
BEGIN;

DO $$
DECLARE
  v_attacker uuid := 'a0230000-0000-4000-8000-000000000001';
  v_staff    uuid := 'a0230000-0000-4000-8000-000000000002';
  v_grant_a  uuid;
  v_grant_b  uuid;
BEGIN
  INSERT INTO public.platform_access_grants (email, roles, note)
  VALUES ('pending.admin@test-only.local', ARRAY['platform_admin'], 'TEST_ONLY')
  RETURNING id INTO v_grant_a;
  INSERT INTO public.platform_access_grants (email, roles, note)
  VALUES ('google.staff@test-only.local', ARRAY['finance_officer'], 'TEST_ONLY')
  RETURNING id INTO v_grant_b;

  -- Auto-confirmed email/password signup for the pending address: no roles.
  INSERT INTO auth.users (id, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
  VALUES (v_attacker, 'Pending.Admin@test-only.local', now(),
          '{"provider":"email","providers":["email"]}', '{}');
  IF EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = v_attacker AND role = 'platform_admin') THEN
    RAISE EXCEPTION 'TEST_FAIL (GRANT-01): password signup received a staff grant';
  END IF;
  IF EXISTS (SELECT 1 FROM public.platform_access_grants WHERE id = v_grant_a AND applied_at IS NOT NULL) THEN
    RAISE EXCEPTION 'TEST_FAIL (GRANT-01): password signup consumed the grant';
  END IF;

  -- Unrelated metadata updates keep it untrusted.
  UPDATE auth.users SET raw_app_meta_data = raw_app_meta_data || '{"x":1}' WHERE id = v_attacker;
  IF EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = v_attacker AND role = 'platform_admin') THEN
    RAISE EXCEPTION 'TEST_FAIL (GRANT-02): untrusted update applied the grant';
  END IF;

  -- Confirmed Google signup receives its grant.
  INSERT INTO auth.users (id, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
  VALUES (v_staff, 'google.staff@test-only.local', now(),
          '{"provider":"google","providers":["google"]}', '{}');
  IF NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = v_staff AND role = 'finance_officer') THEN
    RAISE EXCEPTION 'TEST_FAIL (GRANT-03): Google signup did not receive its grant';
  END IF;

  -- Linking Google later applies the pending grant.
  UPDATE auth.users
  SET raw_app_meta_data = '{"provider":"email","providers":["email","google"]}'
  WHERE id = v_attacker;
  IF NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = v_attacker AND role = 'platform_admin') THEN
    RAISE EXCEPTION 'TEST_FAIL (GRANT-04): grant not applied after Google identity was linked';
  END IF;

  RAISE NOTICE 'SUCCESS: access grants require a confirmed Google identity.';
END $$;

ROLLBACK;
