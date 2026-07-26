-- NetYemen Core RLS Policies, Authorization Helpers, and Audit Migration
-- Migration: 20260727091000_netyemen_core_rls_and_audit.sql
-- Task ID: NY-GOV-BE-001
-- Scope: Security Definer helpers, public.audit_events table, and RLS policies across all core tables

-- ============================================================================
-- 1. Authorization Helper Functions (SECURITY DEFINER)
-- ============================================================================

-- Helper: Check if current authenticated user has a specific platform role
CREATE OR REPLACE FUNCTION public.has_platform_role(p_role TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN FALSE;
    END IF;
    RETURN EXISTS (
        SELECT 1
        FROM public.user_roles
        WHERE user_id = auth.uid()
          AND role = p_role
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- Helper: Check if current authenticated user is an active member (owner or operator) of a network
CREATE OR REPLACE FUNCTION public.is_network_member(p_network_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF auth.uid() IS NULL OR p_network_id IS NULL THEN
        RETURN FALSE;
    END IF;
    RETURN EXISTS (
        SELECT 1
        FROM public.network_memberships
        WHERE network_id = p_network_id
          AND user_id = auth.uid()
          AND status = 'active'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- Helper: Check if current authenticated user is an active OWNER of a network
CREATE OR REPLACE FUNCTION public.can_manage_network(p_network_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF auth.uid() IS NULL OR p_network_id IS NULL THEN
        RETURN FALSE;
    END IF;
    RETURN EXISTS (
        SELECT 1
        FROM public.network_memberships
        WHERE network_id = p_network_id
          AND user_id = auth.uid()
          AND membership_role = 'owner'
          AND status = 'active'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- Helper: Normalize SSID string (lowercase, trim, replace spaces/special chars with hyphens)
CREATE OR REPLACE FUNCTION public.normalize_ssid(p_ssid TEXT)
RETURNS TEXT AS $$
DECLARE
    v_normalized TEXT;
BEGIN
    IF p_ssid IS NULL OR length(trim(p_ssid)) = 0 THEN
        RETURN '';
    END IF;
    -- Lowercase, trim spaces
    v_normalized := lower(trim(p_ssid));
    -- Replace non-alphanumeric characters with single hyphen
    v_normalized := regexp_replace(v_normalized, '[^a-z0-9]+', '-', 'g');
    -- Trim leading and trailing hyphens
    v_normalized := regexp_replace(v_normalized, '^-+|-+$', '', 'g');
    RETURN v_normalized;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT SECURITY DEFINER SET search_path = public, pg_temp;

-- ============================================================================
-- 2. Table: public.audit_events (Immutable Audit Trail)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.audit_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    actor_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    actor_role TEXT,
    action TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id TEXT,
    result TEXT NOT NULL DEFAULT 'success',
    reason_code TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    correlation_id UUID,
    CONSTRAINT chk_audit_events_result CHECK (result IN ('success', 'failure', 'denied')),
    CONSTRAINT chk_audit_events_metadata_size CHECK (octet_length(metadata::text) <= 8192)
);

COMMENT ON TABLE public.audit_events IS 'Immutable, append-only system audit log for security, authorization, and administrative events.';

CREATE INDEX IF NOT EXISTS idx_audit_events_actor ON public.audit_events (actor_user_id);
CREATE INDEX IF NOT EXISTS idx_audit_events_action ON public.audit_events (action);
CREATE INDEX IF NOT EXISTS idx_audit_events_occurred_at ON public.audit_events (occurred_at);
CREATE INDEX IF NOT EXISTS idx_audit_events_entity ON public.audit_events (entity_type, entity_id);

-- Enable RLS
ALTER TABLE public.audit_events ENABLE ROW LEVEL SECURITY;

-- Prevent UPDATE or DELETE on audit_events at database level
CREATE OR REPLACE FUNCTION public.prevent_audit_events_mutation()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'MUTATION_FORBIDDEN: public.audit_events is an append-only log. UPDATE and DELETE operations are prohibited.'
        USING ERRCODE = '42501';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger WHERE tgname = 'trg_prevent_audit_events_mutation'
    ) THEN
        CREATE TRIGGER trg_prevent_audit_events_mutation
            BEFORE UPDATE OR DELETE ON public.audit_events
            FOR EACH ROW
            EXECUTE FUNCTION public.prevent_audit_events_mutation();
    END IF;
END $$;

-- Centralized Audit Logging Function
CREATE OR REPLACE FUNCTION public.record_audit_event(
    p_action TEXT,
    p_entity_type TEXT,
    p_entity_id TEXT DEFAULT NULL,
    p_result TEXT DEFAULT 'success',
    p_reason_code TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'::jsonb,
    p_correlation_id UUID DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_actor_user_id UUID;
    v_actor_role TEXT;
    v_event_id UUID;
BEGIN
    v_actor_user_id := auth.uid();

    -- Resolve primary role for actor if authenticated
    IF v_actor_user_id IS NOT NULL THEN
        SELECT role INTO v_actor_role
        FROM public.user_roles
        WHERE user_id = v_actor_user_id
        ORDER BY
            CASE role
                WHEN 'platform_admin' THEN 1
                WHEN 'system_auditor' THEN 2
                WHEN 'finance_officer' THEN 3
                WHEN 'support_agent' THEN 4
                WHEN 'network_owner' THEN 5
                WHEN 'network_operator' THEN 6
                WHEN 'customer' THEN 7
                ELSE 8
            END
        LIMIT 1;
    ELSE
        v_actor_role := 'unauthenticated';
    END IF;

    -- Enforce payload size limit
    IF octet_length(COALESCE(p_metadata, '{}'::jsonb)::text) > 8192 THEN
        RAISE EXCEPTION 'AUDIT_METADATA_TOO_LARGE: Audit payload metadata exceeds maximum 8192 byte boundary.'
            USING ERRCODE = '22026';
    END IF;

    INSERT INTO public.audit_events (
        occurred_at,
        actor_user_id,
        actor_role,
        action,
        entity_type,
        entity_id,
        result,
        reason_code,
        metadata,
        correlation_id
    ) VALUES (
        NOW(),
        v_actor_user_id,
        v_actor_role,
        p_action,
        p_entity_type,
        p_entity_id,
        p_result,
        p_reason_code,
        COALESCE(p_metadata, '{}'::jsonb),
        p_correlation_id
    ) RETURNING id INTO v_event_id;

    RETURN v_event_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- Revoke default PUBLIC execution on privileged helpers; grant explicitly
REVOKE EXECUTE ON FUNCTION public.has_platform_role(TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.is_network_member(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.can_manage_network(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.record_audit_event(TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.prevent_audit_events_mutation() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.set_updated_at() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.has_platform_role(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_network_member(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_manage_network(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_audit_event(TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.normalize_ssid(TEXT) TO PUBLIC;

REVOKE ALL ON TABLE public.audit_events FROM PUBLIC;
GRANT SELECT ON TABLE public.audit_events TO authenticated;

-- ============================================================================
-- 3. Row-Level Security Policies
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Policies for public.profiles
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS profiles_select_policy ON public.profiles;
CREATE POLICY profiles_select_policy ON public.profiles
    FOR SELECT
    USING (
        auth.uid() = id
        OR public.has_platform_role('platform_admin')
        OR public.has_platform_role('system_auditor')
        OR public.has_platform_role('support_agent')
        OR public.has_platform_role('finance_officer')
    );

DROP POLICY IF EXISTS profiles_update_policy ON public.profiles;
CREATE POLICY profiles_update_policy ON public.profiles
    FOR UPDATE
    USING (auth.uid() = id)
    WITH CHECK (
        auth.uid() = id
        -- Prevent customer from self-mutating account_status
        AND account_status = (SELECT p.account_status FROM public.profiles p WHERE p.id = auth.uid())
    );

DROP POLICY IF EXISTS profiles_insert_policy ON public.profiles;
CREATE POLICY profiles_insert_policy ON public.profiles
    FOR INSERT
    WITH CHECK (auth.uid() = id);

-- ----------------------------------------------------------------------------
-- Policies for public.user_roles
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS user_roles_select_policy ON public.user_roles;
CREATE POLICY user_roles_select_policy ON public.user_roles
    FOR SELECT
    USING (
        user_id = auth.uid()
        OR public.has_platform_role('platform_admin')
        OR public.has_platform_role('system_auditor')
    );

DROP POLICY IF EXISTS user_roles_admin_manage_policy ON public.user_roles;
CREATE POLICY user_roles_admin_manage_policy ON public.user_roles
    FOR ALL
    USING (public.has_platform_role('platform_admin'))
    WITH CHECK (
        public.has_platform_role('platform_admin')
        -- Client operations can never assign system_service
        AND role != 'system_service'
    );

-- ----------------------------------------------------------------------------
-- Policies for public.networks
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS networks_select_policy ON public.networks;
CREATE POLICY networks_select_policy ON public.networks
    FOR SELECT
    USING (
        (status = 'active' AND verification_status = 'verified')
        OR public.is_network_member(id)
        OR public.has_platform_role('platform_admin')
        OR public.has_platform_role('system_auditor')
    );

DROP POLICY IF EXISTS networks_insert_policy ON public.networks;
CREATE POLICY networks_insert_policy ON public.networks
    FOR INSERT
    WITH CHECK (
        (
            auth.uid() IS NOT NULL
            AND created_by = auth.uid()
            AND status = 'pending_approval'
            AND verification_status = 'unverified'
        )
        OR public.has_platform_role('platform_admin')
    );

DROP POLICY IF EXISTS networks_update_policy ON public.networks;
CREATE POLICY networks_update_policy ON public.networks
    FOR UPDATE
    USING (
        public.can_manage_network(id)
        OR public.has_platform_role('platform_admin')
    )
    WITH CHECK (
        (
            public.can_manage_network(id)
            -- Prevent network owners from self-approving or changing status/verification
            AND status = (SELECT n.status FROM public.networks n WHERE n.id = networks.id)
            AND verification_status = (SELECT n.verification_status FROM public.networks n WHERE n.id = networks.id)
        )
        OR public.has_platform_role('platform_admin')
    );

-- ----------------------------------------------------------------------------
-- Policies for public.network_memberships
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS memberships_select_policy ON public.network_memberships;
CREATE POLICY memberships_select_policy ON public.network_memberships
    FOR SELECT
    USING (
        user_id = auth.uid()
        OR public.is_network_member(network_id)
        OR public.has_platform_role('platform_admin')
        OR public.has_platform_role('system_auditor')
    );

DROP POLICY IF EXISTS memberships_owner_manage_policy ON public.network_memberships;
CREATE POLICY memberships_owner_manage_policy ON public.network_memberships
    FOR ALL
    USING (
        public.can_manage_network(network_id)
        OR public.has_platform_role('platform_admin')
    )
    WITH CHECK (
        public.can_manage_network(network_id)
        OR public.has_platform_role('platform_admin')
    );

-- ----------------------------------------------------------------------------
-- Policies for public.network_ssid_aliases
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS ssid_aliases_select_policy ON public.network_ssid_aliases;
CREATE POLICY ssid_aliases_select_policy ON public.network_ssid_aliases
    FOR SELECT
    USING (
        (
            status = 'active'
            AND EXISTS (
                SELECT 1
                FROM public.networks n
                WHERE n.id = network_id
                  AND n.status = 'active'
                  AND n.verification_status = 'verified'
            )
        )
        OR public.is_network_member(network_id)
        OR public.has_platform_role('platform_admin')
        OR public.has_platform_role('system_auditor')
    );

DROP POLICY IF EXISTS ssid_aliases_owner_manage_policy ON public.network_ssid_aliases;
CREATE POLICY ssid_aliases_owner_manage_policy ON public.network_ssid_aliases
    FOR ALL
    USING (
        public.can_manage_network(network_id)
        OR public.has_platform_role('platform_admin')
    )
    WITH CHECK (
        public.can_manage_network(network_id)
        OR public.has_platform_role('platform_admin')
    );

-- ----------------------------------------------------------------------------
-- Policies for public.audit_events
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS audit_events_select_policy ON public.audit_events;
CREATE POLICY audit_events_select_policy ON public.audit_events
    FOR SELECT
    USING (
        public.has_platform_role('platform_admin')
        OR public.has_platform_role('system_auditor')
    );

-- Note: No INSERT, UPDATE, or DELETE policies exist for audit_events. Direct client mutations are strictly denied by RLS and database trigger.

-- Force RLS even for table owners / bypass roles used in local tests
ALTER TABLE public.profiles FORCE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles FORCE ROW LEVEL SECURITY;
ALTER TABLE public.networks FORCE ROW LEVEL SECURITY;
ALTER TABLE public.network_memberships FORCE ROW LEVEL SECURITY;
ALTER TABLE public.network_ssid_aliases FORCE ROW LEVEL SECURITY;
ALTER TABLE public.audit_events FORCE ROW LEVEL SECURITY;
