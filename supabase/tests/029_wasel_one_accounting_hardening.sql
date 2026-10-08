-- WASEL One session and accounting hardening (TEST_ONLY, transactional).
-- Verifies 20261008093000_wasel_one_accounting_hardening.sql.
BEGIN;

DO $$
DECLARE
  v_customer   UUID := 'a2900000-0000-4000-8000-000000000001';
  v_other      UUID := 'a2900000-0000-4000-8000-000000000002';
  v_owner      UUID := 'a2900000-0000-4000-8000-000000000003';
  v_admin      UUID := 'a2900000-0000-4000-8000-000000000004';
  v_network    UUID := 'a2900000-0000-4000-8000-000000000010';
  v_network_b  UUID := 'a2900000-0000-4000-8000-000000000011';
  v_plan       UUID := 'a2900000-0000-4000-8000-000000000020';
  v_node       UUID := 'a2900000-0000-4000-8000-000000000030';
  v_node_b     UUID := 'a2900000-0000-4000-8000-000000000031';
  v_ent        UUID := 'a2900000-0000-4000-8000-000000000040';
  v_credential JSONB;
  v_authz      JSONB;
  v_username   TEXT;
  v_password   TEXT;
  v_session    UUID;
  v_session_b  UUID;
  v_session_c  UUID;
  v_result     JSONB;
  v_count      INTEGER;
  v_quantity   NUMERIC;
  v_amount     INTEGER;
  v_msg        TEXT;
  v_text       TEXT;
  v_gib        BIGINT := 1073741824;
BEGIN
  EXECUTE 'SET LOCAL ROLE postgres';
  INSERT INTO auth.users(id,email) VALUES
    (v_customer,'s29-customer@example.test'),(v_other,'s29-other@example.test'),
    (v_owner,'s29-owner@example.test'),(v_admin,'s29-admin@example.test');
  INSERT INTO public.profiles(id,full_name,account_status) VALUES
    (v_customer,'TEST_ONLY S29 Customer','active'),(v_other,'TEST_ONLY S29 Other','active'),
    (v_owner,'TEST_ONLY S29 Owner','active'),(v_admin,'TEST_ONLY S29 Admin','active')
  ON CONFLICT(id) DO UPDATE SET account_status='active';
  INSERT INTO public.user_roles(user_id,role) VALUES
    (v_customer,'customer'),(v_other,'customer'),(v_owner,'network_owner'),(v_admin,'platform_admin')
  ON CONFLICT DO NOTHING;

  INSERT INTO public.networks(id,commercial_name,status,verification_status,created_by,approved_by,approved_at) VALUES
    (v_network,'TEST_ONLY S29 Partner A','active','verified',v_owner,v_admin,NOW()),
    (v_network_b,'TEST_ONLY S29 Partner B','active','verified',v_owner,v_admin,NOW());
  INSERT INTO public.network_memberships(network_id,user_id,membership_role,status,created_by)
  VALUES(v_network,v_owner,'owner','active',v_admin);
  INSERT INTO public.federated_access_plans(id,name,retail_price,validity_seconds,quota_bytes,speed_limit_kbps,status,is_public,created_by)
  VALUES(v_plan,'TEST_ONLY S29 Plan',1000,86400,v_gib,4096,'active',TRUE,v_admin);
  INSERT INTO public.federated_plan_networks(plan_id,network_id,compensation_model,compensation_rate_minor,is_active,created_by) VALUES
    (v_plan,v_network,'per_gib',500,TRUE,v_admin),
    (v_plan,v_network_b,'per_session',100,TRUE,v_admin);
  INSERT INTO public.network_access_nodes(id,network_id,display_name,nas_identifier,status,created_by) VALUES
    (v_node,v_network,'TEST_ONLY S29 Router A','s29-nas-a','active',v_admin),
    (v_node_b,v_network_b,'TEST_ONLY S29 Router B','s29-nas-b','active',v_admin);
  INSERT INTO public.access_entitlements(id,user_id,plan_id,status,starts_at,expires_at,allowance_bytes,speed_limit_kbps,source_type,idempotency_key)
  VALUES(v_ent,v_customer,v_plan,'active',NOW() - INTERVAL '1 hour',NOW() + INTERVAL '1 day',v_gib,4096,'pilot',gen_random_uuid());

  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',v_customer::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer,'role','authenticated')::text,true);
  v_credential := public.issue_radius_access_credential(v_ent);
  v_username := v_credential->>'username';
  v_password := v_credential->>'password';

  -- ----------------------------------------------------- lost Stop recovery
  EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  v_authz := public.radius_authorize_access('s29-nas-a',v_username,v_password,gen_random_uuid(),NULL);
  v_session := (v_authz->>'session_id')::uuid;
  PERFORM public.radius_record_accounting(v_session,'s29-nas-a','s29-a:start','start',NOW(),0,0,0);

  -- A live session holds the single concurrency slot.
  BEGIN
    PERFORM public.radius_authorize_access('s29-nas-a',v_username,v_password,gen_random_uuid(),NULL);
    RAISE EXCEPTION 'S29-01 FAIL: second concurrent session authorized';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'CONCURRENCY_LIMIT_REACHED%' THEN RAISE; END IF;
  END;

  -- The router loses power: no Stop ever arrives.
  EXECUTE 'SET LOCAL ROLE postgres';
  UPDATE public.access_sessions
  SET authorized_at = NOW() - INTERVAL '50 minutes',
      grant_expires_at = NOW() - INTERVAL '45 minutes',
      started_at = NOW() - INTERVAL '49 minutes',
      last_accounting_at = NOW() - INTERVAL '40 minutes'
  WHERE id = v_session;

  EXECUTE 'SET LOCAL ROLE service_role';
  v_authz := public.radius_authorize_access('s29-nas-a',v_username,v_password,gen_random_uuid(),NULL);
  v_session_b := (v_authz->>'session_id')::uuid;
  IF v_session_b IS NULL OR v_session_b = v_session THEN
    RAISE EXCEPTION 'S29-01 FAIL: customer still locked out after a lost Stop (%)', v_authz;
  END IF;
  RAISE NOTICE 'S29-01 PASS: a session that went silent no longer blocks the next login';

  v_result := public.radius_close_stale_sessions();
  EXECUTE 'SET LOCAL ROLE postgres';
  SELECT status || '|' || close_reason INTO v_text FROM public.access_sessions WHERE id = v_session;
  IF v_text <> 'closed|stale_timeout' THEN
    RAISE EXCEPTION 'S29-02 FAIL: stale session is %, result %', v_text, v_result;
  END IF;
  SELECT status INTO v_text FROM public.access_sessions WHERE id = v_session_b;
  IF v_text <> 'authorized' THEN RAISE EXCEPTION 'S29-02 FAIL: fresh session was touched (%)', v_text; END IF;
  IF has_function_privilege('authenticated','public.radius_close_stale_sessions(interval)','EXECUTE')
     OR has_function_privilege('anon','public.radius_close_stale_sessions(interval)','EXECUTE') THEN
    RAISE EXCEPTION 'S29-02 FAIL: a client role can run the session reaper';
  END IF;
  RAISE NOTICE 'S29-02 PASS: stale sessions are closed by the service-only reaper';

  -- --------------------------------------------------- accrual is bounded
  EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM public.radius_record_accounting(v_session_b,'s29-nas-a','s29-b:start','start',NOW(),0,0,0);
  -- The partner router claims 100 GiB on a session that was granted 1 GiB.
  PERFORM public.radius_record_accounting(v_session_b,'s29-nas-a','s29-b:stop','stop',NOW(),50 * v_gib,50 * v_gib,2000000000);
  EXECUTE 'SET LOCAL ROLE postgres';
  SELECT quantity, amount_minor INTO v_quantity, v_amount
  FROM public.partner_usage_ledger WHERE session_id = v_session_b AND entry_type = 'accrual';
  IF v_quantity IS NULL OR v_quantity > 1 OR v_amount > 500 THEN
    RAISE EXCEPTION 'S29-03 FAIL: accrual quantity % amount % exceeds the 1 GiB grant', v_quantity, v_amount;
  END IF;
  RAISE NOTICE 'S29-03 PASS: per-GiB accrual is capped at the session grant (quantity %, amount %)', v_quantity, v_amount;

  -- Per-session fee is not paid for an empty login/logout loop.
  UPDATE public.access_entitlements
  SET consumed_bytes = 0, status = 'active', allowance_bytes = NULL WHERE id = v_ent;
  EXECUTE 'SET LOCAL ROLE service_role';
  v_authz := public.radius_authorize_access('s29-nas-b',v_username,v_password,gen_random_uuid(),NULL);
  v_session_c := (v_authz->>'session_id')::uuid;
  PERFORM public.radius_record_accounting(v_session_c,'s29-nas-b','s29-c:start','start',NOW(),0,0,0);
  PERFORM public.radius_record_accounting(v_session_c,'s29-nas-b','s29-c:stop','stop',NOW(),0,0,5);
  EXECUTE 'SET LOCAL ROLE postgres';
  SELECT amount_minor INTO v_amount FROM public.partner_usage_ledger WHERE session_id = v_session_c;
  IF v_amount IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'S29-04 FAIL: empty 5 second session accrued %', v_amount;
  END IF;
  -- A real session on the same network does earn the fee, and reported time
  -- is capped at the wall-clock time since authorization.
  EXECUTE 'SET LOCAL ROLE service_role';
  v_authz := public.radius_authorize_access('s29-nas-b',v_username,v_password,gen_random_uuid(),NULL);
  v_session_c := (v_authz->>'session_id')::uuid;
  PERFORM public.radius_record_accounting(v_session_c,'s29-nas-b','s29-d:start','start',NOW(),0,0,0);
  PERFORM public.radius_record_accounting(v_session_c,'s29-nas-b','s29-d:stop','stop',NOW(),1000,2000,30);
  EXECUTE 'SET LOCAL ROLE postgres';
  SELECT amount_minor INTO v_amount FROM public.partner_usage_ledger WHERE session_id = v_session_c;
  IF v_amount IS DISTINCT FROM 100 THEN
    RAISE EXCEPTION 'S29-04 FAIL: real session accrued %, expected 100', v_amount;
  END IF;
  RAISE NOTICE 'S29-04 PASS: per-session fee needs real usage';

  -- ------------------------------------- inactive accounts get no access
  UPDATE public.profiles SET account_status = 'suspended' WHERE id = v_customer;
  EXECUTE 'SET LOCAL ROLE service_role';
  BEGIN
    PERFORM public.radius_authorize_access('s29-nas-a',v_username,v_password,gen_random_uuid(),NULL);
    RAISE EXCEPTION 'S29-05 FAIL: suspended account authenticated on Wi-Fi';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'ACCOUNT_NOT_ACTIVE%' THEN RAISE; END IF;
  END;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',v_customer::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer,'role','authenticated')::text,true);
  BEGIN
    PERFORM public.issue_radius_access_credential(v_ent);
    RAISE EXCEPTION 'S29-05 FAIL: suspended account issued a credential';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'INACTIVE_PROFILE%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'S29-05 PASS: suspended accounts cannot issue credentials or authenticate';

  -- ---------------------------------- compensation terms are not public
  EXECUTE 'SET LOCAL ROLE anon';
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claims','{}',true);
  SELECT count(*) INTO v_count FROM (
    SELECT plan_id, network_id FROM public.federated_plan_networks WHERE plan_id = v_plan
  ) visible;
  IF v_count <> 2 THEN RAISE EXCEPTION 'S29-06 FAIL: anon sees % plan networks, expected 2', v_count; END IF;
  BEGIN
    PERFORM compensation_rate_minor FROM public.federated_plan_networks LIMIT 1;
    RAISE EXCEPTION 'S29-06 FAIL: anon read partner compensation rates';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',v_other::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_other,'role','authenticated')::text,true);
  BEGIN
    PERFORM compensation_model FROM public.federated_plan_networks LIMIT 1;
    RAISE EXCEPTION 'S29-06 FAIL: a customer read partner compensation terms';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM * FROM public.get_network_compensation_terms(v_network);
    RAISE EXCEPTION 'S29-06 FAIL: a customer read compensation terms through the RPC';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'FORBIDDEN_ROLE%' THEN RAISE; END IF;
  END;
  PERFORM set_config('request.jwt.claim.sub',v_owner::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_owner,'role','authenticated')::text,true);
  SELECT count(*) INTO v_count FROM public.get_network_compensation_terms(v_network)
  WHERE compensation_model = 'per_gib' AND compensation_rate_minor = 500;
  IF v_count <> 1 THEN RAISE EXCEPTION 'S29-06 FAIL: owner cannot read own compensation terms'; END IF;
  BEGIN
    PERFORM * FROM public.get_network_compensation_terms(v_network_b);
    RAISE EXCEPTION 'S29-06 FAIL: owner read another network''s compensation terms';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'FORBIDDEN_ROLE%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'S29-06 PASS: compensation terms are visible to the owner and staff only';

  RAISE NOTICE 'NY_WASEL_ONE_ACCOUNTING_HARDENING_PASS';
END $$;

ROLLBACK;
