-- Operations closure (TEST_ONLY, transactional).
-- Verifies 20261008094000_operations_closure.sql: deposit splitting,
-- notification isolation, account deletion completion and reconciliation.
BEGIN;

DO $$
DECLARE
  v_customer   UUID := 'a3000000-0000-4000-8000-000000000001';
  v_leaver     UUID := 'a3000000-0000-4000-8000-000000000002';
  v_finance    UUID := 'a3000000-0000-4000-8000-000000000003';
  v_finance_b  UUID := 'a3000000-0000-4000-8000-000000000004';
  v_admin      UUID := 'a3000000-0000-4000-8000-000000000005';
  v_destination UUID;
  v_deposit    UUID;
  v_event      UUID;
  v_result     JSONB;
  v_count      INTEGER;
  v_balance    INTEGER;
  v_msg        TEXT;
  v_text       TEXT;
BEGIN
  EXECUTE 'SET LOCAL ROLE postgres';
  INSERT INTO auth.users(id,email,phone,raw_user_meta_data) VALUES
    (v_customer,'s30-customer@pilot.netyemen.test',NULL,'{}'),
    (v_leaver,'s30-leaver@pilot.netyemen.test','967770003002','{"full_name":"TEST_ONLY Leaver"}'),
    (v_finance,'s30-finance@pilot.netyemen.test',NULL,'{}'),
    (v_finance_b,'s30-finance-b@pilot.netyemen.test',NULL,'{}'),
    (v_admin,'s30-admin@pilot.netyemen.test',NULL,'{}');
  INSERT INTO public.profiles(id,full_name,account_status,default_governorate,default_city) VALUES
    (v_customer,'TEST_ONLY S30 Customer','active',NULL,NULL),
    (v_leaver,'TEST_ONLY S30 Leaver','active','صنعاء','صنعاء'),
    (v_finance,'TEST_ONLY S30 Finance','active',NULL,NULL),
    (v_finance_b,'TEST_ONLY S30 Finance B','active',NULL,NULL),
    (v_admin,'TEST_ONLY S30 Admin','active',NULL,NULL)
  ON CONFLICT(id) DO UPDATE SET account_status='active', full_name=EXCLUDED.full_name,
    default_governorate=EXCLUDED.default_governorate, default_city=EXCLUDED.default_city;
  INSERT INTO public.user_roles(user_id,role) VALUES
    (v_customer,'customer'),(v_leaver,'customer'),(v_finance,'finance_officer'),
    (v_finance_b,'finance_officer'),(v_admin,'platform_admin')
  ON CONFLICT DO NOTHING;

  -- ------------------------------------------------ deposit splitting
  IF public.deposit_dual_approval_threshold() <> 50000 THEN
    RAISE EXCEPTION 'S30-SETUP FAIL: threshold changed; update this test';
  END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_admin,'role','authenticated')::text,true);
  v_destination := public.admin_create_payment_destination(
    'bank_account','TEST_ONLY S30 Bank','TEST_ONLY Holder','TEST_ONLY-S30-ACCT','TEST_ONLY','YER',0);

  -- First 30,000: below the threshold, one reviewer is enough.
  PERFORM set_config('request.jwt.claim.sub',v_customer::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer,'role','authenticated')::text,true);
  v_result := public.create_wallet_deposit_request(30000,'TEST_ONLY-S30-REF-1',v_destination,NULL,gen_random_uuid());
  v_deposit := (v_result->>'id')::uuid;
  PERFORM set_config('request.jwt.claim.sub',v_finance::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_finance,'role','authenticated')::text,true);
  v_result := public.review_wallet_deposit_request(v_deposit,'approve');
  IF v_result->>'status' <> 'approved' THEN RAISE EXCEPTION 'S30-01 FAIL: first deposit %', v_result; END IF;

  -- Second 30,000 the same day: together 60,000, so it needs two reviewers.
  PERFORM set_config('request.jwt.claim.sub',v_customer::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer,'role','authenticated')::text,true);
  v_result := public.create_wallet_deposit_request(30000,'TEST_ONLY-S30-REF-2',v_destination,NULL,gen_random_uuid());
  v_deposit := (v_result->>'id')::uuid;
  PERFORM set_config('request.jwt.claim.sub',v_finance::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_finance,'role','authenticated')::text,true);
  v_result := public.review_wallet_deposit_request(v_deposit,'approve');
  IF v_result->>'status' <> 'under_review' OR NOT (v_result->>'requires_second_approval')::boolean THEN
    RAISE EXCEPTION 'S30-01 FAIL: split deposit was credited by one reviewer (%)', v_result;
  END IF;
  v_result := public.review_wallet_deposit_request(v_deposit,'approve');
  IF v_result->>'status' <> 'under_review' THEN
    RAISE EXCEPTION 'S30-01 FAIL: same reviewer approved twice (%)', v_result;
  END IF;
  EXECUTE 'SET LOCAL ROLE postgres';
  SELECT cached_balance INTO v_balance FROM public.wallet_accounts WHERE user_id = v_customer;
  IF v_balance <> 30000 THEN RAISE EXCEPTION 'S30-01 FAIL: balance % before second approval', v_balance; END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',v_finance_b::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_finance_b,'role','authenticated')::text,true);
  v_result := public.review_wallet_deposit_request(v_deposit,'approve');
  IF v_result->>'status' <> 'approved' THEN RAISE EXCEPTION 'S30-01 FAIL: second reviewer %', v_result; END IF;
  EXECUTE 'SET LOCAL ROLE postgres';
  SELECT cached_balance INTO v_balance FROM public.wallet_accounts WHERE user_id = v_customer;
  IF v_balance <> 60000 THEN RAISE EXCEPTION 'S30-01 FAIL: balance % after second approval', v_balance; END IF;
  RAISE NOTICE 'S30-01 PASS: deposits split under the threshold still need two reviewers';

  -- ------------------------------------------------ reconciliation
  SELECT count(*) INTO v_count FROM public.finance_reconcile_wallets() r WHERE r.user_id = v_customer;
  IF v_count <> 0 THEN RAISE EXCEPTION 'S30-02 FAIL: a healthy wallet was reported as broken'; END IF;
  UPDATE public.wallet_accounts SET cached_balance = 61000 WHERE user_id = v_customer;
  SELECT count(*) INTO v_count FROM public.finance_reconcile_wallets() r
  WHERE r.user_id = v_customer AND r.cached_balance = 61000 AND r.ledger_balance = 60000;
  IF v_count <> 1 THEN RAISE EXCEPTION 'S30-02 FAIL: balance drift was not detected'; END IF;
  UPDATE public.wallet_accounts SET cached_balance = 60000 WHERE user_id = v_customer;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',v_customer::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_customer,'role','authenticated')::text,true);
  BEGIN
    PERFORM * FROM public.finance_reconcile_wallets();
    RAISE EXCEPTION 'S30-02 FAIL: a customer ran wallet reconciliation';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'FORBIDDEN_ROLE%' THEN RAISE; END IF;
  END;
  PERFORM set_config('request.jwt.claim.sub',v_finance::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_finance,'role','authenticated')::text,true);
  PERFORM * FROM public.finance_reconcile_wallets();
  RAISE NOTICE 'S30-02 PASS: reconciliation detects drift and is staff-only';

  -- ------------------------------------------------ notifications
  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_admin,'role','authenticated')::text,true);
  BEGIN
    PERFORM public.admin_compose_notification(
      'TEST_ONLY عنوان','TEST_ONLY نص','specific_user','{"user_id":"not-a-uuid"}'::jsonb,
      'announcement','notifications',NOW() + INTERVAL '1 hour',gen_random_uuid(),FALSE);
    RAISE EXCEPTION 'S30-03 FAIL: malformed audience accepted by the composer';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'INVALID_AUDIENCE_PAYLOAD%' THEN RAISE; END IF;
  END;

  -- A broken event that is already stored must not abort whoever triggers
  -- processing next (a purchase, a deposit approval, ...).
  EXECUTE 'SET LOCAL ROLE postgres';
  v_event := public.enqueue_notification_event(
    'admin_announcement','engagement','announcement','TEST_ONLY عنوان','TEST_ONLY نص','notifications',
    'specific_user','{"user_id":"not-a-uuid"}'::jsonb,'test','s30','s30-poison',gen_random_uuid(),v_admin,NOW(),'{}'::jsonb);
  v_result := public.process_notification_outbox(20);
  SELECT status || '|' || COALESCE(last_error,'') INTO v_text
  FROM public.notification_outbox WHERE event_id = v_event;
  IF v_text NOT LIKE 'pending|Processing failed:%' AND v_text NOT LIKE 'failed|Processing failed:%' THEN
    RAISE EXCEPTION 'S30-03 FAIL: broken event was not parked (%)', v_text;
  END IF;
  -- A healthy event queued afterwards is still delivered.
  v_event := public.enqueue_notification_event(
    'admin_announcement','engagement','announcement','TEST_ONLY عنوان سليم','TEST_ONLY نص سليم','notifications',
    'specific_user',jsonb_build_object('user_id',v_customer),'test','s30','s30-healthy',gen_random_uuid(),v_admin,NOW(),'{}'::jsonb);
  SELECT status INTO v_text FROM public.notification_outbox WHERE event_id = v_event;
  IF v_text NOT IN ('materialized','dispatch_blocked') THEN
    RAISE EXCEPTION 'S30-03 FAIL: healthy event stuck behind the broken one (%)', v_text;
  END IF;
  RAISE NOTICE 'S30-03 PASS: a broken notification is parked and never blocks other work';

  -- ------------------------------------------------ account deletion
  INSERT INTO public.device_push_tokens(user_id,platform,token) VALUES (v_leaver,'android','TEST_ONLY_S30_TOKEN');
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',v_leaver::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_leaver,'role','authenticated')::text,true);
  PERFORM public.set_account_pin('135790');
  PERFORM public.request_my_account_deletion('TEST_ONLY leaving');
  BEGIN
    PERFORM public.process_due_account_deletions(10);
    RAISE EXCEPTION 'S30-04 FAIL: a client ran the deletion processor';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  -- Not due yet: nothing happens.
  EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  v_result := public.process_due_account_deletions(10);
  EXECUTE 'SET LOCAL ROLE postgres';
  SELECT account_status INTO v_text FROM public.profiles WHERE id = v_leaver;
  IF v_text <> 'closure_pending' THEN
    RAISE EXCEPTION 'S30-04 FAIL: account deleted before its scheduled date (%)', v_text;
  END IF;

  -- Thirty days later.
  UPDATE public.account_deletion_requests
  SET requested_at = NOW() - INTERVAL '31 days', scheduled_for = NOW() - INTERVAL '1 day'
  WHERE user_id = v_leaver AND status = 'pending';
  EXECUTE 'SET LOCAL ROLE service_role';
  v_result := public.process_due_account_deletions(10);
  IF (v_result->>'completed')::int <> 1 THEN RAISE EXCEPTION 'S30-04 FAIL: %', v_result; END IF;

  EXECUTE 'SET LOCAL ROLE postgres';
  SELECT account_status || '|' || COALESCE(full_name,'') || '|' || COALESCE(default_city,'') INTO v_text
  FROM public.profiles WHERE id = v_leaver;
  IF v_text <> 'anonymized||' THEN RAISE EXCEPTION 'S30-04 FAIL: profile after deletion is %', v_text; END IF;
  IF EXISTS (SELECT 1 FROM public.device_push_tokens WHERE user_id = v_leaver)
     OR EXISTS (SELECT 1 FROM public.account_pins WHERE user_id = v_leaver) THEN
    RAISE EXCEPTION 'S30-04 FAIL: push tokens or PIN survived deletion';
  END IF;
  SELECT status INTO v_text FROM public.account_deletion_requests WHERE user_id = v_leaver;
  IF v_text <> 'completed' THEN RAISE EXCEPTION 'S30-04 FAIL: request status %', v_text; END IF;
  SELECT account_status INTO v_text FROM public.wallet_accounts WHERE user_id = v_leaver;
  IF v_text IS DISTINCT FROM 'closed' THEN RAISE EXCEPTION 'S30-04 FAIL: wallet status %', v_text; END IF;
  IF EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = v_leaver AND (email IS NOT NULL OR phone IS NOT NULL OR raw_user_meta_data <> '{}'::jsonb
      OR banned_until IS NULL)
  ) THEN RAISE EXCEPTION 'S30-04 FAIL: sign-in identity survived deletion'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.audit_events WHERE action = 'ACCOUNT_DELETION_COMPLETED' AND entity_id = v_leaver::text
  ) THEN RAISE EXCEPTION 'S30-04 FAIL: deletion was not audited'; END IF;
  -- Running it again is a no-op.
  EXECUTE 'SET LOCAL ROLE service_role';
  v_result := public.process_due_account_deletions(10);
  IF (v_result->>'completed')::int <> 0 THEN RAISE EXCEPTION 'S30-04 FAIL: deletion ran twice %', v_result; END IF;
  RAISE NOTICE 'S30-04 PASS: a due account deletion is completed once, by the service role only';

  RAISE NOTICE 'NY_OPERATIONS_CLOSURE_PASS';
END $$;

ROLLBACK;
