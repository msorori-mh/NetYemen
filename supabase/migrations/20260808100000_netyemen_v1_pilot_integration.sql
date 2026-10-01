-- NetYemen V1 integrated local-pilot closure.
-- Provider/policy decisions remain explicitly unbound. No production bindings.

-- OD-FIN-02 / OD-SETTLE-01: retain the immutable gross purchase reference but
-- do not silently calculate commission, net settlement, or payout eligibility.
ALTER TABLE public.owner_settlement_items
  ALTER COLUMN platform_commission_amount DROP NOT NULL,
  ALTER COLUMN platform_commission_amount DROP DEFAULT,
  ALTER COLUMN net_settlement_amount DROP NOT NULL,
  ALTER COLUMN settlement_status SET DEFAULT 'awaiting_policy';

ALTER TABLE public.owner_settlement_items
  DROP CONSTRAINT chk_owner_settlement_items_amounts_positive,
  DROP CONSTRAINT chk_owner_settlement_items_net,
  DROP CONSTRAINT chk_owner_settlement_items_status;

ALTER TABLE public.owner_settlement_items
  ADD CONSTRAINT chk_owner_settlement_items_amounts_positive CHECK (
    gross_amount >= 0 AND
    (platform_commission_amount IS NULL OR platform_commission_amount >= 0) AND
    (net_settlement_amount IS NULL OR net_settlement_amount >= 0)
  ),
  ADD CONSTRAINT chk_owner_settlement_items_net CHECK (
    (platform_commission_amount IS NULL AND net_settlement_amount IS NULL)
    OR net_settlement_amount = gross_amount - platform_commission_amount
  ),
  ADD CONSTRAINT chk_owner_settlement_items_status CHECK (
    settlement_status IN ('awaiting_policy','pending','included','paid','disputed')
  );

CREATE OR REPLACE FUNCTION public.enforce_unbound_settlement_policy()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.platform_commission_amount := NULL;
    NEW.net_settlement_amount := NULL;
    NEW.settlement_status := 'awaiting_policy';
    NEW.settlement_voucher_id := NULL;
  ELSIF OLD.settlement_status = 'awaiting_policy' AND
        (NEW.settlement_status IS DISTINCT FROM OLD.settlement_status OR
         NEW.platform_commission_amount IS NOT NULL OR
         NEW.net_settlement_amount IS NOT NULL OR
         NEW.settlement_voucher_id IS NOT NULL) THEN
    RAISE EXCEPTION 'SETTLEMENT_POLICY_UNBOUND: OD-FIN-02 and OD-SETTLE-01 require owner approval.'
      USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END $$;

REVOKE EXECUTE ON FUNCTION public.enforce_unbound_settlement_policy() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_owner_settlement_policy_hold ON public.owner_settlement_items;
CREATE TRIGGER trg_owner_settlement_policy_hold
BEFORE INSERT OR UPDATE ON public.owner_settlement_items
FOR EACH ROW EXECUTE FUNCTION public.enforce_unbound_settlement_policy();

UPDATE public.owner_settlement_items
SET platform_commission_amount = NULL,
    net_settlement_amount = NULL,
    settlement_status = 'awaiting_policy',
    settlement_voucher_id = NULL;

COMMENT ON TABLE public.owner_settlement_items IS
  'Immutable gross purchase references. Commission/net/payout remain NULL and awaiting_policy until OD-FIN-02 and OD-SETTLE-01 are approved.';

-- Link support disputes to a purchase without exposing any fulfillment secret.
ALTER TABLE public.support_cases
  ADD COLUMN purchase_id UUID REFERENCES public.purchase_records(id) ON DELETE SET NULL;
CREATE INDEX support_cases_purchase_idx ON public.support_cases(purchase_id) WHERE purchase_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.create_purchase_support_case(
  p_purchase_id UUID,
  p_priority TEXT,
  p_subject TEXT,
  p_description TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_purchase public.purchase_records%ROWTYPE;
  v_id UUID;
  v_number BIGINT;
BEGIN
  IF NOT public.support_is_active() THEN
    RAISE EXCEPTION 'FORBIDDEN: Active authentication required.' USING ERRCODE='42501';
  END IF;
  IF p_priority NOT IN ('low','normal','high','urgent') THEN
    RAISE EXCEPTION 'INVALID_PRIORITY' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_purchase FROM public.purchase_records
  WHERE id = p_purchase_id AND user_id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PURCHASE_NOT_FOUND' USING ERRCODE='42501';
  END IF;
  INSERT INTO public.support_cases(
    case_type, customer_user_id, network_id, package_id, purchase_id,
    category, priority, subject, description, due_at
  ) VALUES (
    'dispute', auth.uid(), v_purchase.network_id, v_purchase.package_id,
    v_purchase.id, 'service', p_priority, trim(p_subject), trim(p_description),
    now() + CASE p_priority WHEN 'urgent' THEN interval '4 hours'
      WHEN 'high' THEN interval '12 hours' ELSE interval '48 hours' END
  ) RETURNING id, case_number INTO v_id, v_number;
  INSERT INTO public.support_case_events(case_id,actor_user_id,event_type,to_status,metadata)
  VALUES(v_id,auth.uid(),'created','open',jsonb_build_object('purchase_id',p_purchase_id));
  PERFORM public.record_audit_event('PURCHASE_DISPUTE_CREATED','support_case',v_id::text,
    'success','CREATE',jsonb_build_object('purchase_id',p_purchase_id));
  RETURN jsonb_build_object('id',v_id,'case_number',v_number,'purchase_id',p_purchase_id);
END $$;

REVOKE EXECUTE ON FUNCTION public.create_purchase_support_case(UUID,TEXT,TEXT,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_purchase_support_case(UUID,TEXT,TEXT,TEXT) TO authenticated;

-- Cross-domain event hooks: canonical event/outbox entries are created, but
-- external push stays unbound and therefore cannot pretend delivery succeeded.
CREATE OR REPLACE FUNCTION public.emit_commerce_notification_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user UUID;
  v_type TEXT;
  v_title TEXT;
  v_body TEXT;
  v_entity TEXT;
  v_id UUID;
BEGIN
  IF TG_TABLE_NAME = 'purchase_records' AND TG_OP = 'INSERT' THEN
    v_user := NEW.user_id; v_type := 'purchase_created'; v_title := 'تم تسجيل عملية الشراء';
    v_body := 'تم خصم قيمة الباقة، والتسليم بانتظار ربط مزود البطاقات الآمن.';
    v_entity := 'purchase'; v_id := NEW.id;
  ELSIF TG_TABLE_NAME = 'wallet_deposit_requests' AND TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
    v_user := NEW.user_id; v_type := 'deposit_' || NEW.status; v_title := 'تحديث طلب الإيداع';
    v_body := CASE NEW.status WHEN 'approved' THEN 'تم اعتماد الإيداع التجريبي وإضافة الرصيد.'
      WHEN 'rejected' THEN 'تم رفض طلب الإيداع. راجع تفاصيل الطلب.' ELSE 'تم تحديث حالة طلب الإيداع.' END;
    v_entity := 'deposit'; v_id := NEW.id;
  ELSIF TG_TABLE_NAME = 'refund_requests' AND TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
    v_user := NEW.user_id; v_type := 'refund_' || NEW.status; v_title := 'تحديث طلب الاسترداد';
    v_body := 'تم تحديث حالة طلب الاسترداد المرتبط بعملية الشراء.';
    v_entity := 'refund'; v_id := NEW.id;
  ELSE
    RETURN NEW;
  END IF;

  PERFORM public.enqueue_notification_event(
    v_type,'transactional','request_status',v_title,v_body,
    '/notifications','specific_user',jsonb_build_object('user_id',v_user),
    v_entity,v_id::text,v_type || ':' || v_id::text,NULL,auth.uid(),now(),
    jsonb_build_object('provider_state','unbound')
  );
  PERFORM public.record_audit_event(upper(v_type),v_entity,v_id::text,'success','DOMAIN_EVENT');
  RETURN NEW;
END $$;

REVOKE EXECUTE ON FUNCTION public.emit_commerce_notification_event() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER trg_purchase_integrated_event AFTER INSERT ON public.purchase_records
FOR EACH ROW EXECUTE FUNCTION public.emit_commerce_notification_event();
CREATE TRIGGER trg_deposit_integrated_event AFTER UPDATE OF status ON public.wallet_deposit_requests
FOR EACH ROW EXECUTE FUNCTION public.emit_commerce_notification_event();
CREATE TRIGGER trg_refund_integrated_event AFTER UPDATE OF status ON public.refund_requests
FOR EACH ROW EXECUTE FUNCTION public.emit_commerce_notification_event();

-- Re-assert client ACLs for new/changed objects.
REVOKE ALL ON TABLE public.owner_settlement_items, public.support_cases FROM PUBLIC, anon;
GRANT SELECT ON TABLE public.owner_settlement_items, public.support_cases TO authenticated;
