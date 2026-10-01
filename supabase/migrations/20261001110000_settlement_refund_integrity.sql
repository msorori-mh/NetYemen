-- Settlement refund integrity (review finding M-1).
--
-- finance_create_settlement_batch (20260808210000_netyemen_v1_external_pilot_binding.sql)
-- built refund deduction lines incorrectly:
--   (a) every approved refund was deducted from the owner, even when the
--       refunded sale had never been included in a batch / paid to the owner.
--       review_refund_request moves the purchase to status 'refunded', so such
--       a sale is never settled; deducting its refund charged the owner for
--       money they never received;
--   (b) refunds were only collected inside network/owner groups that had
--       pending sales in the period, and only when rr.updated_at fell inside
--       the period, so a refund approved in a week without sales for that
--       network was never deducted by any later batch;
--   (c) the NOT EXISTS duplicate guard on refund lines had neither a lock nor
--       a unique constraint, so two concurrent batch runs could each insert a
--       deduction line for the same refund.
--
-- This migration:
--   1. adds a unique index on settlement_batch_lines (line_type, reference_id)
--      so a sale/refund/adjustment reference can only ever appear once per
--      line type, after a precheck that aborts if existing data violates it;
--   2. re-creates finance_create_settlement_batch so that it
--      * serializes concurrent runs with a transaction-scoped advisory lock;
--      * selects refund lines independently of sales: any approved refund
--        (with a ledger credit) not yet deducted, approved on or before
--        period_end, whose sale is already included in a non-cancelled batch
--        or paid; the deduction goes to the network/owner the sale was
--        settled to;
--      * creates a batch for a network/owner that has only refund deductions
--        in the period (net_settlement may then be negative: owner owes).
--   Everything else (authorization, sale selection, amounts, totals, return
--   shape, grants) is unchanged.

-- ----------------------------------------------------------------------------
-- 1. Uniqueness guard for batch lines.
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.settlement_batch_lines
        WHERE reference_id IS NOT NULL
        GROUP BY line_type, reference_id
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'SETTLEMENT_LINE_INTEGRITY_PRECHECK: at least one sale/refund/adjustment reference appears in more than one settlement_batch_lines row of the same line_type; resolve the duplicate settlement lines (and the affected batch totals) before applying this migration.';
    END IF;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_settlement_batch_lines_type_reference
    ON public.settlement_batch_lines (line_type, reference_id);

-- The unique index serves every lookup the old non-unique one did.
DROP INDEX IF EXISTS public.idx_settlement_batch_lines_reference;

-- ----------------------------------------------------------------------------
-- 2. RPC: finance_create_settlement_batch
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.finance_create_settlement_batch(
    p_period_start DATE,
    p_period_end DATE,
    p_network_id UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_group RECORD;
    v_batch_id UUID;
    v_batch_count INTEGER := 0;
    v_total_sales INTEGER := 0;
    v_total_refunds INTEGER := 0;
    v_gross INTEGER;
    v_commission INTEGER;
    v_net INTEGER;
    v_refunds INTEGER := 0;
    v_purchase RECORD;
    v_refund RECORD;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.' USING ERRCODE = '28000';
    END IF;

    IF NOT public.is_finance_or_admin() THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE: Only finance_officer or platform_admin can create settlement batches.'
            USING ERRCODE = '42501';
    END IF;

    IF p_period_start IS NULL OR p_period_end IS NULL OR p_period_start > p_period_end THEN
        RAISE EXCEPTION 'INVALID_PERIOD: period_start must be <= period_end.' USING ERRCODE = '22000';
    END IF;

    -- Serialize batch creation: a concurrent run waits here and, once the
    -- first commits, its statements see the lines/items that run created.
    -- uq_settlement_batch_lines_type_reference is the backstop.
    PERFORM pg_advisory_xact_lock(hashtext('public.finance_create_settlement_batch'));

    -- Process each network/owner group that has eligible sales in the period
    -- or refund deductions outstanding up to period_end.
    FOR v_group IN
        SELECT g.network_id, g.owner_user_id
        FROM (
            SELECT
                osi.network_id,
                osi.owner_user_id
            FROM public.owner_settlement_items osi
            JOIN public.purchase_records pr ON pr.id = osi.purchase_id
            WHERE osi.settlement_batch_id IS NULL
              AND osi.settlement_status = 'pending'
              AND pr.status = 'completed'
              AND pr.created_at::DATE BETWEEN p_period_start AND p_period_end
              AND (p_network_id IS NULL OR osi.network_id = p_network_id)

            UNION

            SELECT
                osi.network_id,
                osi.owner_user_id
            FROM public.refund_requests rr
            JOIN public.owner_settlement_items osi ON osi.purchase_id = rr.purchase_id
            JOIN public.settlement_batches sb ON sb.id = osi.settlement_batch_id
            WHERE rr.status = 'approved_refund'
              AND rr.ledger_entry_id IS NOT NULL
              AND rr.updated_at::DATE <= p_period_end
              AND osi.settlement_status IN ('included', 'paid')
              AND sb.status <> 'cancelled'
              AND (p_network_id IS NULL OR osi.network_id = p_network_id)
              AND NOT EXISTS (
                  SELECT 1 FROM public.settlement_batch_lines sbl
                  WHERE sbl.line_type = 'refund' AND sbl.reference_id = rr.id
              )
        ) g
        ORDER BY g.network_id, g.owner_user_id
    LOOP
        v_gross := 0;
        v_commission := 0;
        v_net := 0;
        v_refunds := 0;

        INSERT INTO public.settlement_batches (
            period_start,
            period_end,
            network_id,
            owner_user_id,
            status,
            created_by
        ) VALUES (
            p_period_start,
            p_period_end,
            v_group.network_id,
            v_group.owner_user_id,
            'draft',
            v_user_id
        ) RETURNING id INTO v_batch_id;

        -- Sale lines
        FOR v_purchase IN
            SELECT
                osi.id AS settlement_item_id,
                pr.id AS purchase_id,
                pr.gross_amount,
                pr.commission_amount,
                pr.owner_net_amount
            FROM public.owner_settlement_items osi
            JOIN public.purchase_records pr ON pr.id = osi.purchase_id
            WHERE osi.network_id = v_group.network_id
              AND osi.owner_user_id = v_group.owner_user_id
              AND osi.settlement_batch_id IS NULL
              AND osi.settlement_status = 'pending'
              AND pr.status = 'completed'
              AND pr.created_at::DATE BETWEEN p_period_start AND p_period_end
            FOR UPDATE OF osi
        LOOP
            INSERT INTO public.settlement_batch_lines (
                settlement_batch_id,
                line_type,
                reference_id,
                gross_amount,
                commission_amount,
                net_amount
            ) VALUES (
                v_batch_id,
                'sale',
                v_purchase.purchase_id,
                v_purchase.gross_amount,
                v_purchase.commission_amount,
                v_purchase.owner_net_amount
            );

            UPDATE public.owner_settlement_items
            SET settlement_batch_id = v_batch_id,
                settlement_status = 'included',
                updated_at = NOW()
            WHERE id = v_purchase.settlement_item_id;

            v_gross := v_gross + v_purchase.gross_amount;
            v_commission := v_commission + v_purchase.commission_amount;
            v_net := v_net + v_purchase.owner_net_amount;
        END LOOP;

        -- Refund lines: approved refunds not yet deducted, approved on or
        -- before period_end, whose sale was already settled to this owner
        -- (included in a non-cancelled batch, or paid). A refund for a sale
        -- that was never settled is not deducted: the owner never received it.
        FOR v_refund IN
            SELECT
                rr.id AS refund_id,
                pr.id AS purchase_id,
                pr.amount_paid
            FROM public.refund_requests rr
            JOIN public.purchase_records pr ON pr.id = rr.purchase_id
            JOIN public.owner_settlement_items osi ON osi.purchase_id = rr.purchase_id
            JOIN public.settlement_batches sb ON sb.id = osi.settlement_batch_id
            WHERE rr.status = 'approved_refund'
              AND rr.ledger_entry_id IS NOT NULL
              AND rr.updated_at::DATE <= p_period_end
              AND osi.network_id = v_group.network_id
              AND osi.owner_user_id = v_group.owner_user_id
              AND osi.settlement_status IN ('included', 'paid')
              AND sb.status <> 'cancelled'
              AND NOT EXISTS (
                  SELECT 1 FROM public.settlement_batch_lines sbl
                  WHERE sbl.line_type = 'refund' AND sbl.reference_id = rr.id
              )
            ORDER BY rr.updated_at, rr.id
        LOOP
            INSERT INTO public.settlement_batch_lines (
                settlement_batch_id,
                line_type,
                reference_id,
                gross_amount,
                commission_amount,
                net_amount
            ) VALUES (
                v_batch_id,
                'refund',
                v_refund.refund_id,
                v_refund.amount_paid,
                0,
                -v_refund.amount_paid
            );

            v_refunds := v_refunds + v_refund.amount_paid;
        END LOOP;

        UPDATE public.settlement_batches
        SET gross_sales = v_gross,
            total_commission = v_commission,
            total_refunds = v_refunds,
            total_adjustments = 0,
            net_settlement = v_gross - v_commission - v_refunds + 0,
            updated_at = NOW()
        WHERE id = v_batch_id;

        v_total_sales := v_total_sales + v_gross;
        v_total_refunds := v_total_refunds + v_refunds;
        v_batch_count := v_batch_count + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'batches_created', v_batch_count,
        'total_gross_sales', v_total_sales,
        'total_refunds', v_total_refunds
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.finance_create_settlement_batch(DATE, DATE, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finance_create_settlement_batch(DATE, DATE, UUID) TO authenticated;
