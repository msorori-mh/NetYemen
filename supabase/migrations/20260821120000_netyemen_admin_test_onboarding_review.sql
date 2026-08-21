-- WASEL NET controlled tester onboarding administrative review.
-- Source-only until the production migration gate is approved separately.

ALTER TABLE public.test_onboarding_applications
    DROP CONSTRAINT chk_test_onboarding_verification_state;

ALTER TABLE public.test_onboarding_applications
    ADD CONSTRAINT chk_test_onboarding_verification_state
    CHECK (verification_state IN (
        'test_only_pending',
        'test_admin_approved',
        'phone_verified',
        'rejected'
    ));

COMMENT ON COLUMN public.test_onboarding_applications.verification_state IS
    'test_only_pending is fail-closed; test_admin_approved is an explicit temporary admin decision and must never be represented as telecom phone verification.';

CREATE OR REPLACE FUNCTION public.admin_review_test_onboarding(
    p_application_id UUID,
    p_decision TEXT,
    p_reason TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_actor_id UUID := auth.uid();
    v_application public.test_onboarding_applications%ROWTYPE;
    v_decision TEXT := lower(trim(COALESCE(p_decision, '')));
    v_reason TEXT := NULLIF(trim(COALESCE(p_reason, '')), '');
    v_previous_account_status TEXT;
    v_account_status TEXT;
    v_verification_state TEXT;
    v_owner_review_status TEXT;
BEGIN
    PERFORM public.admin_require_role_and_profile(ARRAY['platform_admin']);

    IF v_decision NOT IN ('approve', 'reject') THEN
        RAISE EXCEPTION 'INVALID_DECISION: Decision must be approve or reject.'
            USING ERRCODE = '22023';
    END IF;

    IF char_length(COALESCE(v_reason, '')) > 500 THEN
        RAISE EXCEPTION 'REASON_TOO_LONG: Reason exceeds 500 characters.'
            USING ERRCODE = '22001';
    END IF;

    IF v_decision = 'reject' AND v_reason IS NULL THEN
        RAISE EXCEPTION 'REJECTION_REASON_REQUIRED: A rejection reason is required.'
            USING ERRCODE = '22023';
    END IF;

    SELECT *
    INTO v_application
    FROM public.test_onboarding_applications
    WHERE id = p_application_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND: Test onboarding application not found.'
            USING ERRCODE = 'P0002';
    END IF;

    IF v_application.verification_state <> 'test_only_pending' THEN
        RAISE EXCEPTION 'ALREADY_REVIEWED: Test onboarding application is terminal.'
            USING ERRCODE = 'P0001';
    END IF;

    SELECT account_status
    INTO v_previous_account_status
    FROM public.profiles
    WHERE id = v_application.user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND: Applicant profile not found.'
            USING ERRCODE = 'P0002';
    END IF;

    IF v_previous_account_status <> 'pending_verification' THEN
        RAISE EXCEPTION 'INCONSISTENT_PROFILE_STATUS: Pending application requires a pending profile.'
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.user_roles
        WHERE user_id = v_application.user_id
          AND role = 'customer'
    ) THEN
        RAISE EXCEPTION 'INCONSISTENT_BASELINE_ROLE: Pending applicant lacks customer role.'
            USING ERRCODE = '42501';
    END IF;

    IF (v_application.requested_account_type = 'network_owner'
        AND v_application.owner_review_status <> 'pending')
       OR (v_application.requested_account_type = 'customer'
        AND v_application.owner_review_status <> 'not_requested') THEN
        RAISE EXCEPTION 'INCONSISTENT_REVIEW_STATE: Pending application state is incoherent.'
            USING ERRCODE = '42501';
    END IF;

    -- The signup path must never have granted the privileged owner role. Stop
    -- instead of silently normalising an inconsistent identity.
    IF EXISTS (
        SELECT 1
        FROM public.user_roles
        WHERE user_id = v_application.user_id
          AND role = 'network_owner'
    ) THEN
        RAISE EXCEPTION 'INCONSISTENT_OWNER_ROLE: Pending applicant already has network_owner.'
            USING ERRCODE = '42501';
    END IF;

    IF v_decision = 'approve' THEN
        v_account_status := 'active';
        v_verification_state := 'test_admin_approved';
        v_owner_review_status := CASE
            WHEN v_application.requested_account_type = 'network_owner'
                THEN 'approved'
            ELSE 'not_requested'
        END;

        UPDATE public.profiles
        SET account_status = v_account_status
        WHERE id = v_application.user_id;

        IF v_application.requested_account_type = 'network_owner' THEN
            INSERT INTO public.user_roles (user_id, role, created_by)
            VALUES (v_application.user_id, 'network_owner', v_actor_id);
        END IF;
    ELSE
        v_account_status := 'suspended';
        v_verification_state := 'rejected';
        v_owner_review_status := CASE
            WHEN v_application.requested_account_type = 'network_owner'
                THEN 'rejected'
            ELSE 'not_requested'
        END;

        UPDATE public.profiles
        SET account_status = v_account_status
        WHERE id = v_application.user_id;
    END IF;

    UPDATE public.test_onboarding_applications
    SET verification_state = v_verification_state,
        owner_review_status = v_owner_review_status
    WHERE id = p_application_id;

    PERFORM public.record_audit_event(
        'ADMIN_REVIEW_TEST_ONBOARDING',
        'test_onboarding_application',
        p_application_id::TEXT,
        'success',
        CASE
            WHEN v_decision = 'approve' THEN 'TEST_ADMIN_APPROVED'
            ELSE 'TEST_ADMIN_REJECTED'
        END,
        jsonb_build_object(
            'user_id', v_application.user_id,
            'requested_account_type', v_application.requested_account_type,
            'decision', v_decision,
            'reason', v_reason,
            'account_status', v_account_status,
            'owner_review_status', v_owner_review_status
        )
    );

    RETURN jsonb_build_object(
        'application_id', p_application_id,
        'user_id', v_application.user_id,
        'decision', v_decision,
        'account_status', v_account_status,
        'verification_state', v_verification_state,
        'owner_review_status', v_owner_review_status
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.admin_review_test_onboarding(UUID, TEXT, TEXT)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_test_onboarding(UUID, TEXT, TEXT)
    TO authenticated;
