-- Purchase, card ingest and commission configuration integrity (TEST_ONLY, transactional).
-- Verifies 20261008091000_purchase_card_ingest_commission_integrity.sql.
BEGIN;

DO $$
DECLARE
  v_customer   UUID := 'a2700000-0000-4000-8000-000000000001';
  v_owner      UUID := 'a2700000-0000-4000-8000-000000000002';
  v_finance    UUID := 'a2700000-0000-4000-8000-000000000003';
  v_admin      UUID := 'a2700000-0000-4000-8000-000000000004';
  v_network    UUID := 'a2700000-0000-4000-8000-000000000010';
  v_package    UUID := 'a2700000-0000-4000-8000-000000000011';
  v_package_b  UUID := 'a2700000-0000-4000-8000-000000000012';
  v_key        UUID := 'a2700000-0000-4000-8000-000000000020';
  v_batch_key  UUID := 'a2700000-0000-4000-8000-000000000021';
  v_destination UUID;
  v_result     JSONB;
  v_replay     JSONB;
  v_count      INTEGER;
  v_balance    INTEGER;
  v_msg        TEXT;
BEGIN
  EXECUTE 'SET LOCAL ROLE postgres';
  INSERT INTO auth.users(id,email) VALUES
    (v_customer,'s27-customer@pilot.netyemen.test'),
    (v_owner,'s27-owner@pilot.netyemen.test'),
    (v_finance,'s27-finance@pilot.netyemen.test'),
    (v_admin,'s27-admin@pilot.netyemen.test');

    -- Server-side PIN enforcement (20261009090000): every fixture user has a
    -- PIN verified in the current (claim-less) test session.
    INSERT INTO public.account_pins (user_id, pin_hash)
    SELECT id, 'fixture-not-a-real-hash' FROM auth.users
    ON CONFLICT (user_id) DO NOTHING;
    INSERT INTO public.account_pin_verifications (user_id, session_key)
    SELECT id, '' FROM auth.users
    ON CONFLICT (user_id, session_key) DO UPDATE SET verified_at = now();
  INSERT INTO public.profiles(id,full_name,account_status) VALUES
    (v_customer,'TEST_ONLY S27 Customer','active'),
    (v_owner,'TEST_ONLY S27 Owner','active'),
    (v_finance,'TEST_ONLY S27 Finance','active'),
    (v_admin,'TEST_ONLY S27 Admin','active')
  ON CONFLICT(id) DO UPDATE SET account_status='active';
  INSERT INTO public.user_roles(user_id,role) VALUES
    (v_customer,'customer'),(v_owner,'network_owner'),
    (v_finance,'finance_officer'),(v_admin,'platform_admin')
  ON CONFLICT DO NOTHING;

  INSERT INTO public.networks(id,commercial_name,governorate,city,status,verification_status,created_by,approved_by,approved_at)
  VALUES(v_network,'TEST_ONLY S27 Network','صنعاء','صنعاء','active','verified',v_owner,v_admin,now());
  INSERT INTO public.network_memberships(network_id,user_id,membership_role,status,created_by)
  VALUES(v_network,v_owner,'owner','active',v_admin);
  INSERT INTO public.network_packages(id,network_id,name,price,duration_value,duration_unit,package_type,status,is_public,created_by)
  VALUES
    (v_package,v_network,'TEST_ONLY S27 Package',1000,1,'day','time','active',true,v_owner),
    (v_package_b,v_network,'TEST_ONLY S27 Package B',500,1,'day','time','active',true,v_owner);

  -- Wallet with 3000 YER through the ledger (the trigger maintains the cache).
  INSERT INTO public.customer_wallet_ledger(user_id,entry_type,amount,balance_after,reference_type,reference_id,idempotency_key,actor_user_id,reason_code)
  VALUES(v_customer,'CREDIT',3000,3000,'DEPOSIT',gen_random_uuid(),gen_random_uuid(),v_admin,'TEST_ONLY');

  -- ---------------------------------------------------------------- cards
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',v_owner::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_owner,'role','authenticated')::text,true);
  PERFORM public.adjust_package_inventory(v_package,5,'TEST_ONLY S27 stock',gen_random_uuid());
  PERFORM public.adjust_package_inventory(v_package_b,5,'TEST_ONLY S27 stock B',gen_random_uuid());

  v_result := public.admin_ingest_card_vault_batch(
    v_network, v_package,
    ARRAY[jsonb_build_object('pin','S27CARD0001'),
          jsonb_build_object('pin','S27CARD0002'),
          jsonb_build_object('pin','  S27CARD0002  '),
          jsonb_build_object('pin','S27CARD0003')]::jsonb[],
    v_batch_key);
  IF (v_result->>'ingested_count')::int <> 3 OR (v_result->>'duplicates_skipped')::int <> 1
     OR (v_result->>'replayed')::boolean THEN
    RAISE EXCEPTION 'S27-01 FAIL: unexpected first ingest result %', v_result;
  END IF;

  -- A retried upload with the same batch key stores nothing new.
  v_replay := public.admin_ingest_card_vault_batch(
    v_network, v_package,
    ARRAY[jsonb_build_object('pin','S27CARD0001'),
          jsonb_build_object('pin','S27CARD0002'),
          jsonb_build_object('pin','S27CARD0003')]::jsonb[],
    v_batch_key);
  IF NOT (v_replay->>'replayed')::boolean OR v_replay->>'batch_id' <> v_result->>'batch_id'
     OR (v_replay->>'ingested_count')::int <> 3 THEN
    RAISE EXCEPTION 'S27-01 FAIL: retry was not replayed %', v_replay;
  END IF;

  -- The same card in a NEW batch (no key, or another package) is still refused.
  v_result := public.admin_ingest_card_vault_batch(
    v_network, v_package_b,
    ARRAY[jsonb_build_object('pin','S27CARD0001'),
          jsonb_build_object('pin','S27CARD0004'),
          jsonb_build_object('pin','S27CARD0005')]::jsonb[]);
  IF (v_result->>'ingested_count')::int <> 2 OR (v_result->>'duplicates_skipped')::int <> 1 THEN
    RAISE EXCEPTION 'S27-01 FAIL: duplicate card accepted in a later batch %', v_result;
  END IF;

  EXECUTE 'SET LOCAL ROLE postgres';
  SELECT count(*) INTO v_count FROM public.card_vault WHERE network_id = v_network;
  IF v_count <> 5 THEN RAISE EXCEPTION 'S27-01 FAIL: % cards stored, expected 5', v_count; END IF;
  SELECT count(*) INTO v_count FROM public.card_vault WHERE network_id = v_network AND pin_fingerprint IS NULL;
  IF v_count <> 0 THEN RAISE EXCEPTION 'S27-01 FAIL: % cards without fingerprint', v_count; END IF;
  RAISE NOTICE 'S27-01 PASS: card upload is idempotent and a card is never stored twice';

  EXECUTE 'SET LOCAL ROLE authenticated';
  BEGIN
    PERFORM public.admin_ingest_card_vault_batch(v_network, v_package, ARRAY[jsonb_build_object('pin','BAD PIN')]::jsonb[]);
    RAISE EXCEPTION 'S27-02 FAIL: PIN with whitespace accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'INVALID_CARD%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.admin_ingest_card_vault_batch(v_network, v_package, ARRAY[jsonb_build_object('pin',repeat('9',65))]::jsonb[]);
    RAISE EXCEPTION 'S27-02 FAIL: 65 character PIN accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'INVALID_CARD%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.admin_ingest_card_vault_batch(
      v_network, v_package,
      ARRAY(SELECT jsonb_build_object('pin','S27BULK'||g) FROM generate_series(1,5001) g)::jsonb[]);
    RAISE EXCEPTION 'S27-02 FAIL: 5001 cards accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'TOO_MANY_CARDS%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.admin_ingest_card_vault_batch(
      v_network, v_package_b, ARRAY[jsonb_build_object('pin','S27CARD0009')]::jsonb[], v_batch_key);
    RAISE EXCEPTION 'S27-02 FAIL: batch key reused for another package';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'BATCH_KEY_REUSED%' THEN RAISE; END IF;
  END;
  PERFORM set_config('request.jwt.claim.sub',v_customer::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer,'role','authenticated')::text,true);
  BEGIN
    PERFORM public.admin_ingest_card_vault_batch(v_network, v_package, ARRAY[jsonb_build_object('pin','S27CARD0010')]::jsonb[]);
    RAISE EXCEPTION 'S27-02 FAIL: customer ingested cards';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'FORBIDDEN_ROLE%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM 1 FROM public.card_vault_ingest_batches LIMIT 1;
    RAISE EXCEPTION 'S27-02 FAIL: client read card_vault_ingest_batches';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RAISE NOTICE 'S27-02 PASS: card validation, batch size, key reuse and role checks';

  -- -------------------------------------------------------------- purchase
  BEGIN
    PERFORM public.purchase_package(v_package, gen_random_uuid(), 900);
    RAISE EXCEPTION 'S27-03 FAIL: purchase charged a price the customer did not confirm';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'PRICE_CHANGED%' THEN RAISE; END IF;
  END;
  SELECT cached_balance INTO v_balance FROM public.wallet_accounts WHERE user_id = v_customer;
  IF v_balance <> 3000 THEN RAISE EXCEPTION 'S27-03 FAIL: balance changed to % on a refused purchase', v_balance; END IF;

  v_result := public.purchase_package(v_package, v_key, 1000);
  IF (v_result->>'amount_paid')::int <> 1000 THEN RAISE EXCEPTION 'S27-03 FAIL: %', v_result; END IF;
  v_replay := public.purchase_package(v_package, v_key, 1000);
  IF NOT (v_replay->>'replayed')::boolean OR v_replay->>'purchase_id' <> v_result->>'purchase_id' THEN
    RAISE EXCEPTION 'S27-03 FAIL: replay did not return the original purchase %', v_replay;
  END IF;
  -- A replay still answers after the price moved: the purchase already happened.
  EXECUTE 'SET LOCAL ROLE postgres';
  UPDATE public.network_packages SET price = 1200 WHERE id = v_package;
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_replay := public.purchase_package(v_package, v_key, 1000);
  IF NOT (v_replay->>'replayed')::boolean THEN RAISE EXCEPTION 'S27-03 FAIL: replay refused after price change'; END IF;
  BEGIN
    PERFORM public.purchase_package(v_package_b, v_key, 500);
    RAISE EXCEPTION 'S27-03 FAIL: idempotency key reused for another package';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'IDEMPOTENCY_KEY_REUSED%' THEN RAISE; END IF;
  END;
  -- Old two-argument call shape still works (no expected price).
  v_result := public.purchase_package(v_package_b, gen_random_uuid());
  IF (v_result->>'amount_paid')::int <> 500 THEN RAISE EXCEPTION 'S27-03 FAIL: %', v_result; END IF;
  SELECT cached_balance INTO v_balance FROM public.wallet_accounts WHERE user_id = v_customer;
  IF v_balance <> 1500 THEN RAISE EXCEPTION 'S27-03 FAIL: balance %, expected 1500', v_balance; END IF;
  RAISE NOTICE 'S27-03 PASS: expected price is enforced and idempotency keys are bound to one package';

  -- ---------------------------------------------------------- frozen wallet
  BEGIN
    PERFORM public.admin_set_wallet_status(v_customer, 'frozen', 'TEST_ONLY self service');
    RAISE EXCEPTION 'S27-04 FAIL: customer froze a wallet';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'FORBIDDEN_ROLE%' THEN RAISE; END IF;
  END;
  PERFORM set_config('request.jwt.claim.sub',v_finance::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_finance,'role','authenticated')::text,true);
  BEGIN
    PERFORM public.admin_set_wallet_status(v_customer, 'frozen', '  ');
    RAISE EXCEPTION 'S27-04 FAIL: wallet frozen without a reason';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'REASON_REQUIRED%' THEN RAISE; END IF;
  END;
  PERFORM public.admin_set_wallet_status(v_customer, 'frozen', 'TEST_ONLY suspected fraud');
  PERFORM set_config('request.jwt.claim.sub',v_customer::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer,'role','authenticated')::text,true);
  BEGIN
    PERFORM public.purchase_package(v_package_b, gen_random_uuid(), 500);
    RAISE EXCEPTION 'S27-04 FAIL: frozen wallet was debited';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'WALLET_FROZEN%' THEN RAISE; END IF;
  END;
  PERFORM set_config('request.jwt.claim.sub',v_finance::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_finance,'role','authenticated')::text,true);
  PERFORM public.admin_set_wallet_status(v_customer, 'active', 'TEST_ONLY cleared');
  PERFORM set_config('request.jwt.claim.sub',v_customer::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer,'role','authenticated')::text,true);
  PERFORM public.purchase_package(v_package_b, gen_random_uuid(), 500);
  RAISE NOTICE 'S27-04 PASS: a frozen wallet cannot be debited; freeze is finance-only and audited';

  -- ------------------------------------------------- commission and audit
  BEGIN
    PERFORM public.get_platform_commission_config();
    RAISE EXCEPTION 'S27-05 FAIL: customer read the commission configuration';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'FORBIDDEN_ROLE%' THEN RAISE; END IF;
  END;
  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_admin,'role','authenticated')::text,true);
  PERFORM public.admin_update_default_commission_rate(0.05);
  v_result := public.get_platform_commission_config();
  IF (v_result->>'default_rate')::numeric <> 0.05 THEN
    RAISE EXCEPTION 'S27-05 FAIL: commission config read back %', v_result;
  END IF;
  BEGIN
    PERFORM public.admin_update_default_commission_rate(5);
    RAISE EXCEPTION 'S27-05 FAIL: a percentage (5) was accepted as a rate';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'INVALID_RATE%' THEN RAISE; END IF;
  END;

  v_destination := public.admin_create_payment_destination(
    'bank_account','TEST_ONLY S27 Bank','TEST_ONLY Holder','TEST_ONLY-S27-ACCT-A','TEST_ONLY','YER',0);
  PERFORM public.admin_update_payment_destination(
    v_destination, NULL, NULL, NULL, 'TEST_ONLY-S27-ACCT-B', NULL, NULL, NULL);

  EXECUTE 'SET LOCAL ROLE postgres';
  IF NOT EXISTS (
    SELECT 1 FROM public.audit_events
    WHERE action = 'PLATFORM_COMMISSION_CONFIG_UPDATE' AND actor_user_id = v_admin
      AND (metadata->'after'->>'default_rate')::numeric = 0.05
  ) THEN RAISE EXCEPTION 'S27-05 FAIL: commission change was not audited'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.audit_events
    WHERE action = 'PAYMENT_DESTINATIONS_UPDATE' AND entity_id = v_destination::text AND actor_user_id = v_admin
      AND metadata->'before'->>'account_identifier' = 'TEST_ONLY-S27-ACCT-A'
      AND metadata->'after'->>'account_identifier' = 'TEST_ONLY-S27-ACCT-B'
  ) THEN RAISE EXCEPTION 'S27-05 FAIL: payment destination change was not audited with before/after'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.audit_events WHERE action = 'PAYMENT_DESTINATIONS_INSERT' AND entity_id = v_destination::text) THEN
    RAISE EXCEPTION 'S27-05 FAIL: payment destination creation was not audited';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.audit_events WHERE action = 'ADMIN_SET_WALLET_STATUS' AND entity_id = v_customer::text) THEN
    RAISE EXCEPTION 'S27-05 FAIL: wallet freeze was not audited';
  END IF;
  IF EXISTS (SELECT 1 FROM public.audit_events WHERE metadata::text LIKE '%S27CARD%') THEN
    RAISE EXCEPTION 'S27-05 FAIL: a card PIN reached the audit log';
  END IF;
  RAISE NOTICE 'S27-05 PASS: commission is a fraction, readable by staff only, and money-routing changes are audited';

  RAISE NOTICE 'NY_PURCHASE_CARD_INGEST_INTEGRITY_PASS';
END $$;

ROLLBACK;
