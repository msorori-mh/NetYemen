-- NetYemen Core RLS Policies, Authorization Helpers, and Audit Migration
-- Migration: 20260727091000_netyemen_core_rls_and_audit.sql
-- Task ID: NY-GOV-BE-001 / NY-GOV-BE-001B
-- Scope: Security Definer helpers, public.audit_events table, and RLS policies across all core tables

-- ============================================================================
-- 1. Authorization Helper Functions (SECURITY DEFINER)
-- ============================================================================

-- Helper: Check if current authenticated user has a specific platform role and active account
CREATE OR REPLACE FUNCTION public.has_platform_role(p_role TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN FALSE;
    END IF;
    RETURN EXISTS (
        SELECT 1
        FROM public.user_roles ur
        JOIN public.profiles p ON p.id = ur.user_id
        WHERE ur.user_id = auth.uid()
          AND ur.role = p_role
          AND p.account_status = 'active'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- Helper: Check if current authenticated user is an active member (owner or operator) with active profile of a network
CREATE OR REPLACE FUNCTION public.is_network_member(p_network_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF auth.uid() IS NULL OR p_network_id IS NULL THEN
        RETURN FALSE;
    END IF;
    RETURN EXISTS (
        SELECT 1
        FROM public.network_memberships nm
        JOIN public.profiles p ON p.id = nm.user_id
        WHERE nm.network_id = p_network_id
          AND nm.user_id = auth.uid()
          AND nm.status = 'active'
          AND p.account_status = 'active'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- Helper: Check if current authenticated user is an active OWNER with active profile & network_owner role of a network
CREATE OR REPLACE FUNCTION public.can_manage_network(p_network_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF auth.uid() IS NULL OR p_network_id IS NULL THEN
        RETURN FALSE;
    END IF;
    RETURN EXISTS (
        SELECT 1
        FROM public.network_memberships nm
        JOIN public.profiles p ON p.id = nm.user_id
        JOIN public.user_roles ur ON ur.user_id = nm.user_id AND ur.role = 'network_owner'
        WHERE nm.network_id = p_network_id
          AND nm.user_id = auth.uid()
          AND nm.membership_role = 'owner'
          AND nm.status = 'active'
          AND p.account_status = 'active'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- Helper: Normalize SSID string (preserves Arabic & Unicode script, lowercases, replaces whitespace with hyphens)
CREATE OR REPLACE FUNCTION public.normalize_ssid(p_ssid TEXT)
RETURNS TEXT AS $$
DECLARE
    v_normalized TEXT;
BEGIN
    IF p_ssid IS NULL OR length(trim(p_ssid)) = 0 THEN
        RETURN '';
    END IF;

    -- Feature detect & apply Unicode NFC normalization where available
    BEGIN
        v_normalized := unicode_normalize(p_ssid, 'NFC');
    EXCEPTION WHEN OTHERS THEN
        v_normalized := p_ssid;
    END;

    -- Lowercase English letters while preserving Unicode/Arabic characters, trim surrounding whitespace
    v_normalized := lower(trim(v_normalized));
    -- Replace multiple whitespace characters with a single hyphen
    v_normalized := regexp_replace(v_normalized, '\s+', '-', 'g');
    RETURN v_normalized;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT SECURITY DEFINER SET search_path = public, pg_temp;

-- ============================================================================
-- 2. Atomic Network Creation RPC (Controlled Function)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.create_network_draft(
    p_commercial_name TEXT,
    p_description TEXT DEFAULT NULL,
    p_governorate TEXT DEFAULT NULL,
    p_city TEXT DEFAULT NULL,
    p_district TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_user_id UUID;
    v_network_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required to create network draft.'
            USING ERRCODE = '28000';
    END IF;

    IF NOT public.has_platform_role('network_owner') THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE: Only users possessing network_owner platform role can create a network draft.'
            USING ERRCODE = '42501';
    END IF;

    IF p_commercial_name IS NULL OR length(trim(p_commercial_name)) = 0 THEN
        RAISE EXCEPTION 'INVALID_NAME: Commercial network name cannot be empty.'
            USING ERRCODE = '22000';
    END IF;

    -- Create network draft in pending_approval state
    INSERT INTO public.networks (
        commercial_name,
        description,
        governorate,
        city,
        district,
        status,
        verification_status,
        created_by,
        approved_by,
        approved_at
    ) VALUES (
        trim(p_commercial_name),
        p_description,
        p_governorate,
        p_city,
        p_district,
        'pending_approval',
        'unverified',
        v_user_id,
        NULL,
        NULL
    ) RETURNING id INTO v_network_id;

    -- Create active owner membership atomically for the creator
    INSERT INTO public.network_memberships (
        network_id,
        user_id,
        membership_role,
        status,
        created_by
    ) VALUES (
        v_network_id,
        v_user_id,
        'owner',
        'active',
        v_user_id
    );

    RETURN v_network_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.create_network_draft FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_network_draft TO authenticated;

-- ============================================================================
-- 3. Database Triggers for Network Administrative Field & Membership Protection
-- ============================================================================

-- Trigger: Protect Network Administrative Fields (status, verification_status, approved_by, approved_at, created_by)
CREATE OR REPLACE FUNCTION public.protect_network_admin_fields()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT public.has_platform_role('platform_admin') THEN
        IF NEW.status IS DISTINCT FROM OLD.status OR
           NEW.verification_status IS DISTINCT FROM OLD.verification_status OR
           NEW.approved_by IS DISTINCT FROM OLD.approved_by OR
           NEW.approved_at IS DISTINCT FROM OLD.approved_at OR
           NEW.created_by IS DISTINCT FROM OLD.created_by THEN
            RAISE EXCEPTION 'MUTATION_FORBIDDEN: Non-admin users cannot modify network administrative fields (status, verification_status, approved_by, approved_at, created_by).'
                USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_protect_network_admin_fields') THEN
        CREATE TRIGGER trg_protect_network_admin_fields
            BEFORE UPDATE ON public.networks
            FOR EACH ROW
            EXECUTE FUNCTION public.protect_network_admin_fields();
    END IF;
END $$;

-- Trigger: Validate Membership Target Platform Role (Owner -> network_owner, Operator -> network_operator)
CREATE OR REPLACE FUNCTION public.validate_membership_target_role()
RETURNS TRIGGER AS $$
DECLARE
    v_target_status TEXT;
BEGIN
    -- Derive created_by for non-admin callers on insert
    IF TG_OP = 'INSERT' THEN
        IF auth.uid() IS NOT NULL AND NOT public.has_platform_role('platform_admin') THEN
            NEW.created_by := auth.uid();
        END IF;
    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.created_by IS DISTINCT FROM OLD.created_by THEN
            RAISE EXCEPTION 'MUTATION_FORBIDDEN: Membership created_by field is immutable.'
                USING ERRCODE = '42501';
        END IF;

        IF NOT public.has_platform_role('platform_admin') THEN
            IF OLD.membership_role = 'operator' AND NEW.membership_role = 'owner' THEN
                RAISE EXCEPTION 'FORBIDDEN_PROMOTION: Network owners cannot convert operator memberships to owner memberships.'
                    USING ERRCODE = '42501';
            END IF;
            IF OLD.network_id IS DISTINCT FROM NEW.network_id THEN
                RAISE EXCEPTION 'FORBIDDEN_REASSIGNMENT: Memberships cannot be moved across networks.'
                    USING ERRCODE = '42501';
            END IF;
        END IF;
    END IF;

    -- Target user profile must be active
    SELECT account_status INTO v_target_status
    FROM public.profiles
    WHERE id = NEW.user_id;

    IF v_target_status IS NULL OR v_target_status != 'active' THEN
        RAISE EXCEPTION 'TARGET_ACCOUNT_INACTIVE: Membership target profile must be active.'
            USING ERRCODE = '42501';
    END IF;

    IF NEW.membership_role = 'owner' THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_id = NEW.user_id AND role = 'network_owner'
        ) THEN
            RAISE EXCEPTION 'TARGET_ROLE_INVALID: Target user must possess active network_owner platform role to be assigned owner membership.'
                USING ERRCODE = '42501';
        END IF;
    ELSIF NEW.membership_role = 'operator' THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_id = NEW.user_id AND role = 'network_operator'
        ) THEN
            RAISE EXCEPTION 'TARGET_ROLE_INVALID: Target user must possess active network_operator platform role to be assigned operator membership.'
                USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_validate_membership_target_role') THEN
        CREATE TRIGGER trg_validate_membership_target_role
            BEFORE INSERT OR UPDATE ON public.network_memberships
            FOR EACH ROW
            EXECUTE FUNCTION public.validate_membership_target_role();
    END IF;
END $$;

-- Trigger: Prevent Deletion, Deactivation, or Demotion of Final Active Network Owner (With Concurrency Locking)
CREATE OR REPLACE FUNCTION public.protect_final_active_owner()
RETURNS TRIGGER AS $$
DECLARE
    v_active_owner_count INT;
    v_dummy INT;
BEGIN
    IF OLD.membership_role = 'owner' AND OLD.status = 'active' THEN
        IF (TG_OP = 'DELETE') OR
           (TG_OP = 'UPDATE' AND (NEW.status != 'active' OR NEW.membership_role != 'owner' OR NEW.network_id != OLD.network_id)) THEN

            -- Per-network row lock to serialize concurrent owner mutations
            SELECT 1 INTO v_dummy
            FROM public.networks
            WHERE id = OLD.network_id
            FOR UPDATE;

            SELECT COUNT(*) INTO v_active_owner_count
            FROM public.network_memberships nm
            JOIN public.profiles p ON p.id = nm.user_id
            JOIN public.user_roles ur ON ur.user_id = nm.user_id AND ur.role = 'network_owner'
            WHERE nm.network_id = OLD.network_id
              AND nm.membership_role = 'owner'
              AND nm.status = 'active'
              AND p.account_status = 'active'
              AND nm.user_id != OLD.user_id;

            IF v_active_owner_count = 0 THEN
                RAISE EXCEPTION 'FINAL_OWNER_PROTECTION: Cannot remove, deactivate, demote, or move the final active owner of a network.'
                    USING ERRCODE = '42501';
            END IF;
        END IF;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_protect_final_active_owner') THEN
        CREATE TRIGGER trg_protect_final_active_owner
            BEFORE UPDATE OR DELETE ON public.network_memberships
            FOR EACH ROW
            EXECUTE FUNCTION public.protect_final_active_owner();
    END IF;
END $$;

-- Trigger: Enforce Database-Level SSID Normalization (Client input cannot override generated value)
CREATE OR REPLACE FUNCTION public.enforce_ssid_normalization()
RETURNS TRIGGER AS $$
BEGIN
    NEW.ssid_normalized := public.normalize_ssid(NEW.ssid_display);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_enforce_ssid_normalization') THEN
        CREATE TRIGGER trg_enforce_ssid_normalization
            BEFORE INSERT OR UPDATE ON public.network_ssid_aliases
            FOR EACH ROW
            EXECUTE FUNCTION public.enforce_ssid_normalization();
    END IF;
END $$;

-- Trigger: Protect SSID Verification Metadata & Prevent Self-Activation by Owners
CREATE OR REPLACE FUNCTION public.protect_ssid_verification_metadata()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT public.has_platform_role('platform_admin') THEN
        IF TG_OP = 'INSERT' THEN
            IF NEW.status != 'pending_verification' OR NEW.verified_by IS NOT NULL OR NEW.verified_at IS NOT NULL THEN
                RAISE EXCEPTION 'FORBIDDEN_VERIFICATION: Network owners cannot self-verify SSID aliases or set verification metadata upon creation.'
                    USING ERRCODE = '42501';
            END IF;
        ELSIF TG_OP = 'UPDATE' THEN
            IF NEW.verified_by IS DISTINCT FROM OLD.verified_by OR NEW.verified_at IS DISTINCT FROM OLD.verified_at THEN
                RAISE EXCEPTION 'FORBIDDEN_VERIFICATION: Network owners cannot modify alias verification metadata (verified_by, verified_at).'
                    USING ERRCODE = '42501';
            END IF;

            IF NEW.status = 'active' AND OLD.status != 'active' THEN
                RAISE EXCEPTION 'FORBIDDEN_VERIFICATION: Network owners cannot self-activate SSID aliases.'
                    USING ERRCODE = '42501';
            END IF;

            IF OLD.status = 'active' AND NEW.ssid_display IS DISTINCT FROM OLD.ssid_display THEN
                RAISE EXCEPTION 'FORBIDDEN_RENAME: Network owners cannot modify display name of an active, verified SSID alias.'
                    USING ERRCODE = '42501';
            END IF;

            IF OLD.status IN ('suspended', 'rejected') AND NEW.status NOT IN ('suspended', 'rejected') THEN
                RAISE EXCEPTION 'FORBIDDEN_REACTIVATION: Network owners cannot reactivate suspended or rejected SSID aliases.'
                    USING ERRCODE = '42501';
            END IF;

            IF NEW.status NOT IN ('pending_verification', 'suspended') THEN
                RAISE EXCEPTION 'FORBIDDEN_VERIFICATION: Network owners can only keep pending_verification or suspend aliases.'
                    USING ERRCODE = '42501';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_protect_ssid_verification_metadata') THEN
        CREATE TRIGGER trg_protect_ssid_verification_metadata
            BEFORE INSERT OR UPDATE ON public.network_ssid_aliases
            FOR EACH ROW
            EXECUTE FUNCTION public.protect_ssid_verification_metadata();
    END IF;
END $$;

-- ============================================================================
-- 4. Table: public.audit_events (Immutable Audit Trail)
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

-- Centralized Audit Logging Function (Strictly locked to service_role / internal execution)
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

-- Revoke default execution on privileged helpers; grant explicitly
REVOKE EXECUTE ON FUNCTION public.has_platform_role(TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.is_network_member(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.can_manage_network(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.record_audit_event(TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.prevent_audit_events_mutation() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.set_updated_at() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.protect_network_admin_fields() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.validate_membership_target_role() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.protect_final_active_owner() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.enforce_ssid_normalization() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.protect_ssid_verification_metadata() FROM PUBLIC;

-- RLS policies may invoke these helpers for anon and authenticated callers.
GRANT EXECUTE ON FUNCTION public.has_platform_role(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_network_member(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.can_manage_network(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.normalize_ssid(TEXT) TO anon, authenticated;

-- record_audit_event is locked strictly to service_role / internal database execution!
GRANT EXECUTE ON FUNCTION public.record_audit_event(TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, UUID) TO service_role;

REVOKE ALL ON TABLE public.audit_events FROM PUBLIC;
GRANT SELECT ON TABLE public.audit_events TO authenticated;

-- ============================================================================
-- 5. Row-Level Security Policies
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
    );

DROP POLICY IF EXISTS profiles_update_policy ON public.profiles;
CREATE POLICY profiles_update_policy ON public.profiles
    FOR UPDATE
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- Note: No profiles_insert_policy. Profile creation is strictly via handle_new_user auth trigger.

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

DROP POLICY IF EXISTS networks_update_policy ON public.networks;
CREATE POLICY networks_update_policy ON public.networks
    FOR UPDATE
    USING (
        public.can_manage_network(id)
        OR public.has_platform_role('platform_admin')
    )
    WITH CHECK (
        public.can_manage_network(id)
        OR public.has_platform_role('platform_admin')
    );

-- Note: No direct networks INSERT policy. Draft network creation occurs via create_network_draft RPC.

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
        (public.can_manage_network(network_id) AND membership_role = 'operator')
        OR public.has_platform_role('platform_admin')
    )
    WITH CHECK (
        (
            public.can_manage_network(network_id)
            AND membership_role = 'operator'
            AND user_id != auth.uid()
        )
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

-- Force RLS across all tables
ALTER TABLE public.profiles FORCE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles FORCE ROW LEVEL SECURITY;
ALTER TABLE public.networks FORCE ROW LEVEL SECURITY;
ALTER TABLE public.network_memberships FORCE ROW LEVEL SECURITY;
ALTER TABLE public.network_ssid_aliases FORCE ROW LEVEL SECURITY;
ALTER TABLE public.audit_events FORCE ROW LEVEL SECURITY;
