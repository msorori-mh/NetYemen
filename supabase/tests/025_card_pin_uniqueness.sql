-- Verifies 20261001111000_card_pin_uniqueness.sql (review finding M-2):
--   PIN-01 a PIN repeated inside one batch aborts the whole batch;
--   PIN-02 a PIN already in the network's vault aborts the whole batch;
--   PIN-03 a legacy row without a fingerprint is fingerprinted and matched;
--   PIN-04 the same PIN in another network is accepted (network scope);
--   PIN-05 a batch over 5000 cards is rejected;
--   PIN-06 fingerprints are keyed, unique-indexed and the helpers are internal.
-- Requires the disposable card_master_key Vault secret (as tests 013-015).
-- TEST_ONLY, transactional.
BEGIN;

DO $$
DECLARE
  v_owner     UUID := 'a0250000-0000-4000-8000-000000000001';
  v_admin     UUID := 'a0250000-0000-4000-8000-000000000002';
  v_network   UUID := 'a0250000-0000-4000-8000-000000000010';
  v_network_b UUID := 'a0250000-0000-4000-8000-000000000011';
  v_package   UUID := 'a0250000-0000-4000-8000-000000000020';
  v_package_b UUID := 'a0250000-0000-4000-8000-000000000021';
  v_legacy    UUID := 'a0250000-0000-4000-8000-000000000030';
  v_result    JSONB;
  v_count     INTEGER;
  v_failed    BOOLEAN;
  v_fp        TEXT;
  v_big       JSONB[];
BEGIN
  EXECUTE 'SET LOCAL ROLE postgres';
  INSERT INTO auth.users(id,email) VALUES
    (v_owner,'pin-owner@test-only.local'),
    (v_admin,'pin-admin@test-only.local');
  INSERT INTO public.profiles(id,full_name,account_status) VALUES
    (v_owner,'TEST_ONLY Owner','active'),
    (v_admin,'TEST_ONLY Admin','active')
  ON CONFLICT(id) DO UPDATE SET account_status='active';
  INSERT INTO public.user_roles(user_id,role) VALUES (v_owner,'network_owner'),(v_admin,'platform_admin')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.networks(id,commercial_name,governorate,city,status,verification_status,created_by,approved_by,approved_at)
  VALUES
    (v_network,'TEST_ONLY PIN Network A','صنعاء','صنعاء','active','verified',v_owner,v_admin,now()),
    (v_network_b,'TEST_ONLY PIN Network B','صنعاء','صنعاء','active','verified',v_owner,v_admin,now());
  INSERT INTO public.network_packages(id,network_id,name,price,duration_value,duration_unit,package_type,status,is_public,created_by)
  VALUES
    (v_package,v_network,'TEST_ONLY PIN Package A',1000,1,'day','time','active',true,v_owner),
    (v_package_b,v_network_b,'TEST_ONLY PIN Package B',1000,1,'day','time','active',true,v_owner);

  -- A legacy card ingested before fingerprints existed.
  INSERT INTO public.card_vault(id,network_id,package_id,batch_id,state,ciphertext)
  VALUES (v_legacy,v_network,v_package,'legacy','available',
          pgp_sym_encrypt('TEST_ONLY_PIN_LEGACY', public.get_card_master_key()));

  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_admin,'role','authenticated')::text,true);

  -- PIN-01: duplicate within a batch (whitespace variant of the same PIN).
  v_failed := false;
  BEGIN
    PERFORM public.admin_ingest_card_vault_batch(v_network, v_package, ARRAY[
      jsonb_build_object('pin','TEST_ONLY_PIN_001'),
      jsonb_build_object('pin','TEST_ONLY_PIN_002'),
      jsonb_build_object('pin',' TEST_ONLY_PIN_001 ')
    ]::jsonb[]);
  EXCEPTION WHEN unique_violation THEN
    v_failed := SQLERRM LIKE 'DUPLICATE_CARD_PIN:%';
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'TEST_FAIL (PIN-01): duplicate PIN within a batch was accepted'; END IF;
  EXECUTE 'SET LOCAL ROLE postgres';
  SELECT count(*) INTO v_count FROM public.card_vault WHERE network_id=v_network;
  IF v_count <> 1 THEN RAISE EXCEPTION 'TEST_FAIL (PIN-01): rejected batch left % rows', v_count - 1; END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  RAISE NOTICE 'PIN-01 PASS: duplicate PIN within a batch aborts the batch';

  -- PIN-02: duplicate against an existing card.
  v_result := public.admin_ingest_card_vault_batch(v_network, v_package, ARRAY[
    jsonb_build_object('pin','TEST_ONLY_PIN_001'),
    jsonb_build_object('pin','TEST_ONLY_PIN_002')
  ]::jsonb[]);
  IF (v_result->>'ingested_count')::int <> 2 THEN
    RAISE EXCEPTION 'TEST_FAIL (PIN-02): distinct PINs were not ingested: %', v_result;
  END IF;
  v_failed := false;
  BEGIN
    PERFORM public.admin_ingest_card_vault_batch(v_network, v_package, ARRAY[
      jsonb_build_object('pin','TEST_ONLY_PIN_003'),
      jsonb_build_object('pin','TEST_ONLY_PIN_002')
    ]::jsonb[]);
  EXCEPTION WHEN unique_violation THEN
    v_failed := SQLERRM LIKE 'DUPLICATE_CARD_PIN:%';
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'TEST_FAIL (PIN-02): PIN already in the vault was accepted'; END IF;
  EXECUTE 'SET LOCAL ROLE postgres';
  SELECT count(*) INTO v_count FROM public.card_vault WHERE network_id=v_network;
  IF v_count <> 3 THEN RAISE EXCEPTION 'TEST_FAIL (PIN-02): rejected batch was partially ingested (% rows)', v_count; END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  RAISE NOTICE 'PIN-02 PASS: PIN already in the network vault aborts the batch';

  -- PIN-03: the legacy row was fingerprinted on ingest and is matched.
  v_failed := false;
  BEGIN
    PERFORM public.admin_ingest_card_vault_batch(v_network, v_package,
      ARRAY[jsonb_build_object('pin','TEST_ONLY_PIN_LEGACY')]::jsonb[]);
  EXCEPTION WHEN unique_violation THEN
    v_failed := SQLERRM LIKE 'DUPLICATE_CARD_PIN:%';
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'TEST_FAIL (PIN-03): PIN of a legacy card was accepted'; END IF;
  EXECUTE 'SET LOCAL ROLE postgres';
  IF EXISTS (SELECT 1 FROM public.card_vault WHERE network_id=v_network AND pin_fingerprint IS NULL) THEN
    RAISE EXCEPTION 'TEST_FAIL (PIN-03): card without fingerprint remains in the network';
  END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  RAISE NOTICE 'PIN-03 PASS: legacy card fingerprinted and matched';

  -- PIN-04: the same PIN in another network is a different router login.
  v_result := public.admin_ingest_card_vault_batch(v_network_b, v_package_b,
    ARRAY[jsonb_build_object('pin','TEST_ONLY_PIN_001')]::jsonb[]);
  IF (v_result->>'ingested_count')::int <> 1 THEN
    RAISE EXCEPTION 'TEST_FAIL (PIN-04): same PIN in another network rejected: %', v_result;
  END IF;
  RAISE NOTICE 'PIN-04 PASS: PIN uniqueness is scoped to the network';

  -- PIN-05: oversize batch.
  SELECT array_agg(jsonb_build_object('pin','TEST_ONLY_BULK_'||g)) INTO v_big FROM generate_series(1,5001) g;
  v_failed := false;
  BEGIN
    PERFORM public.admin_ingest_card_vault_batch(v_network, v_package, v_big);
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE 'BATCH_TOO_LARGE:%';
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'TEST_FAIL (PIN-05): batch of 5001 cards was not rejected with BATCH_TOO_LARGE'; END IF;
  RAISE NOTICE 'PIN-05 PASS: oversize batch rejected';

  -- PIN-06: keyed fingerprint, unique index, internal helpers.
  EXECUTE 'SET LOCAL ROLE postgres';
  SELECT pin_fingerprint INTO v_fp FROM public.card_vault WHERE id=v_legacy;
  IF v_fp IS NULL OR v_fp !~ '^[0-9a-f]{64}$'
     OR v_fp = encode(digest('TEST_ONLY_PIN_LEGACY','sha256'),'hex')
     OR v_fp = encode(hmac('TEST_ONLY_PIN_LEGACY', public.get_card_master_key(), 'sha256'),'hex') THEN
    RAISE EXCEPTION 'TEST_FAIL (PIN-06): fingerprint is not a derived-key HMAC';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_index
    WHERE indexrelid = 'public.uq_card_vault_network_pin_fingerprint'::regclass AND indisunique
  ) THEN
    RAISE EXCEPTION 'TEST_FAIL (PIN-06): unique (network_id, pin_fingerprint) index missing';
  END IF;
  IF has_function_privilege('authenticated','public._card_pin_fingerprint(text,text)','EXECUTE')
     OR has_function_privilege('anon','public._card_pin_fingerprint(text,text)','EXECUTE')
     OR has_function_privilege('authenticated','public._backfill_card_pin_fingerprints(uuid,text)','EXECUTE')
     OR has_function_privilege('anon','public._backfill_card_pin_fingerprints(uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION 'TEST_FAIL (PIN-06): fingerprint helpers are callable by client roles';
  END IF;
  IF NOT has_function_privilege('authenticated','public.admin_ingest_card_vault_batch(uuid,uuid,jsonb[])','EXECUTE')
     OR has_function_privilege('anon','public.admin_ingest_card_vault_batch(uuid,uuid,jsonb[])','EXECUTE') THEN
    RAISE EXCEPTION 'TEST_FAIL (PIN-06): admin_ingest_card_vault_batch grants changed';
  END IF;
  RAISE NOTICE 'PIN-06 PASS: keyed fingerprint, unique index, internal helpers';

  RAISE NOTICE 'SUCCESS: duplicate card PINs and oversize batches are rejected.';
END $$;

ROLLBACK;
