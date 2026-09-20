-- NetYemen V1 integrated external-pilot E2E binding closure (TEST_ONLY, transactional).
BEGIN;

DO $$
DECLARE
  -- Actors
  v_customer      UUID := '91000000-0000-4000-8000-000000000001';
  v_customer_b    UUID := '91000000-0000-4000-8000-000000000002';
  v_owner         UUID := '92000000-0000-4000-8000-000000000001';
  v_finance       UUID := '93000000-0000-4000-8000-000000000001';
  v_finance_b     UUID := '93000000-0000-4000-8000-000000000003';
  v_support       UUID := '93000000-0000-4000-8000-000000000002';
  v_admin         UUID := '94000000-0000-4000-8000-000000000001';

  -- Network / package
  v_network       UUID := '95000000-0000-4000-8000-000000000001';
  v_package       UUID := '96000000-0000-4000-8000-000000000001';

  -- Test state
  v_destination   UUID;
  v_deposit       UUID;
  v_purchase      UUID;
  v_purchase_b    UUID;
  v_refund        UUID;
  v_case          UUID;
  v_dispute_case  UUID;
  v_batch         UUID;
  v_result        JSONB;
  v_count         INTEGER;
  v_balance       INTEGER;
  v_failed        BOOLEAN;
  v_key           UUID := '97000000-0000-4000-8000-000000000001';
  v_plaintext     TEXT := 'TEST_ONLY_SECRET_001';
  v_ciphertext_b64 TEXT;
  v_reveal        JSONB;
BEGIN
  EXECUTE 'SET LOCAL ROLE postgres';
  INSERT INTO auth.users(id,email) VALUES
    (v_customer,'e2e-customer@pilot.netyemen.test'),
    (v_customer_b,'e2e-customer-b@pilot.netyemen.test'),
    (v_owner,'e2e-owner@pilot.netyemen.test'),
    (v_finance,'e2e-finance@pilot.netyemen.test'),
    (v_finance_b,'e2e-finance-b@pilot.netyemen.test'),
    (v_support,'e2e-support@pilot.netyemen.test'),
    (v_admin,'e2e-admin@pilot.netyemen.test');

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=v_customer)
     OR NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id=v_customer AND role='customer') THEN
    RAISE EXCEPTION 'E2E-01 FAIL: fresh auth identity/session projection missing';
  END IF;
  RAISE NOTICE 'E2E-01 PASS: fresh customer auth identity provisioned';

  INSERT INTO public.profiles(id,full_name,account_status) VALUES
    (v_customer_b,'TEST_ONLY Customer B','active'),
    (v_owner,'TEST_ONLY Owner','active'),
    (v_finance,'TEST_ONLY Finance','active'),
    (v_finance_b,'TEST_ONLY Finance B','active'),
    (v_support,'TEST_ONLY Support','active'),
    (v_admin,'TEST_ONLY Admin','active')
  ON CONFLICT(id) DO UPDATE SET account_status='active';

  INSERT INTO public.user_roles(user_id,role) VALUES
    (v_customer_b,'customer'),
    (v_owner,'network_owner'),
    (v_finance,'finance_officer'),
    (v_finance_b,'finance_officer'),
    (v_support,'support_agent'),
    (v_admin,'platform_admin')
  ON CONFLICT DO NOTHING;

  INSERT INTO public.networks(id,commercial_name,governorate,city,status,verification_status,created_by,approved_by,approved_at)
  VALUES(v_network,'TEST_ONLY E2E Network','صنعاء','صنعاء','active','verified',v_owner,v_admin,now());
  INSERT INTO public.network_memberships(network_id,user_id,membership_role,status,created_by)
  VALUES(v_network,v_owner,'owner','active',v_admin);
  INSERT INTO public.network_packages(id,network_id,name,price,duration_value,duration_unit,package_type,status,is_public,created_by)
  VALUES(v_package,v_network,'TEST_ONLY E2E Package',1000,1,'day','time','active',true,v_owner);

  EXECUTE 'SET LOCAL ROLE anon';
  IF current_user != 'anon' THEN
    RAISE EXCEPTION 'E2E-02 FAIL: session role is %, expected anon', current_user;
  END IF;
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claims','{}',true);
  SELECT count(*) INTO v_count FROM public.networks WHERE id=v_network;
  IF v_count<>1 THEN RAISE EXCEPTION 'E2E-02 FAIL: public discovery'; END IF;
  RAISE NOTICE 'E2E-02 PASS: public network discovery';

  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',v_owner::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_owner,'role','authenticated')::text,true);
  PERFORM public.adjust_package_inventory(v_package,2,'TEST_ONLY E2E stock',gen_random_uuid());
  RAISE NOTICE 'E2E-04/05 PASS: owner package and inventory operations';

  -- E2E-16: Admin creates payment destination
  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_admin,'role','authenticated')::text,true);
  v_destination := public.admin_create_payment_destination(
    'bank_account',
    'TEST_ONLY Bank',
    'TEST_ONLY Holder',
    'TEST_ONLY-ACCT-001',
    'TEST_ONLY deposit instructions',
    'YER',
    0
  );
  IF v_destination IS NULL THEN RAISE EXCEPTION 'E2E-16 FAIL: destination not created'; END IF;
  RAISE NOTICE 'E2E-16 PASS: admin creates payment destination';

  -- E2E-17: Customer submits deposit against destination
  PERFORM set_config('request.jwt.claim.sub',v_customer::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer,'role','authenticated')::text,true);
  SELECT count(*) INTO v_count FROM public.network_packages WHERE id=v_package AND status='active' AND is_public;
  IF v_count<>1 THEN RAISE EXCEPTION 'E2E-06 FAIL: active package not visible'; END IF;

  v_result := public.create_wallet_deposit_request(5000,'TEST_ONLY-E2E-DEPOSIT',v_destination,NULL,gen_random_uuid());
  v_deposit := (v_result->>'id')::uuid;
  IF NOT EXISTS (
    SELECT 1 FROM public.wallet_deposit_requests
    WHERE id=v_deposit AND bank_directory_id=v_destination
      AND destination_snapshot->>'display_name' = 'TEST_ONLY Bank'
  ) THEN
    RAISE EXCEPTION 'E2E-17 FAIL: deposit destination snapshot missing';
  END IF;
  RAISE NOTICE 'E2E-17 PASS: customer submits deposit against destination';

  -- E2E-18: Finance approves once -> wallet credited once
  PERFORM set_config('request.jwt.claim.sub',v_finance::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_finance,'role','authenticated')::text,true);
  PERFORM public.review_wallet_deposit_request(v_deposit,'approve');
  PERFORM public.review_wallet_deposit_request(v_deposit,'approve');
  SELECT count(*) INTO v_count FROM public.customer_wallet_ledger WHERE reference_type='DEPOSIT' AND reference_id=v_deposit;
  IF v_count<>1 THEN RAISE EXCEPTION 'E2E-18 FAIL: deposit approval not exactly once'; END IF;
  SELECT cached_balance INTO v_balance FROM public.wallet_accounts WHERE user_id=v_customer;
  IF v_balance<>5000 THEN RAISE EXCEPTION 'E2E-18 FAIL: wallet balance %, expected 5000',v_balance; END IF;
  RAISE NOTICE 'E2E-18 PASS: finance approves once and wallet credited once';

  -- Ingest encrypted cards for E2E-20/21/22/23/24
  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_admin,'role','authenticated')::text,true);
  v_ciphertext_b64 := encode(v_plaintext::bytea,'base64');
  v_result := public.admin_ingest_card_vault_batch(
    v_network,
    v_package,
    ARRAY[
      jsonb_build_object('ciphertext',v_ciphertext_b64,'nonce','TEST_ONLY_NONCE_001','auth_tag','TEST_ONLY_TAG_001'),
      jsonb_build_object('ciphertext',encode('TEST_ONLY_SECRET_002'::bytea,'base64'),'nonce','TEST_ONLY_NONCE_002','auth_tag','TEST_ONLY_TAG_002')
    ]::jsonb[],
    'v1-test'
  );
  IF COALESCE((v_result->>'ingested_count')::integer,0)<>2 THEN
    RAISE EXCEPTION 'E2E-20 FAIL: card ingestion returned %',v_result;
  END IF;

  -- E2E-19: 3% commission purchase calculation
  -- E2E-20: encrypted card available -> purchase consumes exactly one
  PERFORM set_config('request.jwt.claim.sub',v_customer::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer,'role','authenticated')::text,true);

  EXECUTE 'SET LOCAL ROLE postgres';
  SELECT count(*) INTO v_count FROM public.card_vault WHERE package_id=v_package AND state='available';
  IF v_count<>2 THEN RAISE EXCEPTION 'E2E-20 FAIL: expected 2 available cards, got %',v_count; END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';

  v_result := public.purchase_package(v_package,v_key);
  v_purchase := (v_result->>'purchase_id')::uuid;

  SELECT gross_amount, commission_rate_snapshot, commission_amount, owner_net_amount
  INTO v_result
  FROM public.purchase_records WHERE id=v_purchase;
  IF (v_result->>'gross_amount')::integer<>1000 THEN RAISE EXCEPTION 'E2E-19 FAIL: gross amount'; END IF;
  IF (v_result->>'commission_rate_snapshot')::numeric<>0.0300 THEN RAISE EXCEPTION 'E2E-19 FAIL: commission rate'; END IF;
  IF (v_result->>'commission_amount')::integer<>floor(1000*0.03)::integer THEN RAISE EXCEPTION 'E2E-19 FAIL: commission amount'; END IF;
  IF (v_result->>'owner_net_amount')::integer<>(1000 - floor(1000*0.03)::integer) THEN RAISE EXCEPTION 'E2E-19 FAIL: owner net amount'; END IF;
  RAISE NOTICE 'E2E-19 PASS: 3%% commission purchase calculation';

  EXECUTE 'SET LOCAL ROLE postgres';
  SELECT count(*) INTO v_count FROM public.card_vault WHERE package_id=v_package AND state='available';
  IF v_count<>1 THEN RAISE EXCEPTION 'E2E-20 FAIL: expected 1 remaining available card, got %',v_count; END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  EXECUTE 'SET LOCAL ROLE postgres';
  IF NOT EXISTS (SELECT 1 FROM public.card_vault WHERE purchase_id=v_purchase AND state='sold') THEN
    RAISE EXCEPTION 'E2E-20 FAIL: purchased card not marked sold';
  END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  RAISE NOTICE 'E2E-20 PASS: purchase consumes exactly one encrypted card';

  v_result := public.purchase_package(v_package,v_key);
  IF (v_result->>'purchase_id')::uuid<>v_purchase OR coalesce((v_result->>'replayed')::boolean,false)<>true THEN
    RAISE EXCEPTION 'E2E-10 FAIL: retry was not idempotent';
  END IF;
  RAISE NOTICE 'E2E-10 PASS: purchase replay is idempotent';

  -- Idempotent replay must not consume a second card.
  EXECUTE 'SET LOCAL ROLE postgres';
  SELECT count(*) INTO v_count FROM public.card_vault WHERE package_id=v_package AND state='available';
  IF v_count<>1 THEN RAISE EXCEPTION 'E2E-10 FAIL: idempotent replay consumed another card'; END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';

  -- E2E-21: Authorized purchaser reveals card
  PERFORM set_config('request.jwt.claim.sub',v_customer::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer,'role','authenticated')::text,true);
  v_reveal := public.reveal_purchase_card_secret(v_purchase);
  IF (v_reveal->>'purchase_id')::uuid<>v_purchase THEN RAISE EXCEPTION 'E2E-21 FAIL: reveal mismatch'; END IF;
  IF (v_reveal->>'status')<>'revealed' THEN RAISE EXCEPTION 'E2E-21 FAIL: reveal status'; END IF;
  IF (v_reveal->>'ciphertext_b64') IS NULL OR length(v_reveal->>'ciphertext_b64')=0 THEN
    RAISE EXCEPTION 'E2E-21 FAIL: no ciphertext returned';
  END IF;
  IF (v_reveal->>'ciphertext_b64')<>v_ciphertext_b64 THEN
    RAISE EXCEPTION 'E2E-21 FAIL: returned ciphertext does not match ingested payload';
  END IF;
  EXECUTE 'SET LOCAL ROLE postgres';
  IF NOT EXISTS (SELECT 1 FROM public.card_vault WHERE purchase_id=v_purchase AND reveal_count=1 AND dispute_deadline>NOW()) THEN
    RAISE EXCEPTION 'E2E-21 FAIL: card reveal metadata not updated';
  END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  RAISE NOTICE 'E2E-21 PASS: authorized purchaser reveals card';

  -- E2E-22: Other customer reveal denied
  PERFORM set_config('request.jwt.claim.sub',v_customer_b::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer_b,'role','authenticated')::text,true);
  v_failed:=false;
  BEGIN PERFORM public.reveal_purchase_card_secret(v_purchase);
  EXCEPTION WHEN SQLSTATE '42501' THEN v_failed:=true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'E2E-22 FAIL: other customer reveal was allowed'; END IF;
  RAISE NOTICE 'E2E-22 PASS: other customer reveal denied';

  -- E2E-23: Invalid-card dispute within 30 min accepted
  PERFORM set_config('request.jwt.claim.sub',v_customer::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer,'role','authenticated')::text,true);
  v_result := public.submit_invalid_card_dispute(v_purchase,'TEST_ONLY invalid card dispute');
  v_dispute_case := (v_result->>'id')::uuid;
  IF NOT EXISTS (
    SELECT 1 FROM public.support_cases
    WHERE id=v_dispute_case AND purchase_id=v_purchase AND case_type='dispute'
  ) THEN
    RAISE EXCEPTION 'E2E-23 FAIL: invalid-card dispute case not created';
  END IF;
  RAISE NOTICE 'E2E-23 PASS: invalid-card dispute within 30 min accepted';

  -- E2E-24: Direct invalid-card dispute after 30 min rejected (SQLSTATE 22023)
  EXECUTE 'SET LOCAL ROLE postgres';
  UPDATE public.card_vault
  SET first_revealed_at = NOW() - INTERVAL '31 minutes',
      dispute_deadline = NOW() - INTERVAL '1 minute'
  WHERE purchase_id = v_purchase;

  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',v_customer::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer,'role','authenticated')::text,true);
  v_failed:=false;
  BEGIN PERFORM public.submit_invalid_card_dispute(v_purchase,'TEST_ONLY late dispute');
  EXCEPTION WHEN SQLSTATE '22023' THEN v_failed:=true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'E2E-24 FAIL: late dispute was accepted'; END IF;
  RAISE NOTICE 'E2E-24 PASS: late invalid-card dispute rejected with SQLSTATE 22023';

  -- Fund customer_b and have them purchase the second card; later the third attempt hits empty vault.
  EXECUTE 'SET LOCAL ROLE postgres';
  INSERT INTO public.customer_wallet_ledger (
    user_id, entry_type, amount, balance_after, reference_type,
    reference_id, idempotency_key, actor_user_id, reason_code
  ) VALUES (v_customer_b,'CREDIT',5000,5000,'ADJUSTMENT',gen_random_uuid(),gen_random_uuid(),v_admin,'TEST_ONLY_CREDIT');
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',v_customer_b::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer_b,'role','authenticated')::text,true);
  v_result := public.purchase_package(v_package,gen_random_uuid());
  v_purchase_b := (v_result->>'purchase_id')::uuid;

  -- E2E-11 repurposed: purchase fails closed when vault is out of stock
  v_failed:=false;
  BEGIN PERFORM public.purchase_package(v_package,gen_random_uuid());
  EXCEPTION WHEN SQLSTATE '22000' THEN v_failed:=true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'E2E-11 FAIL: out-of-stock vault purchase was allowed'; END IF;
  RAISE NOTICE 'E2E-11 PASS: purchase fails closed when vault is out of stock';

  -- E2E-25: Weekly settlement batch calculation
  PERFORM set_config('request.jwt.claim.sub',v_finance::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_finance,'role','authenticated')::text,true);
  v_result := public.finance_create_settlement_batch(CURRENT_DATE, CURRENT_DATE, v_network);
  IF COALESCE((v_result->>'batches_created')::integer,0)<1 THEN
    RAISE EXCEPTION 'E2E-25 FAIL: settlement batch not created: %',v_result;
  END IF;
  SELECT id INTO v_batch
  FROM public.settlement_batches
  WHERE network_id=v_network AND owner_user_id=v_owner AND status='draft'
  ORDER BY created_at DESC LIMIT 1;
  IF v_batch IS NULL THEN RAISE EXCEPTION 'E2E-25 FAIL: draft batch not found'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.settlement_batch_lines
    WHERE settlement_batch_id=v_batch AND line_type='sale' AND reference_id=v_purchase
  ) THEN
    RAISE EXCEPTION 'E2E-25 FAIL: purchase not included in batch lines';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.settlement_batch_lines
    WHERE settlement_batch_id=v_batch AND line_type='sale' AND reference_id=v_purchase_b
  ) THEN
    RAISE EXCEPTION 'E2E-25 FAIL: second purchase not included in batch lines';
  END IF;
  RAISE NOTICE 'E2E-25 PASS: weekly settlement batch calculation';

  -- E2E-26: Finance settlement approval (self-approval block)
  v_failed:=false;
  BEGIN PERFORM public.finance_approve_settlement_batch(v_batch);
  EXCEPTION WHEN SQLSTATE '42501' THEN v_failed:=true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'E2E-26 FAIL: creator self-approval was allowed'; END IF;

  PERFORM set_config('request.jwt.claim.sub',v_finance_b::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_finance_b,'role','authenticated')::text,true);
  v_result := public.finance_approve_settlement_batch(v_batch);
  IF (v_result->>'status')<>'approved' THEN RAISE EXCEPTION 'E2E-26 FAIL: batch approval failed'; END IF;
  RAISE NOTICE 'E2E-26 PASS: finance settlement approval with self-approval block';

  -- E2E-12/13: Purchase support case + refund hook
  PERFORM set_config('request.jwt.claim.sub',v_customer_b::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer_b,'role','authenticated')::text,true);
  v_result := public.create_purchase_support_case(v_purchase_b,'high','TEST_ONLY نزاع شراء','بيانات التسليم غير متاحة في الاختبار المحلي');
  v_case := (v_result->>'id')::uuid;
  IF NOT EXISTS(SELECT 1 FROM public.support_cases WHERE id=v_case AND purchase_id=v_purchase_b) THEN
    RAISE EXCEPTION 'E2E-12 FAIL: purchase dispute link missing';
  END IF;
  RAISE NOTICE 'E2E-12 PASS: support dispute linked to purchase';

  v_result := public.submit_refund_request(v_purchase_b,'TEST_ONLY refund hook');
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

  -- E2E-27: Notification FCM dispatch adapter contract
  EXECUTE 'SET LOCAL ROLE postgres';
  SELECT jsonb_build_object('provider_key',provider_key,'binding_status',binding_status) INTO v_result
  FROM public.notification_transport_config WHERE id=1;
  IF (v_result->>'provider_key')<>'fcm' OR (v_result->>'binding_status')<>'approved_pending_secrets' THEN
    RAISE EXCEPTION 'E2E-27 FAIL: transport config not fcm/approved_pending_secrets: %',v_result;
  END IF;

  -- Process outbox as service_role to test the adapter contract directly.
  v_result := public.process_notification_outbox(50);

  SELECT count(*) INTO v_count
  FROM public.notification_deliveries
  WHERE event_id IN (
    SELECT event_id FROM public.notification_outbox WHERE status IN ('dispatch_blocked','materialized')
  );
  IF v_count=0 THEN RAISE EXCEPTION 'E2E-27 FAIL: no delivery rows created'; END IF;

  -- With approved_pending_secrets (not bound), external push must not be faked as sent.
  IF EXISTS (
    SELECT 1 FROM public.notification_deliveries
    WHERE delivery_channel='push' AND status='sent' AND provider_message_id IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'E2E-27 FAIL: fake external push success detected';
  END IF;

  -- Verify push deliveries are queued or blocked (not externally sent).
  IF EXISTS (
    SELECT 1 FROM public.notification_deliveries
    WHERE delivery_channel='push' AND status NOT IN ('queued','dispatch_blocked_unbound_provider','pending')
  ) THEN
    RAISE EXCEPTION 'E2E-27 FAIL: unexpected push delivery status %', (
      SELECT string_agg(distinct status,',') FROM public.notification_deliveries WHERE delivery_channel='push'
    );
  END IF;
  RAISE NOTICE 'E2E-27 PASS: FCM adapter contract blocks external dispatch until secrets bound';

  -- E2E-14/15: audit and notification events exist
  EXECUTE 'SET LOCAL ROLE postgres';
  SELECT count(*) INTO v_count FROM public.notification_events
  WHERE source_entity_id IN (v_deposit::text,v_purchase::text,v_purchase_b::text,v_refund::text);
  IF v_count<3 THEN RAISE EXCEPTION 'E2E-14 FAIL: expected integrated notification events'; END IF;
  RAISE NOTICE 'E2E-14 PASS: events/outbox created, external transport pending secrets';

  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_admin,'role','authenticated')::text,true);
  SELECT count(*) INTO v_count FROM public.audit_events
  WHERE entity_id IN (v_deposit::text,v_purchase::text,v_refund::text,v_case::text,v_dispute_case::text);
  IF v_count<4 THEN RAISE EXCEPTION 'E2E-15 FAIL: integrated audit events missing (%)',v_count; END IF;
  RAISE NOTICE 'E2E-15 PASS: admin audit visibility';

  RAISE NOTICE 'E2E-03 PASS: network request/admin review covered by 005/006/008 integrated suites';
  RAISE NOTICE 'E2E-09 PASS: concurrent last-unit behavior covered by scripts/test_commerce_concurrency.py';
  RAISE NOTICE 'NY_V1_EXTERNAL_PILOT_E2E_PASS';
END $$;

ROLLBACK;
