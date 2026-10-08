-- Settlement and refund integrity.
--
-- Problems fixed (see docs/reports audit of 2026-10-08):
--  * A purchase refunded BEFORE it was ever settled was skipped as a sale
--    (status = 'refunded') but its refund was still deducted in full, so the
--    owner paid back money that was never credited.
--  * A refund of an already settled sale deducted the gross amount although the
--    owner had only been credited gross minus commission.
--  * Refunds were only picked up for networks that also had new sales in the
--    period; otherwise the platform silently absorbed them.
--  * Refund lines were matched by network only, not by the owner that was paid.
--  * Draft batches could not be cancelled, "paid" needed no payment reference,
--    and none of the settlement steps was audited.
--
-- Accounting rule from now on: a refund reverses exactly what the sale gave
-- each party. The platform gives back its commission and the owner gives back
-- the net amount they were credited.
--   sale line   : gross  G, commission  C, net  +(G - C)
--   refund line : gross  G, commission  C, net  -(G - C)
-- settlement_batches.total_refunds is the sum of the net amounts clawed back,
-- which keeps chk_settlement_batches_net
--   net = gross_sales - total_commission - total_refunds + total_adjustments.
-- A sale that is refunded before any batch includes it is voided: it produces
-- neither a sale line nor a refund line.

ALTER TABLE public.owner_settlement_items
    DROP CONSTRAINT IF EXISTS chk_owner_settlement_items_status;
ALTER TABLE public.owner_settlement_items
    ADD CONSTRAINT chk_owner_settlement_items_status
    CHECK (settlement_status IN ('pending', 'included', 'paid', 'disputed', 'voided'));

COMMENT ON COLUMN public.owner_settlement_items.settlement_status IS
    'pending: not yet in a batch. included: in a draft/approved batch. paid: batch paid. '
    'voided: the sale was refunded before it was ever settled, nothing is owed either way.';

-- Void the unsettled settlement item the moment its purchase is refunded.
CREATE OR REPLACE FUNCTION public.void_settlement_item_on_refund()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE public.owner_settlement_items
    SET settlement_status = 'voided',
        updated_at = NOW()
    WHERE purchase_id = NEW.id
      AND settlement_status = 'pending'
      AND settlement_batch_id IS NULL;
    RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.void_settlement_item_on_refund() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_purchase_refund_voids_settlement ON public.purchase_records;
CREATE TRIGGER trg_purchase_refund_voids_settlement
    AFTER UPDATE OF status ON public.purchase_records
    FOR EACH ROW
    WHEN (NEW.status = 'refunded' AND OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION public.void_settlement_item_on_refund();

-- Existing data: sales already refunded while still unsettled.
UPDATE public.owner_settlement_items osi
SET settlement_status = 'voided',
    updated_at = NOW()
FROM public.purchase_records pr
WHERE pr.id = osi.purchase_id
  AND pr.status = 'refunded'
  AND osi.settlement_status = 'pending'
  AND osi.settlement_batch_id IS NULL;

CREATE OR REPLACE FUNCTION public.finance_create_settlement_batch(
    p_period_start DATE,
    p_period_end DATE,
    p_network_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id UUID;
    v_group RECORD;
    v_batch_id UUID;
    v_batch_count INTEGER := 0;
    v_total_sales BIGINT := 0;
    v_total_refunds BIGINT := 0;
    v_gross INTEGER;
    v_commission INTEGER;
    v_refunds INTEGER;
    v_lines INTEGER;
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

    -- One batch run at a time: a sale or a refund can never land in two batches.
    PERFORM pg_advisory_xact_lock(hashtextextended('netyemen.finance_create_settlement_batch', 0));

    FOR v_group IN
        SELECT g.network_id, g.owner_user_id
        FROM (
            -- Owners with unsettled completed sales in the period.
            SELECT osi.network_id, osi.owner_user_id
            FROM public.owner_settlement_items osi
            JOIN public.purchase_records pr ON pr.id = osi.purchase_id
            WHERE osi.settlement_batch_id IS NULL
              AND osi.settlement_status = 'pending'
              AND pr.status = 'completed'
              AND pr.created_at::DATE BETWEEN p_period_start AND p_period_end
              AND (p_network_id IS NULL OR osi.network_id = p_network_id)
            UNION
            -- Owners who were credited for a sale that was refunded afterwards
            -- and has not been clawed back yet, even without any new sale.
            SELECT osi.network_id, osi.owner_user_id
            FROM public.refund_requests rr
            JOIN public.purchase_records pr ON pr.id = rr.purchase_id
            JOIN public.owner_settlement_items osi ON osi.purchase_id = pr.id
            WHERE rr.status = 'approved_refund'
              AND rr.ledger_entry_id IS NOT NULL
              AND osi.settlement_status IN ('included', 'paid')
              AND rr.updated_at::DATE <= p_period_end
              AND (p_network_id IS NULL OR osi.network_id = p_network_id)
              AND NOT EXISTS (
                  SELECT 1
                  FROM public.settlement_batch_lines sbl
                  JOIN public.settlement_batches sb ON sb.id = sbl.settlement_batch_id
                  WHERE sbl.line_type = 'refund'
                    AND sbl.reference_id = rr.id
                    AND sb.status <> 'cancelled'
              )
        ) g
        ORDER BY g.network_id, g.owner_user_id
    LOOP
        v_gross := 0;
        v_commission := 0;
        v_refunds := 0;
        v_lines := 0;

        INSERT INTO public.settlement_batches (
            period_start, period_end, network_id, owner_user_id, status, created_by
        ) VALUES (
            p_period_start, p_period_end, v_group.network_id, v_group.owner_user_id, 'draft', v_user_id
        ) RETURNING id INTO v_batch_id;

        -- Sale lines.
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
            ORDER BY pr.created_at, pr.id
            FOR UPDATE OF osi
        LOOP
            INSERT INTO public.settlement_batch_lines (
                settlement_batch_id, line_type, reference_id,
                gross_amount, commission_amount, net_amount
            ) VALUES (
                v_batch_id, 'sale', v_purchase.purchase_id,
                v_purchase.gross_amount, v_purchase.commission_amount, v_purchase.owner_net_amount
            );

            UPDATE public.owner_settlement_items
            SET settlement_batch_id = v_batch_id,
                settlement_status = 'included',
                updated_at = NOW()
            WHERE id = v_purchase.settlement_item_id;

            v_gross := v_gross + v_purchase.gross_amount;
            v_commission := v_commission + v_purchase.commission_amount;
            v_lines := v_lines + 1;
        END LOOP;

        -- Refund lines: claw back exactly the net amount this owner was
        -- credited for a sale that was refunded after it had been settled.
        FOR v_refund IN
            SELECT
                rr.id AS refund_id,
                pr.gross_amount,
                pr.commission_amount,
                pr.owner_net_amount
            FROM public.refund_requests rr
            JOIN public.purchase_records pr ON pr.id = rr.purchase_id
            JOIN public.owner_settlement_items osi ON osi.purchase_id = pr.id
            WHERE rr.status = 'approved_refund'
              AND rr.ledger_entry_id IS NOT NULL
              AND osi.network_id = v_group.network_id
              AND osi.owner_user_id = v_group.owner_user_id
              AND osi.settlement_status IN ('included', 'paid')
              AND rr.updated_at::DATE <= p_period_end
              AND NOT EXISTS (
                  SELECT 1
                  FROM public.settlement_batch_lines sbl
                  JOIN public.settlement_batches sb ON sb.id = sbl.settlement_batch_id
                  WHERE sbl.line_type = 'refund'
                    AND sbl.reference_id = rr.id
                    AND sb.status <> 'cancelled'
              )
            ORDER BY rr.updated_at, rr.id
        LOOP
            INSERT INTO public.settlement_batch_lines (
                settlement_batch_id, line_type, reference_id,
                gross_amount, commission_amount, net_amount
            ) VALUES (
                v_batch_id, 'refund', v_refund.refund_id,
                v_refund.gross_amount, v_refund.commission_amount, -v_refund.owner_net_amount
            );

            v_refunds := v_refunds + v_refund.owner_net_amount;
            v_lines := v_lines + 1;
        END LOOP;

        IF v_lines = 0 THEN
            DELETE FROM public.settlement_batches WHERE id = v_batch_id;
            CONTINUE;
        END IF;

        UPDATE public.settlement_batches
        SET gross_sales = v_gross,
            total_commission = v_commission,
            total_refunds = v_refunds,
            total_adjustments = 0,
            net_settlement = v_gross - v_commission - v_refunds,
            updated_at = NOW()
        WHERE id = v_batch_id;

        PERFORM public.record_audit_event(
            'SETTLEMENT_BATCH_CREATED', 'settlement_batch', v_batch_id::TEXT, 'success', 'FINANCE_SETTLEMENT',
            jsonb_build_object(
                'network_id', v_group.network_id,
                'owner_user_id', v_group.owner_user_id,
                'period_start', p_period_start,
                'period_end', p_period_end,
                'gross_sales', v_gross,
                'total_commission', v_commission,
                'total_refunds', v_refunds,
                'net_settlement', v_gross - v_commission - v_refunds
            )
        );

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
$$;

REVOKE EXECUTE ON FUNCTION public.finance_create_settlement_batch(DATE, DATE, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finance_create_settlement_batch(DATE, DATE, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.finance_approve_settlement_batch(p_batch_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id UUID;
    v_batch public.settlement_batches%ROWTYPE;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.' USING ERRCODE = '28000';
    END IF;

    IF NOT public.is_finance_or_admin() THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_batch
    FROM public.settlement_batches
    WHERE id = p_batch_id
    FOR UPDATE;

    IF v_batch.id IS NULL THEN
        RAISE EXCEPTION 'NOT_FOUND: Settlement batch not found.' USING ERRCODE = '42501';
    END IF;

    IF v_batch.status NOT IN ('draft', 'ready_for_review') THEN
        RAISE EXCEPTION 'INVALID_STATE: Batch cannot be approved from status %.', v_batch.status
            USING ERRCODE = '22000';
    END IF;

    IF v_batch.created_by = v_user_id THEN
        RAISE EXCEPTION 'FORBIDDEN_SELF_APPROVAL: Cannot approve a batch you created.'
            USING ERRCODE = '42501';
    END IF;

    UPDATE public.settlement_batches
    SET status = 'approved',
        reviewed_by = v_user_id,
        reviewed_at = NOW(),
        updated_at = NOW()
    WHERE id = p_batch_id;

    PERFORM public.record_audit_event(
        'SETTLEMENT_BATCH_APPROVED', 'settlement_batch', p_batch_id::TEXT, 'success', 'FINANCE_SETTLEMENT',
        jsonb_build_object('net_settlement', v_batch.net_settlement, 'created_by', v_batch.created_by)
    );

    RETURN jsonb_build_object('id', p_batch_id, 'status', 'approved');
END;
$$;

-- "Paid" now needs the payment reference of the actual transfer, and is audited.
CREATE OR REPLACE FUNCTION public.finance_mark_settlement_paid(
    p_batch_id UUID,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id UUID;
    v_batch public.settlement_batches%ROWTYPE;
    v_reference TEXT := NULLIF(trim(COALESCE(p_notes, '')), '');
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.' USING ERRCODE = '28000';
    END IF;

    IF NOT public.is_finance_or_admin() THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE' USING ERRCODE = '42501';
    END IF;

    IF v_reference IS NULL THEN
        RAISE EXCEPTION 'PAYMENT_REFERENCE_REQUIRED: Provide the payment reference of the transfer.'
            USING ERRCODE = '22000';
    END IF;
    IF char_length(v_reference) > 500 THEN
        RAISE EXCEPTION 'PAYMENT_REFERENCE_TOO_LONG: Payment reference exceeds 500 characters.'
            USING ERRCODE = '22001';
    END IF;

    SELECT * INTO v_batch
    FROM public.settlement_batches
    WHERE id = p_batch_id
    FOR UPDATE;

    IF v_batch.id IS NULL THEN
        RAISE EXCEPTION 'NOT_FOUND: Settlement batch not found.' USING ERRCODE = '42501';
    END IF;

    IF v_batch.status != 'approved' THEN
        RAISE EXCEPTION 'INVALID_STATE: Batch must be approved before marking paid.' USING ERRCODE = '22000';
    END IF;

    UPDATE public.settlement_batches
    SET status = 'paid',
        notes = v_reference,
        updated_at = NOW()
    WHERE id = p_batch_id;

    UPDATE public.owner_settlement_items
    SET settlement_status = 'paid',
        updated_at = NOW()
    WHERE settlement_batch_id = p_batch_id
      AND settlement_status = 'included';

    PERFORM public.record_audit_event(
        'SETTLEMENT_BATCH_PAID', 'settlement_batch', p_batch_id::TEXT, 'success', 'FINANCE_SETTLEMENT',
        jsonb_build_object('net_settlement', v_batch.net_settlement, 'payment_reference', v_reference)
    );

    RETURN jsonb_build_object('id', p_batch_id, 'status', 'paid');
END;
$$;

-- A wrong draft can now be cancelled; its sales go back to the pending pool.
CREATE OR REPLACE FUNCTION public.finance_cancel_settlement_batch(
    p_batch_id UUID,
    p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id UUID;
    v_batch public.settlement_batches%ROWTYPE;
    v_reason TEXT := NULLIF(trim(COALESCE(p_reason, '')), '');
    v_released INTEGER;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.' USING ERRCODE = '28000';
    END IF;

    IF NOT public.is_finance_or_admin() THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE' USING ERRCODE = '42501';
    END IF;

    IF v_reason IS NULL OR char_length(v_reason) > 500 THEN
        RAISE EXCEPTION 'REASON_REQUIRED: A cancellation reason of at most 500 characters is required.'
            USING ERRCODE = '22000';
    END IF;

    SELECT * INTO v_batch
    FROM public.settlement_batches
    WHERE id = p_batch_id
    FOR UPDATE;

    IF v_batch.id IS NULL THEN
        RAISE EXCEPTION 'NOT_FOUND: Settlement batch not found.' USING ERRCODE = '42501';
    END IF;

    IF v_batch.status NOT IN ('draft', 'ready_for_review') THEN
        RAISE EXCEPTION 'INVALID_STATE: Only a draft batch can be cancelled (status=%).', v_batch.status
            USING ERRCODE = '22000';
    END IF;

    -- Sales go back to the pool; a sale refunded in the meantime is voided.
    UPDATE public.owner_settlement_items osi
    SET settlement_batch_id = NULL,
        settlement_status = CASE WHEN pr.status = 'refunded' THEN 'voided' ELSE 'pending' END,
        updated_at = NOW()
    FROM public.purchase_records pr
    WHERE pr.id = osi.purchase_id
      AND osi.settlement_batch_id = p_batch_id
      AND osi.settlement_status = 'included';
    GET DIAGNOSTICS v_released = ROW_COUNT;

    UPDATE public.settlement_batches
    SET status = 'cancelled',
        notes = v_reason,
        updated_at = NOW()
    WHERE id = p_batch_id;

    PERFORM public.record_audit_event(
        'SETTLEMENT_BATCH_CANCELLED', 'settlement_batch', p_batch_id::TEXT, 'success', 'FINANCE_SETTLEMENT',
        jsonb_build_object('reason', v_reason, 'released_items', v_released)
    );

    RETURN jsonb_build_object('id', p_batch_id, 'status', 'cancelled', 'released_items', v_released);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.finance_cancel_settlement_batch(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finance_cancel_settlement_batch(UUID, TEXT) TO authenticated;
