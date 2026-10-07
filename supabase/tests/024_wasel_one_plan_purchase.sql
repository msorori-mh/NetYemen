-- WASEL One atomic plan purchase tests.

BEGIN;

DO $$
DECLARE
    v_customer_a UUID := '12400000-0000-4000-8000-000000000001';
    v_customer_b UUID := '12400000-0000-4000-8000-000000000002';
    v_owner UUID := '22400000-0000-4000-8000-000000000001';
    v_admin UUID := '32400000-0000-4000-8000-000000000001';
    v_network UUID := '42400000-0000-4000-8000-000000000001';
    v_plan UUID := '52400000-0000-4000-8000-000000000001';
    v_plan_network UUID := '62400000-0000-4000-8000-000000000001';
    v_key UUID := '72400000-0000-4000-8000-000000000001';
    v_credit_key UUID := '82400000-0000-4000-8000-000000000001';
    v_result JSONB;
    v_replay JSONB;
    v_purchase_id UUID;
    v_entitlement_id UUID;
    v_balance INTEGER;
    v_count INTEGER;
    v_denied BOOLEAN;
BEGIN
    EXECUTE 'SET LOCAL ROLE postgres';

    INSERT INTO auth.users (id, email) VALUES
        (v_customer_a, 'wasel-plan-customer-a@example.test'),
        (v_customer_b, 'wasel-plan-customer-b@example.test'),
        (v_owner, 'wasel-plan-owner@example.test'),
        (v_admin, 'wasel-plan-admin@example.test')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.profiles (id, full_name, account_status) VALUES
        (v_customer_a, 'WASEL Plan Customer A', 'active'),
        (v_customer_b, 'WASEL Plan Customer B', 'active'),
        (v_owner, 'WASEL Plan Owner', 'active'),
        (v_admin, 'WASEL Plan Admin', 'active')
    ON CONFLICT (id) DO UPDATE SET account_status = 'active';

    INSERT INTO public.user_roles (user_id, role) VALUES
        (v_customer_a, 'customer'),
        (v_customer_b, 'customer'),
        (v_owner, 'network_owner'),
        (v_admin, 'platform_admin')
    ON CONFLICT (user_id, role) DO NOTHING;

    INSERT INTO public.networks (
        id, commercial_name, status, verification_status,
        created_by, approved_by, approved_at
    ) VALUES (
        v_network, 'WASEL One Purchase Partner', 'active', 'verified',
        v_owner, v_admin, NOW()
    );

    INSERT INTO public.federated_access_plans (
        id, name, retail_price, validity_seconds, quota_bytes,
        speed_limit_kbps, status, is_public, created_by
    ) VALUES (
        v_plan, 'WASEL One Purchase Test', 1000, 86400, 2147483648,
        4096, 'active', TRUE, v_admin
    );

    INSERT INTO public.federated_plan_networks (
        id, plan_id, network_id, compensation_model,
        compensation_rate_minor, is_active, created_by
    ) VALUES (
        v_plan_network, v_plan, v_network, 'per_gib', 500, TRUE, v_admin
    );

    INSERT INTO public.customer_wallet_ledger (
        user_id, entry_type, amount, balance_after, reference_type,
        reference_id, idempotency_key, actor_user_id, reason_code
    ) VALUES (
        v_customer_a, 'CREDIT', 5000, 5000, 'ADJUSTMENT',
        NULL, v_credit_key, v_admin, 'TEST_ONLY_WASEL_ONE_CREDIT'
    );

    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_customer_a::TEXT, TRUE);
    PERFORM set_config(
        'request.jwt.claims',
        json_build_object('sub', v_customer_a::TEXT, 'role', 'authenticated')::TEXT,
        TRUE
    );

    SELECT public.purchase_federated_access_plan(v_plan, v_key) INTO v_result;
    v_purchase_id := (v_result->>'purchase_id')::UUID;
    v_entitlement_id := (v_result->>'entitlement_id')::UUID;

    IF v_result->>'status' <> 'completed'
       OR (v_result->>'amount_paid')::INTEGER <> 1000
       OR (v_result->>'new_balance')::INTEGER <> 4000
       OR (v_result->>'replayed')::BOOLEAN THEN
        RAISE EXCEPTION 'TEST_FAIL (PURCHASE-01): unexpected purchase response %.', v_result;
    END IF;

    EXECUTE 'SET LOCAL ROLE postgres';
    SELECT cached_balance INTO v_balance
    FROM public.wallet_accounts WHERE user_id = v_customer_a;
    IF v_balance <> 4000 THEN
        RAISE EXCEPTION 'TEST_FAIL (PURCHASE-02): wallet balance is %, expected 4000.', v_balance;
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM public.access_entitlements
    WHERE id = v_entitlement_id
      AND user_id = v_customer_a
      AND plan_id = v_plan
      AND status = 'active'
      AND source_type = 'purchase'
      AND source_id = v_purchase_id
      AND allowance_bytes = 2147483648
      AND speed_limit_kbps = 4096;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (PURCHASE-03): entitlement snapshot is invalid.';
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM public.customer_wallet_ledger
    WHERE user_id = v_customer_a
      AND reason_code = 'WASEL_ONE_PURCHASE'
      AND reference_id = v_purchase_id;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST_FAIL (PURCHASE-04): expected exactly one wallet debit.';
    END IF;

    v_denied := FALSE;
    BEGIN
        UPDATE public.federated_access_purchases
        SET amount_paid = 1
        WHERE id = v_purchase_id;
    EXCEPTION WHEN OTHERS THEN
        v_denied := TRUE;
    END;
    IF NOT v_denied THEN
        RAISE EXCEPTION 'TEST_FAIL (IMMUTABLE-01): purchase record was mutated.';
    END IF;

    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT public.purchase_federated_access_plan(v_plan, v_key) INTO v_replay;
    IF NOT (v_replay->>'replayed')::BOOLEAN
       OR (v_replay->>'purchase_id')::UUID <> v_purchase_id
       OR (v_replay->>'entitlement_id')::UUID <> v_entitlement_id THEN
        RAISE EXCEPTION 'TEST_FAIL (IDEMPOTENCY-01): retry did not replay the purchase.';
    END IF;

    EXECUTE 'SET LOCAL ROLE postgres';
    SELECT cached_balance INTO v_balance
    FROM public.wallet_accounts WHERE user_id = v_customer_a;
    IF v_balance <> 4000 THEN
        RAISE EXCEPTION 'TEST_FAIL (IDEMPOTENCY-02): retry debited the wallet again.';
    END IF;

    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_customer_b::TEXT, TRUE);
    PERFORM set_config(
        'request.jwt.claims',
        json_build_object('sub', v_customer_b::TEXT, 'role', 'authenticated')::TEXT,
        TRUE
    );
    SELECT COUNT(*) INTO v_count
    FROM public.federated_access_purchases
    WHERE id = v_purchase_id;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST_FAIL (RLS-01): another customer read the purchase.';
    END IF;

    v_denied := FALSE;
    BEGIN
        PERFORM public.purchase_federated_access_plan(v_plan, gen_random_uuid());
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE 'INSUFFICIENT_BALANCE%' THEN
            RAISE EXCEPTION 'TEST_FAIL (BALANCE-01): unexpected error %.', SQLERRM;
        END IF;
        v_denied := TRUE;
    END;
    IF NOT v_denied THEN
        RAISE EXCEPTION 'TEST_FAIL (BALANCE-01): zero-balance purchase succeeded.';
    END IF;

    EXECUTE 'SET LOCAL ROLE anon';
    PERFORM set_config('request.jwt.claim.sub', '', TRUE);
    PERFORM set_config('request.jwt.claims', '{"role":"anon"}', TRUE);
    v_denied := FALSE;
    BEGIN
        PERFORM public.purchase_federated_access_plan(v_plan, gen_random_uuid());
    EXCEPTION WHEN OTHERS THEN
        v_denied := TRUE;
    END;
    IF NOT v_denied THEN
        RAISE EXCEPTION 'TEST_FAIL (AUTH-01): anonymous purchase succeeded.';
    END IF;
END;
$$;

ROLLBACK;
