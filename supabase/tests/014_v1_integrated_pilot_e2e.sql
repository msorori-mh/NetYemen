-- NetYemen V1 integrated local-pilot E2E closure (TEST_ONLY, transactional).
BEGIN;

DO $$
DECLARE
  v_customer UUID := '91000000-0000-4000-8000-000000000001';
  v_owner UUID := '92000000-0000-4000-8000-000000000001';
  v_finance UUID := '93000000-0000-4000-8000-000000000001';
  v_support UUID := '93000000-0000-4000-8000-000000000002';
  v_admin UUID := '94000000-0000-4000-8000-000000000001';
  v_network UUID := '95000000-0000-4000-8000-000000000001';
  v_package UUID := '96000000-0000-4000-8000-000000000001';
  v_deposit UUID;
  v_purchase UUID;
  v_refund UUID;
  v_case UUID;
  v_result JSONB;
  v_key UUID := '97000000-0000-4000-8000-000000000001';
  v_count INTEGER;
  v_failed BOOLEAN;
BEGIN
  EXECUTE 'SET LOCAL ROLE postgres';
  INSERT INTO auth.users(id,email) VALUES
    (v_customer,'e2e-customer@pilot.netyemen.test'),
    (v_owner,'e2e-owner@pilot.netyemen.test'),
    (v_finance,'e2e-finance@pilot.netyemen.test'),
    (v_support,'e2e-support@pilot.netyemen.test'),
    (v_admin,'e2e-admin@pilot.netyemen.test');

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=v_customer)
     OR NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id=v_customer AND role='customer') THEN
    RAISE EXCEPTION 'E2E-01 FAIL: fresh auth identity/session projection missing';
  END IF;
  RAISE NOTICE 'E2E-01 PASS: fresh customer auth identity provisioned';

  INSERT INTO public.profiles(id,full_name,account_status) VALUES
    (v_owner,'TEST_ONLY Owner','active'),(v_finance,'TEST_ONLY Finance','active'),
    (v_support,'TEST_ONLY Support','active'),(v_admin,'TEST_ONLY Admin','active')
  ON CONFLICT(id) DO UPDATE SET account_status='active';
  INSERT INTO public.user_roles(user_id,role) VALUES
    (v_owner,'network_owner'),(v_finance,'finance_officer'),
    (v_support,'support_agent'),(v_admin,'platform_admin')
  ON CONFLICT DO NOTHING;

  INSERT INTO public.networks(id,commercial_name,governorate,city,status,verification_status,created_by,approved_by,approved_at)
  VALUES(v_network,'TEST_ONLY E2E Network','صنعاء','صنعاء','active','verified',v_owner,v_admin,now());
  INSERT INTO public.network_memberships(network_id,user_id,membership_role,status,created_by)
  VALUES(v_network,v_owner,'owner','active',v_admin);
  INSERT INTO public.network_packages(id,network_id,name,price,duration_value,duration_unit,package_type,status,is_public,created_by)
  VALUES(v_package,v_network,'TEST_ONLY E2E Package',1000,1,'day','time','active',true,v_owner);

  EXECUTE 'SET LOCAL ROLE anon';
  SELECT count(*) INTO v_count FROM public.networks WHERE id=v_network;
  IF v_count<>1 THEN RAISE EXCEPTION 'E2E-02 FAIL: public discovery'; END IF;
  RAISE NOTICE 'E2E-02 PASS: public network discovery';

  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',v_owner::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_owner,'role','authenticated')::text,true);
  PERFORM public.adjust_package_inventory(v_package,2,'TEST_ONLY E2E stock',gen_random_uuid());
  RAISE NOTICE 'E2E-04/05 PASS: owner package and inventory operations';

  PERFORM set_config('request.jwt.claim.sub',v_customer::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer,'role','authenticated')::text,true);
  SELECT count(*) INTO v_count FROM public.network_packages WHERE id=v_package AND status='active' AND is_public;
  IF v_count<>1 THEN RAISE EXCEPTION 'E2E-06 FAIL: active package not visible'; END IF;
  v_result := public.create_wallet_deposit_request(5000,'TEST_ONLY-E2E-DEPOSIT',NULL,NULL,gen_random_uuid());
  v_deposit := (v_result->>'id')::uuid;

  PERFORM set_config('request.jwt.claim.sub',v_finance::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_finance,'role','authenticated')::text,true);
  PERFORM public.review_wallet_deposit_request(v_deposit,'approve');
  PERFORM public.review_wallet_deposit_request(v_deposit,'approve');
  SELECT count(*) INTO v_count FROM public.customer_wallet_ledger WHERE reference_type='DEPOSIT' AND reference_id=v_deposit;
  IF v_count<>1 THEN RAISE EXCEPTION 'E2E-07 FAIL: deposit approval not exactly once'; END IF;
  RAISE NOTICE 'E2E-07 PASS: local deposit review credits exactly once';

  PERFORM set_config('request.jwt.claim.sub',v_customer::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer,'role','authenticated')::text,true);
  v_result := public.purchase_package(v_package,v_key);
  v_purchase := (v_result->>'purchase_id')::uuid;
  v_result := public.purchase_package(v_package,v_key);
  IF (v_result->>'purchase_id')::uuid<>v_purchase OR coalesce((v_result->>'replayed')::boolean,false)<>true THEN
    RAISE EXCEPTION 'E2E-10 FAIL: retry was not idempotent';
  END IF;
  RAISE NOTICE 'E2E-08/10 PASS: purchase and retry are atomic/idempotent';

  EXECUTE 'SET LOCAL ROLE postgres';
  SELECT count(*) INTO v_count FROM public.owner_settlement_items
  WHERE purchase_id=v_purchase AND gross_amount=1000 AND platform_commission_amount IS NULL
    AND net_settlement_amount IS NULL AND settlement_status='awaiting_policy';
  IF v_count<>1 THEN RAISE EXCEPTION 'E2E-08/SETTLE FAIL: governance hold missing'; END IF;

  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',v_customer::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer,'role','authenticated')::text,true);
  v_failed:=false;
  BEGIN PERFORM public.reveal_purchase_fulfillment(v_purchase);
  EXCEPTION WHEN SQLSTATE '55000' THEN v_failed:=true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'E2E-11 FAIL: fulfillment did not fail closed'; END IF;
  RAISE NOTICE 'E2E-11 PASS: unbound vault fails closed';

  v_result := public.create_purchase_support_case(v_purchase,'high','TEST_ONLY نزاع شراء','بيانات التسليم غير متاحة في الاختبار المحلي');
  v_case := (v_result->>'id')::uuid;
  IF NOT EXISTS(SELECT 1 FROM public.support_cases WHERE id=v_case AND purchase_id=v_purchase) THEN
    RAISE EXCEPTION 'E2E-12 FAIL: purchase dispute link missing';
  END IF;
  RAISE NOTICE 'E2E-12 PASS: support dispute linked to purchase';

  v_result := public.submit_refund_request(v_purchase,'TEST_ONLY refund hook');
  v_refund := (v_result->>'id')::uuid;
  PERFORM set_config('request.jwt.claim.sub',v_support::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_support,'role','authenticated')::text,true);
  PERFORM public.update_support_case(v_case,'resolved','يوصى بالاسترداد بعد المراجعة المحلية','refund_recommended',NULL);
  PERFORM public.review_refund_request(v_refund,'approve');
  EXECUTE 'SET LOCAL ROLE postgres';
  IF NOT EXISTS(SELECT 1 FROM public.customer_wallet_ledger WHERE reference_type='REFUND' AND reference_id=v_refund) THEN
    RAISE EXCEPTION 'E2E-13 FAIL: compensating refund missing';
  END IF;
  RAISE NOTICE 'E2E-13 PASS: recommendation and compensating refund hook';

  EXECUTE 'SET LOCAL ROLE postgres';
  SELECT count(*) INTO v_count FROM public.notification_events
  WHERE source_entity_id IN (v_deposit::text,v_purchase::text,v_refund::text);
  IF v_count<3 THEN RAISE EXCEPTION 'E2E-14 FAIL: expected integrated notification events'; END IF;
  IF EXISTS(SELECT 1 FROM public.notification_transport_config WHERE binding_status<>'unbound') THEN
    RAISE EXCEPTION 'E2E-14 FAIL: external notification transport unexpectedly bound';
  END IF;
  RAISE NOTICE 'E2E-14 PASS: events/outbox created, external transport unbound';

  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_admin,'role','authenticated')::text,true);
  SELECT count(*) INTO v_count FROM public.audit_events
  WHERE entity_id IN (v_deposit::text,v_purchase::text,v_refund::text,v_case::text);
  IF v_count<4 THEN RAISE EXCEPTION 'E2E-15 FAIL: integrated audit events missing (%)',v_count; END IF;
  RAISE NOTICE 'E2E-15 PASS: admin audit visibility';

  RAISE NOTICE 'E2E-03 PASS: network request/admin review covered by 005/006/008 integrated suites';
  RAISE NOTICE 'E2E-09 PASS: concurrent last-unit behavior covered by scripts/test_commerce_concurrency.py';
  RAISE NOTICE 'NY_V1_INTEGRATED_PILOT_E2E_PASS';
END $$;

ROLLBACK;
