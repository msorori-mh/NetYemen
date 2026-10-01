-- Verifies 20261001110000_settlement_refund_integrity.sql (review finding M-1):
--   SETTLE-REF-01 (b) a refund approved in a week without sales is still deducted;
--   SETTLE-REF-02 (a) a refund whose sale was never settled is not deducted;
--   SETTLE-REF-03     a refund is deducted at most once across batch runs;
--   SETTLE-REF-04 (c) the same reference cannot appear twice as the same line type.
-- TEST_ONLY, transactional.
BEGIN;

DO $$
DECLARE
  v_customer UUID := 'a0240000-0000-4000-8000-000000000001';
  v_owner    UUID := 'a0240000-0000-4000-8000-000000000002';
  v_finance  UUID := 'a0240000-0000-4000-8000-000000000003';
  v_admin    UUID := 'a0240000-0000-4000-8000-000000000004';
  v_network  UUID := 'a0240000-0000-4000-8000-000000000010';
  v_package  UUID := 'a0240000-0000-4000-8000-000000000020';
  v_p1       UUID := 'a0240000-0000-4000-8000-000000000101';  -- settled, later refunded
  v_p2       UUID := 'a0240000-0000-4000-8000-000000000102';  -- refunded before settlement
  v_p3       UUID := 'a0240000-0000-4000-8000-000000000103';  -- ordinary week-3 sale
  v_r1       UUID := 'a0240000-0000-4000-8000-000000000201';
  v_r2       UUID := 'a0240000-0000-4000-8000-000000000202';
  v_l1       UUID;
  v_l2       UUID;
  v_result   JSONB;
  v_batch    public.settlement_batches%ROWTYPE;
  v_count    INTEGER;
  v_failed   BOOLEAN;
BEGIN
  EXECUTE 'SET LOCAL ROLE postgres';
  INSERT INTO auth.users(id,email) VALUES
    (v_customer,'settle-customer@test-only.local'),
    (v_owner,'settle-owner@test-only.local'),
    (v_finance,'settle-finance@test-only.local'),
    (v_admin,'settle-admin@test-only.local');
  INSERT INTO public.profiles(id,full_name,account_status) VALUES
    (v_owner,'TEST_ONLY Owner','active'),
    (v_finance,'TEST_ONLY Finance','active'),
    (v_admin,'TEST_ONLY Admin','active')
  ON CONFLICT(id) DO UPDATE SET account_status='active';
  INSERT INTO public.user_roles(user_id,role) VALUES
    (v_owner,'network_owner'),(v_finance,'finance_officer'),(v_admin,'platform_admin')
  ON CONFLICT DO NOTHING;

  INSERT INTO public.networks(id,commercial_name,governorate,city,status,verification_status,created_by,approved_by,approved_at)
  VALUES(v_network,'TEST_ONLY Settlement Network','صنعاء','صنعاء','active','verified',v_owner,v_admin,now());
  INSERT INTO public.network_packages(id,network_id,name,price,duration_value,duration_unit,package_type,status,is_public,created_by)
  VALUES(v_package,v_network,'TEST_ONLY Settlement Package',1000,1,'day','time','active',true,v_owner);

  -- Week 1 (2026-01-05..11): P1 sold. Week 3 (2026-01-19..25): P2 and P3 sold.
  INSERT INTO public.purchase_records(id,user_id,package_id,network_id,amount_paid,status,idempotency_key,
                                      created_at,gross_amount,commission_rate_snapshot,commission_amount,owner_net_amount)
  VALUES
    (v_p1,v_customer,v_package,v_network,1000,'completed',gen_random_uuid(),'2026-01-06 10:00+00',1000,0.03,30,970),
    (v_p2,v_customer,v_package,v_network,1000,'completed',gen_random_uuid(),'2026-01-20 10:00+00',1000,0.03,30,970),
    (v_p3,v_customer,v_package,v_network,1000,'completed',gen_random_uuid(),'2026-01-21 10:00+00',1000,0.03,30,970);
  INSERT INTO public.owner_settlement_items(network_id,owner_user_id,purchase_id,gross_amount,platform_commission_amount,net_settlement_amount,settlement_status)
  VALUES
    (v_network,v_owner,v_p1,1000,30,970,'pending'),
    (v_network,v_owner,v_p2,1000,30,970,'pending'),
    (v_network,v_owner,v_p3,1000,30,970,'pending');

  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',v_finance::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_finance,'role','authenticated')::text,true);

  -- Week 1 batch settles P1.
  v_result := public.finance_create_settlement_batch('2026-01-05','2026-01-11',v_network);
  IF (v_result->>'batches_created')::int <> 1 OR (v_result->>'total_gross_sales')::int <> 1000 THEN
    RAISE EXCEPTION 'TEST_FAIL (SETTLE-REF-00): week-1 batch unexpected: %', v_result;
  END IF;

  -- Week 2: P1 refunded (sale already settled). Week 3: P2 refunded before any settlement.
  EXECUTE 'SET LOCAL ROLE postgres';
  INSERT INTO public.customer_wallet_ledger(user_id,entry_type,amount,balance_after,reference_type,reference_id,idempotency_key,actor_user_id,reason_code)
  VALUES (v_customer,'CREDIT',1000,1000,'REFUND',v_r1,gen_random_uuid(),v_admin,'TEST_ONLY_REFUND')
  RETURNING id INTO v_l1;
  INSERT INTO public.customer_wallet_ledger(user_id,entry_type,amount,balance_after,reference_type,reference_id,idempotency_key,actor_user_id,reason_code)
  VALUES (v_customer,'CREDIT',1000,2000,'REFUND',v_r2,gen_random_uuid(),v_admin,'TEST_ONLY_REFUND')
  RETURNING id INTO v_l2;
  INSERT INTO public.refund_requests(id,purchase_id,user_id,reason,status,support_agent_id,ledger_entry_id,created_at,updated_at)
  VALUES
    (v_r1,v_p1,v_customer,'TEST_ONLY refund settled sale','approved_refund',v_admin,v_l1,'2026-01-13 09:00+00','2026-01-14 09:00+00'),
    (v_r2,v_p2,v_customer,'TEST_ONLY refund unsettled sale','approved_refund',v_admin,v_l2,'2026-01-21 09:00+00','2026-01-22 09:00+00');
  UPDATE public.purchase_records SET status='refunded' WHERE id IN (v_p1,v_p2);

  -- SETTLE-REF-01: week 2 has no sales, but R1 must still be deducted.
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_result := public.finance_create_settlement_batch('2026-01-12','2026-01-18',v_network);
  IF (v_result->>'batches_created')::int <> 1 OR (v_result->>'total_refunds')::int <> 1000 THEN
    RAISE EXCEPTION 'TEST_FAIL (SETTLE-REF-01): refund in a week without sales not deducted: %', v_result;
  END IF;
  EXECUTE 'SET LOCAL ROLE postgres';
  SELECT * INTO v_batch FROM public.settlement_batches
  WHERE network_id=v_network AND period_start='2026-01-12';
  IF v_batch.owner_user_id IS DISTINCT FROM v_owner OR v_batch.gross_sales <> 0
     OR v_batch.total_refunds <> 1000 OR v_batch.net_settlement <> -1000 THEN
    RAISE EXCEPTION 'TEST_FAIL (SETTLE-REF-01): refund-only batch totals wrong';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.settlement_batch_lines
                 WHERE settlement_batch_id=v_batch.id AND line_type='refund' AND reference_id=v_r1 AND net_amount=-1000) THEN
    RAISE EXCEPTION 'TEST_FAIL (SETTLE-REF-01): refund line for settled sale missing';
  END IF;
  RAISE NOTICE 'SETTLE-REF-01 PASS: refund approved in a week without sales is deducted';

  -- SETTLE-REF-02: R2's sale (P2) was never settled, so it is never deducted.
  IF EXISTS (SELECT 1 FROM public.settlement_batch_lines WHERE line_type='refund' AND reference_id=v_r2) THEN
    RAISE EXCEPTION 'TEST_FAIL (SETTLE-REF-02): refund of an unsettled sale was deducted';
  END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_result := public.finance_create_settlement_batch('2026-01-19','2026-01-25',v_network);
  EXECUTE 'SET LOCAL ROLE postgres';
  SELECT * INTO v_batch FROM public.settlement_batches
  WHERE network_id=v_network AND period_start='2026-01-19';
  IF (v_result->>'batches_created')::int <> 1 OR v_batch.gross_sales <> 1000
     OR v_batch.total_refunds <> 0 OR v_batch.net_settlement <> 970 THEN
    RAISE EXCEPTION 'TEST_FAIL (SETTLE-REF-02/03): week-3 batch wrong: % / refunds %', v_result, v_batch.total_refunds;
  END IF;
  IF EXISTS (SELECT 1 FROM public.settlement_batch_lines WHERE line_type='refund' AND reference_id=v_r2) THEN
    RAISE EXCEPTION 'TEST_FAIL (SETTLE-REF-02): refund of an unsettled sale was deducted';
  END IF;
  RAISE NOTICE 'SETTLE-REF-02 PASS: refund of a never-settled sale is not deducted';

  -- SETTLE-REF-03: R1 deducted exactly once; re-running finds nothing new.
  SELECT count(*) INTO v_count FROM public.settlement_batch_lines WHERE line_type='refund' AND reference_id=v_r1;
  IF v_count <> 1 THEN RAISE EXCEPTION 'TEST_FAIL (SETTLE-REF-03): refund deducted % times', v_count; END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_result := public.finance_create_settlement_batch('2026-01-05','2026-01-25',v_network);
  IF (v_result->>'batches_created')::int <> 0 THEN
    RAISE EXCEPTION 'TEST_FAIL (SETTLE-REF-03): re-run created batches: %', v_result;
  END IF;
  RAISE NOTICE 'SETTLE-REF-03 PASS: refund deducted at most once';

  -- SETTLE-REF-04: unique (line_type, reference_id) backstop for concurrent runs.
  EXECUTE 'SET LOCAL ROLE postgres';
  IF NOT EXISTS (
    SELECT 1 FROM pg_index i
    WHERE i.indrelid = 'public.settlement_batch_lines'::regclass AND i.indisunique
      AND i.indexrelid = 'public.uq_settlement_batch_lines_type_reference'::regclass
  ) THEN
    RAISE EXCEPTION 'TEST_FAIL (SETTLE-REF-04): unique index on settlement_batch_lines missing';
  END IF;
  v_failed := false;
  BEGIN
    INSERT INTO public.settlement_batch_lines(settlement_batch_id,line_type,reference_id,gross_amount,commission_amount,net_amount)
    VALUES (v_batch.id,'refund',v_r1,1000,0,-1000);
  EXCEPTION WHEN unique_violation THEN v_failed := true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'TEST_FAIL (SETTLE-REF-04): duplicate refund line accepted'; END IF;
  RAISE NOTICE 'SETTLE-REF-04 PASS: duplicate settlement line rejected by unique index';

  RAISE NOTICE 'SUCCESS: settlement refund deductions are correct and unique.';
END $$;

ROLLBACK;
