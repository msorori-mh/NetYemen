-- NetYemen Core Invariants Test Harness
-- File: supabase/tests/004_core_invariants.sql
-- Task ID: NY-GOV-BE-001 / NY-GOV-BE-001B

BEGIN;

DO $$
DECLARE
    v_user_id   UUID := '10101010-1010-4010-a010-101010101010';
    v_new_user_id UUID := '20202020-2020-4020-a020-202020202020';
    v_net_1_id  UUID := 'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1';
    v_net_2_id  UUID := 'a2a2a2a2-a2a2-4a2a-a2a2-a2a2a2a2a2a2';
    v_admin_id  UUID := 'a4a4a4a4-a4a4-4a4a-a4a4-a4a4a4a4a4a4';

    v_audit_id  UUID;
    v_count     INT;
    v_err_occurred BOOLEAN;
    v_norm_arabic TEXT;
BEGIN
    -- Setup auth.users if auth schema exists
    IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth') THEN
        INSERT INTO auth.users (id, email) VALUES
            (v_user_id, 'invariant_user@netyemen.local'),
            (v_admin_id, 'invariant_admin@netyemen.local')
        ON CONFLICT (id) DO NOTHING;
    END IF;

    -- Setup Profiles and Admin Role
    INSERT INTO public.profiles (id, full_name, account_status) VALUES
        (v_user_id, 'Invariant User', 'active'),
        (v_admin_id, 'Invariant Admin', 'active')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.user_roles (user_id, role) VALUES
        (v_admin_id, 'platform_admin')
    ON CONFLICT (user_id, role) DO NOTHING;

    -- ------------------------------------------------------------------------
    -- Invariant 1: All eight approved role values are accepted by the constraint
    -- ------------------------------------------------------------------------
    INSERT INTO public.user_roles (user_id, role) VALUES
        (v_user_id, 'customer'),
        (v_user_id, 'network_owner'),
        (v_user_id, 'network_operator'),
        (v_user_id, 'finance_officer'),
        (v_user_id, 'support_agent'),
        (v_user_id, 'platform_admin'),
        (v_user_id, 'system_auditor'),
        (v_user_id, 'system_service')
    ON CONFLICT (user_id, role) DO NOTHING;

    SELECT COUNT(DISTINCT role) INTO v_count FROM public.user_roles WHERE user_id = v_user_id;
    IF v_count <> 8 THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-01): Expected 8 approved roles, got %', v_count;
    END IF;

    -- Switch connection to postgres role for fixture cleanup
    EXECUTE 'SET LOCAL ROLE postgres';
    DELETE FROM public.user_roles WHERE user_id = v_user_id;
    EXECUTE 'SET LOCAL ROLE authenticated';

    -- ------------------------------------------------------------------------
    -- Invariant 2: Unknown and deferred roles are rejected
    -- ------------------------------------------------------------------------
    v_err_occurred := FALSE;
    BEGIN
        INSERT INTO public.user_roles (user_id, role) VALUES (v_user_id, 'merchant');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-02): Deferred merchant role was accepted!';
    END IF;

    -- ------------------------------------------------------------------------
    -- Invariant 3: Client cannot assign system_service
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    v_err_occurred := FALSE;
    BEGIN
        INSERT INTO public.user_roles (user_id, role) VALUES (v_user_id, 'system_service');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    SELECT COUNT(*) INTO v_count FROM public.user_roles WHERE user_id = v_user_id AND role = 'system_service';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-03): Client assigned system_service role!';
    END IF;

    -- ------------------------------------------------------------------------
    -- Invariant 4: Trigger provisioning creates one profile and one customer role
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE postgres';
    IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth') THEN
        INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
            (v_new_user_id, 'newprovisioned@netyemen.local', '{"full_name":"New Provisioned User"}'::jsonb);
    ELSE
        PERFORM public.handle_new_user();
    END IF;
    EXECUTE 'SET LOCAL ROLE authenticated';

    SELECT COUNT(*) INTO v_count FROM public.profiles WHERE id = v_new_user_id;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-04): Profile trigger provisioning failed.';
    END IF;

    SELECT COUNT(*) INTO v_count FROM public.user_roles WHERE user_id = v_new_user_id AND role = 'customer';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-04): Customer role trigger provisioning failed.';
    END IF;

    -- ------------------------------------------------------------------------
    -- Invariant 5: Duplicate provisioning remains idempotent
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE postgres';
    INSERT INTO public.profiles (id, full_name, account_status) VALUES (v_new_user_id, 'New Provisioned User', 'active') ON CONFLICT (id) DO NOTHING;
    INSERT INTO public.user_roles (user_id, role) VALUES (v_new_user_id, 'customer') ON CONFLICT (user_id, role) DO NOTHING;
    EXECUTE 'SET LOCAL ROLE authenticated';

    SELECT COUNT(*) INTO v_count FROM public.profiles WHERE id = v_new_user_id;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-05): Profile count changed after idempotent insert.';
    END IF;

    -- ------------------------------------------------------------------------
    -- Invariant 6: Active SSID normalized uniqueness works
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE postgres';
    INSERT INTO public.networks (id, commercial_name, status, verification_status, approved_by, approved_at) VALUES
        (v_net_1_id, 'Hotspot Alpha', 'active', 'verified', v_admin_id, NOW()),
        (v_net_2_id, 'Hotspot Beta', 'active', 'verified', v_admin_id, NOW())
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.network_ssid_aliases (network_id, ssid_display, status, verified_by, verified_at) VALUES
        (v_net_1_id, 'Yemen Net Hotspot', 'active', v_admin_id, NOW());
    EXECUTE 'SET LOCAL ROLE authenticated';

    v_err_occurred := FALSE;
    BEGIN
        INSERT INTO public.network_ssid_aliases (network_id, ssid_display, status, verified_by, verified_at) VALUES
            (v_net_2_id, 'Yemen-Net-Hotspot', 'active', v_admin_id, NOW());
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-06): Duplicate active normalized SSID alias was accepted!';
    END IF;

    -- ------------------------------------------------------------------------
    -- Invariant 7: Unicode NFC normalization, canonical equivalence & Arabic safety
    -- ------------------------------------------------------------------------
    -- Decomposed vs Composed Unicode sequence canonical equivalence (E + COMBINING ACUTE vs É)
    IF public.normalize_ssid(U&'E\0301') <> public.normalize_ssid(U&'\00C9') THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-07): NFC canonical equivalence test failed for composed/decomposed sequence!';
    END IF;

    v_norm_arabic := public.normalize_ssid('شبكة عدن Wi-Fi 5G');
    IF v_norm_arabic IS NULL OR length(v_norm_arabic) = 0 OR v_norm_arabic NOT LIKE '%شبكة%' THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-07): Arabic SSID normalization failed: %', v_norm_arabic;
    END IF;

    IF public.normalize_ssid('شبكة 1') = public.normalize_ssid('شبكة 2') THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-07): Distinct Arabic SSIDs collided!';
    END IF;

    IF public.normalize_ssid('  Yemen   Hotspot   ') <> 'yemen-hotspot' THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-07): Whitespace normalization failed!';
    END IF;

    IF public.normalize_ssid('   ') <> '' THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-07): Whitespace-only SSID returned non-empty string!';
    END IF;

    -- ------------------------------------------------------------------------
    -- Invariant 8: Final active owner cannot be removed or deactivated
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE postgres';
    INSERT INTO public.user_roles (user_id, role) VALUES (v_user_id, 'network_owner') ON CONFLICT (user_id, role) DO NOTHING;
    INSERT INTO public.network_memberships (network_id, user_id, membership_role, status) VALUES (v_net_1_id, v_user_id, 'owner', 'active') ON CONFLICT (network_id, user_id) DO NOTHING;
    EXECUTE 'SET LOCAL ROLE authenticated';

    v_err_occurred := FALSE;
    BEGIN
        DELETE FROM public.network_memberships WHERE network_id = v_net_1_id AND user_id = v_user_id;
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-08): Final active network owner was deleted!';
    END IF;

    -- ------------------------------------------------------------------------
    -- Invariant 9: Audit event cannot be updated
    -- ------------------------------------------------------------------------
    EXECUTE 'SET LOCAL ROLE postgres';
    v_audit_id := public.record_audit_event('SYSTEM_BOOT', 'system', 'sys-01', 'success');
    EXECUTE 'SET LOCAL ROLE authenticated';

    v_err_occurred := FALSE;
    BEGIN
        UPDATE public.audit_events SET action = 'TAMPERED' WHERE id = v_audit_id;
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-09): Audit event row was updated!';
    END IF;

    -- ------------------------------------------------------------------------
    -- Invariant 10: Audit event cannot be deleted
    -- ------------------------------------------------------------------------
    v_err_occurred := FALSE;
    BEGIN
        DELETE FROM public.audit_events WHERE id = v_audit_id;
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-10): Audit event row was deleted!';
    END IF;

    -- ------------------------------------------------------------------------
    -- Invariant 11: Authenticated client cannot invoke audit-write RPC
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_user_id::text, true);
    v_err_occurred := FALSE;
    BEGIN
        PERFORM public.record_audit_event('CLIENT_RPC_ATTEMPT', 'test');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-11): Authenticated client invoked record_audit_event!';
    END IF;

    -- ------------------------------------------------------------------------
    -- Invariant 12: No deferred tables exist
    -- ------------------------------------------------------------------------
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name IN ('wallets', 'cards', 'settlements', 'merchants', 'telecom_services')
    ) THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-12): Prohibited deferred tables exist in database!';
    END IF;

    RAISE NOTICE 'SUCCESS: All 12 Core Invariants Passed.';
END $$;

ROLLBACK;
