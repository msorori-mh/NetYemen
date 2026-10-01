-- NetYemen Network Package Catalog Foundation
-- Migration: 20260728090000_netyemen_network_packages.sql
-- Task ID: NY-V1-INVENTORY-PACKAGES-001
-- Scope: Public package catalog and owner package management (NO card secrets)
-- Governance: OD-CARD-01 remains OPEN; this migration MUST NOT store Wi-Fi credentials, voucher codes, card payloads, or secrets.

-- ============================================================================
-- 1. Table: public.network_packages
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.network_packages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    network_id UUID NOT NULL REFERENCES public.networks(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    price INTEGER NOT NULL,
    currency TEXT NOT NULL DEFAULT 'YER',
    duration_value INTEGER,
    duration_unit TEXT,
    speed_mbps INTEGER,
    package_type TEXT NOT NULL DEFAULT 'time',
    status TEXT NOT NULL DEFAULT 'draft',
    is_public BOOLEAN NOT NULL DEFAULT FALSE,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_network_packages_name_non_empty CHECK (length(trim(name)) > 0),
    CONSTRAINT chk_network_packages_price_non_negative CHECK (price >= 0),
    CONSTRAINT chk_network_packages_duration_positive CHECK (duration_value IS NULL OR duration_value > 0),
    CONSTRAINT chk_network_packages_speed_non_negative CHECK (speed_mbps IS NULL OR speed_mbps >= 0),
    CONSTRAINT chk_network_packages_duration_unit CHECK (duration_unit IS NULL OR duration_unit IN ('hour', 'day', 'week', 'month')),
    CONSTRAINT chk_network_packages_type CHECK (package_type IN ('time', 'volume', 'unlimited')),
    CONSTRAINT chk_network_packages_status CHECK (status IN ('draft', 'active', 'inactive', 'archived')),
    CONSTRAINT chk_network_packages_public_requires_active CHECK (
        is_public = FALSE OR (is_public = TRUE AND status = 'active')
    )
);

COMMENT ON TABLE public.network_packages IS 'Commercial network package catalog. V1 non-secret package definitions only; no card/voucher/secret storage.';
COMMENT ON COLUMN public.network_packages.status IS 'Lifecycle state: draft, active, inactive, archived.';
COMMENT ON COLUMN public.network_packages.is_public IS 'When TRUE and status=active and network is approved, the package appears in the public customer catalog.';
COMMENT ON COLUMN public.network_packages.price IS 'Price in smallest currency unit (e.g., YER fils/rial integer). No decimals to avoid floating-point financial errors.';

CREATE INDEX IF NOT EXISTS idx_network_packages_network ON public.network_packages (network_id);
CREATE INDEX IF NOT EXISTS idx_network_packages_status ON public.network_packages (status);
CREATE INDEX IF NOT EXISTS idx_network_packages_public_catalog ON public.network_packages (network_id, status, is_public, sort_order);

CREATE TRIGGER trg_network_packages_set_updated_at
    BEFORE UPDATE ON public.network_packages
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.network_packages ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 2. Authorization Helpers
-- ============================================================================

-- Helper: Check if current user can manage packages for a network (active owner)
CREATE OR REPLACE FUNCTION public.can_manage_package_network(p_network_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF auth.uid() IS NULL OR p_network_id IS NULL THEN
        RETURN FALSE;
    END IF;
    RETURN public.can_manage_network(p_network_id);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp;

-- Helper: Check if current user can operate inventory for a network (active owner OR operator)
CREATE OR REPLACE FUNCTION public.can_operate_package_network(p_network_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF auth.uid() IS NULL OR p_network_id IS NULL THEN
        RETURN FALSE;
    END IF;
    RETURN public.is_network_member(p_network_id);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp;

-- Helper: Check if a package is visible in the public customer catalog
CREATE OR REPLACE FUNCTION public.is_package_publicly_visible(p_package_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM public.network_packages p
        JOIN public.networks n ON n.id = p.network_id
        WHERE p.id = p_package_id
          AND p.status = 'active'
          AND p.is_public = TRUE
          AND n.status = 'active'
          AND n.verification_status = 'verified'
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.can_manage_package_network(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.can_operate_package_network(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.is_package_publicly_visible(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_manage_package_network(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.can_operate_package_network(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_package_publicly_visible(UUID) TO anon, authenticated;

-- ============================================================================
-- 3. Controlled Package RPCs
-- ============================================================================

-- ----------------------------------------------------------------------------
-- RPC: create_network_package
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_network_package(
    p_network_id UUID,
    p_name TEXT,
    p_description TEXT DEFAULT NULL,
    p_price INTEGER DEFAULT 0,
    p_currency TEXT DEFAULT 'YER',
    p_duration_value INTEGER DEFAULT NULL,
    p_duration_unit TEXT DEFAULT NULL,
    p_speed_mbps INTEGER DEFAULT NULL,
    p_package_type TEXT DEFAULT 'time'
)
RETURNS UUID AS $$
DECLARE
    v_user_id UUID;
    v_package_id UUID;
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

    IF NOT public.can_manage_package_network(p_network_id) THEN
        RAISE EXCEPTION 'FORBIDDEN: Not authorized to manage packages for this network.'
            USING ERRCODE = '42501';
    END IF;

    IF p_name IS NULL OR length(trim(p_name)) = 0 THEN
        RAISE EXCEPTION 'INVALID_NAME: Package name cannot be empty.'
            USING ERRCODE = '22000';
    END IF;

    IF p_price < 0 THEN
        RAISE EXCEPTION 'INVALID_PRICE: Price cannot be negative.'
            USING ERRCODE = '22000';
    END IF;

    INSERT INTO public.network_packages (
        network_id,
        name,
        description,
        price,
        currency,
        duration_value,
        duration_unit,
        speed_mbps,
        package_type,
        status,
        is_public,
        sort_order,
        created_by
    ) VALUES (
        p_network_id,
        trim(p_name),
        p_description,
        p_price,
        COALESCE(p_currency, 'YER'),
        p_duration_value,
        p_duration_unit,
        p_speed_mbps,
        COALESCE(p_package_type, 'time'),
        'draft',
        FALSE,
        0,
        v_user_id
    ) RETURNING id INTO v_package_id;

    RETURN v_package_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.create_network_package(UUID, TEXT, TEXT, INTEGER, TEXT, INTEGER, TEXT, INTEGER, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_network_package(UUID, TEXT, TEXT, INTEGER, TEXT, INTEGER, TEXT, INTEGER, TEXT) TO authenticated;

-- ----------------------------------------------------------------------------
-- RPC: update_network_package
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_network_package(
    p_package_id UUID,
    p_name TEXT DEFAULT NULL,
    p_description TEXT DEFAULT NULL,
    p_price INTEGER DEFAULT NULL,
    p_currency TEXT DEFAULT NULL,
    p_duration_value INTEGER DEFAULT NULL,
    p_duration_unit TEXT DEFAULT NULL,
    p_speed_mbps INTEGER DEFAULT NULL,
    p_package_type TEXT DEFAULT NULL,
    p_sort_order INTEGER DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_network_id UUID;
    v_current_status TEXT;
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

    SELECT network_id, status INTO v_network_id, v_current_status
    FROM public.network_packages
    WHERE id = p_package_id;

    IF v_network_id IS NULL THEN
        RAISE EXCEPTION 'NOT_FOUND: Package not found.'
            USING ERRCODE = '42501';
    END IF;

    IF NOT public.can_manage_package_network(v_network_id) THEN
        RAISE EXCEPTION 'FORBIDDEN: Not authorized to update packages for this network.'
            USING ERRCODE = '42501';
    END IF;

    IF v_current_status = 'archived' THEN
        RAISE EXCEPTION 'INVALID_STATE: Archived packages cannot be edited.'
            USING ERRCODE = '22000';
    END IF;

    UPDATE public.network_packages
    SET
        name = COALESCE(trim(p_name), name),
        description = COALESCE(p_description, description),
        price = COALESCE(p_price, price),
        currency = COALESCE(p_currency, currency),
        duration_value = COALESCE(p_duration_value, duration_value),
        duration_unit = COALESCE(p_duration_unit, duration_unit),
        speed_mbps = COALESCE(p_speed_mbps, speed_mbps),
        package_type = COALESCE(p_package_type, package_type),
        sort_order = COALESCE(p_sort_order, sort_order),
        updated_at = NOW()
    WHERE id = p_package_id;

    RETURN jsonb_build_object('id', p_package_id, 'updated', TRUE);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.update_network_package(UUID, TEXT, TEXT, INTEGER, TEXT, INTEGER, TEXT, INTEGER, TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_network_package(UUID, TEXT, TEXT, INTEGER, TEXT, INTEGER, TEXT, INTEGER, TEXT, INTEGER) TO authenticated;

-- ----------------------------------------------------------------------------
-- RPC: publish_network_package
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.publish_network_package(
    p_package_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_network_id UUID;
    v_current_status TEXT;
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

    SELECT network_id, status INTO v_network_id, v_current_status
    FROM public.network_packages
    WHERE id = p_package_id;

    IF v_network_id IS NULL THEN
        RAISE EXCEPTION 'NOT_FOUND: Package not found.'
            USING ERRCODE = '42501';
    END IF;

    IF NOT public.can_manage_package_network(v_network_id) THEN
        RAISE EXCEPTION 'FORBIDDEN: Not authorized to publish packages for this network.'
            USING ERRCODE = '42501';
    END IF;

    IF v_current_status = 'archived' THEN
        RAISE EXCEPTION 'INVALID_STATE: Archived packages cannot be published.'
            USING ERRCODE = '22000';
    END IF;

    UPDATE public.network_packages
    SET status = 'active', is_public = TRUE, updated_at = NOW()
    WHERE id = p_package_id;

    RETURN jsonb_build_object('id', p_package_id, 'status', 'active');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.publish_network_package(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.publish_network_package(UUID) TO authenticated;

-- ----------------------------------------------------------------------------
-- RPC: archive_network_package
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.archive_network_package(
    p_package_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_network_id UUID;
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

    SELECT network_id INTO v_network_id
    FROM public.network_packages
    WHERE id = p_package_id;

    IF v_network_id IS NULL THEN
        RAISE EXCEPTION 'NOT_FOUND: Package not found.'
            USING ERRCODE = '42501';
    END IF;

    IF NOT public.can_manage_package_network(v_network_id) THEN
        RAISE EXCEPTION 'FORBIDDEN: Not authorized to archive packages for this network.'
            USING ERRCODE = '42501';
    END IF;

    UPDATE public.network_packages
    SET status = 'archived', is_public = FALSE, updated_at = NOW()
    WHERE id = p_package_id;

    RETURN jsonb_build_object('id', p_package_id, 'status', 'archived');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.archive_network_package(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.archive_network_package(UUID) TO authenticated;

-- ----------------------------------------------------------------------------
-- RPC: deactivate_network_package
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.deactivate_network_package(
    p_package_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_network_id UUID;
    v_current_status TEXT;
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

    SELECT network_id, status INTO v_network_id, v_current_status
    FROM public.network_packages
    WHERE id = p_package_id;

    IF v_network_id IS NULL THEN
        RAISE EXCEPTION 'NOT_FOUND: Package not found.'
            USING ERRCODE = '42501';
    END IF;

    IF NOT public.can_manage_package_network(v_network_id) THEN
        RAISE EXCEPTION 'FORBIDDEN: Not authorized to deactivate packages for this network.'
            USING ERRCODE = '42501';
    END IF;

    IF v_current_status != 'active' THEN
        RAISE EXCEPTION 'INVALID_STATE: Only active packages can be deactivated.'
            USING ERRCODE = '22000';
    END IF;

    UPDATE public.network_packages
    SET status = 'inactive', is_public = FALSE, updated_at = NOW()
    WHERE id = p_package_id;

    RETURN jsonb_build_object('id', p_package_id, 'status', 'inactive');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.deactivate_network_package(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.deactivate_network_package(UUID) TO authenticated;

-- ============================================================================
-- 4. Row-Level Security Policies for network_packages
-- ============================================================================

-- Least-privilege table grants
REVOKE ALL ON TABLE public.network_packages FROM PUBLIC;
GRANT SELECT ON TABLE public.network_packages TO anon;
GRANT SELECT ON TABLE public.network_packages TO authenticated;

-- ----------------------------------------------------------------------------
-- Policies for public.network_packages
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS network_packages_public_select_policy ON public.network_packages;
CREATE POLICY network_packages_public_select_policy ON public.network_packages
    FOR SELECT
    USING (
        status = 'active'
        AND is_public = TRUE
        AND EXISTS (
            SELECT 1 FROM public.networks n
            WHERE n.id = network_id
              AND n.status = 'active'
              AND n.verification_status = 'verified'
        )
    );

DROP POLICY IF EXISTS network_packages_owner_select_policy ON public.network_packages;
CREATE POLICY network_packages_owner_select_policy ON public.network_packages
    FOR SELECT
    USING (
        public.can_operate_package_network(network_id)
        OR public.has_platform_role('platform_admin')
        OR public.has_platform_role('system_auditor')
    );

-- Note: No direct INSERT/UPDATE/DELETE policy. Package lifecycle is controlled via RPCs only.

-- Force RLS
ALTER TABLE public.network_packages FORCE ROW LEVEL SECURITY;
