-- NetYemen Network Addition Requests Migration
-- Migration: 20260727130000_netyemen_network_addition_requests.sql
-- Task ID: NY-V1-NETWORK-DISCOVERY-001
-- Scope: Network addition request table, RPC, RLS policies
-- Privacy: No BSSID, MAC, device ID, latitude, longitude, Wi-Fi password, or IP storage

-- ============================================================================
-- 1. Table: public.network_addition_requests
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.network_addition_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    idempotency_key UUID NOT NULL,
    proposed_network_name TEXT,
    observed_ssid_display TEXT NOT NULL,
    observed_ssid_normalized TEXT NOT NULL,
    governorate TEXT,
    city TEXT,
    district TEXT,
    notes TEXT,
    status TEXT NOT NULL DEFAULT 'submitted',
    duplicate_of UUID REFERENCES public.network_addition_requests(id) ON DELETE SET NULL,
    matched_network_id UUID REFERENCES public.networks(id) ON DELETE SET NULL,
    resolution_note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMPTZ,
    resolved_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    CONSTRAINT chk_network_addition_requests_status CHECK (
        status IN ('submitted', 'under_review', 'matched_existing', 'approved', 'rejected', 'cancelled')
    ),
    CONSTRAINT chk_network_addition_requests_ssid_display_non_empty CHECK (
        length(trim(observed_ssid_display)) > 0
    ),
    CONSTRAINT chk_network_addition_requests_ssid_display_length CHECK (
        char_length(observed_ssid_display) <= 64
    ),
    CONSTRAINT chk_network_addition_requests_ssid_normalized_non_empty CHECK (
        length(trim(observed_ssid_normalized)) > 0
    ),
    CONSTRAINT chk_network_addition_requests_notes_length CHECK (
        char_length(notes) <= 500
    ),
    CONSTRAINT chk_network_addition_requests_proposed_name_length CHECK (
        proposed_network_name IS NULL OR char_length(proposed_network_name) <= 100
    ),
    CONSTRAINT chk_network_addition_requests_resolution_note_length CHECK (
        resolution_note IS NULL OR char_length(resolution_note) <= 500
    ),
    CONSTRAINT chk_network_addition_requests_resolved_coherence CHECK (
        (status IN ('approved', 'rejected', 'matched_existing') AND resolved_at IS NOT NULL AND resolved_by IS NOT NULL) OR
        (status IN ('submitted', 'under_review', 'cancelled') AND resolved_at IS NULL)
    )
);

COMMENT ON TABLE public.network_addition_requests IS 'Customer-submitted requests to add new Wi-Fi networks not yet in the approved catalog. Privacy-first: no BSSID, MAC, device ID, or location coordinates.';

CREATE INDEX IF NOT EXISTS idx_network_addition_requests_requester ON public.network_addition_requests (requester_user_id);
CREATE INDEX IF NOT EXISTS idx_network_addition_requests_status ON public.network_addition_requests (status);
CREATE INDEX IF NOT EXISTS idx_network_addition_requests_normalized_ssid ON public.network_addition_requests (observed_ssid_normalized);
CREATE INDEX IF NOT EXISTS idx_network_addition_requests_created_at ON public.network_addition_requests (created_at);
CREATE UNIQUE INDEX IF NOT EXISTS idx_network_addition_requests_idempotency ON public.network_addition_requests (requester_user_id, idempotency_key);

CREATE TRIGGER trg_network_addition_requests_set_updated_at
    BEFORE UPDATE ON public.network_addition_requests
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.network_addition_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.network_addition_requests FORCE ROW LEVEL SECURITY;

-- Least-privilege grants
REVOKE ALL ON TABLE public.network_addition_requests FROM PUBLIC;
GRANT SELECT ON TABLE public.network_addition_requests TO authenticated;
-- No direct INSERT grant; submission is strictly via submit_network_addition_request RPC

-- ============================================================================
-- 2. RPC: public.submit_network_addition_request
-- ============================================================================

CREATE OR REPLACE FUNCTION public.submit_network_addition_request(
    p_idempotency_key UUID,
    p_observed_ssid_display TEXT,
    p_proposed_network_name TEXT DEFAULT NULL,
    p_governorate TEXT DEFAULT NULL,
    p_city TEXT DEFAULT NULL,
    p_district TEXT DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_normalized TEXT;
    v_existing_id UUID;
    v_request_id UUID;
    v_result JSONB;
BEGIN
    -- 1. Authenticate
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    -- 2. Require active profile
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = v_user_id AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'INACTIVE_PROFILE: Account is not active.'
            USING ERRCODE = '42501';
    END IF;

    -- 3. Validate SSID
    IF p_observed_ssid_display IS NULL OR length(trim(p_observed_ssid_display)) = 0 THEN
        RAISE EXCEPTION 'INVALID_SSID: Observed SSID cannot be empty.'
            USING ERRCODE = '22000';
    END IF;

    IF char_length(p_observed_ssid_display) > 64 THEN
        RAISE EXCEPTION 'SSID_TOO_LONG: Observed SSID exceeds 64 characters.'
            USING ERRCODE = '22000';
    END IF;

    -- 4. Validate notes length
    IF p_notes IS NOT NULL AND char_length(p_notes) > 500 THEN
        RAISE EXCEPTION 'NOTES_TOO_LONG: Notes exceed 500 characters.'
            USING ERRCODE = '22000';
    END IF;

    -- 5. Validate proposed name length
    IF p_proposed_network_name IS NOT NULL AND char_length(p_proposed_network_name) > 100 THEN
        RAISE EXCEPTION 'NAME_TOO_LONG: Proposed network name exceeds 100 characters.'
            USING ERRCODE = '22000';
    END IF;

    -- 6. Validate idempotency key
    IF p_idempotency_key IS NULL THEN
        RAISE EXCEPTION 'MISSING_IDEMPOTENCY: Idempotency key is required.'
            USING ERRCODE = '22000';
    END IF;

    -- 7. Check idempotency: same requester + same key = return existing
    SELECT id INTO v_existing_id
    FROM public.network_addition_requests
    WHERE requester_user_id = v_user_id
      AND idempotency_key = p_idempotency_key;

    IF v_existing_id IS NOT NULL THEN
        SELECT jsonb_build_object(
            'id', r.id,
            'status', r.status
        ) INTO v_result
        FROM public.network_addition_requests r
        WHERE r.id = v_existing_id;

        RETURN v_result;
    END IF;

    -- 8. Derive normalized SSID in database (client cannot override)
    v_normalized := public.normalize_ssid(p_observed_ssid_display);

    IF length(v_normalized) = 0 THEN
        RAISE EXCEPTION 'INVALID_SSID_NORMALIZED: Normalized SSID is empty after processing.'
            USING ERRCODE = '22000';
    END IF;

    -- 9. Check for existing open request with same normalized SSID (any requester)
    SELECT id INTO v_existing_id
    FROM public.network_addition_requests
    WHERE observed_ssid_normalized = v_normalized
      AND status IN ('submitted', 'under_review')
    ORDER BY created_at ASC
    LIMIT 1;

    -- 10. Insert the new request
    INSERT INTO public.network_addition_requests (
        requester_user_id,
        idempotency_key,
        proposed_network_name,
        observed_ssid_display,
        observed_ssid_normalized,
        governorate,
        city,
        district,
        notes,
        status,
        duplicate_of
    ) VALUES (
        v_user_id,
        p_idempotency_key,
        trim(p_proposed_network_name),
        trim(p_observed_ssid_display),
        v_normalized,
        p_governorate,
        p_city,
        p_district,
        p_notes,
        'submitted',
        v_existing_id
    ) RETURNING id INTO v_request_id;

    -- 11. Return safe result (only caller's own request ID and status)
    SELECT jsonb_build_object(
        'id', r.id,
        'status', r.status
    ) INTO v_result
    FROM public.network_addition_requests r
    WHERE r.id = v_request_id;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.submit_network_addition_request(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_network_addition_request(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- ============================================================================
-- 3. RPC: public.cancel_network_addition_request
-- ============================================================================

CREATE OR REPLACE FUNCTION public.cancel_network_addition_request(
    p_request_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_current_status TEXT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    -- Only the requester can cancel their own submitted request
    SELECT status INTO v_current_status
    FROM public.network_addition_requests
    WHERE id = p_request_id
      AND requester_user_id = v_user_id;

    IF v_current_status IS NULL THEN
        RAISE EXCEPTION 'NOT_FOUND: Request not found or not owned by caller.'
            USING ERRCODE = '42501';
    END IF;

    IF v_current_status != 'submitted' THEN
        RAISE EXCEPTION 'INVALID_STATE: Only submitted requests can be cancelled.'
            USING ERRCODE = '42501';
    END IF;

    UPDATE public.network_addition_requests
    SET status = 'cancelled',
        updated_at = NOW()
    WHERE id = p_request_id
      AND requester_user_id = v_user_id;

    RETURN jsonb_build_object('id', p_request_id, 'status', 'cancelled');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.cancel_network_addition_request(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_network_addition_request(UUID) TO authenticated;

-- ============================================================================
-- 4. RPC: public.resolve_network_addition_request (admin/support)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.resolve_network_addition_request(
    p_request_id UUID,
    p_new_status TEXT,
    p_resolution_note TEXT DEFAULT NULL,
    p_matched_network_id UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    -- Only platform_admin or support_agent can resolve
    IF NOT (public.has_platform_role('platform_admin') OR public.has_platform_role('support_agent')) THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE: Only platform_admin or support_agent can resolve requests.'
            USING ERRCODE = '42501';
    END IF;

    IF p_new_status NOT IN ('under_review', 'matched_existing', 'approved', 'rejected') THEN
        RAISE EXCEPTION 'INVALID_STATUS: Resolution status must be under_review, matched_existing, approved, or rejected.'
            USING ERRCODE = '22000';
    END IF;

    IF p_resolution_note IS NOT NULL AND char_length(p_resolution_note) > 500 THEN
        RAISE EXCEPTION 'NOTE_TOO_LONG: Resolution note exceeds 500 characters.'
            USING ERRCODE = '22000';
    END IF;

    UPDATE public.network_addition_requests
    SET status = p_new_status,
        resolution_note = p_resolution_note,
        matched_network_id = p_matched_network_id,
        resolved_at = CASE
            WHEN p_new_status IN ('approved', 'rejected', 'matched_existing') THEN NOW()
            ELSE resolved_at
        END,
        resolved_by = CASE
            WHEN p_new_status IN ('approved', 'rejected', 'matched_existing') THEN v_user_id
            ELSE resolved_by
        END,
        updated_at = NOW()
    WHERE id = p_request_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND: Request not found.'
            USING ERRCODE = '42501';
    END IF;

    RETURN jsonb_build_object('id', p_request_id, 'status', p_new_status);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.resolve_network_addition_request(UUID, TEXT, TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_network_addition_request(UUID, TEXT, TEXT, UUID) TO authenticated;

-- ============================================================================
-- 5. RLS Policies for network_addition_requests
-- ============================================================================

-- Customer: read own requests only
DROP POLICY IF EXISTS network_addition_requests_customer_select_policy ON public.network_addition_requests;
CREATE POLICY network_addition_requests_customer_select_policy ON public.network_addition_requests
    FOR SELECT
    USING (
        requester_user_id = auth.uid()
    );

-- Support agent: read requests needed for triage
DROP POLICY IF EXISTS network_addition_requests_support_select_policy ON public.network_addition_requests;
CREATE POLICY network_addition_requests_support_select_policy ON public.network_addition_requests
    FOR SELECT
    USING (
        public.has_platform_role('support_agent')
    );

-- Platform admin: full read access
DROP POLICY IF EXISTS network_addition_requests_admin_select_policy ON public.network_addition_requests;
CREATE POLICY network_addition_requests_admin_select_policy ON public.network_addition_requests
    FOR SELECT
    USING (
        public.has_platform_role('platform_admin')
    );

-- Auditor: read-only governance access
DROP POLICY IF EXISTS network_addition_requests_auditor_select_policy ON public.network_addition_requests;
CREATE POLICY network_addition_requests_auditor_select_policy ON public.network_addition_requests
    FOR SELECT
    USING (
        public.has_platform_role('system_auditor')
    );

-- Support agent: update allowed review fields through resolve RPC only (no direct UPDATE policy)
-- Platform admin: update through resolve RPC only (no direct UPDATE policy)
-- No direct UPDATE policy — all mutations go through controlled RPCs

-- Force RLS
ALTER TABLE public.network_addition_requests FORCE ROW LEVEL SECURITY;
