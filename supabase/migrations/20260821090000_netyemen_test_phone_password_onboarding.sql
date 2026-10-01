-- WASEL NET controlled phone/password tester onboarding.
-- Source-only until the production migration gate is approved separately.

CREATE TABLE public.test_onboarding_applications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
    requested_account_type TEXT NOT NULL,
    verification_state TEXT NOT NULL DEFAULT 'test_only_pending',
    owner_review_status TEXT NOT NULL DEFAULT 'not_requested',
    governorate TEXT NOT NULL,
    city TEXT NOT NULL,
    latitude NUMERIC(9, 6) NOT NULL,
    longitude NUMERIC(9, 6) NOT NULL,
    location_accuracy_m NUMERIC(10, 2),
    invite_label TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_test_onboarding_account_type
        CHECK (requested_account_type IN ('customer', 'network_owner')),
    CONSTRAINT chk_test_onboarding_verification_state
        CHECK (verification_state IN ('test_only_pending', 'phone_verified', 'rejected')),
    CONSTRAINT chk_test_onboarding_owner_review
        CHECK (owner_review_status IN ('not_requested', 'pending', 'approved', 'rejected')),
    CONSTRAINT chk_test_onboarding_owner_request_coherence CHECK (
        (requested_account_type = 'customer' AND owner_review_status = 'not_requested') OR
        (requested_account_type = 'network_owner' AND owner_review_status IN ('pending', 'approved', 'rejected'))
    ),
    CONSTRAINT chk_test_onboarding_governorate_length
        CHECK (length(trim(governorate)) BETWEEN 2 AND 80),
    CONSTRAINT chk_test_onboarding_city_length
        CHECK (length(trim(city)) BETWEEN 2 AND 120),
    CONSTRAINT chk_test_onboarding_latitude CHECK (latitude BETWEEN -90 AND 90),
    CONSTRAINT chk_test_onboarding_longitude CHECK (longitude BETWEEN -180 AND 180),
    CONSTRAINT chk_test_onboarding_accuracy
        CHECK (location_accuracy_m IS NULL OR location_accuracy_m BETWEEN 0 AND 100000),
    CONSTRAINT chk_test_onboarding_invite_label_length
        CHECK (length(trim(invite_label)) BETWEEN 1 AND 80)
);

COMMENT ON TABLE public.test_onboarding_applications IS
    'Controlled pilot onboarding records. Exact location is private; a network_owner selection is only a pending request and never a role grant.';
COMMENT ON COLUMN public.test_onboarding_applications.verification_state IS
    'test_only_pending accounts are not telecom-verified and remain fail-closed through profiles.account_status=pending_verification.';
COMMENT ON COLUMN public.test_onboarding_applications.invite_label IS
    'Non-secret server-side invite identifier. The invite code or digest is never stored here.';

CREATE INDEX idx_test_onboarding_verification_state
    ON public.test_onboarding_applications (verification_state, created_at DESC);
CREATE INDEX idx_test_onboarding_owner_review
    ON public.test_onboarding_applications (owner_review_status, created_at DESC)
    WHERE requested_account_type = 'network_owner';

CREATE TRIGGER trg_test_onboarding_set_updated_at
    BEFORE UPDATE ON public.test_onboarding_applications
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.test_onboarding_applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.test_onboarding_applications FORCE ROW LEVEL SECURITY;

-- Test-invite accounts must be pending from the same transaction that creates
-- auth.users. raw_app_meta_data is admin-controlled; client-supplied metadata
-- cannot opt into or out of this state.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    v_account_status TEXT := 'active';
BEGIN
    IF COALESCE(NEW.raw_app_meta_data->>'onboarding_channel', '') = 'test_invite' THEN
        v_account_status := 'pending_verification';
    END IF;

    INSERT INTO public.profiles (id, full_name, account_status)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', ''),
        v_account_status
    )
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.user_roles (user_id, role, created_at)
    VALUES (NEW.id, 'customer', NOW())
    ON CONFLICT (user_id, role) DO NOTHING;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;

-- Called only by the invite-protected Edge Function after auth.admin.createUser.
-- It records the user's requested account type without granting privileged roles.
CREATE OR REPLACE FUNCTION public.register_test_onboarding(
    p_user_id UUID,
    p_requested_account_type TEXT,
    p_governorate TEXT,
    p_city TEXT,
    p_latitude NUMERIC,
    p_longitude NUMERIC,
    p_location_accuracy_m NUMERIC DEFAULT NULL,
    p_invite_label TEXT DEFAULT 'controlled-pilot'
)
RETURNS JSONB AS $$
DECLARE
    v_application_id UUID;
    v_owner_review_status TEXT;
BEGIN
    IF COALESCE(auth.role(), '') <> 'service_role' THEN
        RAISE EXCEPTION 'FORBIDDEN: test onboarding is service-only.'
            USING ERRCODE = '42501';
    END IF;

    IF p_requested_account_type NOT IN ('customer', 'network_owner') THEN
        RAISE EXCEPTION 'INVALID_ACCOUNT_TYPE' USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM auth.users u
        WHERE u.id = p_user_id
          AND COALESCE(u.raw_app_meta_data->>'onboarding_channel', '') = 'test_invite'
    ) THEN
        RAISE EXCEPTION 'INVALID_TEST_USER' USING ERRCODE = '22023';
    END IF;

    v_owner_review_status := CASE
        WHEN p_requested_account_type = 'network_owner' THEN 'pending'
        ELSE 'not_requested'
    END;

    INSERT INTO public.test_onboarding_applications (
        user_id,
        requested_account_type,
        verification_state,
        owner_review_status,
        governorate,
        city,
        latitude,
        longitude,
        location_accuracy_m,
        invite_label
    ) VALUES (
        p_user_id,
        p_requested_account_type,
        'test_only_pending',
        v_owner_review_status,
        trim(p_governorate),
        trim(p_city),
        p_latitude,
        p_longitude,
        p_location_accuracy_m,
        trim(p_invite_label)
    )
    RETURNING id INTO v_application_id;

    UPDATE public.profiles
    SET account_status = 'pending_verification',
        default_governorate = trim(p_governorate),
        default_city = trim(p_city)
    WHERE id = p_user_id;

    -- Explicitly preserve the least-privileged role. Owner access requires a
    -- later, audited administrative review outside this test signup flow.
    INSERT INTO public.user_roles (user_id, role, created_at)
    VALUES (p_user_id, 'customer', NOW())
    ON CONFLICT (user_id, role) DO NOTHING;

    PERFORM public.record_audit_event(
        'test_onboarding.created',
        'test_onboarding_application',
        v_application_id::TEXT,
        'success',
        'TEST_ONLY_PENDING_VERIFICATION',
        jsonb_build_object(
            'user_id', p_user_id,
            'requested_account_type', p_requested_account_type,
            'owner_review_status', v_owner_review_status,
            'invite_label', trim(p_invite_label)
        )
    );

    RETURN jsonb_build_object(
        'application_id', v_application_id,
        'verification_state', 'test_only_pending',
        'owner_review_status', v_owner_review_status
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp;

REVOKE EXECUTE ON FUNCTION public.register_test_onboarding(
    UUID, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC, TEXT
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_test_onboarding(
    UUID, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC, TEXT
) TO service_role;

REVOKE ALL ON TABLE public.test_onboarding_applications FROM PUBLIC;
GRANT SELECT ON TABLE public.test_onboarding_applications TO authenticated;

CREATE POLICY test_onboarding_select_own_or_admin
ON public.test_onboarding_applications
FOR SELECT
TO authenticated
USING (
    user_id = auth.uid()
    OR public.has_platform_role('platform_admin')
    OR public.has_platform_role('system_auditor')
);
