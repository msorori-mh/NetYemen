-- WASEL NET self-service account deletion request lifecycle.
-- The authenticated request is immediate and fail-closed; final PII
-- anonymisation is performed after the disclosed 30-day reconciliation window.

ALTER TABLE public.profiles
    DROP CONSTRAINT chk_profiles_account_status;

ALTER TABLE public.profiles
    ADD CONSTRAINT chk_profiles_account_status
    CHECK (account_status IN (
        'active',
        'suspended',
        'pending_verification',
        'closure_pending',
        'anonymized'
    ));

CREATE TABLE public.account_deletion_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE RESTRICT,
    status TEXT NOT NULL DEFAULT 'pending',
    previous_account_status TEXT NOT NULL,
    reason TEXT,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    scheduled_for TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '30 days'),
    cancelled_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_account_deletion_status
        CHECK (status IN ('pending', 'cancelled', 'completed')),
    CONSTRAINT chk_account_deletion_previous_status
        CHECK (previous_account_status IN (
            'active', 'suspended', 'pending_verification'
        )),
    CONSTRAINT chk_account_deletion_reason_length
        CHECK (reason IS NULL OR char_length(reason) <= 500),
    CONSTRAINT chk_account_deletion_schedule
        CHECK (scheduled_for >= requested_at),
    CONSTRAINT chk_account_deletion_terminal_dates CHECK (
        (status = 'pending' AND cancelled_at IS NULL AND completed_at IS NULL)
        OR (status = 'cancelled' AND cancelled_at IS NOT NULL AND completed_at IS NULL)
        OR (status = 'completed' AND completed_at IS NOT NULL)
    )
);

COMMENT ON TABLE public.account_deletion_requests IS
    'Audited self-service deletion requests. PII is anonymised after the 30-day financial reconciliation window; immutable financial and audit records are retained.';

CREATE INDEX idx_account_deletion_requests_due
    ON public.account_deletion_requests (scheduled_for)
    WHERE status = 'pending';

CREATE TRIGGER trg_account_deletion_requests_set_updated_at
    BEFORE UPDATE ON public.account_deletion_requests
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.account_deletion_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_deletion_requests FORCE ROW LEVEL SECURITY;

CREATE POLICY account_deletion_requests_owner_select
    ON public.account_deletion_requests
    FOR SELECT
    USING (
        user_id = auth.uid()
        OR public.has_platform_role('platform_admin')
        OR public.has_platform_role('system_auditor')
    );

REVOKE ALL ON public.account_deletion_requests FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.account_deletion_requests TO authenticated;
GRANT ALL ON public.account_deletion_requests TO service_role;

CREATE OR REPLACE FUNCTION public.request_my_account_deletion(
    p_reason TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_profile public.profiles%ROWTYPE;
    v_request public.account_deletion_requests%ROWTYPE;
    v_reason TEXT := NULLIF(trim(COALESCE(p_reason, '')), '');
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: Sign in before requesting account deletion.'
            USING ERRCODE = '42501';
    END IF;

    IF char_length(COALESCE(v_reason, '')) > 500 THEN
        RAISE EXCEPTION 'REASON_TOO_LONG: Reason exceeds 500 characters.'
            USING ERRCODE = '22001';
    END IF;

    SELECT * INTO v_profile
    FROM public.profiles
    WHERE id = v_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'PROFILE_NOT_FOUND: Account profile does not exist.'
            USING ERRCODE = 'P0002';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.user_roles
        WHERE user_id = v_user_id
          AND role IN (
              'platform_admin',
              'finance_officer',
              'support_agent',
              'system_auditor',
              'system_service'
          )
    ) THEN
        RAISE EXCEPTION 'ADMIN_HANDOFF_REQUIRED: Administrative accounts require role handoff before deletion.'
            USING ERRCODE = '42501';
    END IF;

    IF v_profile.account_status = 'anonymized' THEN
        RAISE EXCEPTION 'ACCOUNT_ALREADY_ANONYMIZED: Account deletion is complete.'
            USING ERRCODE = 'P0001';
    END IF;

    SELECT * INTO v_request
    FROM public.account_deletion_requests
    WHERE user_id = v_user_id
    FOR UPDATE;

    IF FOUND AND v_request.status = 'pending' THEN
        RETURN jsonb_build_object(
            'request_id', v_request.id,
            'status', v_request.status,
            'requested_at', v_request.requested_at,
            'scheduled_for', v_request.scheduled_for,
            'idempotent', TRUE
        );
    END IF;

    IF v_profile.account_status = 'closure_pending' THEN
        RAISE EXCEPTION 'INCONSISTENT_CLOSURE_STATE: Profile is pending closure without an active request.'
            USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.account_deletion_requests (
        user_id,
        status,
        previous_account_status,
        reason,
        requested_at,
        scheduled_for,
        cancelled_at,
        completed_at
    ) VALUES (
        v_user_id,
        'pending',
        v_profile.account_status,
        v_reason,
        NOW(),
        NOW() + INTERVAL '30 days',
        NULL,
        NULL
    )
    ON CONFLICT (user_id) DO UPDATE
    SET status = 'pending',
        previous_account_status = EXCLUDED.previous_account_status,
        reason = EXCLUDED.reason,
        requested_at = EXCLUDED.requested_at,
        scheduled_for = EXCLUDED.scheduled_for,
        cancelled_at = NULL,
        completed_at = NULL
    RETURNING * INTO v_request;

    UPDATE public.profiles
    SET account_status = 'closure_pending'
    WHERE id = v_user_id;

    UPDATE public.device_push_tokens
    SET is_active = FALSE
    WHERE user_id = v_user_id
      AND is_active = TRUE;

    PERFORM public.record_audit_event(
        'ACCOUNT_DELETION_REQUESTED',
        'account_deletion_request',
        v_request.id::TEXT,
        'success',
        'USER_REQUEST',
        jsonb_build_object(
            'user_id', v_user_id,
            'previous_account_status', v_request.previous_account_status,
            'scheduled_for', v_request.scheduled_for
        )
    );

    RETURN jsonb_build_object(
        'request_id', v_request.id,
        'status', v_request.status,
        'requested_at', v_request.requested_at,
        'scheduled_for', v_request.scheduled_for,
        'idempotent', FALSE
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.request_my_account_deletion(TEXT)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_my_account_deletion(TEXT)
    TO authenticated;

CREATE OR REPLACE FUNCTION public.cancel_my_account_deletion()
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_request public.account_deletion_requests%ROWTYPE;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: Sign in before cancelling account deletion.'
            USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_request
    FROM public.account_deletion_requests
    WHERE user_id = v_user_id
    FOR UPDATE;

    IF NOT FOUND OR v_request.status <> 'pending' THEN
        RAISE EXCEPTION 'NO_PENDING_DELETION: No pending account deletion exists.'
            USING ERRCODE = 'P0002';
    END IF;

    IF NOW() >= v_request.scheduled_for THEN
        RAISE EXCEPTION 'DELETION_WINDOW_CLOSED: Account anonymisation is already due.'
            USING ERRCODE = 'P0001';
    END IF;

    UPDATE public.account_deletion_requests
    SET status = 'cancelled',
        cancelled_at = NOW()
    WHERE id = v_request.id;

    UPDATE public.profiles
    SET account_status = v_request.previous_account_status
    WHERE id = v_user_id
      AND account_status = 'closure_pending';

    PERFORM public.record_audit_event(
        'ACCOUNT_DELETION_CANCELLED',
        'account_deletion_request',
        v_request.id::TEXT,
        'success',
        'USER_CANCELLED',
        jsonb_build_object('user_id', v_user_id)
    );

    RETURN jsonb_build_object(
        'request_id', v_request.id,
        'status', 'cancelled'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.cancel_my_account_deletion()
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_my_account_deletion()
    TO authenticated;
