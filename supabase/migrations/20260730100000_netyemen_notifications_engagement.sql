-- NetYemen V1 Notifications & Engagement
-- Migration: 20260730100000_netyemen_notifications_engagement.sql
-- Task ID: NY-V1-NOTIFICATIONS-ENGAGEMENT-001
-- Scope: Provider-neutral push token registry, preferences, events, outbox,
--        deliveries, inbox, targeting, admin composer, deep links, rate limits.
-- Governance: OD-NOTIF-01 remains OPEN_DECISION. No provider credentials.
--             Transport adapter stays unbound until explicit provider approval.

-- ============================================================================
-- 0. Transport binding registry (provider-neutral; unbound by default)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.notification_transport_config (
    id SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    provider_key TEXT NOT NULL DEFAULT 'unbound',
    binding_status TEXT NOT NULL DEFAULT 'unbound',
    adapter_interface TEXT NOT NULL DEFAULT 'NotificationTransportAdapter',
    notes TEXT NOT NULL DEFAULT 'OD-NOTIF-01 OPEN: provider binding requires explicit approval. Architecture is provider-neutral.',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_notification_transport_binding_status CHECK (
        binding_status IN ('unbound', 'approved_pending_secrets', 'bound')
    ),
    CONSTRAINT chk_notification_transport_no_secrets CHECK (
        notes !~* '(api[_-]?key|secret|private[_-]?key|service[_-]?account|firebase|onesignal).{0,40}[=:]'
    )
);

COMMENT ON TABLE public.notification_transport_config IS
    'Singleton transport binding state. V1 ships unbound; no provider secrets stored.';

INSERT INTO public.notification_transport_config (id)
VALUES (1)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.notification_transport_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS notification_transport_config_admin_select ON public.notification_transport_config;
CREATE POLICY notification_transport_config_admin_select
    ON public.notification_transport_config
    FOR SELECT
    USING (
        public.has_platform_role('platform_admin')
        OR public.has_platform_role('system_auditor')
    );

-- ============================================================================
-- 1. device_push_tokens
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.device_push_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    platform TEXT NOT NULL,
    token TEXT NOT NULL,
    device_fingerprint TEXT,
    app_version TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_device_push_tokens_platform CHECK (
        platform IN ('android', 'ios', 'web', 'unknown')
    ),
    CONSTRAINT chk_device_push_tokens_token_non_empty CHECK (length(trim(token)) > 0),
    CONSTRAINT chk_device_push_tokens_token_not_secret_blob CHECK (
        token !~* '(BEGIN (RSA |EC )?PRIVATE KEY|service_account|private_key)'
    ),
    CONSTRAINT uq_device_push_tokens_user_token UNIQUE (user_id, token)
);

COMMENT ON TABLE public.device_push_tokens IS
    'Per-user device push tokens. Tokens are INTERNAL; no provider service credentials.';

CREATE INDEX IF NOT EXISTS idx_device_push_tokens_user_active
    ON public.device_push_tokens (user_id) WHERE is_active;

CREATE INDEX IF NOT EXISTS idx_device_push_tokens_token
    ON public.device_push_tokens (token);

CREATE TRIGGER trg_device_push_tokens_set_updated_at
    BEFORE UPDATE ON public.device_push_tokens
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.device_push_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS device_push_tokens_owner_select ON public.device_push_tokens;
CREATE POLICY device_push_tokens_owner_select ON public.device_push_tokens
    FOR SELECT
    USING (user_id = auth.uid());

DROP POLICY IF EXISTS device_push_tokens_owner_update ON public.device_push_tokens;
CREATE POLICY device_push_tokens_owner_update ON public.device_push_tokens
    FOR UPDATE
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- Direct INSERT/DELETE denied; use controlled RPCs only.
REVOKE ALL ON public.device_push_tokens FROM PUBLIC, anon, authenticated;
GRANT SELECT, UPDATE ON public.device_push_tokens TO authenticated;
GRANT ALL ON public.device_push_tokens TO service_role;

-- ============================================================================
-- 2. notification_preferences
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.notification_preferences (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    -- TRANSACTIONAL preferences are informational only; server ignores opt-out
    transactional_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    -- ENGAGEMENT categories (user-controllable)
    network_added_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    package_added_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    stock_restored_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    platform_updates_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    offers_announcements_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_notification_preferences_transactional_locked CHECK (
        transactional_enabled = TRUE
    )
);

COMMENT ON TABLE public.notification_preferences IS
    'Per-user notification preferences. Transactional channel cannot be disabled.';

CREATE TRIGGER trg_notification_preferences_set_updated_at
    BEFORE UPDATE ON public.notification_preferences
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS notification_preferences_owner_select ON public.notification_preferences;
CREATE POLICY notification_preferences_owner_select ON public.notification_preferences
    FOR SELECT
    USING (user_id = auth.uid());

DROP POLICY IF EXISTS notification_preferences_owner_update ON public.notification_preferences;
CREATE POLICY notification_preferences_owner_update ON public.notification_preferences
    FOR UPDATE
    USING (user_id = auth.uid())
    WITH CHECK (
        user_id = auth.uid()
        AND transactional_enabled = TRUE
    );

REVOKE ALL ON public.notification_preferences FROM PUBLIC, anon, authenticated;
GRANT SELECT, UPDATE ON public.notification_preferences TO authenticated;
GRANT ALL ON public.notification_preferences TO service_role;

-- ============================================================================
-- 3. notification_events (canonical server-generated events)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.notification_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type TEXT NOT NULL,
    category TEXT NOT NULL,
    channel_class TEXT NOT NULL,
    title_ar TEXT NOT NULL,
    body_ar TEXT NOT NULL,
    deep_link TEXT,
    audience_type TEXT NOT NULL,
    audience_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    source_entity_type TEXT,
    source_entity_id TEXT,
    dedupe_key TEXT NOT NULL,
    idempotency_key UUID,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    scheduled_for TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT chk_notification_events_category CHECK (
        category IN ('transactional', 'engagement')
    ),
    CONSTRAINT chk_notification_events_channel_class CHECK (
        channel_class IN (
            'request_status',
            'network_added',
            'package_added',
            'stock_restored',
            'platform_update',
            'announcement',
            'offer'
        )
    ),
    CONSTRAINT chk_notification_events_audience_type CHECK (
        audience_type IN (
            'specific_user',
            'all_active_customers',
            'governorate',
            'city',
            'network_related',
            'network_owner_operator',
            'role_based'
        )
    ),
    CONSTRAINT chk_notification_events_title_non_empty CHECK (length(trim(title_ar)) > 0),
    CONSTRAINT chk_notification_events_body_non_empty CHECK (length(trim(body_ar)) > 0),
    CONSTRAINT chk_notification_events_title_len CHECK (char_length(title_ar) <= 120),
    CONSTRAINT chk_notification_events_body_len CHECK (char_length(body_ar) <= 500),
    CONSTRAINT chk_notification_events_no_secrets CHECK (
        title_ar !~* '(كلمة\s*المرور|باسورد|password|pin\b|card\s*code|voucher|cvv|secret)'
        AND body_ar !~* '(كلمة\s*المرور|باسورد|password|pin\b|card\s*code|voucher|cvv|secret)'
        AND COALESCE(deep_link, '') !~* '(password|secret|token=)'
    ),
    CONSTRAINT chk_notification_events_metadata_size CHECK (
        octet_length(metadata::text) <= 4096
    ),
    CONSTRAINT uq_notification_events_dedupe UNIQUE (dedupe_key)
);

COMMENT ON TABLE public.notification_events IS
    'Server-generated notification events. No Wi-Fi passwords, card codes, or payment secrets.';

CREATE UNIQUE INDEX IF NOT EXISTS uq_notification_events_idempotency
    ON public.notification_events (idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_notification_events_type_created
    ON public.notification_events (event_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notification_events_scheduled
    ON public.notification_events (scheduled_for);

ALTER TABLE public.notification_events ENABLE ROW LEVEL SECURITY;

-- Users never read raw events table directly; inbox/delivery RPCs mediate.
DROP POLICY IF EXISTS notification_events_admin_select ON public.notification_events;
CREATE POLICY notification_events_admin_select ON public.notification_events
    FOR SELECT
    USING (
        public.has_platform_role('platform_admin')
        OR public.has_platform_role('system_auditor')
    );

REVOKE ALL ON public.notification_events FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.notification_events TO authenticated;
GRANT ALL ON public.notification_events TO service_role;

-- ============================================================================
-- 4. notification_outbox
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.notification_outbox (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES public.notification_events(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending',
    attempts INTEGER NOT NULL DEFAULT 0,
    max_attempts INTEGER NOT NULL DEFAULT 8,
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_error TEXT,
    locked_at TIMESTAMPTZ,
    locked_by TEXT,
    processed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_notification_outbox_status CHECK (
        status IN ('pending', 'processing', 'materialized', 'dispatch_blocked', 'failed', 'cancelled')
    ),
    CONSTRAINT chk_notification_outbox_attempts CHECK (attempts >= 0 AND attempts <= max_attempts),
    CONSTRAINT uq_notification_outbox_event UNIQUE (event_id)
);

COMMENT ON TABLE public.notification_outbox IS
    'Outbox for event materialization and provider-neutral dispatch. Dispatch remains blocked while OD-NOTIF-01 unbound.';

CREATE INDEX IF NOT EXISTS idx_notification_outbox_pending
    ON public.notification_outbox (status, next_attempt_at)
    WHERE status IN ('pending', 'processing');

CREATE TRIGGER trg_notification_outbox_set_updated_at
    BEFORE UPDATE ON public.notification_outbox
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.notification_outbox ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS notification_outbox_admin_select ON public.notification_outbox;
CREATE POLICY notification_outbox_admin_select ON public.notification_outbox
    FOR SELECT
    USING (
        public.has_platform_role('platform_admin')
        OR public.has_platform_role('system_auditor')
    );

REVOKE ALL ON public.notification_outbox FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.notification_outbox TO authenticated;
GRANT ALL ON public.notification_outbox TO service_role;

-- ============================================================================
-- 5. notification_deliveries
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.notification_deliveries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES public.notification_events(id) ON DELETE CASCADE,
    recipient_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    delivery_channel TEXT NOT NULL DEFAULT 'push',
    status TEXT NOT NULL DEFAULT 'pending',
    skip_reason TEXT,
    provider_message_id TEXT,
    attempt_count INTEGER NOT NULL DEFAULT 0,
    last_attempt_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_notification_deliveries_channel CHECK (
        delivery_channel IN ('push', 'in_app')
    ),
    CONSTRAINT chk_notification_deliveries_status CHECK (
        status IN (
            'pending',
            'queued',
            'skipped_opt_out',
            'skipped_rate_limit',
            'skipped_inactive',
            'dispatch_blocked_unbound_provider',
            'sent',
            'failed',
            'read'
        )
    ),
    CONSTRAINT uq_notification_deliveries_event_user_channel UNIQUE (event_id, recipient_user_id, delivery_channel)
);

COMMENT ON TABLE public.notification_deliveries IS
    'Per-recipient delivery tracking with retry metadata and opt-out/rate-limit outcomes.';

CREATE INDEX IF NOT EXISTS idx_notification_deliveries_recipient
    ON public.notification_deliveries (recipient_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notification_deliveries_event
    ON public.notification_deliveries (event_id);

CREATE INDEX IF NOT EXISTS idx_notification_deliveries_status
    ON public.notification_deliveries (status)
    WHERE status IN ('pending', 'queued', 'dispatch_blocked_unbound_provider');

CREATE TRIGGER trg_notification_deliveries_set_updated_at
    BEFORE UPDATE ON public.notification_deliveries
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.notification_deliveries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS notification_deliveries_owner_select ON public.notification_deliveries;
CREATE POLICY notification_deliveries_owner_select ON public.notification_deliveries
    FOR SELECT
    USING (recipient_user_id = auth.uid());

DROP POLICY IF EXISTS notification_deliveries_admin_select ON public.notification_deliveries;
CREATE POLICY notification_deliveries_admin_select ON public.notification_deliveries
    FOR SELECT
    USING (
        public.has_platform_role('platform_admin')
        OR public.has_platform_role('system_auditor')
    );

REVOKE ALL ON public.notification_deliveries FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.notification_deliveries TO authenticated;
GRANT ALL ON public.notification_deliveries TO service_role;

-- ============================================================================
-- 6. notification_inbox (in-app history / unread)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.notification_inbox (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    event_id UUID NOT NULL REFERENCES public.notification_events(id) ON DELETE CASCADE,
    delivery_id UUID REFERENCES public.notification_deliveries(id) ON DELETE SET NULL,
    title_ar TEXT NOT NULL,
    body_ar TEXT NOT NULL,
    deep_link TEXT,
    category TEXT NOT NULL,
    channel_class TEXT NOT NULL,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    read_at TIMESTAMPTZ,
    CONSTRAINT uq_notification_inbox_user_event UNIQUE (user_id, event_id)
);

COMMENT ON TABLE public.notification_inbox IS
    'In-app notification center rows. Safe Arabic copy only; no secrets.';

CREATE INDEX IF NOT EXISTS idx_notification_inbox_user_unread
    ON public.notification_inbox (user_id, created_at DESC)
    WHERE is_read = FALSE;

ALTER TABLE public.notification_inbox ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS notification_inbox_owner_select ON public.notification_inbox;
CREATE POLICY notification_inbox_owner_select ON public.notification_inbox
    FOR SELECT
    USING (user_id = auth.uid());

DROP POLICY IF EXISTS notification_inbox_owner_update ON public.notification_inbox;
CREATE POLICY notification_inbox_owner_update ON public.notification_inbox
    FOR UPDATE
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

REVOKE ALL ON public.notification_inbox FROM PUBLIC, anon, authenticated;
GRANT SELECT, UPDATE ON public.notification_inbox TO authenticated;
GRANT ALL ON public.notification_inbox TO service_role;

-- ============================================================================
-- 7. Rate-limit ledger (non-invasive; no tracking beyond delivery counts)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.notification_rate_limits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bucket_key TEXT NOT NULL,
    window_started_at TIMESTAMPTZ NOT NULL,
    window_seconds INTEGER NOT NULL,
    hit_count INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_notification_rate_limits_bucket_window UNIQUE (bucket_key, window_started_at),
    CONSTRAINT chk_notification_rate_limits_hits CHECK (hit_count >= 0)
);

CREATE INDEX IF NOT EXISTS idx_notification_rate_limits_bucket
    ON public.notification_rate_limits (bucket_key, window_started_at DESC);

ALTER TABLE public.notification_rate_limits ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.notification_rate_limits FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.notification_rate_limits TO service_role;

-- ============================================================================
-- Helpers
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ensure_notification_preferences(p_user_id UUID)
RETURNS VOID AS $$
BEGIN
    INSERT INTO public.notification_preferences (user_id)
    VALUES (p_user_id)
    ON CONFLICT (user_id) DO NOTHING;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.ensure_notification_preferences(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_notification_preferences(UUID) TO service_role;

CREATE OR REPLACE FUNCTION public.notification_assert_no_secrets(
    p_title TEXT,
    p_body TEXT,
    p_deep_link TEXT DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
    IF p_title ~* '(كلمة\s*المرور|باسورد|password|pin\b|card\s*code|voucher|cvv|secret)'
       OR p_body ~* '(كلمة\s*المرور|باسورد|password|pin\b|card\s*code|voucher|cvv|secret)'
       OR COALESCE(p_deep_link, '') ~* '(password|secret|token=)' THEN
        RAISE EXCEPTION 'SECRET_PAYLOAD_FORBIDDEN: Notification text must not contain secrets.'
            USING ERRCODE = '22000';
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.notification_assert_no_secrets(TEXT, TEXT, TEXT) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.notification_preference_allows(
    p_user_id UUID,
    p_category TEXT,
    p_channel_class TEXT
)
RETURNS BOOLEAN AS $$
DECLARE
    v_prefs public.notification_preferences%ROWTYPE;
BEGIN
    IF p_category = 'transactional' THEN
        RETURN TRUE;
    END IF;

    PERFORM public.ensure_notification_preferences(p_user_id);
    SELECT * INTO v_prefs FROM public.notification_preferences WHERE user_id = p_user_id;

    RETURN CASE p_channel_class
        WHEN 'network_added' THEN v_prefs.network_added_enabled
        WHEN 'package_added' THEN v_prefs.package_added_enabled
        WHEN 'stock_restored' THEN v_prefs.stock_restored_enabled
        WHEN 'platform_update' THEN v_prefs.platform_updates_enabled
        WHEN 'announcement' THEN v_prefs.offers_announcements_enabled
        WHEN 'offer' THEN v_prefs.offers_announcements_enabled
        ELSE TRUE
    END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.notification_preference_allows(UUID, TEXT, TEXT) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.notification_rate_limit_hit(
    p_bucket_key TEXT,
    p_window_seconds INTEGER,
    p_max_hits INTEGER
)
RETURNS BOOLEAN AS $$
DECLARE
    v_window_start TIMESTAMPTZ;
    v_count INTEGER;
BEGIN
    v_window_start := to_timestamp(
        floor(extract(epoch FROM NOW()) / p_window_seconds) * p_window_seconds
    );

    INSERT INTO public.notification_rate_limits (bucket_key, window_started_at, window_seconds, hit_count)
    VALUES (p_bucket_key, v_window_start, p_window_seconds, 1)
    ON CONFLICT (bucket_key, window_started_at)
    DO UPDATE SET
        hit_count = public.notification_rate_limits.hit_count + 1,
        updated_at = NOW()
    RETURNING hit_count INTO v_count;

    RETURN v_count <= p_max_hits;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.notification_rate_limit_hit(TEXT, INTEGER, INTEGER) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.resolve_notification_audience(
    p_audience_type TEXT,
    p_audience_payload JSONB
)
RETURNS TABLE (user_id UUID) AS $$
BEGIN
    IF p_audience_type = 'specific_user' THEN
        RETURN QUERY
        SELECT p.id
        FROM public.profiles p
        WHERE p.id = (p_audience_payload->>'user_id')::uuid
          AND p.account_status = 'active';
        RETURN;
    END IF;

    IF p_audience_type = 'all_active_customers' THEN
        RETURN QUERY
        SELECT DISTINCT ur.user_id
        FROM public.user_roles ur
        JOIN public.profiles p ON p.id = ur.user_id
        WHERE ur.role = 'customer'
          AND p.account_status = 'active';
        RETURN;
    END IF;

    IF p_audience_type = 'governorate' THEN
        RETURN QUERY
        SELECT p.id
        FROM public.profiles p
        WHERE p.account_status = 'active'
          AND p.default_governorate IS NOT NULL
          AND p.default_governorate = p_audience_payload->>'governorate';
        RETURN;
    END IF;

    IF p_audience_type = 'city' THEN
        RETURN QUERY
        SELECT p.id
        FROM public.profiles p
        WHERE p.account_status = 'active'
          AND p.default_city IS NOT NULL
          AND p.default_city = p_audience_payload->>'city'
          AND (
              p_audience_payload->>'governorate' IS NULL
              OR p.default_governorate = p_audience_payload->>'governorate'
          );
        RETURN;
    END IF;

    IF p_audience_type = 'network_related' THEN
        RETURN QUERY
        SELECT DISTINCT nm.user_id
        FROM public.network_memberships nm
        JOIN public.profiles p ON p.id = nm.user_id
        WHERE nm.network_id = (p_audience_payload->>'network_id')::uuid
          AND nm.status = 'active'
          AND p.account_status = 'active';
        RETURN;
    END IF;

    IF p_audience_type = 'network_owner_operator' THEN
        RETURN QUERY
        SELECT DISTINCT nm.user_id
        FROM public.network_memberships nm
        JOIN public.profiles p ON p.id = nm.user_id
        WHERE nm.network_id = (p_audience_payload->>'network_id')::uuid
          AND nm.membership_role IN ('owner', 'operator')
          AND nm.status = 'active'
          AND p.account_status = 'active';
        RETURN;
    END IF;

    IF p_audience_type = 'role_based' THEN
        RETURN QUERY
        SELECT DISTINCT ur.user_id
        FROM public.user_roles ur
        JOIN public.profiles p ON p.id = ur.user_id
        WHERE ur.role = p_audience_payload->>'role'
          AND p.account_status = 'active';
        RETURN;
    END IF;

    RAISE EXCEPTION 'INVALID_AUDIENCE: Unsupported audience_type %', p_audience_type
        USING ERRCODE = '22000';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.resolve_notification_audience(TEXT, JSONB) FROM PUBLIC;

-- ============================================================================
-- Core: enqueue_notification_event (idempotent)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.enqueue_notification_event(
    p_event_type TEXT,
    p_category TEXT,
    p_channel_class TEXT,
    p_title_ar TEXT,
    p_body_ar TEXT,
    p_deep_link TEXT,
    p_audience_type TEXT,
    p_audience_payload JSONB,
    p_source_entity_type TEXT DEFAULT NULL,
    p_source_entity_id TEXT DEFAULT NULL,
    p_dedupe_key TEXT DEFAULT NULL,
    p_idempotency_key UUID DEFAULT NULL,
    p_created_by UUID DEFAULT NULL,
    p_scheduled_for TIMESTAMPTZ DEFAULT NOW(),
    p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID AS $$
DECLARE
    v_event_id UUID;
    v_dedupe TEXT;
BEGIN
    PERFORM public.notification_assert_no_secrets(p_title_ar, p_body_ar, p_deep_link);

    v_dedupe := COALESCE(
        NULLIF(trim(p_dedupe_key), ''),
        p_event_type || ':' || COALESCE(p_source_entity_type, 'none') || ':' || COALESCE(p_source_entity_id, 'none')
    );

    IF p_idempotency_key IS NOT NULL THEN
        SELECT id INTO v_event_id
        FROM public.notification_events
        WHERE idempotency_key = p_idempotency_key;
        IF v_event_id IS NOT NULL THEN
            RETURN v_event_id;
        END IF;
    END IF;

    SELECT id INTO v_event_id
    FROM public.notification_events
    WHERE dedupe_key = v_dedupe;
    IF v_event_id IS NOT NULL THEN
        RETURN v_event_id;
    END IF;

    INSERT INTO public.notification_events (
        event_type,
        category,
        channel_class,
        title_ar,
        body_ar,
        deep_link,
        audience_type,
        audience_payload,
        source_entity_type,
        source_entity_id,
        dedupe_key,
        idempotency_key,
        created_by,
        scheduled_for,
        metadata
    ) VALUES (
        p_event_type,
        p_category,
        p_channel_class,
        trim(p_title_ar),
        trim(p_body_ar),
        NULLIF(trim(p_deep_link), ''),
        p_audience_type,
        COALESCE(p_audience_payload, '{}'::jsonb),
        p_source_entity_type,
        p_source_entity_id,
        v_dedupe,
        p_idempotency_key,
        p_created_by,
        COALESCE(p_scheduled_for, NOW()),
        COALESCE(p_metadata, '{}'::jsonb)
    )
    ON CONFLICT (dedupe_key) DO NOTHING
    RETURNING id INTO v_event_id;

    IF v_event_id IS NULL THEN
        SELECT id INTO v_event_id
        FROM public.notification_events
        WHERE dedupe_key = v_dedupe;
        RETURN v_event_id;
    END IF;

    INSERT INTO public.notification_outbox (event_id, status)
    VALUES (v_event_id, 'pending')
    ON CONFLICT (event_id) DO NOTHING;

    RETURN v_event_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.enqueue_notification_event(
    TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, TEXT, TEXT, TEXT, UUID, UUID, TIMESTAMPTZ, JSONB
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.enqueue_notification_event(
    TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, TEXT, TEXT, TEXT, UUID, UUID, TIMESTAMPTZ, JSONB
) TO service_role;

-- ============================================================================
-- Materialize outbox → deliveries + inbox (provider-neutral)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.process_notification_outbox(
    p_limit INTEGER DEFAULT 50
)
RETURNS JSONB AS $$
DECLARE
    v_row public.notification_outbox%ROWTYPE;
    v_event public.notification_events%ROWTYPE;
    v_recipient UUID;
    v_processed INTEGER := 0;
    v_deliveries INTEGER := 0;
    v_skipped INTEGER := 0;
    v_binding TEXT;
    v_delivery_id UUID;
    v_allowed BOOLEAN;
    v_rate_ok BOOLEAN;
BEGIN
    SELECT binding_status INTO v_binding
    FROM public.notification_transport_config
    WHERE id = 1;

    FOR v_row IN
        SELECT *
        FROM public.notification_outbox
        WHERE status = 'pending'
          AND next_attempt_at <= NOW()
        ORDER BY created_at
        LIMIT GREATEST(p_limit, 1)
        FOR UPDATE SKIP LOCKED
    LOOP
        UPDATE public.notification_outbox
        SET status = 'processing',
            attempts = attempts + 1,
            locked_at = NOW(),
            locked_by = 'process_notification_outbox'
        WHERE id = v_row.id;

        SELECT * INTO v_event FROM public.notification_events WHERE id = v_row.event_id;

        IF v_event.scheduled_for > NOW() THEN
            UPDATE public.notification_outbox
            SET status = 'pending',
                next_attempt_at = v_event.scheduled_for,
                locked_at = NULL,
                locked_by = NULL
            WHERE id = v_row.id;
            CONTINUE;
        END IF;

        FOR v_recipient IN
            SELECT ra.user_id FROM public.resolve_notification_audience(
                v_event.audience_type,
                v_event.audience_payload
            ) ra
        LOOP
            v_allowed := public.notification_preference_allows(
                v_recipient,
                v_event.category,
                v_event.channel_class
            );

            IF NOT v_allowed THEN
                INSERT INTO public.notification_deliveries (
                    event_id, recipient_user_id, delivery_channel, status, skip_reason
                ) VALUES (
                    v_event.id, v_recipient, 'push', 'skipped_opt_out', 'user_opted_out'
                )
                ON CONFLICT (event_id, recipient_user_id, delivery_channel) DO NOTHING;
                v_skipped := v_skipped + 1;
                CONTINUE;
            END IF;

            IF v_event.category = 'engagement' THEN
                v_rate_ok := public.notification_rate_limit_hit(
                    'engagement:' || v_recipient::text,
                    3600,
                    20
                );
                IF NOT v_rate_ok THEN
                    INSERT INTO public.notification_deliveries (
                        event_id, recipient_user_id, delivery_channel, status, skip_reason
                    ) VALUES (
                        v_event.id, v_recipient, 'push', 'skipped_rate_limit', 'hourly_engagement_cap'
                    )
                    ON CONFLICT (event_id, recipient_user_id, delivery_channel) DO NOTHING;
                    v_skipped := v_skipped + 1;
                    CONTINUE;
                END IF;
            END IF;

            IF COALESCE(v_binding, 'unbound') <> 'bound' THEN
                INSERT INTO public.notification_deliveries (
                    event_id, recipient_user_id, delivery_channel, status, skip_reason, attempt_count, last_attempt_at
                ) VALUES (
                    v_event.id,
                    v_recipient,
                    'push',
                    'dispatch_blocked_unbound_provider',
                    'OD-NOTIF-01_provider_unbound',
                    1,
                    NOW()
                )
                ON CONFLICT (event_id, recipient_user_id, delivery_channel) DO NOTHING
                RETURNING id INTO v_delivery_id;
            ELSE
                INSERT INTO public.notification_deliveries (
                    event_id, recipient_user_id, delivery_channel, status, attempt_count, last_attempt_at
                ) VALUES (
                    v_event.id, v_recipient, 'push', 'queued', 1, NOW()
                )
                ON CONFLICT (event_id, recipient_user_id, delivery_channel) DO NOTHING
                RETURNING id INTO v_delivery_id;
            END IF;

            -- Always create in-app inbox row (safe local history regardless of provider)
            INSERT INTO public.notification_deliveries (
                event_id, recipient_user_id, delivery_channel, status, attempt_count, last_attempt_at
            ) VALUES (
                v_event.id, v_recipient, 'in_app', 'sent', 1, NOW()
            )
            ON CONFLICT (event_id, recipient_user_id, delivery_channel) DO NOTHING
            RETURNING id INTO v_delivery_id;

            INSERT INTO public.notification_inbox (
                user_id, event_id, delivery_id, title_ar, body_ar, deep_link, category, channel_class
            ) VALUES (
                v_recipient,
                v_event.id,
                v_delivery_id,
                v_event.title_ar,
                v_event.body_ar,
                v_event.deep_link,
                v_event.category,
                v_event.channel_class
            )
            ON CONFLICT (user_id, event_id) DO NOTHING;

            v_deliveries := v_deliveries + 1;
        END LOOP;

        UPDATE public.notification_outbox
        SET status = CASE
                WHEN COALESCE(v_binding, 'unbound') <> 'bound' THEN 'dispatch_blocked'
                ELSE 'materialized'
            END,
            processed_at = NOW(),
            locked_at = NULL,
            locked_by = NULL,
            last_error = CASE
                WHEN COALESCE(v_binding, 'unbound') <> 'bound'
                    THEN 'Provider transport unbound (OD-NOTIF-01). In-app deliveries materialized.'
                ELSE NULL
            END
        WHERE id = v_row.id;

        v_processed := v_processed + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'processed', v_processed,
        'deliveries_created', v_deliveries,
        'skipped', v_skipped,
        'transport_binding', COALESCE(v_binding, 'unbound')
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.process_notification_outbox(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.process_notification_outbox(INTEGER) TO service_role;
-- Allow authenticated admins to trigger materialization for ops visibility (no provider send).
GRANT EXECUTE ON FUNCTION public.process_notification_outbox(INTEGER) TO authenticated;

CREATE OR REPLACE FUNCTION public.process_notification_outbox_guarded(
    p_limit INTEGER DEFAULT 50
)
RETURNS JSONB AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    IF NOT (
        public.has_platform_role('platform_admin')
        OR public.has_platform_role('system_service')
    ) THEN
        -- service_role / internal callers with no auth.uid still blocked here;
        -- use process_notification_outbox via service_role directly.
        RAISE EXCEPTION 'FORBIDDEN_ROLE: Only platform_admin can trigger outbox processing.'
            USING ERRCODE = '42501';
    END IF;

    RETURN public.process_notification_outbox(p_limit);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.process_notification_outbox_guarded(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.process_notification_outbox_guarded(INTEGER) TO authenticated;

-- Restrict direct process_notification_outbox for non-service authenticated:
-- Keep grant but wrap: actually revoke authenticated from unguarded and only grant guarded.
REVOKE EXECUTE ON FUNCTION public.process_notification_outbox(INTEGER) FROM authenticated;

-- ============================================================================
-- User RPCs: tokens, preferences, inbox
-- ============================================================================

CREATE OR REPLACE FUNCTION public.register_device_push_token(
    p_platform TEXT,
    p_token TEXT,
    p_device_fingerprint TEXT DEFAULT NULL,
    p_app_version TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_id UUID;
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

    IF p_platform NOT IN ('android', 'ios', 'web', 'unknown') THEN
        RAISE EXCEPTION 'INVALID_PLATFORM: Unsupported platform.'
            USING ERRCODE = '22000';
    END IF;

    IF p_token IS NULL OR length(trim(p_token)) = 0 THEN
        RAISE EXCEPTION 'INVALID_TOKEN: Token required.'
            USING ERRCODE = '22000';
    END IF;

    IF p_token ~* '(BEGIN (RSA |EC )?PRIVATE KEY|service_account|private_key|AIza)' THEN
        RAISE EXCEPTION 'SECRET_TOKEN_FORBIDDEN: Provider secrets must not be registered as device tokens.'
            USING ERRCODE = '22000';
    END IF;

    INSERT INTO public.device_push_tokens (
        user_id, platform, token, device_fingerprint, app_version, is_active, last_seen_at
    ) VALUES (
        v_user_id, p_platform, trim(p_token), p_device_fingerprint, p_app_version, TRUE, NOW()
    )
    ON CONFLICT (user_id, token) DO UPDATE SET
        platform = EXCLUDED.platform,
        device_fingerprint = COALESCE(EXCLUDED.device_fingerprint, public.device_push_tokens.device_fingerprint),
        app_version = COALESCE(EXCLUDED.app_version, public.device_push_tokens.app_version),
        is_active = TRUE,
        last_seen_at = NOW(),
        updated_at = NOW()
    RETURNING id INTO v_id;

    PERFORM public.ensure_notification_preferences(v_user_id);

    RETURN jsonb_build_object('id', v_id, 'user_id', v_user_id, 'is_active', TRUE);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.register_device_push_token(TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_device_push_token(TEXT, TEXT, TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.deactivate_device_push_token(
    p_token TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_count INTEGER;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    UPDATE public.device_push_tokens
    SET is_active = FALSE, updated_at = NOW()
    WHERE user_id = v_user_id
      AND token = p_token;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN jsonb_build_object('deactivated', v_count > 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.deactivate_device_push_token(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.deactivate_device_push_token(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_notification_preferences()
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_prefs public.notification_preferences%ROWTYPE;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    PERFORM public.ensure_notification_preferences(v_user_id);
    SELECT * INTO v_prefs FROM public.notification_preferences WHERE user_id = v_user_id;

    RETURN jsonb_build_object(
        'user_id', v_prefs.user_id,
        'transactional_enabled', v_prefs.transactional_enabled,
        'network_added_enabled', v_prefs.network_added_enabled,
        'package_added_enabled', v_prefs.package_added_enabled,
        'stock_restored_enabled', v_prefs.stock_restored_enabled,
        'platform_updates_enabled', v_prefs.platform_updates_enabled,
        'offers_announcements_enabled', v_prefs.offers_announcements_enabled,
        'updated_at', v_prefs.updated_at
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.get_notification_preferences() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_notification_preferences() TO authenticated;

CREATE OR REPLACE FUNCTION public.update_notification_preferences(
    p_network_added_enabled BOOLEAN DEFAULT NULL,
    p_package_added_enabled BOOLEAN DEFAULT NULL,
    p_stock_restored_enabled BOOLEAN DEFAULT NULL,
    p_platform_updates_enabled BOOLEAN DEFAULT NULL,
    p_offers_announcements_enabled BOOLEAN DEFAULT NULL
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

    PERFORM public.ensure_notification_preferences(v_user_id);

    UPDATE public.notification_preferences
    SET
        network_added_enabled = COALESCE(p_network_added_enabled, network_added_enabled),
        package_added_enabled = COALESCE(p_package_added_enabled, package_added_enabled),
        stock_restored_enabled = COALESCE(p_stock_restored_enabled, stock_restored_enabled),
        platform_updates_enabled = COALESCE(p_platform_updates_enabled, platform_updates_enabled),
        offers_announcements_enabled = COALESCE(p_offers_announcements_enabled, offers_announcements_enabled),
        transactional_enabled = TRUE,
        updated_at = NOW()
    WHERE user_id = v_user_id;

    RETURN public.get_notification_preferences();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.update_notification_preferences(BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_notification_preferences(BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.list_my_notifications(
    p_limit INTEGER DEFAULT 50,
    p_unread_only BOOLEAN DEFAULT FALSE
)
RETURNS SETOF public.notification_inbox AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    RETURN QUERY
    SELECT n.*
    FROM public.notification_inbox n
    WHERE n.user_id = v_user_id
      AND (NOT p_unread_only OR n.is_read = FALSE)
    ORDER BY n.created_at DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.list_my_notifications(INTEGER, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_my_notifications(INTEGER, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_notification_read(
    p_inbox_id UUID
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

    UPDATE public.notification_inbox
    SET is_read = TRUE, read_at = NOW()
    WHERE id = p_inbox_id AND user_id = v_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND: Notification not found.'
            USING ERRCODE = '42501';
    END IF;

    UPDATE public.notification_deliveries d
    SET status = 'read', read_at = NOW(), updated_at = NOW()
    FROM public.notification_inbox i
    WHERE i.id = p_inbox_id
      AND i.user_id = v_user_id
      AND d.event_id = i.event_id
      AND d.recipient_user_id = v_user_id;

    RETURN jsonb_build_object('id', p_inbox_id, 'is_read', TRUE);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.mark_notification_read(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_notification_read(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_unread_notification_count()
RETURNS INTEGER AS $$
DECLARE
    v_user_id UUID;
    v_count INTEGER;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    SELECT COUNT(*)::INTEGER INTO v_count
    FROM public.notification_inbox
    WHERE user_id = v_user_id AND is_read = FALSE;

    RETURN COALESCE(v_count, 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.get_unread_notification_count() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_unread_notification_count() TO authenticated;

-- ============================================================================
-- Admin composer + delivery summary
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admin_compose_notification(
    p_title_ar TEXT,
    p_body_ar TEXT,
    p_audience_type TEXT,
    p_audience_payload JSONB DEFAULT '{}'::jsonb,
    p_channel_class TEXT DEFAULT 'announcement',
    p_deep_link TEXT DEFAULT 'notifications',
    p_scheduled_for TIMESTAMPTZ DEFAULT NOW(),
    p_idempotency_key UUID DEFAULT NULL,
    p_process_immediately BOOLEAN DEFAULT TRUE
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_event_id UUID;
    v_process JSONB;
    v_rate_ok BOOLEAN;
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

    IF NOT public.has_platform_role('platform_admin') THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE: Only platform_admin can compose announcements.'
            USING ERRCODE = '42501';
    END IF;

    IF p_channel_class NOT IN ('platform_update', 'announcement', 'offer') THEN
        RAISE EXCEPTION 'INVALID_CHANNEL: Admin composer supports platform_update, announcement, offer.'
            USING ERRCODE = '22000';
    END IF;

    IF p_audience_type NOT IN (
        'all_active_customers', 'governorate', 'city',
        'network_related', 'network_owner_operator', 'specific_user', 'role_based'
    ) THEN
        RAISE EXCEPTION 'INVALID_AUDIENCE: Unsupported audience for admin composer.'
            USING ERRCODE = '22000';
    END IF;

    v_rate_ok := public.notification_rate_limit_hit(
        'admin_compose:' || v_user_id::text,
        86400,
        50
    );
    IF NOT v_rate_ok THEN
        RAISE EXCEPTION 'RATE_LIMITED: Daily admin compose limit reached.'
            USING ERRCODE = '54000';
    END IF;

    v_event_id := public.enqueue_notification_event(
        'admin_announcement',
        'engagement',
        p_channel_class,
        p_title_ar,
        p_body_ar,
        COALESCE(NULLIF(trim(p_deep_link), ''), 'notifications'),
        p_audience_type,
        COALESCE(p_audience_payload, '{}'::jsonb),
        'admin_compose',
        COALESCE(p_idempotency_key::text, gen_random_uuid()::text),
        'admin_compose:' || COALESCE(p_idempotency_key::text, gen_random_uuid()::text),
        p_idempotency_key,
        v_user_id,
        COALESCE(p_scheduled_for, NOW()),
        jsonb_build_object('composer', 'admin', 'preview', TRUE)
    );

    PERFORM public.record_audit_event(
        'ADMIN_COMPOSE_NOTIFICATION',
        'notification_event',
        v_event_id::text,
        'success',
        'ADMIN_COMPOSE',
        jsonb_build_object(
            'audience_type', p_audience_type,
            'channel_class', p_channel_class,
            'scheduled_for', COALESCE(p_scheduled_for, NOW())
        )
    );

    IF p_process_immediately AND COALESCE(p_scheduled_for, NOW()) <= NOW() THEN
        v_process := public.process_notification_outbox(100);
    ELSE
        v_process := jsonb_build_object('processed', 0, 'deferred', TRUE);
    END IF;

    RETURN jsonb_build_object(
        'event_id', v_event_id,
        'title_ar', trim(p_title_ar),
        'body_ar', trim(p_body_ar),
        'audience_type', p_audience_type,
        'process_result', v_process
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.admin_compose_notification(
    TEXT, TEXT, TEXT, JSONB, TEXT, TEXT, TIMESTAMPTZ, UUID, BOOLEAN
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_compose_notification(
    TEXT, TEXT, TEXT, JSONB, TEXT, TEXT, TIMESTAMPTZ, UUID, BOOLEAN
) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_notification_delivery_summary(
    p_event_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_event public.notification_events%ROWTYPE;
    v_summary JSONB;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    IF NOT (
        public.has_platform_role('platform_admin')
        OR public.has_platform_role('system_auditor')
    ) THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE: Only platform_admin or system_auditor can view delivery summary.'
            USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_event FROM public.notification_events WHERE id = p_event_id;
    IF v_event.id IS NULL THEN
        RAISE EXCEPTION 'NOT_FOUND: Notification event not found.'
            USING ERRCODE = '42501';
    END IF;

    SELECT jsonb_build_object(
        'event_id', v_event.id,
        'event_type', v_event.event_type,
        'category', v_event.category,
        'channel_class', v_event.channel_class,
        'title_ar', v_event.title_ar,
        'body_ar', v_event.body_ar,
        'audience_type', v_event.audience_type,
        'scheduled_for', v_event.scheduled_for,
        'created_at', v_event.created_at,
        'counts', COALESCE((
            SELECT jsonb_object_agg(status, cnt)
            FROM (
                SELECT status, COUNT(*)::INTEGER AS cnt
                FROM public.notification_deliveries
                WHERE event_id = p_event_id
                GROUP BY status
            ) s
        ), '{}'::jsonb),
        'total_deliveries', (
            SELECT COUNT(*)::INTEGER FROM public.notification_deliveries WHERE event_id = p_event_id
        ),
        'inbox_rows', (
            SELECT COUNT(*)::INTEGER FROM public.notification_inbox WHERE event_id = p_event_id
        ),
        'transport', (
            SELECT jsonb_build_object(
                'provider_key', provider_key,
                'binding_status', binding_status,
                'adapter_interface', adapter_interface
            )
            FROM public.notification_transport_config WHERE id = 1
        )
    ) INTO v_summary;

    RETURN v_summary;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.admin_notification_delivery_summary(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_notification_delivery_summary(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_notification_transport_status()
RETURNS JSONB AS $$
DECLARE
    v_cfg public.notification_transport_config%ROWTYPE;
BEGIN
    SELECT * INTO v_cfg FROM public.notification_transport_config WHERE id = 1;
    RETURN jsonb_build_object(
        'provider_key', v_cfg.provider_key,
        'binding_status', v_cfg.binding_status,
        'adapter_interface', v_cfg.adapter_interface,
        'notes', v_cfg.notes,
        'od_notif_01', 'OPEN_DECISION',
        'external_push_dispatch_enabled', v_cfg.binding_status = 'bound'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.get_notification_transport_status() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_notification_transport_status() TO authenticated;

-- ============================================================================
-- Domain event hooks (triggers) — transactional + engagement
-- ============================================================================

CREATE OR REPLACE FUNCTION public.trg_notify_network_request_status()
RETURNS TRIGGER AS $$
DECLARE
    v_title TEXT;
    v_body TEXT;
    v_deep TEXT;
BEGIN
    IF TG_OP = 'UPDATE'
       AND NEW.status IS DISTINCT FROM OLD.status
       AND NEW.status IN ('under_review', 'approved', 'rejected', 'matched_existing') THEN

        v_deep := 'request/' || NEW.id::text;

        IF NEW.status = 'approved' THEN
            v_title := 'تم قبول طلب الشبكة';
            v_body := 'تم قبول طلب إضافة الشبكة الخاص بك.';
        ELSIF NEW.status = 'rejected' THEN
            v_title := 'تم رفض طلب الشبكة';
            v_body := 'تم رفض طلب إضافة الشبكة. راجع التفاصيل في التطبيق.';
        ELSIF NEW.status = 'matched_existing' THEN
            v_title := 'تم مطابقة طلبك مع شبكة موجودة';
            v_body := 'طلبك يطابق شبكة موجودة في الكتالوج.';
        ELSE
            v_title := 'طلب الشبكة قيد المراجعة';
            v_body := 'طلب إضافة الشبكة قيد المراجعة الآن.';
        END IF;

        PERFORM public.enqueue_notification_event(
            'network_request_' || NEW.status,
            'transactional',
            'request_status',
            v_title,
            v_body,
            v_deep,
            'specific_user',
            jsonb_build_object('user_id', NEW.requester_user_id),
            'network_addition_request',
            NEW.id::text,
            'request_status:' || NEW.id::text || ':' || NEW.status,
            NULL,
            NEW.resolved_by,
            NOW(),
            jsonb_build_object('status', NEW.status)
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_notify_network_request_status') THEN
        CREATE TRIGGER trg_notify_network_request_status
            AFTER UPDATE OF status ON public.network_addition_requests
            FOR EACH ROW
            EXECUTE FUNCTION public.trg_notify_network_request_status();
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.trg_notify_network_added()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE'
       AND NEW.status = 'active'
       AND NEW.verification_status = 'verified'
       AND (OLD.status IS DISTINCT FROM NEW.status OR OLD.verification_status IS DISTINCT FROM NEW.verification_status) THEN

        PERFORM public.enqueue_notification_event(
            'network_added',
            'engagement',
            'network_added',
            'شبكة جديدة متاحة',
            'تمت إضافة شبكة جديدة: ' || NEW.commercial_name,
            'network/' || NEW.id::text,
            'all_active_customers',
            '{}'::jsonb,
            'network',
            NEW.id::text,
            'network_added:' || NEW.id::text,
            NULL,
            NEW.approved_by,
            NOW(),
            jsonb_build_object(
                'commercial_name', NEW.commercial_name,
                'governorate', NEW.governorate,
                'city', NEW.city
            )
        );

        -- Also notify network owners/operators
        PERFORM public.enqueue_notification_event(
            'network_approved_ops',
            'transactional',
            'request_status',
            'تمت الموافقة على شبكتك',
            'شبكتك أصبحت نشطة في الكتالوج.',
            'network/' || NEW.id::text,
            'network_owner_operator',
            jsonb_build_object('network_id', NEW.id),
            'network',
            NEW.id::text,
            'network_approved_ops:' || NEW.id::text,
            NULL,
            NEW.approved_by,
            NOW(),
            '{}'::jsonb
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_notify_network_added') THEN
        CREATE TRIGGER trg_notify_network_added
            AFTER UPDATE OF status, verification_status ON public.networks
            FOR EACH ROW
            EXECUTE FUNCTION public.trg_notify_network_added();
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.trg_notify_package_added()
RETURNS TRIGGER AS $$
DECLARE
    v_network_name TEXT;
BEGIN
    IF TG_OP = 'UPDATE'
       AND NEW.status = 'active'
       AND NEW.is_public = TRUE
       AND (OLD.status IS DISTINCT FROM NEW.status OR OLD.is_public IS DISTINCT FROM NEW.is_public) THEN

        SELECT commercial_name INTO v_network_name
        FROM public.networks WHERE id = NEW.network_id;

        PERFORM public.enqueue_notification_event(
            'package_added',
            'engagement',
            'package_added',
            'باقة جديدة متاحة',
            'تتوفر باقة جديدة على شبكة ' || COALESCE(v_network_name, 'معتمدة'),
            'package/' || NEW.id::text,
            'all_active_customers',
            '{}'::jsonb,
            'network_package',
            NEW.id::text,
            'package_added:' || NEW.id::text,
            NULL,
            NULL,
            NOW(),
            jsonb_build_object('network_id', NEW.network_id)
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_notify_package_added') THEN
        CREATE TRIGGER trg_notify_package_added
            AFTER UPDATE OF status, is_public ON public.network_packages
            FOR EACH ROW
            EXECUTE FUNCTION public.trg_notify_package_added();
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.trg_notify_stock_restored()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE'
       AND OLD.available_units = 0
       AND NEW.available_units > 0 THEN

        PERFORM public.enqueue_notification_event(
            'stock_restored',
            'engagement',
            'stock_restored',
            'تم تجديد المخزون',
            'عادت الباقة إلى التوفر. افتح التطبيق للاطلاع.',
            'package/' || NEW.package_id::text,
            'all_active_customers',
            '{}'::jsonb,
            'package_inventory',
            NEW.package_id::text,
            'stock_restored:' || NEW.package_id::text || ':' || date_trunc('hour', NOW())::text,
            NULL,
            NULL,
            NOW(),
            jsonb_build_object('network_id', NEW.network_id, 'available_units', NEW.available_units)
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_notify_stock_restored') THEN
        CREATE TRIGGER trg_notify_stock_restored
            AFTER UPDATE OF available_units ON public.package_inventory_balances
            FOR EACH ROW
            EXECUTE FUNCTION public.trg_notify_stock_restored();
    END IF;
END $$;

-- Auto-process outbox shortly after enqueue (best-effort within same transaction path)
CREATE OR REPLACE FUNCTION public.trg_notification_outbox_autoclose()
RETURNS TRIGGER AS $$
BEGIN
    -- Materialize within same session for source-side completeness; provider remains unbound.
    PERFORM public.process_notification_outbox(20);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_notification_outbox_autoclose') THEN
        CREATE TRIGGER trg_notification_outbox_autoclose
            AFTER INSERT ON public.notification_outbox
            FOR EACH STATEMENT
            EXECUTE FUNCTION public.trg_notification_outbox_autoclose();
    END IF;
END $$;
