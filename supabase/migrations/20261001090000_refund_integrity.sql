-- Refund integrity (review finding C-2).
--
-- Before this migration a single purchase could be refunded many times:
--   * submit_refund_request accepted any number of requests per purchase,
--     regardless of purchase status;
--   * review_refund_request never re-checked the purchase status, so every
--     approval credited amount_paid again (with a random ledger key);
--   * the reviewer could approve a refund they had requested themselves;
--   * the refunded card stayed revealable.
--
-- This migration:
--   1. allows at most one live (non-rejected) refund request per purchase;
--   2. allows at most one REFUND credit per refund request in the ledger;
--   3. only accepts/approves refunds for purchases in status 'completed',
--      locking the purchase row so concurrent approvals serialize;
--   4. honours the recorded dispute window (card_fulfillment_records
--      .dispute_window_ends_at) when one is set;
--   5. forbids self-review;
--   6. uses a deterministic ledger idempotency key per refund request;
--   7. quarantines the card on approval (reveal already refuses quarantined
--      cards).

-- ----------------------------------------------------------------------------
-- 1/2. Uniqueness guards. Fail loudly instead of silently rewriting financial
-- history if duplicates already exist; an operator must resolve them first.
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.refund_requests
        WHERE status <> 'rejected_dispute'
        GROUP BY purchase_id
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'REFUND_INTEGRITY_PRECHECK: duplicate live refund requests exist for at least one purchase; resolve them before applying this migration.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.customer_wallet_ledger
        WHERE reference_type = 'REFUND'
        GROUP BY reference_id
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'REFUND_INTEGRITY_PRECHECK: a refund request has more than one ledger credit; resolve before applying this migration.';
    END IF;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_refund_requests_one_live_per_purchase
    ON public.refund_requests (purchase_id)
    WHERE status <> 'rejected_dispute';

CREATE UNIQUE INDEX IF NOT EXISTS uq_customer_wallet_ledger_one_credit_per_refund
    ON public.customer_wallet_ledger (reference_id)
    WHERE reference_type = 'REFUND';

-- ----------------------------------------------------------------------------
-- 3/4. submit_refund_request
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_refund_request(
    p_purchase_id UUID,
    p_reason TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_purchase public.purchase_records%ROWTYPE;
    v_existing public.refund_requests%ROWTYPE;
    v_window_ends_at TIMESTAMPTZ;
    v_refund_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    -- Lock the purchase so concurrent submissions serialize.
    SELECT * INTO v_purchase
    FROM public.purchase_records
    WHERE id = p_purchase_id
    FOR UPDATE;

    IF v_purchase.id IS NULL OR v_purchase.user_id != v_user_id THEN
        RAISE EXCEPTION 'NOT_FOUND: Purchase not found.'
            USING ERRCODE = '42501';
    END IF;

    IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
        RAISE EXCEPTION 'REASON_REQUIRED: Refund reason is required.'
            USING ERRCODE = '22000';
    END IF;

    -- One live request per purchase: return the existing one (idempotent).
    SELECT * INTO v_existing
    FROM public.refund_requests
    WHERE purchase_id = p_purchase_id
      AND status <> 'rejected_dispute'
    LIMIT 1;

    IF v_existing.id IS NOT NULL THEN
        RETURN jsonb_build_object('id', v_existing.id, 'status', v_existing.status, 'replayed', TRUE);
    END IF;

    IF v_purchase.status <> 'completed' THEN
        RAISE EXCEPTION 'PURCHASE_NOT_REFUNDABLE: Purchase is not eligible for a refund.'
            USING ERRCODE = '22000';
    END IF;

    SELECT dispute_window_ends_at INTO v_window_ends_at
    FROM public.card_fulfillment_records
    WHERE purchase_id = p_purchase_id;

    IF v_window_ends_at IS NOT NULL AND NOW() > v_window_ends_at THEN
        RAISE EXCEPTION 'DISPUTE_WINDOW_CLOSED: The dispute window for this purchase has ended.'
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

REVOKE EXECUTE ON FUNCTION public.submit_refund_request(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_refund_request(UUID, TEXT) TO authenticated;

-- ----------------------------------------------------------------------------
-- 3/5/6/7. review_refund_request
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

    IF v_refund.user_id = v_user_id THEN
        RAISE EXCEPTION 'SELF_REVIEW_FORBIDDEN: A refund cannot be reviewed by its requester.'
            USING ERRCODE = '42501';
    END IF;

    -- Lock the purchase: concurrent approvals of different requests for the
    -- same purchase serialize here and the second one sees status 'refunded'.
    SELECT * INTO v_purchase
    FROM public.purchase_records
    WHERE id = v_refund.purchase_id
    FOR UPDATE;

    IF p_action = 'reject' THEN
        UPDATE public.refund_requests
        SET status = 'rejected_dispute',
            support_agent_id = v_user_id,
            updated_at = NOW()
        WHERE id = p_refund_id;

        RETURN jsonb_build_object('id', p_refund_id, 'status', 'rejected_dispute');
    END IF;

    IF v_refund.ledger_entry_id IS NOT NULL THEN
        RETURN jsonb_build_object('id', p_refund_id, 'status', 'approved_refund', 'replayed', TRUE);
    END IF;

    IF v_purchase.id IS NULL OR v_purchase.status <> 'completed' THEN
        RAISE EXCEPTION 'PURCHASE_NOT_REFUNDABLE: Purchase is not eligible for a refund.'
            USING ERRCODE = '22000';
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
        -- Deterministic per refund request: a retried approval collides on
        -- (user_id, idempotency_key) instead of crediting twice.
        md5('refund-credit:' || p_refund_id::TEXT)::UUID,
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

    -- The refunded card must not be revealable or resold.
    UPDATE public.card_vault
    SET state = 'quarantined'
    WHERE purchase_id = v_purchase.id
      AND state <> 'invalidated';

    RETURN jsonb_build_object('id', p_refund_id, 'status', 'approved_refund', 'ledger_entry_id', v_ledger_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.review_refund_request(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.review_refund_request(UUID, TEXT) TO authenticated;
