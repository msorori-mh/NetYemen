-- WASEL One access federation foundation.
-- Initiative: WASEL-ONE-PIVOT-001
-- Scope: catalog, partner participation, RADIUS nodes, entitlements, sessions,
-- accounting events, and usage accruals. No router or customer secrets.

-- ============================================================================
-- 1. Platform-wide plans and participating partner networks
-- ============================================================================

CREATE TABLE public.federated_access_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    retail_price INTEGER NOT NULL,
    currency TEXT NOT NULL DEFAULT 'YER',
    validity_seconds INTEGER NOT NULL,
    quota_bytes BIGINT,
    speed_limit_kbps INTEGER,
    max_concurrent_sessions INTEGER NOT NULL DEFAULT 1,
    status TEXT NOT NULL DEFAULT 'draft',
    is_public BOOLEAN NOT NULL DEFAULT FALSE,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_federated_plans_name CHECK (length(trim(name)) > 0),
    CONSTRAINT chk_federated_plans_price CHECK (retail_price >= 0),
    CONSTRAINT chk_federated_plans_currency CHECK (currency = 'YER'),
    CONSTRAINT chk_federated_plans_validity CHECK (validity_seconds > 0),
    CONSTRAINT chk_federated_plans_quota CHECK (quota_bytes IS NULL OR quota_bytes > 0),
    CONSTRAINT chk_federated_plans_speed CHECK (speed_limit_kbps IS NULL OR speed_limit_kbps > 0),
    CONSTRAINT chk_federated_plans_concurrency CHECK (max_concurrent_sessions > 0 AND max_concurrent_sessions <= 5),
    CONSTRAINT chk_federated_plans_status CHECK (status IN ('draft', 'active', 'retired')),
    CONSTRAINT chk_federated_plans_public_state CHECK (NOT is_public OR status = 'active')
);

COMMENT ON TABLE public.federated_access_plans IS
    'Platform-wide WASEL One plans, independent of any single partner network.';

CREATE INDEX idx_federated_access_plans_catalog
    ON public.federated_access_plans (status, is_public, created_at DESC);

CREATE TRIGGER trg_federated_access_plans_updated_at
    BEFORE UPDATE ON public.federated_access_plans
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE public.federated_plan_networks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_id UUID NOT NULL REFERENCES public.federated_access_plans(id) ON DELETE CASCADE,
    network_id UUID NOT NULL REFERENCES public.networks(id) ON DELETE RESTRICT,
    compensation_model TEXT NOT NULL,
    compensation_rate_minor INTEGER NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT FALSE,
    effective_from TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    effective_until TIMESTAMPTZ,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_federated_plan_network UNIQUE (plan_id, network_id),
    CONSTRAINT uq_federated_plan_network_id_network UNIQUE (id, network_id),
    CONSTRAINT chk_federated_plan_network_model CHECK (
        compensation_model IN ('per_gib', 'per_minute', 'per_session')
    ),
    CONSTRAINT chk_federated_plan_network_rate CHECK (compensation_rate_minor >= 0),
    CONSTRAINT chk_federated_plan_network_window CHECK (
        effective_until IS NULL OR effective_until > effective_from
    )
);

COMMENT ON TABLE public.federated_plan_networks IS
    'Networks accepting a WASEL One plan and the versioned compensation contract.';

CREATE INDEX idx_federated_plan_networks_network
    ON public.federated_plan_networks (network_id, is_active);

CREATE TRIGGER trg_federated_plan_networks_updated_at
    BEFORE UPDATE ON public.federated_plan_networks
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============================================================================
-- 2. Partner router/NAS registry (deliberately contains no RADIUS secret)
-- ============================================================================

CREATE TABLE public.network_access_nodes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    network_id UUID NOT NULL REFERENCES public.networks(id) ON DELETE RESTRICT,
    display_name TEXT NOT NULL,
    vendor TEXT NOT NULL DEFAULT 'mikrotik',
    nas_identifier TEXT NOT NULL,
    radius_source_address INET,
    status TEXT NOT NULL DEFAULT 'provisioning',
    last_seen_at TIMESTAMPTZ,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_network_access_node_name UNIQUE (network_id, display_name),
    CONSTRAINT uq_network_access_node_id_network UNIQUE (id, network_id),
    CONSTRAINT chk_network_access_nodes_name CHECK (length(trim(display_name)) > 0),
    CONSTRAINT chk_network_access_nodes_nas CHECK (length(trim(nas_identifier)) > 0),
    CONSTRAINT chk_network_access_nodes_vendor CHECK (vendor IN ('mikrotik', 'generic_radius')),
    CONSTRAINT chk_network_access_nodes_status CHECK (
        status IN ('provisioning', 'active', 'degraded', 'suspended', 'retired')
    )
);

CREATE UNIQUE INDEX uq_network_access_nodes_nas_identifier
    ON public.network_access_nodes (lower(nas_identifier));
CREATE INDEX idx_network_access_nodes_network_status
    ON public.network_access_nodes (network_id, status);

COMMENT ON TABLE public.network_access_nodes IS
    'RADIUS NAS registry. Shared secrets live outside PostgreSQL in the runtime secret manager.';

CREATE TRIGGER trg_network_access_nodes_updated_at
    BEFORE UPDATE ON public.network_access_nodes
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============================================================================
-- 3. Customer entitlement and access-session state
-- ============================================================================

CREATE TABLE public.access_entitlements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    plan_id UUID NOT NULL REFERENCES public.federated_access_plans(id) ON DELETE RESTRICT,
    status TEXT NOT NULL DEFAULT 'pending',
    starts_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    allowance_bytes BIGINT,
    consumed_bytes BIGINT NOT NULL DEFAULT 0,
    speed_limit_kbps INTEGER,
    max_concurrent_sessions INTEGER NOT NULL DEFAULT 1,
    source_type TEXT NOT NULL,
    source_id UUID,
    idempotency_key UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_access_entitlements_idempotency UNIQUE (user_id, idempotency_key),
    CONSTRAINT uq_access_entitlement_id_user UNIQUE (id, user_id),
    CONSTRAINT chk_access_entitlements_status CHECK (
        status IN ('pending', 'active', 'exhausted', 'expired', 'revoked')
    ),
    CONSTRAINT chk_access_entitlements_window CHECK (expires_at > starts_at),
    CONSTRAINT chk_access_entitlements_allowance CHECK (allowance_bytes IS NULL OR allowance_bytes > 0),
    CONSTRAINT chk_access_entitlements_consumed CHECK (
        consumed_bytes >= 0 AND (allowance_bytes IS NULL OR consumed_bytes <= allowance_bytes)
    ),
    CONSTRAINT chk_access_entitlements_speed CHECK (speed_limit_kbps IS NULL OR speed_limit_kbps > 0),
    CONSTRAINT chk_access_entitlements_concurrency CHECK (
        max_concurrent_sessions > 0 AND max_concurrent_sessions <= 5
    ),
    CONSTRAINT chk_access_entitlements_source CHECK (
        source_type IN ('purchase', 'promotion', 'admin', 'pilot')
    )
);

CREATE INDEX idx_access_entitlements_user_status
    ON public.access_entitlements (user_id, status, expires_at);
CREATE INDEX idx_access_entitlements_plan
    ON public.access_entitlements (plan_id, status);

CREATE TRIGGER trg_access_entitlements_updated_at
    BEFORE UPDATE ON public.access_entitlements
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE public.access_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entitlement_id UUID NOT NULL,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    network_id UUID NOT NULL REFERENCES public.networks(id) ON DELETE RESTRICT,
    access_node_id UUID NOT NULL,
    external_session_id TEXT,
    status TEXT NOT NULL DEFAULT 'authorized',
    device_fingerprint_hash TEXT,
    grant_expires_at TIMESTAMPTZ NOT NULL,
    authorized_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    started_at TIMESTAMPTZ,
    last_accounting_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    input_bytes BIGINT NOT NULL DEFAULT 0,
    output_bytes BIGINT NOT NULL DEFAULT 0,
    session_seconds INTEGER NOT NULL DEFAULT 0,
    close_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_access_session_entitlement_user FOREIGN KEY (entitlement_id, user_id)
        REFERENCES public.access_entitlements(id, user_id) ON DELETE RESTRICT,
    CONSTRAINT fk_access_session_node_network FOREIGN KEY (access_node_id, network_id)
        REFERENCES public.network_access_nodes(id, network_id) ON DELETE RESTRICT,
    CONSTRAINT uq_access_session_id_node_network UNIQUE (id, access_node_id, network_id),
    CONSTRAINT uq_access_session_id_entitlement_network UNIQUE (id, entitlement_id, network_id),
    CONSTRAINT chk_access_sessions_status CHECK (
        status IN ('authorized', 'active', 'closed', 'rejected')
    ),
    CONSTRAINT chk_access_sessions_counters CHECK (
        input_bytes >= 0 AND output_bytes >= 0 AND session_seconds >= 0
    ),
    CONSTRAINT chk_access_sessions_grant_window CHECK (grant_expires_at > authorized_at),
    CONSTRAINT chk_access_sessions_end CHECK (ended_at IS NULL OR started_at IS NULL OR ended_at >= started_at),
    CONSTRAINT chk_access_sessions_device_hash CHECK (
        device_fingerprint_hash IS NULL OR char_length(device_fingerprint_hash) BETWEEN 32 AND 128
    )
);

CREATE UNIQUE INDEX uq_access_sessions_external
    ON public.access_sessions (access_node_id, external_session_id)
    WHERE external_session_id IS NOT NULL;
CREATE INDEX idx_access_sessions_entitlement_status
    ON public.access_sessions (entitlement_id, status);
CREATE INDEX idx_access_sessions_network_started
    ON public.access_sessions (network_id, started_at DESC);
CREATE INDEX idx_access_sessions_user_started
    ON public.access_sessions (user_id, started_at DESC);

CREATE TRIGGER trg_access_sessions_updated_at
    BEFORE UPDATE ON public.access_sessions
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============================================================================
-- 4. Immutable RADIUS accounting and partner usage accruals
-- ============================================================================

CREATE TABLE public.radius_accounting_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL,
    access_node_id UUID NOT NULL,
    network_id UUID NOT NULL,
    event_key TEXT NOT NULL,
    event_type TEXT NOT NULL,
    event_at TIMESTAMPTZ NOT NULL,
    input_bytes BIGINT NOT NULL DEFAULT 0,
    output_bytes BIGINT NOT NULL DEFAULT 0,
    session_seconds INTEGER NOT NULL DEFAULT 0,
    source_packet_hash TEXT,
    received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_radius_event_session_scope FOREIGN KEY (session_id, access_node_id, network_id)
        REFERENCES public.access_sessions(id, access_node_id, network_id) ON DELETE RESTRICT,
    CONSTRAINT uq_radius_accounting_event UNIQUE (access_node_id, event_key),
    CONSTRAINT chk_radius_accounting_event_key CHECK (length(trim(event_key)) > 0),
    CONSTRAINT chk_radius_accounting_event_type CHECK (
        event_type IN ('start', 'interim_update', 'stop')
    ),
    CONSTRAINT chk_radius_accounting_counters CHECK (
        input_bytes >= 0 AND output_bytes >= 0 AND session_seconds >= 0
    ),
    CONSTRAINT chk_radius_accounting_packet_hash CHECK (
        source_packet_hash IS NULL OR source_packet_hash ~ '^[0-9a-f]{64}$'
    )
);

CREATE INDEX idx_radius_accounting_session_time
    ON public.radius_accounting_events (session_id, event_at);
CREATE INDEX idx_radius_accounting_network_time
    ON public.radius_accounting_events (network_id, event_at DESC);

COMMENT ON TABLE public.radius_accounting_events IS
    'Typed accounting counters only. Raw RADIUS packets, passwords, shared secrets, and device identifiers are not retained.';

CREATE OR REPLACE FUNCTION public.enforce_radius_accounting_monotonic()
RETURNS TRIGGER AS $$
DECLARE
    v_previous public.radius_accounting_events%ROWTYPE;
BEGIN
    -- Serialize events for one session so two workers cannot both validate
    -- against the same previous counter snapshot.
    PERFORM pg_advisory_xact_lock(hashtextextended(NEW.session_id::text, 0));

    SELECT * INTO v_previous
    FROM public.radius_accounting_events
    WHERE session_id = NEW.session_id
    ORDER BY event_at DESC, received_at DESC
    LIMIT 1;

    IF FOUND THEN
        IF v_previous.event_type = 'stop' THEN
            RAISE EXCEPTION 'ACCOUNTING_CLOSED: Session already has a stop event.'
                USING ERRCODE = '23514';
        END IF;
        IF NEW.event_type = 'start' THEN
            RAISE EXCEPTION 'ACCOUNTING_DUPLICATE_START: Session already started.'
                USING ERRCODE = '23514';
        END IF;
        IF NEW.event_at < v_previous.event_at
           OR NEW.input_bytes < v_previous.input_bytes
           OR NEW.output_bytes < v_previous.output_bytes
           OR NEW.session_seconds < v_previous.session_seconds THEN
            RAISE EXCEPTION 'ACCOUNTING_REGRESSION: Event time and cumulative counters must be monotonic.'
                USING ERRCODE = '23514';
        END IF;
    ELSIF NEW.event_type <> 'start' THEN
        RAISE EXCEPTION 'ACCOUNTING_START_REQUIRED: First session event must be start.'
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

CREATE TRIGGER trg_radius_accounting_events_monotonic
    BEFORE INSERT ON public.radius_accounting_events
    FOR EACH ROW EXECUTE FUNCTION public.enforce_radius_accounting_monotonic();

CREATE TABLE public.partner_usage_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    network_id UUID NOT NULL,
    session_id UUID NOT NULL,
    entitlement_id UUID NOT NULL,
    plan_network_id UUID NOT NULL,
    entry_type TEXT NOT NULL DEFAULT 'accrual',
    quantity NUMERIC(20, 6) NOT NULL,
    unit TEXT NOT NULL,
    rate_minor INTEGER NOT NULL,
    amount_minor INTEGER NOT NULL,
    currency TEXT NOT NULL DEFAULT 'YER',
    reverses_entry_id UUID REFERENCES public.partner_usage_ledger(id) ON DELETE RESTRICT,
    idempotency_key UUID NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_partner_usage_session_scope FOREIGN KEY (session_id, entitlement_id, network_id)
        REFERENCES public.access_sessions(id, entitlement_id, network_id) ON DELETE RESTRICT,
    CONSTRAINT fk_partner_usage_plan_network FOREIGN KEY (plan_network_id, network_id)
        REFERENCES public.federated_plan_networks(id, network_id) ON DELETE RESTRICT,
    CONSTRAINT uq_partner_usage_session_entry UNIQUE (session_id, entry_type),
    CONSTRAINT chk_partner_usage_entry_type CHECK (entry_type IN ('accrual', 'reversal')),
    CONSTRAINT chk_partner_usage_quantity CHECK (quantity >= 0),
    CONSTRAINT chk_partner_usage_unit CHECK (unit IN ('gib', 'minute', 'session')),
    CONSTRAINT chk_partner_usage_rate CHECK (rate_minor >= 0),
    CONSTRAINT chk_partner_usage_calculation CHECK (
        abs(amount_minor) = round(quantity * rate_minor)::INTEGER
    ),
    CONSTRAINT chk_partner_usage_amount CHECK (
        (entry_type = 'accrual' AND amount_minor >= 0 AND reverses_entry_id IS NULL)
        OR (entry_type = 'reversal' AND amount_minor <= 0 AND reverses_entry_id IS NOT NULL)
    ),
    CONSTRAINT chk_partner_usage_currency CHECK (currency = 'YER')
);

CREATE INDEX idx_partner_usage_ledger_network_time
    ON public.partner_usage_ledger (network_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.prevent_wasel_one_event_mutation()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'MUTATION_FORBIDDEN: %.% is append-only.', TG_TABLE_SCHEMA, TG_TABLE_NAME
        USING ERRCODE = '42501';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

CREATE TRIGGER trg_radius_accounting_events_immutable
    BEFORE UPDATE OR DELETE ON public.radius_accounting_events
    FOR EACH ROW EXECUTE FUNCTION public.prevent_wasel_one_event_mutation();

CREATE TRIGGER trg_partner_usage_ledger_immutable
    BEFORE UPDATE OR DELETE ON public.partner_usage_ledger
    FOR EACH ROW EXECUTE FUNCTION public.prevent_wasel_one_event_mutation();

REVOKE EXECUTE ON FUNCTION public.prevent_wasel_one_event_mutation() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.enforce_radius_accounting_monotonic() FROM PUBLIC;

-- ============================================================================
-- 5. Row-level isolation. Runtime writes are service-only in this slice.
-- ============================================================================

ALTER TABLE public.federated_access_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.federated_access_plans FORCE ROW LEVEL SECURITY;
ALTER TABLE public.federated_plan_networks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.federated_plan_networks FORCE ROW LEVEL SECURITY;
ALTER TABLE public.network_access_nodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.network_access_nodes FORCE ROW LEVEL SECURITY;
ALTER TABLE public.access_entitlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.access_entitlements FORCE ROW LEVEL SECURITY;
ALTER TABLE public.access_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.access_sessions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.radius_accounting_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.radius_accounting_events FORCE ROW LEVEL SECURITY;
ALTER TABLE public.partner_usage_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.partner_usage_ledger FORCE ROW LEVEL SECURITY;

CREATE POLICY federated_access_plans_catalog_read
    ON public.federated_access_plans FOR SELECT
    USING (
        (status = 'active' AND is_public)
        OR public.has_platform_role('platform_admin')
        OR public.has_platform_role('system_auditor')
    );

CREATE POLICY federated_plan_networks_scoped_read
    ON public.federated_plan_networks FOR SELECT
    USING (
        (
            is_active
            AND (effective_until IS NULL OR effective_until > NOW())
            AND EXISTS (
                SELECT 1 FROM public.federated_access_plans p
                WHERE p.id = plan_id AND p.status = 'active' AND p.is_public
            )
            AND EXISTS (
                SELECT 1 FROM public.networks n
                WHERE n.id = network_id
                  AND n.status = 'active'
                  AND n.verification_status = 'verified'
            )
        )
        OR public.is_network_member(network_id)
        OR public.has_platform_role('platform_admin')
        OR public.has_platform_role('system_auditor')
    );

CREATE POLICY network_access_nodes_partner_read
    ON public.network_access_nodes FOR SELECT
    USING (
        public.is_network_member(network_id)
        OR public.has_platform_role('platform_admin')
        OR public.has_platform_role('system_auditor')
    );

CREATE POLICY access_entitlements_owner_read
    ON public.access_entitlements FOR SELECT
    USING (
        user_id = auth.uid()
        OR public.has_platform_role('platform_admin')
        OR public.has_platform_role('support_agent')
        OR public.has_platform_role('system_auditor')
    );

CREATE POLICY access_sessions_scoped_read
    ON public.access_sessions FOR SELECT
    USING (
        user_id = auth.uid()
        OR public.is_network_member(network_id)
        OR public.has_platform_role('platform_admin')
        OR public.has_platform_role('support_agent')
        OR public.has_platform_role('system_auditor')
    );

CREATE POLICY radius_accounting_events_partner_read
    ON public.radius_accounting_events FOR SELECT
    USING (
        public.is_network_member(network_id)
        OR public.has_platform_role('platform_admin')
        OR public.has_platform_role('support_agent')
        OR public.has_platform_role('system_auditor')
    );

CREATE POLICY partner_usage_ledger_scoped_read
    ON public.partner_usage_ledger FOR SELECT
    USING (
        public.is_network_member(network_id)
        OR public.has_platform_role('platform_admin')
        OR public.has_platform_role('finance_officer')
        OR public.has_platform_role('system_auditor')
    );

REVOKE ALL ON TABLE
    public.federated_access_plans,
    public.federated_plan_networks,
    public.network_access_nodes,
    public.access_entitlements,
    public.access_sessions,
    public.radius_accounting_events,
    public.partner_usage_ledger
FROM PUBLIC, anon, authenticated;

GRANT SELECT ON TABLE
    public.federated_access_plans,
    public.federated_plan_networks
TO anon, authenticated;

GRANT SELECT ON TABLE
    public.network_access_nodes,
    public.access_entitlements,
    public.access_sessions,
    public.radius_accounting_events,
    public.partner_usage_ledger
TO authenticated;

GRANT ALL ON TABLE
    public.federated_access_plans,
    public.federated_plan_networks,
    public.network_access_nodes,
    public.access_entitlements,
    public.access_sessions,
    public.radius_accounting_events,
    public.partner_usage_ledger
TO service_role;
