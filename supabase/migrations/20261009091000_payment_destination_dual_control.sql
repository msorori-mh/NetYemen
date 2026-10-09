-- Dual control (maker/checker) for payment destinations.
--
-- A payment destination is the bank account / wallet number customers are told
-- to transfer money to. Before this migration one finance_officer or
-- platform_admin could create a destination, or change the account number of
-- an active one, and customers would see it at once: a single compromised or
-- malicious staff account could redirect every deposit.
--
-- Rule now: nothing reaches customers without a second, different staff member.
--   * admin_create_payment_destination   creates the destination INACTIVE.
--   * admin_update_payment_destination   edits an INACTIVE destination only
--                                        (DESTINATION_ACTIVE otherwise; the
--                                        sort order may still change).
--   * admin_set_payment_destination_active(id, false) deactivates at once
--     (always safe); (id, true) is refused with APPROVAL_REQUIRED.
--   * admin_request_payment_destination_activation  files an activation
--     request that pins a hash of the destination's content.
--   * admin_review_payment_destination_activation   approves (activates) or
--     rejects it; the reviewer must differ from the requester, and approval
--     fails with STALE_CHANGE_REQUEST if the content changed after the request.
--   * admin_cancel_payment_destination_activation   withdraws a request.
-- Every step writes an audit event; the existing row trigger keeps auditing the
-- destination itself (the approver is the actor of the activation).

-- ---------------------------------------------------------------------------
-- 1. Direct table access: read-only for staff (writes go through the RPCs).
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS payment_destinations_admin_manage_policy ON public.payment_destinations;
DROP POLICY IF EXISTS payment_destinations_staff_select_policy ON public.payment_destinations;
CREATE POLICY payment_destinations_staff_select_policy ON public.payment_destinations
  FOR SELECT TO authenticated
  USING (public.is_finance_or_admin());
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.payment_destinations FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Activation requests.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payment_destination_activation_requests (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  destination_id  uuid NOT NULL REFERENCES public.payment_destinations(id) ON DELETE CASCADE,
  status          text NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  content_hash    text NOT NULL,
  content_snapshot jsonb NOT NULL,
  reason          text,
  requested_by    uuid NOT NULL REFERENCES auth.users(id),
  requested_at    timestamptz NOT NULL DEFAULT now(),
  reviewed_by     uuid REFERENCES auth.users(id),
  reviewed_at     timestamptz,
  review_note     text,
  CONSTRAINT chk_pdar_reviewer_differs CHECK (reviewed_by IS NULL OR reviewed_by <> requested_by),
  CONSTRAINT chk_pdar_review_complete CHECK (
    (status = 'pending' AND reviewed_by IS NULL AND reviewed_at IS NULL)
    OR (status <> 'pending' AND reviewed_at IS NOT NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS payment_destination_activation_one_pending
  ON public.payment_destination_activation_requests (destination_id)
  WHERE status = 'pending';

ALTER TABLE public.payment_destination_activation_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.payment_destination_activation_requests FROM PUBLIC, anon, authenticated;

-- Content customers see; the activation request pins it.
CREATE OR REPLACE FUNCTION public._payment_destination_content(p_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object(
    'provider_type', d.provider_type,
    'display_name', d.display_name,
    'account_holder_name', d.account_holder_name,
    'account_identifier', d.account_identifier,
    'instructions', d.instructions,
    'currency', d.currency
  )
  FROM public.payment_destinations d
  WHERE d.id = p_id
$$;

CREATE OR REPLACE FUNCTION public._require_active_finance_staff()
RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.' USING ERRCODE = '28000';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_user AND account_status = 'active') THEN
    RAISE EXCEPTION 'INACTIVE_PROFILE: Active account required.' USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_finance_or_admin() THEN
    RAISE EXCEPTION 'FORBIDDEN_ROLE: Only finance_officer or platform_admin can manage payment destinations.'
      USING ERRCODE = '42501';
  END IF;
  RETURN v_user;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Create: always inactive.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_create_payment_destination(
  p_provider_type text,
  p_display_name text,
  p_account_holder_name text DEFAULT NULL::text,
  p_account_identifier text DEFAULT NULL::text,
  p_instructions text DEFAULT NULL::text,
  p_currency text DEFAULT 'YER'::text,
  p_sort_order integer DEFAULT 0
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user uuid;
  v_id uuid;
BEGIN
  v_user := public._require_active_finance_staff();

  IF p_provider_type IS NULL OR p_provider_type NOT IN ('bank_account', 'mobile_wallet', 'manual_transfer', 'other') THEN
    RAISE EXCEPTION 'INVALID_PROVIDER_TYPE: Must be one of bank_account, mobile_wallet, manual_transfer, other.'
      USING ERRCODE = '22000';
  END IF;

  IF p_display_name IS NULL OR length(trim(p_display_name)) = 0 THEN
    RAISE EXCEPTION 'INVALID_DISPLAY_NAME: Display name is required.' USING ERRCODE = '22000';
  END IF;

  -- Created inactive: customers see it only after a second staff member
  -- approves an activation request.
  INSERT INTO public.payment_destinations (
    provider_type, display_name, account_holder_name, account_identifier,
    instructions, currency, is_active, sort_order
  ) VALUES (
    p_provider_type, trim(p_display_name), NULLIF(trim(p_account_holder_name), ''),
    NULLIF(trim(p_account_identifier), ''), NULLIF(trim(p_instructions), ''),
    COALESCE(p_currency, 'YER'), FALSE, COALESCE(p_sort_order, 0)
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Update: content only while inactive; sort order any time.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_update_payment_destination(
  p_id uuid,
  p_provider_type text DEFAULT NULL::text,
  p_display_name text DEFAULT NULL::text,
  p_account_holder_name text DEFAULT NULL::text,
  p_account_identifier text DEFAULT NULL::text,
  p_instructions text DEFAULT NULL::text,
  p_currency text DEFAULT NULL::text,
  p_sort_order integer DEFAULT NULL::integer
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user uuid;
  v_dest public.payment_destinations%ROWTYPE;
  v_content_change boolean;
BEGIN
  v_user := public._require_active_finance_staff();

  SELECT * INTO v_dest FROM public.payment_destinations WHERE id = p_id FOR UPDATE;
  IF v_dest.id IS NULL THEN
    RAISE EXCEPTION 'NOT_FOUND: Payment destination not found.' USING ERRCODE = '42501';
  END IF;

  IF p_provider_type IS NOT NULL AND p_provider_type NOT IN ('bank_account', 'mobile_wallet', 'manual_transfer', 'other') THEN
    RAISE EXCEPTION 'INVALID_PROVIDER_TYPE' USING ERRCODE = '22000';
  END IF;

  IF p_display_name IS NOT NULL AND length(trim(p_display_name)) = 0 THEN
    RAISE EXCEPTION 'INVALID_DISPLAY_NAME: Display name is required.' USING ERRCODE = '22000';
  END IF;

  v_content_change :=
       (p_provider_type IS NOT NULL AND p_provider_type IS DISTINCT FROM v_dest.provider_type)
    OR (p_display_name IS NOT NULL AND trim(p_display_name) IS DISTINCT FROM v_dest.display_name)
    OR (p_account_holder_name IS NOT NULL AND p_account_holder_name IS DISTINCT FROM v_dest.account_holder_name)
    OR (p_account_identifier IS NOT NULL AND p_account_identifier IS DISTINCT FROM v_dest.account_identifier)
    OR (p_instructions IS NOT NULL AND p_instructions IS DISTINCT FROM v_dest.instructions)
    OR (p_currency IS NOT NULL AND p_currency IS DISTINCT FROM v_dest.currency);

  IF v_content_change AND v_dest.is_active THEN
    RAISE EXCEPTION 'DESTINATION_ACTIVE: Deactivate the destination before editing it; re-activation needs a second approver.'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.payment_destinations
  SET
    provider_type = COALESCE(p_provider_type, provider_type),
    display_name = COALESCE(trim(p_display_name), display_name),
    account_holder_name = COALESCE(p_account_holder_name, account_holder_name),
    account_identifier = COALESCE(p_account_identifier, account_identifier),
    instructions = COALESCE(p_instructions, instructions),
    currency = COALESCE(p_currency, currency),
    sort_order = COALESCE(p_sort_order, sort_order),
    updated_at = NOW()
  WHERE id = p_id;

  RETURN jsonb_build_object('id', p_id, 'updated', TRUE, 'is_active', v_dest.is_active);
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Active flag: deactivation is immediate, activation needs approval.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_set_payment_destination_active(p_id uuid, p_active boolean)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user uuid;
BEGIN
  v_user := public._require_active_finance_staff();

  IF p_active IS NOT FALSE THEN
    RAISE EXCEPTION 'APPROVAL_REQUIRED: Activation needs a second approver (admin_request_payment_destination_activation).'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.payment_destinations
  SET is_active = FALSE, updated_at = NOW()
  WHERE id = p_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND: Payment destination not found.' USING ERRCODE = '42501';
  END IF;

  RETURN jsonb_build_object('id', p_id, 'is_active', FALSE);
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. Activation requests: file, review, cancel, list.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_request_payment_destination_activation(
  p_destination_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user uuid;
  v_dest public.payment_destinations%ROWTYPE;
  v_content jsonb;
  v_id uuid;
BEGIN
  v_user := public._require_active_finance_staff();

  SELECT * INTO v_dest FROM public.payment_destinations WHERE id = p_destination_id FOR UPDATE;
  IF v_dest.id IS NULL THEN
    RAISE EXCEPTION 'NOT_FOUND: Payment destination not found.' USING ERRCODE = '42501';
  END IF;
  IF v_dest.is_active THEN
    RAISE EXCEPTION 'ALREADY_ACTIVE: Payment destination is already active.' USING ERRCODE = '22000';
  END IF;
  IF v_dest.account_identifier IS NULL OR length(trim(v_dest.account_identifier)) = 0 THEN
    RAISE EXCEPTION 'INVALID_DESTINATION: An account number is required before activation.' USING ERRCODE = '22000';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.payment_destination_activation_requests
    WHERE destination_id = p_destination_id AND status = 'pending'
  ) THEN
    RAISE EXCEPTION 'CHANGE_ALREADY_PENDING: An activation request is already pending for this destination.'
      USING ERRCODE = '22000';
  END IF;

  v_content := public._payment_destination_content(p_destination_id);

  INSERT INTO public.payment_destination_activation_requests (
    destination_id, content_hash, content_snapshot, reason, requested_by
  ) VALUES (
    p_destination_id, md5(v_content::text), v_content, NULLIF(trim(p_reason), ''), v_user
  ) RETURNING id INTO v_id;

  PERFORM public.record_audit_event(
    'PAYMENT_DESTINATION_ACTIVATION_REQUESTED', 'payment_destinations', p_destination_id::text,
    'success', 'FINANCE_CONFIGURATION',
    jsonb_build_object('request_id', v_id, 'content', v_content, 'reason', NULLIF(trim(p_reason), ''))
  );

  RETURN jsonb_build_object('request_id', v_id, 'destination_id', p_destination_id, 'status', 'pending');
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_review_payment_destination_activation(
  p_request_id uuid,
  p_approve boolean,
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user uuid;
  v_req public.payment_destination_activation_requests%ROWTYPE;
  v_content jsonb;
  v_status text;
BEGIN
  v_user := public._require_active_finance_staff();

  IF p_approve IS NULL THEN
    RAISE EXCEPTION 'INVALID_DECISION: p_approve is required.' USING ERRCODE = '22000';
  END IF;

  SELECT * INTO v_req FROM public.payment_destination_activation_requests
  WHERE id = p_request_id FOR UPDATE;
  IF v_req.id IS NULL THEN
    RAISE EXCEPTION 'NOT_FOUND: Activation request not found.' USING ERRCODE = '42501';
  END IF;
  IF v_req.status <> 'pending' THEN
    RAISE EXCEPTION 'ALREADY_RESOLVED: Activation request is no longer pending.' USING ERRCODE = '22000';
  END IF;
  IF v_req.requested_by = v_user THEN
    RAISE EXCEPTION 'SELF_APPROVAL_FORBIDDEN: A different staff member must review this request.'
      USING ERRCODE = '42501';
  END IF;

  IF NOT p_approve THEN
    IF p_note IS NULL OR length(trim(p_note)) = 0 THEN
      RAISE EXCEPTION 'REASON_REQUIRED: A rejection needs a note.' USING ERRCODE = '22000';
    END IF;
    v_status := 'rejected';
  ELSE
    IF v_req.requested_at < now() - interval '7 days' THEN
      RAISE EXCEPTION 'REQUEST_EXPIRED: Activation requests expire after 7 days; file a new one.'
        USING ERRCODE = '22000';
    END IF;

    -- Lock the destination and make sure it is what the requester submitted.
    PERFORM 1 FROM public.payment_destinations WHERE id = v_req.destination_id FOR UPDATE;
    v_content := public._payment_destination_content(v_req.destination_id);
    IF v_content IS NULL OR md5(v_content::text) <> v_req.content_hash THEN
      RAISE EXCEPTION 'STALE_CHANGE_REQUEST: The destination changed after the request; reject it and file a new one.'
        USING ERRCODE = '22000';
    END IF;

    UPDATE public.payment_destinations
    SET is_active = TRUE, updated_at = NOW()
    WHERE id = v_req.destination_id;
    v_status := 'approved';
  END IF;

  UPDATE public.payment_destination_activation_requests
  SET status = v_status, reviewed_by = v_user, reviewed_at = now(),
      review_note = NULLIF(trim(p_note), '')
  WHERE id = p_request_id;

  PERFORM public.record_audit_event(
    CASE WHEN p_approve THEN 'PAYMENT_DESTINATION_ACTIVATION_APPROVED'
         ELSE 'PAYMENT_DESTINATION_ACTIVATION_REJECTED' END,
    'payment_destinations', v_req.destination_id::text,
    'success', 'FINANCE_CONFIGURATION',
    jsonb_build_object('request_id', p_request_id, 'requested_by', v_req.requested_by,
                       'note', NULLIF(trim(p_note), ''))
  );

  RETURN jsonb_build_object(
    'request_id', p_request_id,
    'destination_id', v_req.destination_id,
    'status', v_status,
    'is_active', p_approve
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_cancel_payment_destination_activation(p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user uuid;
  v_req public.payment_destination_activation_requests%ROWTYPE;
BEGIN
  v_user := public._require_active_finance_staff();

  SELECT * INTO v_req FROM public.payment_destination_activation_requests
  WHERE id = p_request_id FOR UPDATE;
  IF v_req.id IS NULL THEN
    RAISE EXCEPTION 'NOT_FOUND: Activation request not found.' USING ERRCODE = '42501';
  END IF;
  IF v_req.status <> 'pending' THEN
    RAISE EXCEPTION 'ALREADY_RESOLVED: Activation request is no longer pending.' USING ERRCODE = '22000';
  END IF;
  IF v_req.requested_by <> v_user AND NOT public.has_platform_role('platform_admin') THEN
    RAISE EXCEPTION 'FORBIDDEN: Only the requester or a platform admin can cancel this request.'
      USING ERRCODE = '42501';
  END IF;

  -- A cancellation is not a review: reviewed_by stays NULL (it may be the
  -- requester), reviewed_at records when it was closed.
  UPDATE public.payment_destination_activation_requests
  SET status = 'cancelled', reviewed_at = now()
  WHERE id = p_request_id;

  PERFORM public.record_audit_event(
    'PAYMENT_DESTINATION_ACTIVATION_CANCELLED', 'payment_destinations', v_req.destination_id::text,
    'success', 'FINANCE_CONFIGURATION', jsonb_build_object('request_id', p_request_id)
  );

  RETURN jsonb_build_object('request_id', p_request_id, 'status', 'cancelled');
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_list_payment_destination_activations(p_status text DEFAULT 'pending')
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user uuid;
  v_result jsonb;
BEGIN
  v_user := public._require_active_finance_staff();

  IF p_status IS NOT NULL AND p_status NOT IN ('pending', 'approved', 'rejected', 'cancelled') THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING ERRCODE = '22000';
  END IF;

  SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.requested_at DESC), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      q.id,
      q.destination_id,
      q.status,
      q.content_snapshot,
      q.reason,
      q.requested_by,
      req.email AS requested_by_email,
      q.requested_at,
      q.reviewed_by,
      rev.email AS reviewed_by_email,
      q.reviewed_at,
      q.review_note,
      (q.requested_by = v_user) AS requested_by_me,
      (q.status = 'pending'
        AND md5(COALESCE(public._payment_destination_content(q.destination_id)::text, '')) <> q.content_hash
      ) AS is_stale
    FROM public.payment_destination_activation_requests q
    LEFT JOIN auth.users req ON req.id = q.requested_by
    LEFT JOIN auth.users rev ON rev.id = q.reviewed_by
    WHERE p_status IS NULL OR q.status = p_status
    ORDER BY q.requested_at DESC
    LIMIT 200
  ) AS r;

  RETURN v_result;
END;
$$;

-- ---------------------------------------------------------------------------
-- 7. Privileges.
-- ---------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public._payment_destination_content(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._require_active_finance_staff() FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.admin_request_payment_destination_activation(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_review_payment_destination_activation(uuid, boolean, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_cancel_payment_destination_activation(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_list_payment_destination_activations(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_request_payment_destination_activation(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_review_payment_destination_activation(uuid, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_cancel_payment_destination_activation(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_payment_destination_activations(text) TO authenticated;
