-- NetYemen Core Identity and Networks Schema Migration
-- Migration: 20260727090000_netyemen_core_identity_and_networks.sql
-- Task ID: NY-GOV-BE-001 / NY-GOV-BE-001B
-- Scope: Core Identity (profiles, user_roles) and Networks (networks, network_memberships, network_ssid_aliases)

-- Enable pgcrypto extension for UUID generation if needed
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- Helper Functions & Triggers
-- ============================================================================

-- Function to automatically set updated_at column on mutation
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- ============================================================================
-- 1. Table: public.profiles
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE RESTRICT,
    full_name TEXT,
    account_status TEXT NOT NULL DEFAULT 'active',
    default_governorate TEXT,
    default_city TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_profiles_account_status CHECK (account_status IN ('active', 'suspended', 'pending_verification', 'anonymized'))
);

COMMENT ON TABLE public.profiles IS 'NetYemen user profiles linked 1-to-1 with auth.users identity.';
COMMENT ON COLUMN public.profiles.account_status IS 'V1 approved user account lifecycle status (active, suspended, pending_verification, anonymized).';

CREATE INDEX IF NOT EXISTS idx_profiles_account_status ON public.profiles (account_status);

CREATE TRIGGER trg_profiles_set_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

-- Enable RLS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 2. Table: public.user_roles
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.user_roles (
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    PRIMARY KEY (user_id, role),
    CONSTRAINT chk_user_roles_active_v1_roles CHECK (
        role IN (
            'customer',
            'network_owner',
            'network_operator',
            'finance_officer',
            'support_agent',
            'platform_admin',
            'system_auditor',
            'system_service'
        )
    )
);

COMMENT ON TABLE public.user_roles IS 'Role assignments for NetYemen authorization matrix. Restricted strictly to 8 active V1 roles.';
COMMENT ON COLUMN public.user_roles.role IS 'Explicit V1 platform role assignment.';

CREATE INDEX IF NOT EXISTS idx_user_roles_user_id ON public.user_roles (user_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_role ON public.user_roles (role);

-- Enable RLS
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- Trigger: Automatic Profile and Customer Role Creation on auth.users Signup
-- (Fail-closed: No exception swallowing to guarantee atomic provisioning)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    -- Insert default user profile
    INSERT INTO public.profiles (id, full_name, account_status)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', ''),
        'active'
    )
    ON CONFLICT (id) DO NOTHING;

    -- Assign default 'customer' role
    INSERT INTO public.user_roles (user_id, role, created_at)
    VALUES (NEW.id, 'customer', NOW())
    ON CONFLICT (user_id, role) DO NOTHING;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- Trigger definition on auth.users
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth') THEN
        IF NOT EXISTS (
            SELECT 1 FROM pg_trigger WHERE tgname = 'on_auth_user_created'
        ) THEN
            CREATE TRIGGER on_auth_user_created
                AFTER INSERT ON auth.users
                FOR EACH ROW
                EXECUTE FUNCTION public.handle_new_user();
        END IF;
    END IF;
END $$;

-- ============================================================================
-- 3. Table: public.networks
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.networks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    commercial_name TEXT NOT NULL,
    description TEXT,
    governorate TEXT,
    city TEXT,
    district TEXT,
    status TEXT NOT NULL DEFAULT 'pending_approval',
    verification_status TEXT NOT NULL DEFAULT 'unverified',
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    approved_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_networks_commercial_name_length CHECK (length(trim(commercial_name)) > 0),
    CONSTRAINT chk_networks_status CHECK (status IN ('pending_approval', 'active', 'suspended', 'rejected')),
    CONSTRAINT chk_networks_verification_status CHECK (verification_status IN ('unverified', 'verified', 'rejected')),
    CONSTRAINT chk_networks_approval_state_coherence CHECK (
        (status = 'active' AND verification_status = 'verified' AND approved_by IS NOT NULL AND approved_at IS NOT NULL) OR
        (status = 'pending_approval' AND verification_status = 'unverified' AND approved_by IS NULL AND approved_at IS NULL) OR
        (status IN ('suspended', 'rejected'))
    )
);

COMMENT ON TABLE public.networks IS 'Commercial Wi-Fi hotspot network parent entities.';
COMMENT ON COLUMN public.networks.status IS 'Lifecycle state of the commercial network catalog listing.';
COMMENT ON COLUMN public.networks.verification_status IS 'Platform administrative verification status.';

CREATE INDEX IF NOT EXISTS idx_networks_status_verification ON public.networks (status, verification_status);
CREATE INDEX IF NOT EXISTS idx_networks_created_by ON public.networks (created_by);
CREATE INDEX IF NOT EXISTS idx_networks_governorate_city ON public.networks (governorate, city);

CREATE TRIGGER trg_networks_set_updated_at
    BEFORE UPDATE ON public.networks
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

-- Enable RLS
ALTER TABLE public.networks ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 4. Table: public.network_memberships
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.network_memberships (
    network_id UUID NOT NULL REFERENCES public.networks(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    membership_role TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    PRIMARY KEY (network_id, user_id),
    CONSTRAINT chk_network_memberships_role CHECK (membership_role IN ('owner', 'operator')),
    CONSTRAINT chk_network_memberships_status CHECK (status IN ('active', 'inactive', 'suspended'))
);

COMMENT ON TABLE public.network_memberships IS 'Explicit user membership relationships for hotspot network authorization (owner, operator).';

CREATE INDEX IF NOT EXISTS idx_network_memberships_user ON public.network_memberships (user_id, status);
CREATE INDEX IF NOT EXISTS idx_network_memberships_role ON public.network_memberships (membership_role);

CREATE TRIGGER trg_network_memberships_set_updated_at
    BEFORE UPDATE ON public.network_memberships
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

-- Enable RLS
ALTER TABLE public.network_memberships ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 5. Table: public.network_ssid_aliases
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.network_ssid_aliases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    network_id UUID NOT NULL REFERENCES public.networks(id) ON DELETE CASCADE,
    ssid_display TEXT NOT NULL,
    ssid_normalized TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending_verification',
    verified_at TIMESTAMPTZ,
    verified_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_ssid_aliases_display_non_empty CHECK (length(trim(ssid_display)) > 0),
    CONSTRAINT chk_ssid_aliases_display_length CHECK (char_length(ssid_display) <= 32),
    CONSTRAINT chk_ssid_aliases_normalized_non_empty CHECK (length(trim(ssid_normalized)) > 0),
    CONSTRAINT chk_ssid_aliases_normalized_length CHECK (char_length(ssid_normalized) <= 64),
    CONSTRAINT chk_ssid_aliases_status CHECK (status IN ('pending_verification', 'active', 'suspended', 'rejected')),
    CONSTRAINT chk_ssid_aliases_verification_coherence CHECK (
        (status = 'active' AND verified_by IS NOT NULL AND verified_at IS NOT NULL) OR
        (status = 'pending_verification' AND verified_by IS NULL AND verified_at IS NULL) OR
        (status IN ('suspended', 'rejected'))
    )
);

COMMENT ON TABLE public.network_ssid_aliases IS 'Wi-Fi SSID broadcast aliases mapping to parent networks. Excludes BSSID and hardware serial numbers.';

CREATE INDEX IF NOT EXISTS idx_network_ssid_aliases_network ON public.network_ssid_aliases (network_id);
CREATE INDEX IF NOT EXISTS idx_network_ssid_aliases_normalized ON public.network_ssid_aliases (ssid_normalized);

-- Unique Active Normalized SSID Alias Partial Index across all active networks
CREATE UNIQUE INDEX IF NOT EXISTS idx_network_ssid_aliases_unique_active_normalized
    ON public.network_ssid_aliases (ssid_normalized)
    WHERE status = 'active';

CREATE TRIGGER trg_network_ssid_aliases_set_updated_at
    BEFORE UPDATE ON public.network_ssid_aliases
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

-- Enable RLS
ALTER TABLE public.network_ssid_aliases ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- Least-privilege table grants (explicit privileges only; never grant-all)
-- ============================================================================

REVOKE ALL ON TABLE public.profiles FROM PUBLIC;
REVOKE ALL ON TABLE public.user_roles FROM PUBLIC;
REVOKE ALL ON TABLE public.networks FROM PUBLIC;
REVOKE ALL ON TABLE public.network_memberships FROM PUBLIC;
REVOKE ALL ON TABLE public.network_ssid_aliases FROM PUBLIC;

-- Profile creation strictly via trusted auth trigger; no direct INSERT grant for clients!
REVOKE ALL ON TABLE public.profiles FROM authenticated;
GRANT SELECT ON TABLE public.profiles TO authenticated;
GRANT UPDATE (full_name, default_governorate, default_city) ON TABLE public.profiles TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.user_roles TO authenticated;

-- Network creation strictly via create_network_draft RPC; no direct INSERT grant for clients!
REVOKE ALL ON TABLE public.networks FROM authenticated;
GRANT SELECT, UPDATE ON TABLE public.networks TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.network_memberships TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.network_ssid_aliases TO authenticated;

-- Anonymous catalog visibility (RLS further restricts to active+verified)
REVOKE ALL ON TABLE public.networks FROM anon;
GRANT SELECT (id, commercial_name, description, governorate, city, district, status, verification_status) ON TABLE public.networks TO anon;

REVOKE ALL ON TABLE public.network_ssid_aliases FROM anon;
GRANT SELECT (id, network_id, ssid_display, ssid_normalized, status) ON TABLE public.network_ssid_aliases TO anon;
