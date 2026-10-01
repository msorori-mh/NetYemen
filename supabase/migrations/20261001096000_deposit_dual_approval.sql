-- Second approver for large deposits (review finding H-4, THR-23).
--
-- Deposits at or above deposit_dual_approval_threshold() (50,000 YER, the
-- figure in NETYEMEN-THREAT-AND-FRAUD-MODEL-01 THR-23) need two different
-- reviewers (finance_officer or platform_admin). The first approval records
-- first_approved_by and moves the request to under_review without crediting;
-- the second approval by someone else credits the wallet. Rejection is
-- possible at either stage. The requester can never review (see
-- 20261001093000_deposit_review_integrity.sql).
--
-- To change the threshold, replace deposit_dual_approval_threshold() in a
-- new migration.

CREATE OR REPLACE FUNCTION public.deposit_dual_approval_threshold()
RETURNS INTEGER
LANGUAGE sql IMMUTABLE
SET search_path = public, pg_temp
AS $$ SELECT 50000 $$;
REVOKE EXECUTE ON FUNCTION public.deposit_dual_approval_threshold() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.deposit_dual_approval_threshold() TO authenticated;

ALTER TABLE public.wallet_deposit_requests
    ADD COLUMN IF NOT EXISTS first_approved_by UUID REFERENCES auth.users(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS first_approved_at TIMESTAMPTZ;
ALTER TABLE public.wallet_deposit_requests
    DROP CONSTRAINT IF EXISTS chk_wallet_deposit_requests_second_approver;
ALTER TABLE public.wallet_deposit_requests
    ADD CONSTRAINT chk_wallet_deposit_requests_second_approver
    CHECK (status <> 'approved' OR first_approved_by IS NULL OR reviewed_by <> first_approved_by);

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

    -- Separation of duties: staff cannot review their own deposits.
    IF v_deposit.user_id = v_user_id THEN
        RAISE EXCEPTION 'SELF_REVIEW_FORBIDDEN: A deposit cannot be reviewed by its requester.'
            USING ERRCODE = '42501';
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

    -- The same bank transfer reference may only be credited once per
    -- destination (THR-09). The unique index below backs this up under
    -- concurrent approvals.
    IF EXISTS (
        SELECT 1
        FROM public.wallet_deposit_requests d
        WHERE d.id <> p_deposit_id
          AND d.status = 'approved'
          AND d.bank_directory_id IS NOT DISTINCT FROM v_deposit.bank_directory_id
          AND lower(trim(d.reference_number)) = lower(trim(v_deposit.reference_number))
    ) THEN
        RAISE EXCEPTION 'DUPLICATE_REFERENCE: This transfer reference was already credited.'
            USING ERRCODE = '23505';
    END IF;

    -- Four-eyes rule for large deposits (THR-23): the first approval only
    -- records the approver and moves the request to under_review; a second,
    -- different reviewer credits the wallet.
    IF v_deposit.amount >= public.deposit_dual_approval_threshold() THEN
        IF v_deposit.first_approved_by IS NULL THEN
            UPDATE public.wallet_deposit_requests
            SET status = 'under_review',
                first_approved_by = v_user_id,
                first_approved_at = NOW()
            WHERE id = p_deposit_id;

            RETURN jsonb_build_object(
                'id', p_deposit_id,
                'status', 'under_review',
                'requires_second_approval', TRUE
            );
        ELSIF v_deposit.first_approved_by = v_user_id THEN
            -- Same reviewer again (e.g. a retried request): nothing changes.
            RETURN jsonb_build_object(
                'id', p_deposit_id,
                'status', 'under_review',
                'requires_second_approval', TRUE,
                'replayed', TRUE
            );
        END IF;
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
        jsonb_build_object(
            'reference_number', v_deposit.reference_number,
            'first_approved_by', v_deposit.first_approved_by
        )
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

REVOKE EXECUTE ON FUNCTION public.review_wallet_deposit_request(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.review_wallet_deposit_request(UUID, TEXT, TEXT) TO authenticated;
