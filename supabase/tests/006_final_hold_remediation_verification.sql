-- NetYemen V1 Network Discovery — Final Hold Remediation Local Verification
-- File: supabase/tests/006_final_hold_remediation_verification.sql
-- Task ID: NY-V1-NETWORK-DISCOVERY-001-FINAL-HOLD-REMEDIATION-02
--
-- This is a source-controlled, locally-runnable verification script for the
-- realistic checks mandated by the remediation mission. It must be executed
-- after `npx supabase db reset --no-seed` against the local container.

BEGIN;

DO $$
DECLARE
    v_user_id        UUID := 'f0f0f0f0-f0f0-4f0f-a0f0-f0f0f0f0f0f0';
    v_admin_id       UUID := 'a3a3a3a3-a3a3-4a3a-a3a3-a3a3a3a3a3a3';
    v_network_id     UUID := 'f1f1f1f1-f1f1-4f1f-a1f1-f1f1f1f1f1f1';
    v_request_id     UUID;
    v_request_id_2   UUID;
    v_result         JSONB;
    v_normalized     TEXT;
    v_err_occurred   BOOLEAN;
    v_users_exists   TEXT;
BEGIN
    EXECUTE 'SET LOCAL ROLE postgres';

    -- Fixture users/profiles/roles/network for the verification checks.
    IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth') THEN
        INSERT INTO auth.users (id, email) VALUES
            (v_user_id, 'fresh@netyemen.local'),
            (v_admin_id, 'admin@netyemen.local')
        ON CONFLICT (id) DO NOTHING;
    END IF;

    INSERT INTO public.profiles (id, full_name, account_status) VALUES
        (v_admin_id, 'Admin', 'active')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.user_roles (user_id, role) VALUES
        (v_admin_id, 'platform_admin')
    ON CONFLICT (user_id, role) DO NOTHING;

    INSERT INTO public.networks (
        id, commercial_name, status, verification_status,
        created_by, approved_by, approved_at
    ) VALUES (
        v_network_id, 'Test Approved Net', 'active', 'verified',
        v_admin_id, v_admin_id, NOW()
    ) ON CONFLICT (id) DO NOTHING;

    -- ========================================================================
    -- CHECK 1: Fresh-user auth completion does not depend on public.users
    -- ========================================================================
    SELECT to_regclass('public.users')::TEXT INTO v_users_exists;
    IF v_users_exists IS NOT NULL THEN
        RAISE EXCEPTION 'CHECK_FAIL (auth-01): public.users exists; V1 identity must rely on auth.users + public.profiles.';
    END IF;

    -- Simulate a fresh Supabase Auth signup and verify the trigger provisions
    -- the application identity in public.profiles / public.user_roles.
    IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth') THEN
        INSERT INTO auth.users (id, email) VALUES (v_user_id, 'fresh@netyemen.local')
        ON CONFLICT (id) DO NOTHING;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_user_id) THEN
        RAISE EXCEPTION 'CHECK_FAIL (auth-02): Fresh auth user did not trigger public.profiles provisioning.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = v_user_id AND role = 'customer') THEN
        RAISE EXCEPTION 'CHECK_FAIL (auth-03): Fresh auth user did not receive default customer role.';
    END IF;

    RAISE NOTICE 'AUTH_FRESH_USER_PASS: Fresh user identity provisioned via profiles/user_roles; no public.users reference.';

    -- ========================================================================
    -- CHECK 2: Idempotency — same payload + same UUID returns same logical result
    -- ========================================================================
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_user_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_id::text, 'role', 'authenticated')::text, true);

    v_result := public.submit_network_addition_request(
        'd1d1d1d1-d1d1-4d1d-a1d1-d1d1d1d1d1d1'::UUID,
        'Idempotent_SSID',
        'Proposed Name',
        'Governorate',
        'City',
        'District',
        'Notes'
    );
    v_request_id := (v_result->>'id')::UUID;

    v_result := public.submit_network_addition_request(
        'd1d1d1d1-d1d1-4d1d-a1d1-d1d1d1d1d1d1'::UUID,
        'Idempotent_SSID',
        'Proposed Name',
        'Governorate',
        'City',
        'District',
        'Notes'
    );
    IF (v_result->>'id')::UUID <> v_request_id THEN
        RAISE EXCEPTION 'CHECK_FAIL (idempotency-01): Same payload + same UUID returned a different request.';
    END IF;

    RAISE NOTICE 'IDEMPOTENCY_SAME_PAYLOAD_PASS: Same logical request replay returns identical row.';

    -- ========================================================================
    -- CHECK 3: Changed logical request with same UUID is rejected
    -- ========================================================================
    v_err_occurred := FALSE;
    BEGIN
        v_result := public.submit_network_addition_request(
            'd1d1d1d1-d1d1-4d1d-a1d1-d1d1d1d1d1d1'::UUID,
            'Different_SSID'
        );
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'CHECK_FAIL (idempotency-02): Reused UUID with different payload was accepted.';
    END IF;

    RAISE NOTICE 'IDEMPOTENCY_MISMATCH_PASS: Reusing a UUID with a different payload is rejected.';

    -- ========================================================================
    -- CHECK 4: Terminal state cannot be rewritten
    -- ========================================================================
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text, 'role', 'authenticated')::text, true);

    v_result := public.submit_network_addition_request(
        'e1e1e1e1-e1e1-4e1e-a1e1-e1e1e1e1e1e1'::UUID,
        'TerminalRewrite_SSID'
    );
    v_request_id_2 := (v_result->>'id')::UUID;

    v_result := public.resolve_network_addition_request(v_request_id_2, 'approved');
    IF (v_result->>'status') <> 'approved' THEN
        RAISE EXCEPTION 'CHECK_FAIL (state-01): Could not set request to approved for terminal test.';
    END IF;

    v_err_occurred := FALSE;
    BEGIN
        v_result := public.resolve_network_addition_request(v_request_id_2, 'rejected');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'CHECK_FAIL (state-02): Terminal approved -> rejected rewrite succeeded.';
    END IF;

    v_err_occurred := FALSE;
    BEGIN
        v_result := public.resolve_network_addition_request(v_request_id_2, 'under_review');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'CHECK_FAIL (state-03): Terminal approved -> under_review reopening succeeded.';
    END IF;

    RAISE NOTICE 'STATE_MACHINE_TERMINAL_PASS: Terminal approved status cannot be rewritten.';

    -- ========================================================================
    -- CHECK 5: matched_existing is terminal and cannot transition
    -- ========================================================================
    PERFORM set_config('request.jwt.claim.sub', v_user_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_id::text, 'role', 'authenticated')::text, true);

    v_result := public.submit_network_addition_request(
        'e2e2e2e2-e2e2-4e2e-a2e2-e2e2e2e2e2e2'::UUID,
        'MatchedTerminal_SSID'
    );
    v_request_id_2 := (v_result->>'id')::UUID;

    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text, 'role', 'authenticated')::text, true);

    v_result := public.resolve_network_addition_request(
        v_request_id_2,
        'matched_existing',
        'Matched existing approved network.',
        v_network_id
    );
    IF (v_result->>'status') <> 'matched_existing' THEN
        RAISE EXCEPTION 'CHECK_FAIL (state-04): Could not set matched_existing for terminal test.';
    END IF;

    v_err_occurred := FALSE;
    BEGIN
        v_result := public.resolve_network_addition_request(v_request_id_2, 'approved');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'CHECK_FAIL (state-05): matched_existing -> approved rewrite succeeded.';
    END IF;

    RAISE NOTICE 'STATE_MACHINE_MATCHED_EXISTING_PASS: matched_existing terminal status cannot be rewritten.';

    -- ========================================================================
    -- CHECK 6: Unicode whitespace normalization contract (NBSP and others)
    -- ========================================================================
    v_normalized := public.normalize_ssid(U&'A\00A0B');
    IF v_normalized <> 'a-b' THEN
        RAISE EXCEPTION 'CHECK_FAIL (unicode-01): NBSP U+00A0 not collapsed. Got %.', v_normalized;
    END IF;

    v_normalized := public.normalize_ssid(U&'A\2000B\202F');
    IF v_normalized <> 'a-b' THEN
        RAISE EXCEPTION 'CHECK_FAIL (unicode-02): U+2000/U+202F not collapsed. Got %.', v_normalized;
    END IF;

    v_normalized := public.normalize_ssid(U&'\3000A\3000');
    IF v_normalized <> 'a' THEN
        RAISE EXCEPTION 'CHECK_FAIL (unicode-03): U+3000 ideographic space not trimmed. Got %.', v_normalized;
    END IF;

    v_normalized := public.normalize_ssid(U&'A\0085B');
    IF v_normalized <> 'a-b' THEN
        RAISE EXCEPTION 'CHECK_FAIL (unicode-04): U+0085 NEL not collapsed. Got %.', v_normalized;
    END IF;

    -- Arabic NFC preservation sanity check.
    v_normalized := public.normalize_ssid(U&'\0623\0645\0627\0646\0629');
    IF v_normalized = '' OR v_normalized IS NULL THEN
        RAISE EXCEPTION 'CHECK_FAIL (unicode-05): Arabic content lost during normalization.';
    END IF;

    RAISE NOTICE 'UNICODE_NORMALIZATION_PASS: Defined Unicode whitespace contract applied consistently.';

    RAISE NOTICE 'SUCCESS: All final-hold remediation verification checks passed.';
END $$;

ROLLBACK;
