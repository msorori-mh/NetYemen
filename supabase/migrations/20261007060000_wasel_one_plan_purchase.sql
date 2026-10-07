-- WASEL One customer purchase path.
-- Scope: atomically debit the customer wallet and issue a federated entitlement.

CREATE TABLE public.federated_access_purchases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    plan_id UUID NOT NULL REFERENCES public.federated_access_plans(id) ON DELETE RESTRICT,
    entitlement_id UUID NOT NULL UNIQUE REFERENCES public.access_entitlements(id) ON DELETE RESTRICT,
    amount_paid INTEGER NOT NULL,
    currency TEXT NOT NULL DEFAULT 'YER',
    status TEXT NOT NULL DEFAULT 'completed',
    idempotency_key UUID NOT NULL,
    ledger_entry_id UUID NOT NULL UNIQUE REFERENCES public.customer_wallet_ledger(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_federated_access_purchase_idempotency UNIQUE (user_id, idempotency_key),
    CONSTRAINT chk_federated_access_purchase_amount CHECK (amount_paid > 0),
    CONSTRAINT chk_federated_access_purchase_currency CHECK (currency = 'YER'),
    CONSTRAINT chk_federated_access_purchase_status CHECK (status = 'completed')
);

COMMENT ON TABLE public.federated_access_purchases IS
    'Immutable customer purchases of WASEL One plans. Each completed purchase owns exactly one entitlement and wallet debit.';

CREATE INDEX idx_federated_access_purchases_user_created
    ON public.federated_access_purchases (user_id, created_at DESC);
CREATE INDEX idx_federated_access_purchases_plan
    ON public.federated_access_purchases (plan_id, status);

CREATE TRIGGER trg_federated_access_purchases_immutable
    BEFORE UPDATE OR DELETE ON public.federated_access_purchases
    FOR EACH ROW EXECUTE FUNCTION public.prevent_wasel_one_event_mutation();

ALTER TABLE public.federated_access_purchases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.federated_access_purchases FORCE ROW LEVEL SECURITY;

CREATE POLICY federated_access_purchases_scoped_read
    ON public.federated_access_purchases FOR SELECT
    USING (
        user_id = auth.uid()
        OR public.has_platform_role('platform_admin')
        OR public.has_platform_role('finance_officer')
        OR public.has_platform_role('support_agent')
        OR public.has_platform_role('system_auditor')
    );

REVOKE ALL ON TABLE public.federated_access_purchases
    FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.federated_access_purchases TO authenticated;
GRANT ALL ON TABLE public.federated_access_purchases TO service_role;

CREATE OR REPLACE FUNCTION public.purchase_federated_access_plan(
    p_plan_id UUID,
    p_idempotency_key UUID
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_plan public.federated_access_plans%ROWTYPE;
    v_wallet public.wallet_accounts%ROWTYPE;
    v_existing public.federated_access_purchases%ROWTYPE;
    v_purchase_id UUID := gen_random_uuid();
    v_entitlement_id UUID := gen_random_uuid();
    v_ledger_id UUID;
    v_starts_at TIMESTAMPTZ := NOW();
    v_expires_at TIMESTAMPTZ;
    v_new_balance INTEGER;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    IF p_idempotency_key IS NULL THEN
        RAISE EXCEPTION 'MISSING_IDEMPOTENCY: Idempotency key is required.'
            USING ERRCODE = '22000';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = v_user_id AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'INACTIVE_PROFILE: Account is not active.'
            USING ERRCODE = '42501';
    END IF;

    -- Serialize retries with the same customer/key before checking replay state.
    PERFORM pg_advisory_xact_lock(
        hashtextextended(v_user_id::TEXT || ':' || p_idempotency_key::TEXT, 0)
    );

    SELECT * INTO v_existing
    FROM public.federated_access_purchases
    WHERE user_id = v_user_id AND idempotency_key = p_idempotency_key;

    IF v_existing.id IS NOT NULL THEN
        RETURN jsonb_build_object(
            'purchase_id', v_existing.id,
            'entitlement_id', v_existing.entitlement_id,
            'status', v_existing.status,
            'amount_paid', v_existing.amount_paid,
            'currency', v_existing.currency,
            'new_balance', (
                SELECT balance_after FROM public.customer_wallet_ledger
                WHERE id = v_existing.ledger_entry_id
            ),
            'replayed', TRUE
        );
    END IF;

    SELECT * INTO v_plan
    FROM public.federated_access_plans
    WHERE id = p_plan_id;

    IF v_plan.id IS NULL
       OR v_plan.status <> 'active'
       OR NOT v_plan.is_public THEN
        RAISE EXCEPTION 'PLAN_UNAVAILABLE: WASEL One plan is not available.'
            USING ERRCODE = '42501';
    END IF;

    IF v_plan.retail_price <= 0 OR v_plan.currency <> 'YER' THEN
        RAISE EXCEPTION 'INVALID_PLAN_PRICE: Purchasable plan price is invalid.'
            USING ERRCODE = '22000';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.federated_plan_networks pn
        JOIN public.networks n ON n.id = pn.network_id
        WHERE pn.plan_id = v_plan.id
          AND pn.is_active
          AND pn.effective_from <= NOW()
          AND (pn.effective_until IS NULL OR pn.effective_until > NOW())
          AND n.status = 'active'
          AND n.verification_status = 'verified'
    ) THEN
        RAISE EXCEPTION 'PLAN_HAS_NO_ACTIVE_NETWORKS: Plan has no active partner networks.'
            USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_wallet
    FROM public.wallet_accounts
    WHERE user_id = v_user_id
    FOR UPDATE;

    IF v_wallet.user_id IS NULL OR v_wallet.account_status <> 'active' THEN
        RAISE EXCEPTION 'WALLET_UNAVAILABLE: Customer wallet is not active.'
            USING ERRCODE = '42501';
    END IF;

    IF v_wallet.currency <> v_plan.currency THEN
        RAISE EXCEPTION 'CURRENCY_MISMATCH: Wallet and plan currencies differ.'
            USING ERRCODE = '22000';
    END IF;

    IF v_wallet.cached_balance < v_plan.retail_price THEN
        RAISE EXCEPTION 'INSUFFICIENT_BALANCE: Wallet balance is insufficient.'
            USING ERRCODE = '22000';
    END IF;

    v_new_balance := v_wallet.cached_balance - v_plan.retail_price;
    v_expires_at := v_starts_at + make_interval(secs => v_plan.validity_seconds);

    INSERT INTO public.customer_wallet_ledger (
        user_id, entry_type, amount, balance_after, reference_type,
        reference_id, idempotency_key, actor_user_id, reason_code, metadata
    ) VALUES (
        v_user_id, 'DEBIT', v_plan.retail_price, v_new_balance, 'PURCHASE',
        v_purchase_id, p_idempotency_key, v_user_id, 'WASEL_ONE_PURCHASE',
        jsonb_build_object('plan_id', v_plan.id, 'purchase_id', v_purchase_id)
    ) RETURNING id INTO v_ledger_id;

    INSERT INTO public.access_entitlements (
        id, user_id, plan_id, status, starts_at, expires_at,
        allowance_bytes, consumed_bytes, speed_limit_kbps,
        max_concurrent_sessions, source_type, source_id, idempotency_key
    ) VALUES (
        v_entitlement_id, v_user_id, v_plan.id, 'active', v_starts_at, v_expires_at,
        v_plan.quota_bytes, 0, v_plan.speed_limit_kbps,
        v_plan.max_concurrent_sessions, 'purchase', v_purchase_id, p_idempotency_key
    );

    INSERT INTO public.federated_access_purchases (
        id, user_id, plan_id, entitlement_id, amount_paid,
        currency, status, idempotency_key, ledger_entry_id
    ) VALUES (
        v_purchase_id, v_user_id, v_plan.id, v_entitlement_id,
        v_plan.retail_price, v_plan.currency, 'completed',
        p_idempotency_key, v_ledger_id
    );

    RETURN jsonb_build_object(
        'purchase_id', v_purchase_id,
        'entitlement_id', v_entitlement_id,
        'status', 'completed',
        'amount_paid', v_plan.retail_price,
        'currency', v_plan.currency,
        'new_balance', v_new_balance,
        'starts_at', v_starts_at,
        'expires_at', v_expires_at,
        'replayed', FALSE
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.purchase_federated_access_plan(UUID, UUID)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.purchase_federated_access_plan(UUID, UUID)
    TO authenticated;
