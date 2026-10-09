-- Settlement / refund integrity (TEST_ONLY, transactional).
-- Verifies 20261008090000_settlement_refund_integrity.sql.
BEGIN;

DO $$
DECLARE
  v_customer   UUID := 'a2600000-0000-4000-8000-000000000001';
  v_owner      UUID := 'a2600000-0000-4000-8000-000000000002';
  v_finance    UUID := 'a2600000-0000-4000-8000-000000000003';
  v_finance_b  UUID := 'a2600000-0000-4000-8000-000000000004';
  v_support    UUID := 'a2600000-0000-4000-8000-000000000005';
  v_admin      UUID := 'a2600000-0000-4000-8000-000000000006';
  v_network    UUID := 'a2600000-0000-4000-8000-000000000010';
  v_package    UUID := 'a2600000-0000-4000-8000-000000000011';
  v_destination UUID;
  v_deposit    UUID;
  v_purchases  UUID[] := ARRAY[]::UUID[];
  v_purchase   UUID;
  v_refund     UUID;
  v_batch      UUID;
  v_batch_b    UUID;
  v_batch_c    UUID;
  v_row        public.settlement_batches%ROWTYPE;
  v_result     JSONB;
  v_count      INTEGER;
  v_text       TEXT;
  v_msg        TEXT;
  i            INTEGER;
BEGIN
  EXECUTE 'SET LOCAL ROLE postgres';
  INSERT INTO auth.users(id,email) VALUES
    (v_customer,'s26-customer@pilot.netyemen.test'),
    (v_owner,'s26-owner@pilot.netyemen.test'),
    (v_finance,'s26-finance@pilot.netyemen.test'),
    (v_finance_b,'s26-finance-b@pilot.netyemen.test'),
    (v_support,'s26-support@pilot.netyemen.test'),
    (v_admin,'s26-admin@pilot.netyemen.test');

    -- Server-side PIN enforcement (20261009090000): every fixture user has a
    -- PIN verified in the current (claim-less) test session.
    INSERT INTO public.account_pins (user_id, pin_hash)
    SELECT id, 'fixture-not-a-real-hash' FROM auth.users
    ON CONFLICT (user_id) DO NOTHING;
    INSERT INTO public.account_pin_verifications (user_id, session_key)
    SELECT id, '' FROM auth.users
    ON CONFLICT (user_id, session_key) DO UPDATE SET verified_at = now();
  INSERT INTO public.profiles(id,full_name,account_status) VALUES
    (v_customer,'TEST_ONLY S26 Customer','active'),
    (v_owner,'TEST_ONLY S26 Owner','active'),
    (v_finance,'TEST_ONLY S26 Finance','active'),
    (v_finance_b,'TEST_ONLY S26 Finance B','active'),
    (v_support,'TEST_ONLY S26 Support','active'),
    (v_admin,'TEST_ONLY S26 Admin','active')
  ON CONFLICT(id) DO UPDATE SET account_status='active';
  INSERT INTO public.user_roles(user_id,role) VALUES
    (v_customer,'customer'),(v_owner,'network_owner'),(v_finance,'finance_officer'),
    (v_finance_b,'finance_officer'),(v_support,'support_agent'),(v_admin,'platform_admin')
  ON CONFLICT DO NOTHING;

  UPDATE public.platform_commission_config SET default_rate = 0.03 WHERE id = 1;

  INSERT INTO public.networks(id,commercial_name,governorate,city,status,verification_status,created_by,approved_by,approved_at)
  VALUES(v_network,'TEST_ONLY S26 Network','صنعاء','صنعاء','active','verified',v_owner,v_admin,now());
  INSERT INTO public.network_memberships(network_id,user_id,membership_role,status,created_by)
  VALUES(v_network,v_owner,'owner','active',v_admin);
  INSERT INTO public.network_packages(id,network_id,name,price,duration_value,duration_unit,package_type,status,is_public,created_by)
  VALUES(v_package,v_network,'TEST_ONLY S26 Package',1000,1,'day','time','active',true,v_owner);

  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',v_owner::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_owner,'role','authenticated')::text,true);
  PERFORM public.adjust_package_inventory(v_package,12,'TEST_ONLY S26 stock',gen_random_uuid());
  v_result := public.admin_ingest_card_vault_batch(
    v_network, v_package,
    ARRAY(SELECT jsonb_build_object('pin','TEST_ONLY_S26_CARD_'||g) FROM generate_series(1,12) g)::jsonb[]
  );
  IF (v_result->>'ingested_count')::int <> 12 THEN
    RAISE EXCEPTION 'S26-SETUP FAIL: expected 12 cards, got %', v_result;
  END IF;

  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_admin,'role','authenticated')::text,true);
  v_destination := public.admin_create_payment_destination(
    'bank_account','TEST_ONLY S26 Bank','TEST_ONLY Holder','TEST_ONLY-S26-ACCT','TEST_ONLY','YER',0);
    -- Dual control (20261009091000): destinations are created inactive and a
    -- second staff member approves activation; the fixture activates directly.
    EXECUTE 'SET LOCAL ROLE postgres';
    UPDATE public.payment_destinations SET is_active = TRUE WHERE id = v_destination;
    EXECUTE 'SET LOCAL ROLE authenticated';

  PERFORM set_config('request.jwt.claim.sub',v_customer::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer,'role','authenticated')::text,true);
  v_result := public.create_wallet_deposit_request(20000,'TEST_ONLY-S26-DEP',v_destination,NULL,gen_random_uuid());
  v_deposit := (v_result->>'id')::uuid;

  PERFORM set_config('request.jwt.claim.sub',v_finance::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_finance,'role','authenticated')::text,true);
  PERFORM public.review_wallet_deposit_request(v_deposit,'approve');

  -- Ten sales of 1000 at 3%: each gives the owner 970 and the platform 30.
  PERFORM set_config('request.jwt.claim.sub',v_customer::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer,'role','authenticated')::text,true);
  FOR i IN 1..10 LOOP
    v_result := public.purchase_package(v_package, gen_random_uuid());
    v_purchases := v_purchases || (v_result->>'purchase_id')::uuid;
  END LOOP;

  -- Sale #1 is refunded BEFORE any settlement.
  v_result := public.submit_refund_request(v_purchases[1],'TEST_ONLY refund before settlement');
  v_refund := (v_result->>'id')::uuid;
  PERFORM set_config('request.jwt.claim.sub',v_support::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_support,'role','authenticated')::text,true);
  PERFORM public.review_refund_request(v_refund,'approve');

  EXECUTE 'SET LOCAL ROLE postgres';
  SELECT settlement_status INTO v_text FROM public.owner_settlement_items WHERE purchase_id = v_purchases[1];
  IF v_text <> 'voided' THEN
    RAISE EXCEPTION 'S26-01 FAIL: unsettled refunded sale is %, expected voided', v_text;
  END IF;
  RAISE NOTICE 'S26-01 PASS: a sale refunded before settlement is voided';

  -- First batch: nine sales, no refund deduction.
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',v_finance::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_finance,'role','authenticated')::text,true);
  v_result := public.finance_create_settlement_batch(current_date - 1, current_date + 1, v_network);
  IF (v_result->>'batches_created')::int <> 1 THEN
    RAISE EXCEPTION 'S26-02 FAIL: expected 1 batch, got %', v_result;
  END IF;
  EXECUTE 'SET LOCAL ROLE postgres';
  SELECT * INTO v_row FROM public.settlement_batches WHERE network_id = v_network AND status = 'draft';
  v_batch := v_row.id;
  IF v_row.gross_sales <> 9000 OR v_row.total_commission <> 270
     OR v_row.total_refunds <> 0 OR v_row.net_settlement <> 8730 THEN
    RAISE EXCEPTION 'S26-02 FAIL: batch totals gross=% commission=% refunds=% net=% (expected 9000/270/0/8730)',
      v_row.gross_sales, v_row.total_commission, v_row.total_refunds, v_row.net_settlement;
  END IF;
  SELECT count(*) INTO v_count FROM public.settlement_batch_lines WHERE settlement_batch_id = v_batch AND line_type = 'refund';
  IF v_count <> 0 THEN RAISE EXCEPTION 'S26-02 FAIL: refund line for a never-settled sale'; END IF;
  SELECT count(*) INTO v_count FROM public.settlement_batch_lines WHERE settlement_batch_id = v_batch AND line_type = 'sale';
  IF v_count <> 9 THEN RAISE EXCEPTION 'S26-02 FAIL: % sale lines, expected 9', v_count; END IF;
  RAISE NOTICE 'S26-02 PASS: owner is not charged for a sale that was never credited (net 8730)';

  -- Creator cannot approve; "paid" needs a payment reference.
  EXECUTE 'SET LOCAL ROLE authenticated';
  BEGIN
    PERFORM public.finance_approve_settlement_batch(v_batch);
    RAISE EXCEPTION 'S26-03 FAIL: creator approved own batch';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'FORBIDDEN_SELF_APPROVAL%' THEN RAISE; END IF;
  END;
  PERFORM set_config('request.jwt.claim.sub',v_finance_b::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_finance_b,'role','authenticated')::text,true);
  PERFORM public.finance_approve_settlement_batch(v_batch);
  BEGIN
    PERFORM public.finance_mark_settlement_paid(v_batch, '   ');
    RAISE EXCEPTION 'S26-03 FAIL: batch marked paid without a payment reference';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'PAYMENT_REFERENCE_REQUIRED%' THEN RAISE; END IF;
  END;
  PERFORM public.finance_mark_settlement_paid(v_batch, 'TEST_ONLY-TRANSFER-REF-1');
  RAISE NOTICE 'S26-03 PASS: self-approval blocked and payment reference required';

  -- Sale #2 was paid out to the owner and is refunded afterwards.
  PERFORM set_config('request.jwt.claim.sub',v_customer::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer,'role','authenticated')::text,true);
  v_result := public.submit_refund_request(v_purchases[2],'TEST_ONLY refund after settlement');
  v_refund := (v_result->>'id')::uuid;
  PERFORM set_config('request.jwt.claim.sub',v_support::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_support,'role','authenticated')::text,true);
  PERFORM public.review_refund_request(v_refund,'approve');

  -- No new sale exists: the claw-back must still be picked up.
  PERFORM set_config('request.jwt.claim.sub',v_finance::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_finance,'role','authenticated')::text,true);
  v_result := public.finance_create_settlement_batch(current_date - 1, current_date + 1, v_network);
  IF (v_result->>'batches_created')::int <> 1 THEN
    RAISE EXCEPTION 'S26-04 FAIL: refund on a network without new sales was not batched (%)', v_result;
  END IF;
  EXECUTE 'SET LOCAL ROLE postgres';
  SELECT * INTO v_row FROM public.settlement_batches WHERE network_id = v_network AND status = 'draft';
  v_batch_b := v_row.id;
  IF v_row.gross_sales <> 0 OR v_row.total_commission <> 0
     OR v_row.total_refunds <> 970 OR v_row.net_settlement <> -970 THEN
    RAISE EXCEPTION 'S26-04 FAIL: claw-back totals gross=% commission=% refunds=% net=% (expected 0/0/970/-970)',
      v_row.gross_sales, v_row.total_commission, v_row.total_refunds, v_row.net_settlement;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.settlement_batch_lines
    WHERE settlement_batch_id = v_batch_b AND line_type = 'refund' AND reference_id = v_refund
      AND gross_amount = 1000 AND commission_amount = 30 AND net_amount = -970
  ) THEN
    RAISE EXCEPTION 'S26-04 FAIL: refund line does not reverse the net amount';
  END IF;
  RAISE NOTICE 'S26-04 PASS: refund of a settled sale claws back the net (970), commission is returned';

  -- The same refund is never clawed back twice.
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_result := public.finance_create_settlement_batch(current_date - 1, current_date + 1, v_network);
  IF (v_result->>'batches_created')::int <> 0 THEN
    RAISE EXCEPTION 'S26-05 FAIL: refund clawed back twice (%)', v_result;
  END IF;
  RAISE NOTICE 'S26-05 PASS: a refund is deducted exactly once';

  -- Cancelling a draft releases its lines so they can be batched again.
  PERFORM public.finance_cancel_settlement_batch(v_batch_b, 'TEST_ONLY wrong period');
  BEGIN
    PERFORM public.finance_cancel_settlement_batch(v_batch_b, 'TEST_ONLY again');
    RAISE EXCEPTION 'S26-06 FAIL: cancelled batch was cancelled twice';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'INVALID_STATE%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.finance_cancel_settlement_batch(v_batch, 'TEST_ONLY paid batch');
    RAISE EXCEPTION 'S26-06 FAIL: paid batch was cancelled';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'INVALID_STATE%' THEN RAISE; END IF;
  END;

  PERFORM set_config('request.jwt.claim.sub',v_customer::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer,'role','authenticated')::text,true);
  v_result := public.purchase_package(v_package, gen_random_uuid());
  v_purchase := (v_result->>'purchase_id')::uuid;

  PERFORM set_config('request.jwt.claim.sub',v_finance::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_finance,'role','authenticated')::text,true);
  v_result := public.finance_create_settlement_batch(current_date - 1, current_date + 1, v_network);
  EXECUTE 'SET LOCAL ROLE postgres';
  SELECT * INTO v_row FROM public.settlement_batches WHERE network_id = v_network AND status = 'draft';
  v_batch_c := v_row.id;
  -- One new sale (1000 - 30) and the released claw-back (970): net zero.
  IF v_row.gross_sales <> 1000 OR v_row.total_commission <> 30
     OR v_row.total_refunds <> 970 OR v_row.net_settlement <> 0 THEN
    RAISE EXCEPTION 'S26-06 FAIL: re-batched totals gross=% commission=% refunds=% net=% (expected 1000/30/970/0)',
      v_row.gross_sales, v_row.total_commission, v_row.total_refunds, v_row.net_settlement;
  END IF;
  RAISE NOTICE 'S26-06 PASS: a cancelled draft releases its lines; paid and cancelled batches cannot be cancelled';

  -- A draft sale that is refunded and then released by a cancel is voided.
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',v_customer::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer,'role','authenticated')::text,true);
  v_result := public.submit_refund_request(v_purchase,'TEST_ONLY refund while in draft');
  v_refund := (v_result->>'id')::uuid;
  PERFORM set_config('request.jwt.claim.sub',v_support::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_support,'role','authenticated')::text,true);
  PERFORM public.review_refund_request(v_refund,'approve');
  PERFORM set_config('request.jwt.claim.sub',v_finance::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_finance,'role','authenticated')::text,true);
  PERFORM public.finance_cancel_settlement_batch(v_batch_c, 'TEST_ONLY sale refunded');
  EXECUTE 'SET LOCAL ROLE postgres';
  SELECT settlement_status INTO v_text FROM public.owner_settlement_items WHERE purchase_id = v_purchase;
  IF v_text <> 'voided' THEN
    RAISE EXCEPTION 'S26-07 FAIL: refunded sale released from a cancelled draft is %, expected voided', v_text;
  END IF;
  RAISE NOTICE 'S26-07 PASS: a refunded sale released by a cancel is voided, not re-settled';

  -- Every settlement step is audited.
  SELECT count(DISTINCT action) INTO v_count FROM public.audit_events
  WHERE entity_type = 'settlement_batch'
    AND action IN ('SETTLEMENT_BATCH_CREATED','SETTLEMENT_BATCH_APPROVED','SETTLEMENT_BATCH_PAID','SETTLEMENT_BATCH_CANCELLED');
  IF v_count <> 4 THEN RAISE EXCEPTION 'S26-08 FAIL: only % of 4 settlement audit actions recorded', v_count; END IF;
  RAISE NOTICE 'S26-08 PASS: settlement lifecycle is audited';

  -- Customers and owners cannot run settlement functions.
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',v_owner::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_owner,'role','authenticated')::text,true);
  BEGIN
    PERFORM public.finance_cancel_settlement_batch(v_batch, 'TEST_ONLY owner');
    RAISE EXCEPTION 'S26-09 FAIL: owner cancelled a settlement batch';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'FORBIDDEN_ROLE%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'S26-09 PASS: settlement functions are finance-only';

  RAISE NOTICE 'NY_SETTLEMENT_REFUND_INTEGRITY_PASS';
END $$;

ROLLBACK;
