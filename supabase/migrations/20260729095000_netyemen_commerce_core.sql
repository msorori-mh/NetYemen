-- NetYemen V1 Commerce Core Migration
-- Migration: 20260729095000_netyemen_commerce_core.sql
-- Task ID: NY-V1-COMMERCE-CORE-001
-- Scope: Wallet foundation, deposit requests/reviews, atomic package purchase,
--         provider-neutral card fulfillment boundary, refund hooks, settlement hooks.
-- Governance:
--   - OD-CARD-01 remains OPEN. No Wi-Fi credentials, voucher codes, card payloads,
--     or encrypted secrets are stored. The fulfillment boundary fails closed until
--     a secure vault architecture is approved and configured.
--   - OD-FIN-01 / OD-FIN-03 use provider-neutral reference fields and a
--     configuration-driven bank directory; no real bank API or gateway is bound.
--   - OD-WALLET-01 follows Option A: cached balance maintained by database trigger
--     on the immutable ledger (customer_wallet_ledger).
--   - OD-SETTLE-01 remains OPEN. Only immutable settlement-ready accounting
--     references are tracked; no payout schedule or automated batch is implemented.

-- ============================================================================
-- 1. Table: public.bank_directory
-- Provider-neutral deposit channels managed by platform finance.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.bank_directory (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_name TEXT NOT NULL,
    account_label TEXT,
    account_number TEXT,
    iban TEXT,
    currency TEXT NOT NULL DEFAULT 'YER',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_bank_directory_provider_non_empty CHECK (length(trim(provider_name)) > 0),
    CONSTRAINT chk_bank_directory_currency CHECK (currency IN ('YER'))
);

COMMENT ON TABLE public.bank_directory IS 'Configuration-driven directory of customer deposit channels. Provider names are illustrative until official accounts are configured (OD-FIN-03).';

CREATE INDEX IF NOT EXISTS idx_bank_directory_active ON public.bank_directory (is_active, sort_order);

CREATE TRIGGER trg_bank_directory_set_updated_at
    BEFORE UPDATE ON public.bank_directory
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.bank_directory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bank_directory FORCE ROW LEVEL SECURITY;

-- ============================================================================
-- 2. Table: public.wallet_accounts
-- Cached customer wallet state. Balance is derived from customer_wallet_ledger.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.wallet_accounts (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE RESTRICT,
    currency TEXT NOT NULL DEFAULT 'YER',
    cached_balance INTEGER NOT NULL DEFAULT 0,
    account_status TEXT NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_wallet_accounts_currency CHECK (currency IN ('YER')),
    CONSTRAINT chk_wallet_accounts_balance_non_negative CHECK (cached_balance >= 0),
    CONSTRAINT chk_wallet_accounts_status CHECK (account_status IN ('active', 'frozen', 'closed'))
);

COMMENT ON TABLE public.wallet_accounts IS 'Customer wallet cached balance per OD-WALLET-01 Option A. Updated exclusively by trigger on customer_wallet_ledger.';

CREATE INDEX IF NOT EXISTS idx_wallet_accounts_status ON public.wallet_accounts (account_status);

CREATE TRIGGER trg_wallet_accounts_set_updated_at
    BEFORE UPDATE ON public.wallet_accounts
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.wallet_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_accounts FORCE ROW LEVEL SECURITY;

-- ============================================================================
-- 3. Trigger: Initialize wallet account on profile creation
-- ============================================================================

CREATE OR REPLACE FUNCTION public.initialize_wallet_account()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.wallet_accounts (user_id, currency, cached_balance, account_status)
    VALUES (NEW.id, 'YER', 0, 'active')
    ON CONFLICT (user_id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_initialize_wallet_account') THEN
        CREATE TRIGGER trg_initialize_wallet_account
            AFTER INSERT ON public.profiles
            FOR EACH ROW
            EXECUTE FUNCTION public.initialize_wallet_account();
    END IF;
END $$;

REVOKE EXECUTE ON FUNCTION public.initialize_wallet_account() FROM PUBLIC;

-- ============================================================================
-- 4. Table: public.customer_wallet_ledger
-- Immutable append-only financial ledger.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.customer_wallet_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    entry_type TEXT NOT NULL,
    amount INTEGER NOT NULL,
    balance_after INTEGER NOT NULL,
    reference_type TEXT NOT NULL,
    reference_id UUID,
    idempotency_key UUID NOT NULL,
    actor_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    reason_code TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_customer_wallet_ledger_entry_type CHECK (entry_type IN ('CREDIT', 'DEBIT', 'REVERSAL')),
    CONSTRAINT chk_customer_wallet_ledger_amount_positive CHECK (amount > 0),
    CONSTRAINT chk_customer_wallet_ledger_balance_non_negative CHECK (balance_after >= 0),
    CONSTRAINT chk_customer_wallet_ledger_reference_type CHECK (reference_type IN ('DEPOSIT', 'PURCHASE', 'REFUND', 'SETTLEMENT', 'ADJUSTMENT')),
    CONSTRAINT chk_customer_wallet_ledger_metadata_size CHECK (octet_length(metadata::text) <= 8192)
);

COMMENT ON TABLE public.customer_wallet_ledger IS 'Immutable customer wallet ledger. DELETE/UPDATE revoked for all client roles. Balance cached in wallet_accounts via trigger.';

CREATE UNIQUE INDEX idx_customer_wallet_ledger_idempotency ON public.customer_wallet_ledger (user_id, idempotency_key);
CREATE INDEX IF NOT EXISTS idx_customer_wallet_ledger_user ON public.customer_wallet_ledger (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_customer_wallet_ledger_reference ON public.customer_wallet_ledger (reference_type, reference_id);

ALTER TABLE public.customer_wallet_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_wallet_ledger FORCE ROW LEVEL SECURITY;

-- ============================================================================
-- 5. Trigger: Maintain cached wallet balance from ledger entries
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_wallet_account_balance()
RETURNS TRIGGER AS $$
DECLARE
    v_delta INTEGER;
BEGIN
    IF NEW.entry_type = 'DEBIT' THEN
        v_delta := -NEW.amount;
    ELSE
        v_delta := NEW.amount;
    END IF;

    UPDATE public.wallet_accounts
    SET cached_balance = cached_balance + v_delta,
        updated_at = NOW()
    WHERE user_id = NEW.user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'WALLET_ACCOUNT_MISSING: No wallet account for user %.', NEW.user_id
            USING ERRCODE = '23503';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_update_wallet_account_balance') THEN
        CREATE TRIGGER trg_update_wallet_account_balance
            AFTER INSERT ON public.customer_wallet_ledger
            FOR EACH ROW
            EXECUTE FUNCTION public.update_wallet_account_balance();
    END IF;
END $$;

REVOKE EXECUTE ON FUNCTION public.update_wallet_account_balance() FROM PUBLIC;

-- ============================================================================
-- 6. Table: public.wallet_deposit_requests
-- Customer deposit request workflow with manual review (OD-FIN-01 Option A).
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.wallet_deposit_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    bank_directory_id UUID REFERENCES public.bank_directory(id) ON DELETE SET NULL,
    amount INTEGER NOT NULL,
    currency TEXT NOT NULL DEFAULT 'YER',
    reference_number TEXT NOT NULL,
    proof_storage_path TEXT,
    status TEXT NOT NULL DEFAULT 'pending',
    reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMPTZ,
    rejection_reason TEXT,
    ledger_entry_id UUID REFERENCES public.customer_wallet_ledger(id) ON DELETE SET NULL,
    idempotency_key UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_wallet_deposit_requests_amount_positive CHECK (amount > 0),
    CONSTRAINT chk_wallet_deposit_requests_currency CHECK (currency IN ('YER')),
    CONSTRAINT chk_wallet_deposit_requests_status CHECK (status IN ('pending', 'under_review', 'approved', 'rejected', 'cancelled')),
    CONSTRAINT chk_wallet_deposit_requests_reference_non_empty CHECK (length(trim(reference_number)) > 0),
    CONSTRAINT chk_wallet_deposit_requests_rejection_length CHECK (rejection_reason IS NULL OR char_length(rejection_reason) <= 500),
    CONSTRAINT chk_wallet_deposit_requests_reviewed_coherence CHECK (
        (status IN ('approved', 'rejected') AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL) OR
        (status IN ('pending', 'under_review', 'cancelled') AND reviewed_by IS NULL AND reviewed_at IS NULL)
    )
);

COMMENT ON TABLE public.wallet_deposit_requests IS 'Customer wallet deposit requests. Approval creates exactly one CREDIT ledger entry (idempotent). No direct client status mutation.';

CREATE UNIQUE INDEX idx_wallet_deposit_requests_idempotency ON public.wallet_deposit_requests (user_id, idempotency_key);
CREATE INDEX IF NOT EXISTS idx_wallet_deposit_requests_user ON public.wallet_deposit_requests (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_wallet_deposit_requests_status ON public.wallet_deposit_requests (status, created_at);

CREATE TRIGGER trg_wallet_deposit_requests_set_updated_at
    BEFORE UPDATE ON public.wallet_deposit_requests
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.wallet_deposit_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_deposit_requests FORCE ROW LEVEL SECURITY;

-- ============================================================================
-- 7. Table: public.purchase_records
-- Immutable customer package purchase history.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.purchase_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    package_id UUID NOT NULL REFERENCES public.network_packages(id) ON DELETE RESTRICT,
    network_id UUID NOT NULL REFERENCES public.networks(id) ON DELETE RESTRICT,
    amount_paid INTEGER NOT NULL,
    currency TEXT NOT NULL DEFAULT 'YER',
    units_purchased INTEGER NOT NULL DEFAULT 1,
    status TEXT NOT NULL DEFAULT 'completed',
    idempotency_key UUID NOT NULL,
    ledger_entry_id UUID REFERENCES public.customer_wallet_ledger(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_purchase_records_amount_positive CHECK (amount_paid > 0),
    CONSTRAINT chk_purchase_records_currency CHECK (currency IN ('YER')),
    CONSTRAINT chk_purchase_records_units_positive CHECK (units_purchased > 0),
    CONSTRAINT chk_purchase_records_status CHECK (status IN ('initiated', 'completed', 'failed', 'refunded'))
);

COMMENT ON TABLE public.purchase_records IS 'Customer package purchase records. Created atomically by purchase_package RPC with wallet debit and inventory consumption.';

CREATE UNIQUE INDEX idx_purchase_records_idempotency ON public.purchase_records (user_id, idempotency_key);
CREATE INDEX IF NOT EXISTS idx_purchase_records_user ON public.purchase_records (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_purchase_records_package ON public.purchase_records (package_id, status);
CREATE INDEX IF NOT EXISTS idx_purchase_records_network ON public.purchase_records (network_id, status);

CREATE TRIGGER trg_purchase_records_set_updated_at
    BEFORE UPDATE ON public.purchase_records
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.purchase_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_records FORCE ROW LEVEL SECURITY;

-- ============================================================================
-- 8. Table: public.card_fulfillment_records
-- Provider-neutral fulfillment boundary. No secrets stored.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.card_fulfillment_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    purchase_id UUID NOT NULL UNIQUE REFERENCES public.purchase_records(id) ON DELETE RESTRICT,
    network_id UUID NOT NULL REFERENCES public.networks(id) ON DELETE RESTRICT,
    package_id UUID NOT NULL REFERENCES public.network_packages(id) ON DELETE RESTRICT,
    status TEXT NOT NULL DEFAULT 'pending',
    secret_payload_storage_path TEXT,
    secret_payload_retrieval_token TEXT,
    fulfilled_at TIMESTAMPTZ,
    quarantined_at TIMESTAMPTZ,
    dispute_window_ends_at TIMESTAMPTZ,
    refund_entry_id UUID REFERENCES public.customer_wallet_ledger(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_card_fulfillment_records_status CHECK (status IN ('pending', 'fulfilled', 'quarantined', 'refunded', 'failed'))
);

COMMENT ON TABLE public.card_fulfillment_records IS 'Provider-neutral card/voucher fulfillment boundary. secret_payload_* fields are NULL until OD-CARD-01 approved and a secure vault configured. No plaintext or encrypted secrets stored in V1.';

CREATE INDEX IF NOT EXISTS idx_card_fulfillment_records_purchase ON public.card_fulfillment_records (purchase_id);
CREATE INDEX IF NOT EXISTS idx_card_fulfillment_records_network ON public.card_fulfillment_records (network_id, status);

CREATE TRIGGER trg_card_fulfillment_records_set_updated_at
    BEFORE UPDATE ON public.card_fulfillment_records
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.card_fulfillment_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.card_fulfillment_records FORCE ROW LEVEL SECURITY;

-- ============================================================================
-- 9. Table: public.refund_requests
-- Refund/dispute hook. Approved refunds create compensating CREDIT entries.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.refund_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    purchase_id UUID NOT NULL REFERENCES public.purchase_records(id) ON DELETE RESTRICT,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    reason TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'submitted',
    support_agent_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    ledger_entry_id UUID REFERENCES public.customer_wallet_ledger(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_refund_requests_reason_non_empty CHECK (length(trim(reason)) > 0),
    CONSTRAINT chk_refund_requests_status CHECK (status IN ('submitted', 'investigating', 'refund_recommended', 'rejected_dispute', 'approved_refund'))
);

COMMENT ON TABLE public.refund_requests IS 'Card purchase refund/dispute requests. Approved refund creates a compensating CREDIT ledger entry; original DEBIT is never modified.';

CREATE INDEX IF NOT EXISTS idx_refund_requests_purchase ON public.refund_requests (purchase_id);
CREATE INDEX IF NOT EXISTS idx_refund_requests_user ON public.refund_requests (user_id, status);

CREATE TRIGGER trg_refund_requests_set_updated_at
    BEFORE UPDATE ON public.refund_requests
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.refund_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refund_requests FORCE ROW LEVEL SECURITY;

-- ============================================================================
-- 10. Table: public.owner_settlement_items
-- Immutable purchase accounting references for later settlement (OD-SETTLE-01).
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.owner_settlement_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    network_id UUID NOT NULL REFERENCES public.networks(id) ON DELETE RESTRICT,
    owner_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    purchase_id UUID NOT NULL UNIQUE REFERENCES public.purchase_records(id) ON DELETE RESTRICT,
    gross_amount INTEGER NOT NULL,
    platform_commission_amount INTEGER NOT NULL DEFAULT 0,
    net_settlement_amount INTEGER NOT NULL,
    settlement_status TEXT NOT NULL DEFAULT 'pending',
    settlement_voucher_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_owner_settlement_items_amounts_positive CHECK (gross_amount >= 0 AND platform_commission_amount >= 0 AND net_settlement_amount >= 0),
    CONSTRAINT chk_owner_settlement_items_net CHECK (net_settlement_amount = gross_amount - platform_commission_amount),
    CONSTRAINT chk_owner_settlement_items_status CHECK (settlement_status IN ('pending', 'included', 'paid', 'disputed'))
);

COMMENT ON TABLE public.owner_settlement_items IS 'Settlement-ready accounting references per purchase. No payout schedule implemented pending OD-SETTLE-01.';

CREATE INDEX IF NOT EXISTS idx_owner_settlement_items_network ON public.owner_settlement_items (network_id, settlement_status);
CREATE INDEX IF NOT EXISTS idx_owner_settlement_items_owner ON public.owner_settlement_items (owner_user_id, settlement_status);

CREATE TRIGGER trg_owner_settlement_items_set_updated_at
    BEFORE UPDATE ON public.owner_settlement_items
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.owner_settlement_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.owner_settlement_items FORCE ROW LEVEL SECURITY;


-- ============================================================================
-- 11. Authorization Helpers
-- ============================================================================

-- Helper: Check if current user is a finance officer
CREATE OR REPLACE FUNCTION public.is_finance_officer()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN public.has_platform_role('finance_officer');
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp;

-- Helper: Check if current user is a support agent
CREATE OR REPLACE FUNCTION public.is_support_agent()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN public.has_platform_role('support_agent');
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.is_finance_officer() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.is_support_agent() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_finance_officer() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_support_agent() TO anon, authenticated;

-- ============================================================================
-- 12. Controlled Commerce RPCs
-- ============================================================================

-- ----------------------------------------------------------------------------
-- RPC: create_wallet_deposit_request
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_wallet_deposit_request(
    p_amount INTEGER,
    p_reference_number TEXT,
    p_bank_directory_id UUID DEFAULT NULL,
    p_proof_storage_path TEXT DEFAULT NULL,
    p_idempotency_key UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_key UUID;
    v_request_id UUID;
    v_existing_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.profiles WHERE id = v_user_id AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'INACTIVE_PROFILE: Account is not active.'
            USING ERRCODE = '42501';
    END IF;

    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'INVALID_AMOUNT: Deposit amount must be positive.'
            USING ERRCODE = '22000';
    END IF;

    IF p_reference_number IS NULL OR length(trim(p_reference_number)) = 0 THEN
        RAISE EXCEPTION 'INVALID_REFERENCE: Reference number is required.'
            USING ERRCODE = '22000';
    END IF;

    v_key := COALESCE(p_idempotency_key, gen_random_uuid());

    -- Idempotent lookup
    SELECT id INTO v_existing_id
    FROM public.wallet_deposit_requests
    WHERE user_id = v_user_id AND idempotency_key = v_key;

    IF v_existing_id IS NOT NULL THEN
        RETURN jsonb_build_object('id', v_existing_id, 'status', 'existing');
    END IF;

    INSERT INTO public.wallet_deposit_requests (
        user_id,
        bank_directory_id,
        amount,
        currency,
        reference_number,
        proof_storage_path,
        status,
        idempotency_key
    ) VALUES (
        v_user_id,
        p_bank_directory_id,
        p_amount,
        'YER',
        trim(p_reference_number),
        p_proof_storage_path,
        'pending',
        v_key
    ) RETURNING id INTO v_request_id;

    RETURN jsonb_build_object('id', v_request_id, 'status', 'pending');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.create_wallet_deposit_request(INTEGER, TEXT, UUID, TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_wallet_deposit_request(INTEGER, TEXT, UUID, TEXT, UUID) TO authenticated;

-- ----------------------------------------------------------------------------
-- RPC: review_wallet_deposit_request
-- Finance officer approves or rejects a deposit. Approval atomically credits wallet.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.review_wallet_deposit_request(
    p_deposit_id UUID,
    p_action TEXT,
    p_rejection_reason TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_deposit public.wallet_deposit_requests%ROWTYPE;
    v_existing_ledger UUID;
    v_ledger_id UUID;
    v_balance_after INTEGER;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.profiles WHERE id = v_user_id AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'INACTIVE_PROFILE: Account is not active.'
            USING ERRCODE = '42501';
    END IF;

    IF NOT public.is_finance_officer() AND NOT public.has_platform_role('platform_admin') THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE: Only finance_officer or platform_admin can review deposits.'
            USING ERRCODE = '42501';
    END IF;

    IF p_action NOT IN ('approve', 'reject') THEN
        RAISE EXCEPTION 'INVALID_ACTION: Action must be approve or reject.'
            USING ERRCODE = '22000';
    END IF;

    IF p_action = 'reject' AND (p_rejection_reason IS NULL OR length(trim(p_rejection_reason)) = 0) THEN
        RAISE EXCEPTION 'REJECTION_REASON_REQUIRED: Rejection requires a reason.'
            USING ERRCODE = '22000';
    END IF;

    -- Lock deposit row for review
    SELECT * INTO v_deposit
    FROM public.wallet_deposit_requests
    WHERE id = p_deposit_id
    FOR UPDATE;

    IF v_deposit.id IS NULL THEN
        RAISE EXCEPTION 'NOT_FOUND: Deposit request not found.'
            USING ERRCODE = '42501';
    END IF;

    -- Idempotency: already approved/rejected returns existing state without double credit
    IF v_deposit.status = 'approved' THEN
        RETURN jsonb_build_object('id', p_deposit_id, 'status', 'approved', 'replayed', TRUE);
    END IF;

    IF v_deposit.status = 'rejected' THEN
        RETURN jsonb_build_object('id', p_deposit_id, 'status', 'rejected', 'replayed', TRUE);
    END IF;

    IF v_deposit.status NOT IN ('pending', 'under_review') THEN
        RAISE EXCEPTION 'INVALID_STATE: Deposit is not reviewable (status=%).', v_deposit.status
            USING ERRCODE = '22000';
    END IF;

    IF p_action = 'reject' THEN
        UPDATE public.wallet_deposit_requests
        SET status = 'rejected',
            reviewed_by = v_user_id,
            reviewed_at = NOW(),
            rejection_reason = trim(p_rejection_reason)
        WHERE id = p_deposit_id;

        RETURN jsonb_build_object('id', p_deposit_id, 'status', 'rejected');
    END IF;

    -- Approve: exactly one credit ledger entry. Check for pre-existing ledger to prevent double credit.
    IF v_deposit.ledger_entry_id IS NOT NULL THEN
        RETURN jsonb_build_object('id', p_deposit_id, 'status', 'approved', 'replayed', TRUE);
    END IF;

    -- Lock wallet account to serialize balance changes for this user
    SELECT cached_balance INTO v_balance_after
    FROM public.wallet_accounts
    WHERE user_id = v_deposit.user_id
    FOR UPDATE;

    IF v_balance_after IS NULL THEN
        RAISE EXCEPTION 'WALLET_ACCOUNT_MISSING: Customer wallet account not found.'
            USING ERRCODE = '42501';
    END IF;

    v_balance_after := v_balance_after + v_deposit.amount;

    INSERT INTO public.customer_wallet_ledger (
        user_id,
        entry_type,
        amount,
        balance_after,
        reference_type,
        reference_id,
        idempotency_key,
        actor_user_id,
        reason_code,
        metadata
    ) VALUES (
        v_deposit.user_id,
        'CREDIT',
        v_deposit.amount,
        v_balance_after,
        'DEPOSIT',
        p_deposit_id,
        gen_random_uuid(),
        v_user_id,
        'DEPOSIT_APPROVED',
        jsonb_build_object('reference_number', v_deposit.reference_number)
    ) RETURNING id INTO v_ledger_id;

    UPDATE public.wallet_deposit_requests
    SET status = 'approved',
        reviewed_by = v_user_id,
        reviewed_at = NOW(),
        ledger_entry_id = v_ledger_id
    WHERE id = p_deposit_id;

    RETURN jsonb_build_object('id', p_deposit_id, 'status', 'approved', 'ledger_entry_id', v_ledger_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.review_wallet_deposit_request(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.review_wallet_deposit_request(UUID, TEXT, TEXT) TO authenticated;

-- ----------------------------------------------------------------------------
-- RPC: purchase_package
-- Atomic package purchase: validate, lock wallet, lock inventory, debit, consume, record.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.purchase_package(
    p_package_id UUID,
    p_idempotency_key UUID
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_package public.network_packages%ROWTYPE;
    v_network public.networks%ROWTYPE;
    v_balance public.wallet_accounts%ROWTYPE;
    v_inventory public.package_inventory_balances%ROWTYPE;
    v_existing_purchase public.purchase_records%ROWTYPE;
    v_ledger_id UUID;
    v_purchase_id UUID;
    v_fulfillment_id UUID;
    v_new_balance INTEGER;
    v_settlement_item_id UUID;
    v_owner_user_id UUID;
    v_commission_rate NUMERIC := 0.05; -- Provisional 5% pending OD-FIN-02
    v_commission_amount INTEGER;
    v_net_amount INTEGER;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.profiles WHERE id = v_user_id AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'INACTIVE_PROFILE: Account is not active.'
            USING ERRCODE = '42501';
    END IF;

    IF p_idempotency_key IS NULL THEN
        RAISE EXCEPTION 'MISSING_IDEMPOTENCY: Idempotency key is required.'
            USING ERRCODE = '22000';
    END IF;

    -- 1. Validate package and network (server-trusted price)
    SELECT * INTO v_package
    FROM public.network_packages
    WHERE id = p_package_id;

    IF v_package.id IS NULL THEN
        RAISE EXCEPTION 'NOT_FOUND: Package not found.'
            USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_network
    FROM public.networks
    WHERE id = v_package.network_id;

    IF v_network.status != 'active' OR v_network.verification_status != 'verified' THEN
        RAISE EXCEPTION 'NETWORK_UNAVAILABLE: Network is not active or verified.'
            USING ERRCODE = '42501';
    END IF;

    IF v_package.status != 'active' OR v_package.is_public != TRUE THEN
        RAISE EXCEPTION 'PACKAGE_UNAVAILABLE: Package is not active or public.'
            USING ERRCODE = '42501';
    END IF;

    IF v_package.price <= 0 THEN
        RAISE EXCEPTION 'INVALID_PRICE: Package price must be positive.'
            USING ERRCODE = '22000';
    END IF;

    -- 2. Idempotency: replay returns original purchase
    SELECT * INTO v_existing_purchase
    FROM public.purchase_records
    WHERE user_id = v_user_id AND idempotency_key = p_idempotency_key;

    IF v_existing_purchase.id IS NOT NULL THEN
        RETURN jsonb_build_object(
            'purchase_id', v_existing_purchase.id,
            'status', v_existing_purchase.status,
            'amount_paid', v_existing_purchase.amount_paid,
            'replayed', TRUE
        );
    END IF;

    -- 3. Lock wallet account and verify balance
    SELECT * INTO v_balance
    FROM public.wallet_accounts
    WHERE user_id = v_user_id
    FOR UPDATE;

    IF v_balance.user_id IS NULL THEN
        RAISE EXCEPTION 'WALLET_ACCOUNT_MISSING: Customer wallet account not found.'
            USING ERRCODE = '42501';
    END IF;

    IF v_balance.cached_balance < v_package.price THEN
        RAISE EXCEPTION 'INSUFFICIENT_BALANCE: Wallet balance is insufficient.'
            USING ERRCODE = '22000';
    END IF;

    -- 4. Lock inventory and verify stock
    SELECT * INTO v_inventory
    FROM public.package_inventory_balances
    WHERE package_id = p_package_id
    FOR UPDATE;

    IF v_inventory.package_id IS NULL THEN
        RAISE EXCEPTION 'INVENTORY_NOT_FOUND: Inventory balance not found.'
            USING ERRCODE = '42501';
    END IF;

    IF v_inventory.available_units <= 0 THEN
        RAISE EXCEPTION 'OUT_OF_STOCK: Package is out of stock.'
            USING ERRCODE = '22000';
    END IF;

    -- 5. Calculate post-transaction balance
    v_new_balance := v_balance.cached_balance - v_package.price;

    -- 6. Insert debit ledger entry (trigger updates cached balance)
    INSERT INTO public.customer_wallet_ledger (
        user_id,
        entry_type,
        amount,
        balance_after,
        reference_type,
        reference_id,
        idempotency_key,
        actor_user_id,
        reason_code,
        metadata
    ) VALUES (
        v_user_id,
        'DEBIT',
        v_package.price,
        v_new_balance,
        'PURCHASE',
        gen_random_uuid(),
        gen_random_uuid(),
        v_user_id,
        'PACKAGE_PURCHASE',
        jsonb_build_object('package_id', p_package_id, 'network_id', v_package.network_id)
    ) RETURNING id INTO v_ledger_id;

    -- 7. Insert purchase record
    INSERT INTO public.purchase_records (
        user_id,
        package_id,
        network_id,
        amount_paid,
        currency,
        units_purchased,
        status,
        idempotency_key,
        ledger_entry_id
    ) VALUES (
        v_user_id,
        p_package_id,
        v_package.network_id,
        v_package.price,
        v_package.currency,
        1,
        'completed',
        p_idempotency_key,
        v_ledger_id
    ) RETURNING id INTO v_purchase_id;

    -- 8. Consume inventory atomically
    INSERT INTO public.package_inventory_movements (
        package_id,
        network_id,
        quantity_change,
        previous_total,
        new_total,
        previous_available,
        new_available,
        reason,
        actor_user_id,
        idempotency_key
    ) VALUES (
        p_package_id,
        v_package.network_id,
        -1,
        v_inventory.total_units,
        v_inventory.total_units - 1,
        v_inventory.available_units,
        v_inventory.available_units - 1,
        'Customer purchase',
        v_user_id,
        gen_random_uuid()
    );

    UPDATE public.package_inventory_balances
    SET total_units = v_inventory.total_units - 1,
        available_units = v_inventory.available_units - 1,
        is_available = (v_inventory.available_units - 1 > 0),
        updated_at = NOW()
    WHERE package_id = p_package_id;

    -- 9. Create provider-neutral fulfillment record (no secrets)
    INSERT INTO public.card_fulfillment_records (
        purchase_id,
        network_id,
        package_id,
        status,
        dispute_window_ends_at
    ) VALUES (
        v_purchase_id,
        v_package.network_id,
        p_package_id,
        'pending',
        NOW() + INTERVAL '24 hours'
    ) RETURNING id INTO v_fulfillment_id;

    -- 10. Settlement-ready accounting reference
    SELECT nm.user_id INTO v_owner_user_id
    FROM public.network_memberships nm
    JOIN public.user_roles ur ON ur.user_id = nm.user_id AND ur.role = 'network_owner'
    WHERE nm.network_id = v_package.network_id
      AND nm.membership_role = 'owner'
      AND nm.status = 'active'
    LIMIT 1;

    v_commission_amount := floor(v_package.price * v_commission_rate)::INTEGER;
    v_net_amount := v_package.price - v_commission_amount;

    INSERT INTO public.owner_settlement_items (
        network_id,
        owner_user_id,
        purchase_id,
        gross_amount,
        platform_commission_amount,
        net_settlement_amount,
        settlement_status
    ) VALUES (
        v_package.network_id,
        COALESCE(v_owner_user_id, v_network.created_by),
        v_purchase_id,
        v_package.price,
        v_commission_amount,
        v_net_amount,
        'pending'
    ) RETURNING id INTO v_settlement_item_id;

    RETURN jsonb_build_object(
        'purchase_id', v_purchase_id,
        'fulfillment_id', v_fulfillment_id,
        'status', 'completed',
        'amount_paid', v_package.price,
        'new_balance', v_new_balance,
        'settlement_item_id', v_settlement_item_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.purchase_package(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.purchase_package(UUID, UUID) TO authenticated;

-- ----------------------------------------------------------------------------
-- RPC: reveal_purchase_fulfillment
-- Fails closed if no secure vault is configured (OD-CARD-01 OPEN).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reveal_purchase_fulfillment(
    p_purchase_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_purchase public.purchase_records%ROWTYPE;
    v_fulfillment public.card_fulfillment_records%ROWTYPE;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    SELECT * INTO v_purchase
    FROM public.purchase_records
    WHERE id = p_purchase_id;

    IF v_purchase.id IS NULL OR v_purchase.user_id != v_user_id THEN
        RAISE EXCEPTION 'NOT_FOUND: Purchase not found.'
            USING ERRCODE = '42501';
    END IF;

    IF v_purchase.status != 'completed' THEN
        RAISE EXCEPTION 'INVALID_STATE: Purchase is not completed.'
            USING ERRCODE = '22000';
    END IF;

    SELECT * INTO v_fulfillment
    FROM public.card_fulfillment_records
    WHERE purchase_id = p_purchase_id;

    -- Fail closed: no secret vault configured in V1 source.
    IF v_fulfillment.secret_payload_retrieval_token IS NULL OR
       v_fulfillment.secret_payload_storage_path IS NULL THEN
        RAISE EXCEPTION 'FULFILLMENT_VAULT_NOT_CONFIGURED: Secure card vault is not configured (OD-CARD-01). Reveal is not available in source-only builds.'
            USING ERRCODE = '55000';
    END IF;

    UPDATE public.card_fulfillment_records
    SET status = 'fulfilled',
        fulfilled_at = NOW()
    WHERE purchase_id = p_purchase_id;

    RETURN jsonb_build_object(
        'purchase_id', p_purchase_id,
        'status', 'fulfilled',
        'masked_secret', '**********',
        'vault_path', v_fulfillment.secret_payload_storage_path
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.reveal_purchase_fulfillment(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reveal_purchase_fulfillment(UUID) TO authenticated;

-- ----------------------------------------------------------------------------
-- RPC: submit_refund_request
-- Customer dispute hook. Does not execute refund.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_refund_request(
    p_purchase_id UUID,
    p_reason TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_purchase public.purchase_records%ROWTYPE;
    v_refund_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    SELECT * INTO v_purchase
    FROM public.purchase_records
    WHERE id = p_purchase_id;

    IF v_purchase.id IS NULL OR v_purchase.user_id != v_user_id THEN
        RAISE EXCEPTION 'NOT_FOUND: Purchase not found.'
            USING ERRCODE = '42501';
    END IF;

    IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
        RAISE EXCEPTION 'REASON_REQUIRED: Refund reason is required.'
            USING ERRCODE = '22000';
    END IF;

    INSERT INTO public.refund_requests (
        purchase_id,
        user_id,
        reason,
        status
    ) VALUES (
        p_purchase_id,
        v_user_id,
        trim(p_reason),
        'submitted'
    ) RETURNING id INTO v_refund_id;

    RETURN jsonb_build_object('id', v_refund_id, 'status', 'submitted');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.submit_refund_request(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_refund_request(UUID, TEXT) TO authenticated;

-- ----------------------------------------------------------------------------
-- RPC: review_refund_request
-- Support agent / admin resolves refund. Approved refunds create compensating CREDIT.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.review_refund_request(
    p_refund_id UUID,
    p_action TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_refund public.refund_requests%ROWTYPE;
    v_purchase public.purchase_records%ROWTYPE;
    v_balance INTEGER;
    v_new_balance INTEGER;
    v_ledger_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.profiles WHERE id = v_user_id AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'INACTIVE_PROFILE: Account is not active.'
            USING ERRCODE = '42501';
    END IF;

    IF NOT public.is_support_agent() AND NOT public.has_platform_role('platform_admin') THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE: Only support_agent or platform_admin can review refunds.'
            USING ERRCODE = '42501';
    END IF;

    IF p_action NOT IN ('approve', 'reject') THEN
        RAISE EXCEPTION 'INVALID_ACTION: Action must be approve or reject.'
            USING ERRCODE = '22000';
    END IF;

    SELECT * INTO v_refund
    FROM public.refund_requests
    WHERE id = p_refund_id
    FOR UPDATE;

    IF v_refund.id IS NULL THEN
        RAISE EXCEPTION 'NOT_FOUND: Refund request not found.'
            USING ERRCODE = '42501';
    END IF;

    IF v_refund.status IN ('approved_refund', 'rejected_dispute') THEN
        RETURN jsonb_build_object('id', p_refund_id, 'status', v_refund.status, 'replayed', TRUE);
    END IF;

    SELECT * INTO v_purchase
    FROM public.purchase_records
    WHERE id = v_refund.purchase_id;

    IF p_action = 'reject' THEN
        UPDATE public.refund_requests
        SET status = 'rejected_dispute',
            support_agent_id = v_user_id,
            updated_at = NOW()
        WHERE id = p_refund_id;

        RETURN jsonb_build_object('id', p_refund_id, 'status', 'rejected_dispute');
    END IF;

    -- Approve: idempotent compensating credit
    IF v_refund.ledger_entry_id IS NOT NULL THEN
        RETURN jsonb_build_object('id', p_refund_id, 'status', 'approved_refund', 'replayed', TRUE);
    END IF;

    SELECT cached_balance INTO v_balance
    FROM public.wallet_accounts
    WHERE user_id = v_purchase.user_id
    FOR UPDATE;

    IF v_balance IS NULL THEN
        RAISE EXCEPTION 'WALLET_ACCOUNT_MISSING: Customer wallet account not found.'
            USING ERRCODE = '42501';
    END IF;

    v_new_balance := v_balance + v_purchase.amount_paid;

    INSERT INTO public.customer_wallet_ledger (
        user_id,
        entry_type,
        amount,
        balance_after,
        reference_type,
        reference_id,
        idempotency_key,
        actor_user_id,
        reason_code,
        metadata
    ) VALUES (
        v_purchase.user_id,
        'CREDIT',
        v_purchase.amount_paid,
        v_new_balance,
        'REFUND',
        p_refund_id,
        gen_random_uuid(),
        v_user_id,
        'REFUND_APPROVED',
        jsonb_build_object('purchase_id', v_purchase.id)
    ) RETURNING id INTO v_ledger_id;

    UPDATE public.refund_requests
    SET status = 'approved_refund',
        support_agent_id = v_user_id,
        ledger_entry_id = v_ledger_id,
        updated_at = NOW()
    WHERE id = p_refund_id;

    UPDATE public.purchase_records
    SET status = 'refunded',
        updated_at = NOW()
    WHERE id = v_purchase.id;

    UPDATE public.card_fulfillment_records
    SET status = 'refunded'
    WHERE purchase_id = v_purchase.id;

    RETURN jsonb_build_object('id', p_refund_id, 'status', 'approved_refund', 'ledger_entry_id', v_ledger_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.review_refund_request(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.review_refund_request(UUID, TEXT) TO authenticated;

-- ----------------------------------------------------------------------------
-- RPC: get_customer_wallet
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_customer_wallet()
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_wallet public.wallet_accounts%ROWTYPE;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    SELECT * INTO v_wallet
    FROM public.wallet_accounts
    WHERE user_id = v_user_id;

    IF v_wallet.user_id IS NULL THEN
        RETURN jsonb_build_object('user_id', v_user_id, 'cached_balance', 0, 'currency', 'YER', 'account_status', 'active');
    END IF;

    RETURN jsonb_build_object(
        'user_id', v_wallet.user_id,
        'cached_balance', v_wallet.cached_balance,
        'currency', v_wallet.currency,
        'account_status', v_wallet.account_status
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.get_customer_wallet() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_customer_wallet() TO authenticated;

-- ----------------------------------------------------------------------------
-- RPC: get_owner_commercial_summary
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_owner_commercial_summary(p_network_id UUID DEFAULT NULL)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_network_ids UUID[];
    v_gross_sales INTEGER := 0;
    v_pending_settlement INTEGER := 0;
    v_total_sold INTEGER := 0;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    IF NOT public.has_platform_role('network_owner') THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE: Only network_owner can view commercial summary.'
            USING ERRCODE = '42501';
    END IF;

    IF p_network_id IS NOT NULL THEN
        IF NOT public.can_manage_network(p_network_id) THEN
            RAISE EXCEPTION 'FORBIDDEN: Not authorized to view this network summary.'
                USING ERRCODE = '42501';
        END IF;
        v_network_ids := ARRAY[p_network_id];
    ELSE
        SELECT ARRAY_AGG(nm.network_id) INTO v_network_ids
        FROM public.network_memberships nm
        JOIN public.profiles p ON p.id = nm.user_id
        JOIN public.user_roles ur ON ur.user_id = nm.user_id AND ur.role = 'network_owner'
        WHERE nm.user_id = v_user_id
          AND nm.membership_role = 'owner'
          AND nm.status = 'active'
          AND p.account_status = 'active';
    END IF;

    IF v_network_ids IS NULL OR array_length(v_network_ids, 1) IS NULL THEN
        RETURN jsonb_build_object('gross_sales', 0, 'pending_settlement', 0, 'total_sold', 0);
    END IF;

    SELECT COALESCE(SUM(gross_amount), 0), COALESCE(SUM(net_settlement_amount), 0), COUNT(*)
    INTO v_gross_sales, v_pending_settlement, v_total_sold
    FROM public.owner_settlement_items
    WHERE network_id = ANY(v_network_ids)
      AND settlement_status IN ('pending', 'included');

    RETURN jsonb_build_object(
        'gross_sales', v_gross_sales,
        'pending_settlement', v_pending_settlement,
        'total_sold', v_total_sold
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.get_owner_commercial_summary(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_owner_commercial_summary(UUID) TO authenticated;

-- ----------------------------------------------------------------------------
-- RPC: get_finance_deposit_queue
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_finance_deposit_queue(p_status TEXT DEFAULT NULL)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_result JSONB;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    IF NOT public.is_finance_officer() AND NOT public.has_platform_role('platform_admin') THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE: Only finance_officer or platform_admin can view deposit queue.'
            USING ERRCODE = '42501';
    END IF;

    SELECT jsonb_agg(row_to_json(t))
    INTO v_result
    FROM (
        SELECT
            d.id,
            d.user_id,
            d.amount,
            d.currency,
            d.reference_number,
            d.proof_storage_path,
            d.status,
            d.created_at,
            p.full_name AS customer_name
        FROM public.wallet_deposit_requests d
        LEFT JOIN public.profiles p ON p.id = d.user_id
        WHERE (p_status IS NULL OR d.status = p_status)
        ORDER BY d.created_at ASC
        LIMIT 200
    ) t;

    RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.get_finance_deposit_queue(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_finance_deposit_queue(TEXT) TO authenticated;

-- ----------------------------------------------------------------------------
-- RPC: get_commerce_admin_summary
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_commerce_admin_summary()
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_total_customer_liability INTEGER := 0;
    v_total_pending_deposits INTEGER := 0;
    v_total_completed_purchases INTEGER := 0;
    v_total_gross_sales INTEGER := 0;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    IF NOT public.has_platform_role('platform_admin') AND NOT public.has_platform_role('system_auditor') THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE: Only platform_admin or system_auditor can view commerce summary.'
            USING ERRCODE = '42501';
    END IF;

    SELECT COALESCE(SUM(cached_balance), 0) INTO v_total_customer_liability
    FROM public.wallet_accounts;

    SELECT COALESCE(SUM(amount), 0) INTO v_total_pending_deposits
    FROM public.wallet_deposit_requests
    WHERE status IN ('pending', 'under_review');

    SELECT COALESCE(SUM(amount_paid), 0), COUNT(*) INTO v_total_gross_sales, v_total_completed_purchases
    FROM public.purchase_records
    WHERE status = 'completed';

    RETURN jsonb_build_object(
        'total_customer_liability', v_total_customer_liability,
        'total_pending_deposits', v_total_pending_deposits,
        'total_completed_purchases', v_total_completed_purchases,
        'total_gross_sales', v_total_gross_sales
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.get_commerce_admin_summary() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_commerce_admin_summary() TO authenticated;


-- ============================================================================
-- 13. Row-Level Security Policies
-- ============================================================================

-- ----------------------------------------------------------------------------
-- bank_directory
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS bank_directory_public_select_policy ON public.bank_directory;
CREATE POLICY bank_directory_public_select_policy ON public.bank_directory
    FOR SELECT
    USING (is_active = TRUE);

DROP POLICY IF EXISTS bank_directory_admin_manage_policy ON public.bank_directory;
CREATE POLICY bank_directory_admin_manage_policy ON public.bank_directory
    FOR ALL
    USING (public.has_platform_role('platform_admin'))
    WITH CHECK (public.has_platform_role('platform_admin'));

-- ----------------------------------------------------------------------------
-- wallet_accounts
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS wallet_accounts_owner_select_policy ON public.wallet_accounts;
CREATE POLICY wallet_accounts_owner_select_policy ON public.wallet_accounts
    FOR SELECT
    USING (
        user_id = auth.uid()
        OR public.is_finance_officer()
        OR public.has_platform_role('platform_admin')
        OR public.has_platform_role('system_auditor')
    );

-- No direct UPDATE policy. Balance maintained exclusively by ledger trigger.

-- ----------------------------------------------------------------------------
-- customer_wallet_ledger
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS customer_wallet_ledger_owner_select_policy ON public.customer_wallet_ledger;
CREATE POLICY customer_wallet_ledger_owner_select_policy ON public.customer_wallet_ledger
    FOR SELECT
    USING (
        user_id = auth.uid()
        OR public.is_finance_officer()
        OR public.has_platform_role('platform_admin')
        OR public.has_platform_role('system_auditor')
    );

-- No direct INSERT/UPDATE/DELETE. Entries created exclusively by controlled RPCs.

-- ----------------------------------------------------------------------------
-- wallet_deposit_requests
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS wallet_deposit_requests_owner_select_policy ON public.wallet_deposit_requests;
CREATE POLICY wallet_deposit_requests_owner_select_policy ON public.wallet_deposit_requests
    FOR SELECT
    USING (
        user_id = auth.uid()
        OR public.is_finance_officer()
        OR public.has_platform_role('platform_admin')
        OR public.has_platform_role('system_auditor')
    );

-- No direct INSERT/UPDATE. Requests created via create_wallet_deposit_request; reviewed via review_wallet_deposit_request.

-- ----------------------------------------------------------------------------
-- purchase_records
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS purchase_records_owner_select_policy ON public.purchase_records;
CREATE POLICY purchase_records_owner_select_policy ON public.purchase_records
    FOR SELECT
    USING (
        user_id = auth.uid()
        OR public.can_operate_package_network(network_id)
        OR public.has_platform_role('platform_admin')
        OR public.has_platform_role('system_auditor')
    );

-- No direct INSERT/UPDATE. Purchases created exclusively via purchase_package RPC.

-- ----------------------------------------------------------------------------
-- card_fulfillment_records
-- ----------------------------------------------------------------------------
-- Purchase owners can see their fulfillment status (no secret columns).
-- Secret reveal is strictly through reveal_purchase_fulfillment RPC, which fails
-- closed when no secure vault is configured (OD-CARD-01 OPEN).
DROP POLICY IF EXISTS card_fulfillment_records_owner_select_policy ON public.card_fulfillment_records;
CREATE POLICY card_fulfillment_records_owner_select_policy ON public.card_fulfillment_records
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.purchase_records pr
            WHERE pr.id = public.card_fulfillment_records.purchase_id
              AND pr.user_id = auth.uid()
        )
        OR public.has_platform_role('platform_admin')
        OR public.has_platform_role('system_auditor')
    );

-- No direct INSERT/UPDATE/DELETE. Records are created exclusively by purchase_package RPC.

-- ----------------------------------------------------------------------------
-- refund_requests
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS refund_requests_owner_select_policy ON public.refund_requests;
CREATE POLICY refund_requests_owner_select_policy ON public.refund_requests
    FOR SELECT
    USING (
        user_id = auth.uid()
        OR public.is_support_agent()
        OR public.has_platform_role('platform_admin')
        OR public.has_platform_role('system_auditor')
    );

-- No direct INSERT/UPDATE. Created via submit_refund_request; reviewed via review_refund_request.

-- ----------------------------------------------------------------------------
-- owner_settlement_items
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS owner_settlement_items_owner_select_policy ON public.owner_settlement_items;
CREATE POLICY owner_settlement_items_owner_select_policy ON public.owner_settlement_items
    FOR SELECT
    USING (
        owner_user_id = auth.uid()
        OR public.is_finance_officer()
        OR public.has_platform_role('platform_admin')
        OR public.has_platform_role('system_auditor')
    );

-- No direct INSERT/UPDATE. Created exclusively by purchase_package RPC.

-- ============================================================================
-- 14. Least-Privilege Table Grants
-- Default privileges were hardened by Operations Closure; explicit grants below
-- document the intended client surface for commerce tables.
-- ============================================================================

-- bank_directory
REVOKE ALL ON TABLE public.bank_directory FROM PUBLIC;
REVOKE ALL ON TABLE public.bank_directory FROM anon;
REVOKE ALL ON TABLE public.bank_directory FROM authenticated;
GRANT SELECT ON TABLE public.bank_directory TO anon;
GRANT SELECT ON TABLE public.bank_directory TO authenticated;

-- wallet_accounts
REVOKE ALL ON TABLE public.wallet_accounts FROM PUBLIC;
REVOKE ALL ON TABLE public.wallet_accounts FROM anon;
REVOKE ALL ON TABLE public.wallet_accounts FROM authenticated;
GRANT SELECT ON TABLE public.wallet_accounts TO authenticated;

-- customer_wallet_ledger
REVOKE ALL ON TABLE public.customer_wallet_ledger FROM PUBLIC;
REVOKE ALL ON TABLE public.customer_wallet_ledger FROM anon;
REVOKE ALL ON TABLE public.customer_wallet_ledger FROM authenticated;
GRANT SELECT ON TABLE public.customer_wallet_ledger TO authenticated;

-- wallet_deposit_requests
REVOKE ALL ON TABLE public.wallet_deposit_requests FROM PUBLIC;
REVOKE ALL ON TABLE public.wallet_deposit_requests FROM anon;
REVOKE ALL ON TABLE public.wallet_deposit_requests FROM authenticated;
GRANT SELECT ON TABLE public.wallet_deposit_requests TO authenticated;

-- purchase_records
REVOKE ALL ON TABLE public.purchase_records FROM PUBLIC;
REVOKE ALL ON TABLE public.purchase_records FROM anon;
REVOKE ALL ON TABLE public.purchase_records FROM authenticated;
GRANT SELECT ON TABLE public.purchase_records TO authenticated;

-- card_fulfillment_records
REVOKE ALL ON TABLE public.card_fulfillment_records FROM PUBLIC;
REVOKE ALL ON TABLE public.card_fulfillment_records FROM anon;
REVOKE ALL ON TABLE public.card_fulfillment_records FROM authenticated;
-- SELECT restricted to purchase owner by RLS; secret payload columns are never
-- returned because the client uses a column-limited SELECT.
GRANT SELECT ON TABLE public.card_fulfillment_records TO authenticated;

-- refund_requests
REVOKE ALL ON TABLE public.refund_requests FROM PUBLIC;
REVOKE ALL ON TABLE public.refund_requests FROM anon;
REVOKE ALL ON TABLE public.refund_requests FROM authenticated;
GRANT SELECT ON TABLE public.refund_requests TO authenticated;

-- owner_settlement_items
REVOKE ALL ON TABLE public.owner_settlement_items FROM PUBLIC;
REVOKE ALL ON TABLE public.owner_settlement_items FROM anon;
REVOKE ALL ON TABLE public.owner_settlement_items FROM authenticated;
GRANT SELECT ON TABLE public.owner_settlement_items TO authenticated;

-- ============================================================================
-- 15. Lock down internal trigger functions
-- ============================================================================
REVOKE EXECUTE ON FUNCTION public.update_wallet_account_balance() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.initialize_wallet_account() FROM anon, authenticated;
