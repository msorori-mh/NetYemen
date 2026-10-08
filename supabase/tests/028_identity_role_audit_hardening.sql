-- Identity, role and audit hardening (TEST_ONLY, transactional).
-- Verifies 20261008092000_identity_role_audit_hardening.sql.
BEGIN;

DO $$
DECLARE
  v_admin      UUID := 'a2800000-0000-4000-8000-000000000001';
  v_admin_b    UUID := 'a2800000-0000-4000-8000-000000000002';
  v_owner      UUID := 'a2800000-0000-4000-8000-000000000003';
  v_customer   UUID := 'a2800000-0000-4000-8000-000000000004';
  v_gone       UUID := 'a2800000-0000-4000-8000-000000000005';
  v_network    UUID := 'a2800000-0000-4000-8000-000000000010';
  v_ledger     UUID;
  v_count      INTEGER;
  v_msg        TEXT;
  v_text       TEXT;
BEGIN
  EXECUTE 'SET LOCAL ROLE postgres';
  INSERT INTO auth.users(id,email) VALUES
    (v_admin,'s28-admin@pilot.netyemen.test'),
    (v_admin_b,'s28-admin-b@pilot.netyemen.test'),
    (v_owner,'s28-owner@pilot.netyemen.test'),
    (v_customer,'s28-customer@pilot.netyemen.test'),
    (v_gone,'s28-gone@pilot.netyemen.test');
  INSERT INTO public.profiles(id,full_name,account_status) VALUES
    (v_admin,'TEST_ONLY S28 Admin','active'),
    (v_admin_b,'TEST_ONLY S28 Admin B','active'),
    (v_owner,'TEST_ONLY S28 Owner','active'),
    (v_customer,'TEST_ONLY S28 Customer','active'),
    (v_gone,NULL,'anonymized')
  ON CONFLICT(id) DO UPDATE SET account_status=EXCLUDED.account_status;
  INSERT INTO public.user_roles(user_id,role) VALUES
    (v_admin,'platform_admin'),(v_admin_b,'platform_admin'),
    (v_owner,'network_owner'),(v_customer,'customer')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.networks(id,commercial_name,governorate,city,status,verification_status,created_by,approved_by,approved_at)
  VALUES(v_network,'TEST_ONLY S28 Network','صنعاء','صنعاء','active','verified',v_owner,v_admin,now());
  INSERT INTO public.network_memberships(network_id,user_id,membership_role,status,created_by)
  VALUES(v_network,v_owner,'owner','active',v_admin);

  -- ------------------------------------------------ roles only through RPCs
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_admin,'role','authenticated')::text,true);
  BEGIN
    INSERT INTO public.user_roles(user_id,role) VALUES (v_customer,'finance_officer');
    RAISE EXCEPTION 'S28-01 FAIL: administrator granted a role by direct INSERT';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    DELETE FROM public.user_roles WHERE user_id = v_admin_b AND role = 'platform_admin';
    RAISE EXCEPTION 'S28-01 FAIL: administrator removed a role by direct DELETE';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    UPDATE public.user_roles SET role = 'platform_admin' WHERE user_id = v_customer;
    RAISE EXCEPTION 'S28-01 FAIL: administrator changed a role by direct UPDATE';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  -- Reading roles and the audited RPC still work.
  SELECT count(*) INTO v_count FROM public.user_roles WHERE user_id = v_customer;
  IF v_count <> 1 THEN RAISE EXCEPTION 'S28-01 FAIL: administrator cannot read roles'; END IF;
  PERFORM public.admin_set_user_platform_role(v_customer,'finance_officer',TRUE);
  EXECUTE 'SET LOCAL ROLE postgres';
  IF NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = v_customer AND role = 'finance_officer') THEN
    RAISE EXCEPTION 'S28-01 FAIL: audited role RPC did not grant the role';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.audit_events WHERE actor_user_id = v_admin AND entity_id = v_customer::text
      AND metadata::text LIKE '%finance_officer%'
  ) THEN RAISE EXCEPTION 'S28-01 FAIL: role change was not audited'; END IF;
  RAISE NOTICE 'S28-01 PASS: roles change only through the audited RPCs';

  -- ------------------------------------------------------ append-only logs
  BEGIN
    TRUNCATE public.audit_events;
    RAISE EXCEPTION 'S28-02 FAIL: audit_events was truncated';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'MUTATION_FORBIDDEN%' THEN RAISE; END IF;
  END;
  EXECUTE 'SET LOCAL ROLE service_role';
  BEGIN
    TRUNCATE public.audit_events;
    RAISE EXCEPTION 'S28-02 FAIL: service_role truncated audit_events';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    TRUNCATE public.customer_wallet_ledger CASCADE;
    RAISE EXCEPTION 'S28-02 FAIL: service_role truncated the wallet ledger';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  EXECUTE 'SET LOCAL ROLE postgres';
  INSERT INTO public.customer_wallet_ledger(user_id,entry_type,amount,balance_after,reference_type,reference_id,idempotency_key,actor_user_id,reason_code)
  VALUES(v_customer,'CREDIT',700,700,'DEPOSIT',gen_random_uuid(),gen_random_uuid(),v_admin,'TEST_ONLY')
  RETURNING id INTO v_ledger;
  BEGIN
    UPDATE public.customer_wallet_ledger SET amount = 999999 WHERE id = v_ledger;
    RAISE EXCEPTION 'S28-02 FAIL: a ledger entry was rewritten';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'MUTATION_FORBIDDEN%' THEN RAISE; END IF;
  END;
  BEGIN
    DELETE FROM public.customer_wallet_ledger WHERE id = v_ledger;
    RAISE EXCEPTION 'S28-02 FAIL: a ledger entry was deleted';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'MUTATION_FORBIDDEN%' THEN RAISE; END IF;
  END;
  BEGIN
    TRUNCATE public.customer_wallet_ledger CASCADE;
    RAISE EXCEPTION 'S28-02 FAIL: the wallet ledger was truncated';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'MUTATION_FORBIDDEN%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'S28-02 PASS: audit log and wallet ledger are append-only for every role';

  -- ---------------------------------------------------------------- misc
  SELECT provolatile INTO v_text FROM pg_proc WHERE oid = 'public.has_platform_role(text)'::regprocedure;
  IF v_text <> 's' THEN RAISE EXCEPTION 'S28-03 FAIL: has_platform_role volatility is %', v_text; END IF;
  IF has_function_privilege('anon', 'public.get_notification_transport_status()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.is_card_vault_empty()', 'EXECUTE') THEN
    RAISE EXCEPTION 'S28-03 FAIL: anon can still execute an information-leaking function';
  END IF;
  IF NOT public._is_trusted_grant_identity(now(), '{"provider":"google","providers":["google"]}')
     OR public._is_trusted_grant_identity(now(), '{"provider":"email","providers":["email","google"]}')
     OR public._is_trusted_grant_identity(now(), '{"provider":"google","providers":["google","email"]}')
     OR public._is_trusted_grant_identity(NULL, '{"provider":"google","providers":["google"]}')
     OR public._is_trusted_grant_identity(now(), '{"provider":"email"}')
     OR public._is_trusted_grant_identity(now(), NULL) THEN
    RAISE EXCEPTION 'S28-03 FAIL: trusted grant identity truth table is wrong';
  END IF;
  RAISE NOTICE 'S28-03 PASS: stable role check, no anon leak functions, Google-only grant identity';

  -- ------------------------------------------- verified network keeps name
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',v_owner::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_owner,'role','authenticated')::text,true);
  BEGIN
    UPDATE public.networks SET commercial_name = 'TEST_ONLY Famous Competitor' WHERE id = v_network;
    RAISE EXCEPTION 'S28-04 FAIL: owner renamed a verified network';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'REVERIFICATION_REQUIRED%' THEN RAISE; END IF;
  END;
  UPDATE public.networks SET city = 'عدن' WHERE id = v_network;
  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_admin,'role','authenticated')::text,true);
  UPDATE public.networks SET commercial_name = 'TEST_ONLY S28 Network Renamed' WHERE id = v_network;
  EXECUTE 'SET LOCAL ROLE postgres';
  SELECT commercial_name || '|' || city INTO v_text FROM public.networks WHERE id = v_network;
  IF v_text <> 'TEST_ONLY S28 Network Renamed|عدن' THEN
    RAISE EXCEPTION 'S28-04 FAIL: unexpected network row %', v_text;
  END IF;
  RAISE NOTICE 'S28-04 PASS: only an administrator renames a verified network';

  -- ------------------------------------ anonymized accounts stay anonymized
  EXECUTE 'SET LOCAL ROLE authenticated';
  BEGIN
    PERFORM public.admin_set_user_account_status(v_gone, 'active', 'TEST_ONLY resurrect');
    RAISE EXCEPTION 'S28-05 FAIL: an anonymized account was reactivated';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'INVALID_STATE%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'S28-05 PASS: an anonymized account cannot be reactivated';

  -- ------------------------------------------------------- PIN hash cost
  PERFORM set_config('request.jwt.claim.sub',v_customer::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer,'role','authenticated')::text,true);
  PERFORM public.set_account_pin('481516');
  IF NOT public.verify_account_pin('481516') OR public.verify_account_pin('000000') THEN
    RAISE EXCEPTION 'S28-06 FAIL: PIN verification is wrong';
  END IF;
  EXECUTE 'SET LOCAL ROLE postgres';
  SELECT pin_hash INTO v_text FROM public.account_pins WHERE user_id = v_customer;
  IF v_text NOT LIKE '$2a$10$%' THEN RAISE EXCEPTION 'S28-06 FAIL: PIN hash cost is not 10'; END IF;
  RAISE NOTICE 'S28-06 PASS: PIN is hashed with bcrypt cost 10';

  RAISE NOTICE 'NY_IDENTITY_ROLE_AUDIT_HARDENING_PASS';
END $$;

ROLLBACK;
