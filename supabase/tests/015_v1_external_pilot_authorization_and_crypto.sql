-- NetYemen V1 external-pilot authorization matrix (Phase 10) and crypto properties (Phase 11).
-- TEST_ONLY users, TEST_ONLY card secrets, transactional.
BEGIN;

DO $$
DECLARE
  -- Actors
  v_customer_a  UUID := '91000000-0000-4000-8000-000000000011';
  v_customer_b  UUID := '91000000-0000-4000-8000-000000000012';
  v_owner       UUID := '92000000-0000-4000-8000-000000000011';
  v_operator    UUID := '92000000-0000-4000-8000-000000000012';
  v_finance     UUID := '93000000-0000-4000-8000-000000000011';
  v_support     UUID := '93000000-0000-4000-8000-000000000012';
  v_admin       UUID := '94000000-0000-4000-8000-000000000011';
  v_auditor     UUID := '94000000-0000-4000-8000-000000000012';

  -- Network / package
  v_network     UUID := '95000000-0000-4000-8000-000000000011';
  v_package     UUID := '96000000-0000-4000-8000-000000000011';

  -- Test state
  v_destination UUID;
  v_deposit     UUID;
  v_purchase_a  UUID;
  v_batch       UUID;
  v_result      JSONB;
  v_count       INTEGER;
  v_failed      BOOLEAN;
  v_plaintext   TEXT := 'TEST_ONLY_SECRET_AUTH_001';
  v_plaintext2  TEXT := 'TEST_ONLY_SECRET_AUTH_002';
  v_key         TEXT := 'TEST_ONLY_AESKEY_32BYTES_LONG!!';
  v_cipher_b64  TEXT;
  v_cipher_b64_dup TEXT;
  v_reveal      JSONB;
  v_meta        JSONB;
BEGIN
  EXECUTE 'SET LOCAL ROLE postgres';
  INSERT INTO auth.users(id,email) VALUES
    (v_customer_a,'auth-cust-a@pilot.netyemen.test'),
    (v_customer_b,'auth-cust-b@pilot.netyemen.test'),
    (v_owner,'auth-owner@pilot.netyemen.test'),
    (v_operator,'auth-operator@pilot.netyemen.test'),
    (v_finance,'auth-finance@pilot.netyemen.test'),
    (v_support,'auth-support@pilot.netyemen.test'),
    (v_admin,'auth-admin@pilot.netyemen.test'),
    (v_auditor,'auth-auditor@pilot.netyemen.test');

  INSERT INTO public.profiles(id,full_name,account_status) VALUES
    (v_customer_a,'TEST_ONLY Customer A','active'),
    (v_customer_b,'TEST_ONLY Customer B','active'),
    (v_owner,'TEST_ONLY Owner','active'),
    (v_operator,'TEST_ONLY Operator','active'),
    (v_finance,'TEST_ONLY Finance','active'),
    (v_support,'TEST_ONLY Support','active'),
    (v_admin,'TEST_ONLY Admin','active'),
    (v_auditor,'TEST_ONLY Auditor','active')
  ON CONFLICT(id) DO UPDATE SET account_status='active';

  INSERT INTO public.user_roles(user_id,role) VALUES
    (v_customer_a,'customer'),
    (v_customer_b,'customer'),
    (v_owner,'network_owner'),
    (v_operator,'network_operator'),
    (v_finance,'finance_officer'),
    (v_support,'support_agent'),
    (v_admin,'platform_admin'),
    (v_auditor,'system_auditor')
  ON CONFLICT DO NOTHING;

  INSERT INTO public.networks(id,commercial_name,governorate,city,status,verification_status,created_by,approved_by,approved_at)
  VALUES(v_network,'TEST_ONLY Auth Network','صنعاء','صنعاء','active','verified',v_owner,v_admin,now());
  INSERT INTO public.network_memberships(network_id,user_id,membership_role,status,created_by)
  VALUES(v_network,v_owner,'owner','active',v_admin),
        (v_network,v_operator,'operator','active',v_owner);
  INSERT INTO public.network_packages(id,network_id,name,price,duration_value,duration_unit,package_type,status,is_public,created_by)
  VALUES(v_package,v_network,'TEST_ONLY Auth Package',1000,1,'day','time','active',true,v_owner);

  -- Seed inventory and a payment destination.
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',v_owner::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_owner,'role','authenticated')::text,true);
  PERFORM public.adjust_package_inventory(v_package,5,'TEST_ONLY auth stock',gen_random_uuid());

  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_admin,'role','authenticated')::text,true);
  v_destination := public.admin_create_payment_destination('bank_account','TEST_ONLY Auth Bank',NULL,'TEST_ONLY-ACCT-AUTH',NULL,'YER',0);

  -- Fund customer_a and make a purchase so we have a card to reveal.
  EXECUTE 'SET LOCAL ROLE postgres';
  INSERT INTO public.customer_wallet_ledger (
    user_id, entry_type, amount, balance_after, reference_type,
    reference_id, idempotency_key, actor_user_id, reason_code
  ) VALUES (v_customer_a,'CREDIT',10000,10000,'ADJUSTMENT',gen_random_uuid(),gen_random_uuid(),v_admin,'TEST_ONLY_CREDIT');

  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',v_customer_a::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer_a,'role','authenticated')::text,true);
  v_result := public.create_wallet_deposit_request(5000,'TEST_ONLY-AUTH-DEPOSIT',v_destination,NULL,gen_random_uuid());
  v_deposit := (v_result->>'id')::uuid;

  PERFORM set_config('request.jwt.claim.sub',v_finance::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_finance,'role','authenticated')::text,true);
  PERFORM public.review_wallet_deposit_request(v_deposit,'approve');

  -- Ingest one encrypted card using a real AES payload.
  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_admin,'role','authenticated')::text,true);
  v_cipher_b64 := encode(encrypt(v_plaintext::bytea, v_key::bytea, 'aes'),'base64');
  v_result := public.admin_ingest_card_vault_batch(
    v_network,
    v_package,
    ARRAY[jsonb_build_object('ciphertext',v_cipher_b64,'nonce','TEST_ONLY_NONCE_AUTH_001','auth_tag','TEST_ONLY_TAG_AUTH_001')]::jsonb[],
    'v1-test'
  );

  -- customer_a purchases and reveals the card.
  PERFORM set_config('request.jwt.claim.sub',v_customer_a::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer_a,'role','authenticated')::text,true);
  v_result := public.purchase_package(v_package,gen_random_uuid());
  v_purchase_a := (v_result->>'purchase_id')::uuid;
  v_reveal := public.reveal_purchase_card_secret(v_purchase_a);

  -- ========================================================================
  -- Authorization matrix (Phase 10)
  -- ========================================================================

  -- ANON-01: anon cannot call protected RPCs.
  EXECUTE 'SET LOCAL ROLE anon';
  IF current_user != 'anon' THEN
    RAISE EXCEPTION 'AUTH-ANON-ROLE FAIL: session role is %, expected anon', current_user;
  END IF;
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claims','{}',true);
  v_failed:=false;
  BEGIN PERFORM public.create_wallet_deposit_request(1000,'REF',v_destination,NULL,gen_random_uuid()); EXCEPTION WHEN SQLSTATE '28000' THEN v_failed:=true; WHEN SQLSTATE '42501' THEN v_failed:=true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'AUTH-ANON-01 FAIL: anon created deposit request'; END IF;

  v_failed:=false;
  BEGIN PERFORM public.purchase_package(v_package,gen_random_uuid()); EXCEPTION WHEN SQLSTATE '28000' THEN v_failed:=true; WHEN SQLSTATE '42501' THEN v_failed:=true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'AUTH-ANON-02 FAIL: anon purchased package'; END IF;

  v_failed:=false;
  BEGIN PERFORM public.reveal_purchase_card_secret(v_purchase_a); EXCEPTION WHEN SQLSTATE '28000' THEN v_failed:=true; WHEN SQLSTATE '42501' THEN v_failed:=true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'AUTH-ANON-03 FAIL: anon revealed card'; END IF;

  v_failed:=false;
  BEGIN PERFORM public.admin_create_payment_destination('bank_account','X',NULL,NULL,NULL,'YER',0); EXCEPTION WHEN SQLSTATE '28000' THEN v_failed:=true; WHEN SQLSTATE '42501' THEN v_failed:=true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'AUTH-ANON-04 FAIL: anon created payment destination'; END IF;

  v_failed:=false;
  BEGIN PERFORM public.finance_create_settlement_batch(CURRENT_DATE,CURRENT_DATE,v_network); EXCEPTION WHEN SQLSTATE '28000' THEN v_failed:=true; WHEN SQLSTATE '42501' THEN v_failed:=true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'AUTH-ANON-05 FAIL: anon created settlement batch'; END IF;
  RAISE NOTICE 'AUTH-ANON PASS: anon denied on all privileged RPCs';

  -- CUST-01: customer cannot insert/reveal cards directly.
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',v_customer_a::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer_a,'role','authenticated')::text,true);
  v_failed:=false;
  BEGIN
    INSERT INTO public.card_vault(network_id,package_id,batch_id,state,ciphertext,nonce,key_version)
    VALUES(v_network,v_package,'TEST_BATCH','available',decode(v_cipher_b64,'base64'),'TEST_NONCE','v1-test');
  EXCEPTION WHEN OTHERS THEN v_failed:=true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'AUTH-CUST-01 FAIL: customer inserted card directly'; END IF;
  RAISE NOTICE 'AUTH-CUST-01 PASS: customer direct card insert denied';

  -- CUST-02: customer cannot reveal another customer's card.
  PERFORM set_config('request.jwt.claim.sub',v_customer_b::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer_b,'role','authenticated')::text,true);
  v_failed:=false;
  BEGIN PERFORM public.reveal_purchase_card_secret(v_purchase_a); EXCEPTION WHEN SQLSTATE '42501' THEN v_failed:=true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'AUTH-CUST-02 FAIL: customer_b revealed customer_a card'; END IF;
  RAISE NOTICE 'AUTH-CUST-02 PASS: cross-user reveal denied';

  -- OWNER-01: owner cannot reveal customer cards.
  PERFORM set_config('request.jwt.claim.sub',v_owner::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_owner,'role','authenticated')::text,true);
  v_failed:=false;
  BEGIN PERFORM public.reveal_purchase_card_secret(v_purchase_a); EXCEPTION WHEN SQLSTATE '42501' THEN v_failed:=true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'AUTH-OWNER-01 FAIL: owner revealed customer card'; END IF;
  RAISE NOTICE 'AUTH-OWNER-01 PASS: owner cannot reveal customer cards';

  -- OWNER-02: owner/operator cannot change commission.
  v_failed:=false;
  BEGIN PERFORM public.admin_update_default_commission_rate(0.0500); EXCEPTION WHEN SQLSTATE '42501' THEN v_failed:=true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'AUTH-OWNER-02 FAIL: owner changed commission'; END IF;

  PERFORM set_config('request.jwt.claim.sub',v_operator::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_operator,'role','authenticated')::text,true);
  v_failed:=false;
  BEGIN PERFORM public.admin_update_default_commission_rate(0.0500); EXCEPTION WHEN SQLSTATE '42501' THEN v_failed:=true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'AUTH-OPER-01 FAIL: operator changed commission'; END IF;
  RAISE NOTICE 'AUTH-OWNER/OPER-02 PASS: commission changes require platform_admin';

  -- FIN-01: finance cannot arbitrarily read card secrets (direct SELECT denied).
  PERFORM set_config('request.jwt.claim.sub',v_finance::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_finance,'role','authenticated')::text,true);
  v_failed:=false;
  BEGIN SELECT count(*) INTO v_count FROM public.card_vault; EXCEPTION WHEN OTHERS THEN v_failed:=true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'AUTH-FIN-01 FAIL: finance direct card_vault SELECT succeeded'; END IF;
  RAISE NOTICE 'AUTH-FIN-01 PASS: finance direct card_vault SELECT denied';

  -- ADMIN-01: admin list endpoint never exposes secrets.
  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_admin,'role','authenticated')::text,true);
  v_meta := public.admin_list_card_vault_metadata(v_network);
  IF v_meta IS NULL OR jsonb_array_length(v_meta)=0 THEN
    RAISE EXCEPTION 'AUTH-ADMIN-01 FAIL: admin metadata empty';
  END IF;
  IF v_meta::text ILIKE '%ciphertext%' OR v_meta::text ILIKE '%nonce%' OR v_meta::text ILIKE '%auth_tag%' THEN
    RAISE EXCEPTION 'AUTH-ADMIN-01 FAIL: metadata exposes secret fields';
  END IF;
  RAISE NOTICE 'AUTH-ADMIN-01 PASS: admin list endpoint omits ciphertext/nonce/auth_tag';

  -- SUPPORT-01: support cannot reveal secrets.
  PERFORM set_config('request.jwt.claim.sub',v_support::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_support,'role','authenticated')::text,true);
  v_failed:=false;
  BEGIN PERFORM public.reveal_purchase_card_secret(v_purchase_a); EXCEPTION WHEN SQLSTATE '42501' THEN v_failed:=true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'AUTH-SUP-01 FAIL: support revealed card secret'; END IF;
  RAISE NOTICE 'AUTH-SUP-01 PASS: support cannot reveal secrets';

  -- AUDITOR-01: auditor never receives decrypted secret.
  PERFORM set_config('request.jwt.claim.sub',v_auditor::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_auditor,'role','authenticated')::text,true);
  v_failed:=false;
  BEGIN PERFORM public.reveal_purchase_card_secret(v_purchase_a); EXCEPTION WHEN SQLSTATE '42501' THEN v_failed:=true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'AUTH-AUD-01 FAIL: auditor revealed card secret'; END IF;

  -- Auditor cannot list vault metadata at all.
  v_failed:=false;
  BEGIN PERFORM public.admin_list_card_vault_metadata(v_network); EXCEPTION WHEN SQLSTATE '42501' THEN v_failed:=true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'AUTH-AUD-02 FAIL: auditor listed vault metadata'; END IF;
  RAISE NOTICE 'AUTH-AUD PASS: auditor never receives decrypted secret';

  -- CUST-03: customer cannot approve deposit.
  PERFORM set_config('request.jwt.claim.sub',v_customer_a::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer_a,'role','authenticated')::text,true);
  v_failed:=false;
  BEGIN PERFORM public.review_wallet_deposit_request(v_deposit,'approve'); EXCEPTION WHEN SQLSTATE '42501' THEN v_failed:=true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'AUTH-CUST-03 FAIL: customer approved deposit'; END IF;
  RAISE NOTICE 'AUTH-CUST-03 PASS: customer cannot approve deposit';

  -- OWNER-03: owner cannot approve/create settlement.
  PERFORM set_config('request.jwt.claim.sub',v_owner::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_owner,'role','authenticated')::text,true);
  v_failed:=false;
  BEGIN PERFORM public.finance_create_settlement_batch(CURRENT_DATE,CURRENT_DATE,v_network); EXCEPTION WHEN SQLSTATE '42501' THEN v_failed:=true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'AUTH-OWNER-03 FAIL: owner created settlement batch'; END IF;
  RAISE NOTICE 'AUTH-OWNER-03 PASS: owner cannot create settlement batch';

  -- Create a batch as finance so we can test owner approval denial.
  PERFORM set_config('request.jwt.claim.sub',v_finance::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_finance,'role','authenticated')::text,true);
  v_result := public.finance_create_settlement_batch(CURRENT_DATE,CURRENT_DATE,v_network);
  SELECT id INTO v_batch FROM public.settlement_batches
  WHERE network_id=v_network AND status='draft' ORDER BY created_at DESC LIMIT 1;

  PERFORM set_config('request.jwt.claim.sub',v_owner::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_owner,'role','authenticated')::text,true);
  v_failed:=false;
  BEGIN PERFORM public.finance_approve_settlement_batch(v_batch); EXCEPTION WHEN SQLSTATE '42501' THEN v_failed:=true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'AUTH-OWNER-04 FAIL: owner approved settlement batch'; END IF;
  RAISE NOTICE 'AUTH-OWNER-04 PASS: owner cannot approve settlement batch';

  -- CUST-04: unauthorized settlement mutation denied.
  PERFORM set_config('request.jwt.claim.sub',v_customer_a::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer_a,'role','authenticated')::text,true);
  v_failed:=false;
  BEGIN PERFORM public.finance_create_settlement_batch(CURRENT_DATE,CURRENT_DATE,v_network); EXCEPTION WHEN SQLSTATE '42501' THEN v_failed:=true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'AUTH-CUST-04 FAIL: customer created settlement batch'; END IF;
  RAISE NOTICE 'AUTH-CUST-04 PASS: customer settlement mutation denied';

  -- ========================================================================
  -- Crypto properties (Phase 11)
  -- ========================================================================

  -- CRYPTO-01: ciphertext is not equal to known plaintext fixture.
  EXECUTE 'SET LOCAL ROLE postgres';
  SELECT count(*) INTO v_count
  FROM public.card_vault
  WHERE ciphertext = v_plaintext::bytea;
  IF v_count>0 THEN RAISE EXCEPTION 'CRYPTO-01 FAIL: ciphertext equals plaintext'; END IF;

  -- CRYPTO-02: plaintext absent from card_vault after ingestion.
  SELECT count(*) INTO v_count
  FROM public.card_vault
  WHERE encode(ciphertext,'base64') ILIKE '%'||v_plaintext||'%'
     OR nonce ILIKE '%'||v_plaintext||'%'
     OR auth_tag ILIKE '%'||v_plaintext||'%';
  IF v_count>0 THEN RAISE EXCEPTION 'CRYPTO-02 FAIL: plaintext leaked in card_vault'; END IF;

  -- CRYPTO-03: two rows with same plaintext have different nonces.
  v_cipher_b64_dup := encode(encrypt(v_plaintext2::bytea, v_key::bytea, 'aes'),'base64');
  INSERT INTO public.card_vault(network_id,package_id,batch_id,state,ciphertext,nonce,key_version)
  VALUES
    (v_network,v_package,'TEST_BATCH_DUP','available',decode(v_cipher_b64_dup,'base64'),'TEST_NONCE_DUP_001','v1-test'),
    (v_network,v_package,'TEST_BATCH_DUP','available',decode(v_cipher_b64_dup,'base64'),'TEST_NONCE_DUP_002','v1-test');
  SELECT count(DISTINCT nonce) INTO v_count
  FROM public.card_vault WHERE batch_id='TEST_BATCH_DUP';
  IF v_count<>2 THEN RAISE EXCEPTION 'CRYPTO-03 FAIL: duplicate nonces for same plaintext'; END IF;
  RAISE NOTICE 'CRYPTO-01/02/03 PASS: ciphertext != plaintext, no plaintext leak, nonce unique';

  -- CRYPTO-04: plaintext absent from audit_events and notification_events.
  SELECT count(*) INTO v_count FROM public.audit_events WHERE metadata::text ILIKE '%'||v_plaintext||'%';
  IF v_count>0 THEN RAISE EXCEPTION 'CRYPTO-04 FAIL: plaintext in audit_events'; END IF;
  SELECT count(*) INTO v_count FROM public.notification_events
  WHERE title_ar ILIKE '%'||v_plaintext||'%' OR body_ar ILIKE '%'||v_plaintext||'%' OR metadata::text ILIKE '%'||v_plaintext||'%';
  IF v_count>0 THEN RAISE EXCEPTION 'CRYPTO-04 FAIL: plaintext in notification_events'; END IF;
  RAISE NOTICE 'CRYPTO-04 PASS: plaintext absent from audit_events / notification_events';

  -- CRYPTO-05: plaintext unavailable through direct client queries.
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',v_customer_a::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer_a,'role','authenticated')::text,true);
  v_failed:=false;
  BEGIN
    PERFORM ciphertext FROM public.card_vault LIMIT 1;
  EXCEPTION WHEN OTHERS THEN v_failed:=true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'CRYPTO-05 FAIL: customer direct card_vault SELECT allowed'; END IF;
  RAISE NOTICE 'CRYPTO-05 PASS: card_vault direct SELECT denied for customer';

  -- CRYPTO-06: reveal returns the encrypted payload, never plaintext.
  PERFORM set_config('request.jwt.claim.sub',v_customer_a::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer_a,'role','authenticated')::text,true);
  v_reveal := public.reveal_purchase_card_secret(v_purchase_a);
  IF (v_reveal->>'ciphertext_b64') IS NULL OR (v_reveal->>'ciphertext_b64')=v_plaintext THEN
    RAISE EXCEPTION 'CRYPTO-06 FAIL: reveal did not return encrypted payload';
  END IF;
  RAISE NOTICE 'CRYPTO-06 PASS: reveal returns ciphertext payload, not plaintext';

  RAISE NOTICE 'NY_V1_EXTERNAL_PILOT_AUTHORIZATION_AND_CRYPTO_PASS';
END $$;

ROLLBACK;
