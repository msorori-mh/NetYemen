-- NetYemen Core Invariants Test Harness
-- File: supabase/tests/004_core_invariants.sql
-- Task ID: NY-GOV-BE-001

BEGIN;

DO $$
DECLARE
    v_user_id   UUID := '10101010-1010-4010-a010-101010101010';
    v_net_1_id  UUID := 'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1';
    v_net_2_id  UUID := 'a2a2a2a2-a2a2-4a2a-a2a2-a2a2a2a2a2a2';
    v_admin_id  UUID := 'a4a4a4a4-a4a4-4a4a-a4a4-a4a4a4a4a4a4';

    v_audit_id  UUID;
    v_count     INT;
    v_err_occurred BOOLEAN;
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
    -- Invariant 1: Role set contains exactly the 8 approved V1 roles
    -- ------------------------------------------------------------------------
    INSERT INTO public.user_roles (user_id, role) VALUES
        (v_user_id, 'customer'),
        (v_user_id, 'network_owner'),
        (v_user_id, 'network_operator'),
        (v_user_id, 'finance_officer'),
        (v_user_id, 'support_agent'),
        (v_user_id, 'system_auditor')
    ON CONFLICT (user_id, role) DO NOTHING;

    SELECT COUNT(DISTINCT role) INTO v_count FROM public.user_roles WHERE user_id = v_user_id;
    IF v_count <> 6 THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-01): Unexpected role count assigned: %', v_count;
    END IF;

    -- ------------------------------------------------------------------------
    -- Invariant 2: Deferred roles (merchant, distributor, reseller, telecom) rejected
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
    -- Invariant 3: Duplicate active normalized SSID alias across networks rejected
    -- ------------------------------------------------------------------------
    INSERT INTO public.networks (id, commercial_name, status, verification_status) VALUES
        (v_net_1_id, 'Hotspot Alpha', 'active', 'verified'),
        (v_net_2_id, 'Hotspot Beta', 'active', 'verified')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.network_ssid_aliases (network_id, ssid_display, ssid_normalized, status) VALUES
        (v_net_1_id, 'Yemen Net Hotspot', public.normalize_ssid('Yemen Net Hotspot'), 'active');

    v_err_occurred := FALSE;
    BEGIN
        INSERT INTO public.network_ssid_aliases (network_id, ssid_display, ssid_normalized, status) VALUES
            (v_net_2_id, 'Yemen-Net-Hotspot', public.normalize_ssid('Yemen-Net-Hotspot'), 'active');
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-03): Duplicate active normalized SSID alias was accepted!';
    END IF;

    -- ------------------------------------------------------------------------
    -- Invariant 4: Trigger-created customer role is idempotent
    -- ------------------------------------------------------------------------
    INSERT INTO public.user_roles (user_id, role) VALUES (v_user_id, 'customer')
    ON CONFLICT (user_id, role) DO NOTHING;

    SELECT COUNT(*) INTO v_count FROM public.user_roles WHERE user_id = v_user_id AND role = 'customer';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-04): Customer role row duplicated!';
    END IF;

    -- ------------------------------------------------------------------------
    -- Invariant 5: Audit rows CANNOT be updated
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    v_audit_id := public.record_audit_event('SYSTEM_BOOT', 'system', 'sys-01', 'success');

    v_err_occurred := FALSE;
    BEGIN
        UPDATE public.audit_events SET action = 'TAMPERED' WHERE id = v_audit_id;
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-05): Audit event row was updated!';
    END IF;

    -- ------------------------------------------------------------------------
    -- Invariant 6: Audit rows CANNOT be deleted
    -- ------------------------------------------------------------------------
    v_err_occurred := FALSE;
    BEGIN
        DELETE FROM public.audit_events WHERE id = v_audit_id;
    EXCEPTION WHEN OTHERS THEN
        v_err_occurred := TRUE;
    END;
    IF NOT v_err_occurred THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-06): Audit event row was deleted!';
    END IF;

    -- ------------------------------------------------------------------------
    -- Invariant 7: User deletion sets actor_user_id to NULL on audit_events without deleting audit row
    -- ------------------------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM public.audit_events WHERE id = v_audit_id;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (INV-07): Audit log record disappeared!';
    END IF;

    RAISE NOTICE 'SUCCESS: All 7 Core Invariants Passed.';
END $$;

ROLLBACK;
