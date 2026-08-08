-- NetYemen V1 External Pilot Binding Migration
-- Migration: 20260808210000_netyemen_v1_external_pilot_binding.sql
-- Task ID: NY-V1-EXTERNAL-PILOT-BINDING-001
-- Scope: Owner-approved binding of OD-NOTIF-01, OD-FIN-01, OD-FIN-02, OD-FIN-03,
--        OD-CARD-01, OD-CARD-02, OD-SETTLE-01 for the V1 external pilot.

-- ============================================================================
-- 0. Notification transport binding state (OD-NOTIF-01)
-- ============================================================================
UPDATE public.notification_transport_config
SET provider_key = 'fcm',
    binding_status = 'approved_pending_secrets',
    notes = 'OD-NOTIF-01 APPROVED. FCM binding approved; real credentials must be configured in Edge Function secrets for physical pilot.',
    updated_at = NOW()
WHERE id = 1;

-- ============================================================================
-- 1. Payment Destination Directory (OD-FIN-03)
-- ============================================================================

-- Migration-safe rename of the legacy bank directory table. Foreign keys follow
-- by OID, so wallet_deposit_requests.bank_directory_id remains valid.
ALTER TABLE IF EXISTS public.bank_directory RENAME TO payment_destinations;

-- Expand the schema to support bank accounts, mobile wallets, and manual transfers.
ALTER TABLE public.payment_destinations
    ADD COLUMN IF NOT EXISTS provider_type TEXT,
    ADD COLUMN IF NOT EXISTS display_name TEXT,
    ADD COLUMN IF NOT EXISTS account_holder_name TEXT,
    ADD COLUMN IF NOT EXISTS account_identifier TEXT,
    ADD COLUMN IF NOT EXISTS instructions TEXT;

-- Migrate legacy column data into the new normalized shape.
UPDATE public.payment_destinations
SET provider_type = COALESCE(provider_type, 'bank_account'),
    display_name = COALESCE(display_name, provider_name),
    account_holder_name = COALESCE(account_holder_name, account_label),
    account_identifier = COALESCE(account_identifier, COALESCE(account_number, iban))
WHERE provider_type IS NULL OR display_name IS NULL;

-- Drop legacy columns.
ALTER TABLE public.payment_destinations
    DROP COLUMN IF EXISTS provider_name,
    DROP COLUMN IF EXISTS account_label,
    DROP COLUMN IF EXISTS account_number,
    DROP COLUMN IF EXISTS iban;

-- Enforce the new shape.
ALTER TABLE public.payment_destinations
    ALTER COLUMN provider_type SET NOT NULL,
    ALTER COLUMN provider_type SET DEFAULT 'bank_account',
    ALTER COLUMN display_name SET NOT NULL,
    ALTER COLUMN currency SET DEFAULT 'YER',
    ALTER COLUMN is_active SET DEFAULT TRUE,
    ALTER COLUMN sort_order SET DEFAULT 0;

ALTER TABLE public.payment_destinations
    DROP CONSTRAINT IF EXISTS chk_payment_destinations_provider_type,
    ADD CONSTRAINT chk_payment_destinations_provider_type
        CHECK (provider_type IN ('bank_account', 'mobile_wallet', 'manual_transfer', 'other'));

COMMENT ON TABLE public.payment_destinations IS
    'Admin-managed directory of customer payment destinations (OD-FIN-03). Supports bank accounts, mobile wallets, and manual transfer instructions.';

-- Snapshot column: preserves the destination as it appeared when the request was created.
ALTER TABLE public.wallet_deposit_requests
    ADD COLUMN IF NOT EXISTS destination_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
    ADD CONSTRAINT chk_wallet_deposit_requests_destination_snapshot_size
        CHECK (octet_length(destination_snapshot::text) <= 4096);

COMMENT ON COLUMN public.wallet_deposit_requests.destination_snapshot IS
    'Immutable snapshot of the selected payment destination at the time the deposit request was created.';

-- Trigger enforcement: legacy rows with NULL bank_directory_id are allowed to remain,
-- but all new inserts/updates must reference a valid payment destination.
CREATE OR REPLACE FUNCTION public.enforce_wallet_deposit_destination_not_null()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.bank_directory_id IS NULL THEN
        RAISE EXCEPTION 'PAYMENT_DESTINATION_REQUIRED: A valid payment destination is required for new deposit requests.'
            USING ERRCODE = '22000';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS trg_wallet_deposit_destination_required ON public.wallet_deposit_requests;
CREATE TRIGGER trg_wallet_deposit_destination_required
    BEFORE INSERT OR UPDATE ON public.wallet_deposit_requests
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_wallet_deposit_destination_not_null();

REVOKE EXECUTE ON FUNCTION public.enforce_wallet_deposit_destination_not_null() FROM PUBLIC;

-- Helper: finance officer or platform admin.
CREATE OR REPLACE FUNCTION public.is_finance_or_admin()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN public.is_finance_officer() OR public.has_platform_role('platform_admin');
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.is_finance_or_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_finance_or_admin() TO anon, authenticated;

-- ----------------------------------------------------------------------------
-- RPC: admin_create_payment_destination
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_create_payment_destination(
    p_provider_type TEXT,
    p_display_name TEXT,
    p_account_holder_name TEXT DEFAULT NULL,
    p_account_identifier TEXT DEFAULT NULL,
    p_instructions TEXT DEFAULT NULL,
    p_currency TEXT DEFAULT 'YER',
    p_sort_order INTEGER DEFAULT 0
)
RETURNS UUID AS $$
DECLARE
    v_user_id UUID;
    v_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.' USING ERRCODE = '28000';
    END IF;

    IF NOT public.is_finance_or_admin() THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE: Only finance_officer or platform_admin can manage payment destinations.'
            USING ERRCODE = '42501';
    END IF;

    IF p_provider_type IS NULL OR p_provider_type NOT IN ('bank_account', 'mobile_wallet', 'manual_transfer', 'other') THEN
        RAISE EXCEPTION 'INVALID_PROVIDER_TYPE: Must be one of bank_account, mobile_wallet, manual_transfer, other.'
            USING ERRCODE = '22000';
    END IF;

    IF p_display_name IS NULL OR length(trim(p_display_name)) = 0 THEN
        RAISE EXCEPTION 'INVALID_DISPLAY_NAME: Display name is required.' USING ERRCODE = '22000';
    END IF;

    INSERT INTO public.payment_destinations (
        provider_type,
        display_name,
        account_holder_name,
        account_identifier,
        instructions,
        currency,
        is_active,
        sort_order
    ) VALUES (
        p_provider_type,
        trim(p_display_name),
        p_account_holder_name,
        p_account_identifier,
        p_instructions,
        COALESCE(p_currency, 'YER'),
        TRUE,
        COALESCE(p_sort_order, 0)
    ) RETURNING id INTO v_id;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.admin_create_payment_destination(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_create_payment_destination(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER) TO authenticated;

-- ----------------------------------------------------------------------------
-- RPC: admin_update_payment_destination
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_update_payment_destination(
    p_id UUID,
    p_provider_type TEXT DEFAULT NULL,
    p_display_name TEXT DEFAULT NULL,
    p_account_holder_name TEXT DEFAULT NULL,
    p_account_identifier TEXT DEFAULT NULL,
    p_instructions TEXT DEFAULT NULL,
    p_currency TEXT DEFAULT NULL,
    p_sort_order INTEGER DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.' USING ERRCODE = '28000';
    END IF;

    IF NOT public.is_finance_or_admin() THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE: Only finance_officer or platform_admin can manage payment destinations.'
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.payment_destinations WHERE id = p_id) THEN
        RAISE EXCEPTION 'NOT_FOUND: Payment destination not found.' USING ERRCODE = '42501';
    END IF;

    IF p_provider_type IS NOT NULL AND p_provider_type NOT IN ('bank_account', 'mobile_wallet', 'manual_transfer', 'other') THEN
        RAISE EXCEPTION 'INVALID_PROVIDER_TYPE' USING ERRCODE = '22000';
    END IF;

    UPDATE public.payment_destinations
    SET
        provider_type = COALESCE(p_provider_type, provider_type),
        display_name = COALESCE(trim(p_display_name), display_name),
        account_holder_name = COALESCE(p_account_holder_name, account_holder_name),
        account_identifier = COALESCE(p_account_identifier, account_identifier),
        instructions = COALESCE(p_instructions, instructions),
        currency = COALESCE(p_currency, currency),
        sort_order = COALESCE(p_sort_order, sort_order),
        updated_at = NOW()
    WHERE id = p_id;

    RETURN jsonb_build_object('id', p_id, 'updated', TRUE);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.admin_update_payment_destination(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_payment_destination(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER) TO authenticated;

-- ----------------------------------------------------------------------------
-- RPC: admin_set_payment_destination_active
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_set_payment_destination_active(
    p_id UUID,
    p_active BOOLEAN
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.' USING ERRCODE = '28000';
    END IF;

    IF NOT public.is_finance_or_admin() THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE' USING ERRCODE = '42501';
    END IF;

    UPDATE public.payment_destinations
    SET is_active = p_active,
        updated_at = NOW()
    WHERE id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND: Payment destination not found.' USING ERRCODE = '42501';
    END IF;

    RETURN jsonb_build_object('id', p_id, 'is_active', p_active);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.admin_set_payment_destination_active(UUID, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_payment_destination_active(UUID, BOOLEAN) TO authenticated;

-- ----------------------------------------------------------------------------
-- RPC: admin_reorder_payment_destinations
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_reorder_payment_destinations(
    p_ordered_ids UUID[]
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_id UUID;
    v_idx INTEGER := 0;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.' USING ERRCODE = '28000';
    END IF;

    IF NOT public.is_finance_or_admin() THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE' USING ERRCODE = '42501';
    END IF;

    IF p_ordered_ids IS NULL OR array_length(p_ordered_ids, 1) IS NULL THEN
        RAISE EXCEPTION 'INVALID_ORDER: Ordered ids array is required.' USING ERRCODE = '22000';
    END IF;

    FOREACH v_id IN ARRAY p_ordered_ids
    LOOP
        UPDATE public.payment_destinations
        SET sort_order = v_idx,
            updated_at = NOW()
        WHERE id = v_id;
        v_idx := v_idx + 1;
    END LOOP;

    RETURN jsonb_build_object('updated', v_idx);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.admin_reorder_payment_destinations(UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_reorder_payment_destinations(UUID[]) TO authenticated;

-- ----------------------------------------------------------------------------
-- RPC: get_active_payment_destinations
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_active_payment_destinations()
RETURNS JSONB AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY sort_order, display_name), '[]'::jsonb)
    INTO v_result
    FROM (
        SELECT
            id,
            provider_type,
            display_name,
            account_holder_name,
            account_identifier,
            instructions,
            currency,
            sort_order
        FROM public.payment_destinations
        WHERE is_active = TRUE
    ) t;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.get_active_payment_destinations() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_active_payment_destinations() TO anon, authenticated;

-- ----------------------------------------------------------------------------
-- Update create_wallet_deposit_request to require a payment destination
-- ----------------------------------------------------------------------------
-- Parameter name changed from p_bank_directory_id; drop and recreate.
DROP FUNCTION IF EXISTS public.create_wallet_deposit_request(INTEGER, TEXT, UUID, TEXT, UUID);

CREATE OR REPLACE FUNCTION public.create_wallet_deposit_request(
    p_amount INTEGER,
    p_reference_number TEXT,
    p_payment_destination_id UUID,
    p_proof_storage_path TEXT DEFAULT NULL,
    p_idempotency_key UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_key UUID;
    v_request_id UUID;
    v_existing_id UUID;
    v_destination public.payment_destinations%ROWTYPE;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.' USING ERRCODE = '28000';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.profiles WHERE id = v_user_id AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'INACTIVE_PROFILE: Account is not active.' USING ERRCODE = '42501';
    END IF;

    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'INVALID_AMOUNT: Deposit amount must be positive.' USING ERRCODE = '22000';
    END IF;

    IF p_reference_number IS NULL OR length(trim(p_reference_number)) = 0 THEN
        RAISE EXCEPTION 'INVALID_REFERENCE: Reference number is required.' USING ERRCODE = '22000';
    END IF;

    IF p_payment_destination_id IS NULL THEN
        RAISE EXCEPTION 'PAYMENT_DESTINATION_REQUIRED: A payment destination is required.' USING ERRCODE = '22000';
    END IF;

    SELECT * INTO v_destination
    FROM public.payment_destinations
    WHERE id = p_payment_destination_id AND is_active = TRUE;

    IF v_destination.id IS NULL THEN
        RAISE EXCEPTION 'INVALID_PAYMENT_DESTINATION: Destination not found or inactive.' USING ERRCODE = '22000';
    END IF;

    v_key := COALESCE(p_idempotency_key, gen_random_uuid());

    SELECT id INTO v_existing_id
    FROM public.wallet_deposit_requests
    WHERE user_id = v_user_id AND idempotency_key = v_key;

    IF v_existing_id IS NOT NULL THEN
        RETURN jsonb_build_object('id', v_existing_id, 'status', 'existing');
    END IF;

    INSERT INTO public.wallet_deposit_requests (
        user_id,
        bank_directory_id,
        amount,
        currency,
        reference_number,
        proof_storage_path,
        status,
        idempotency_key,
        destination_snapshot
    ) VALUES (
        v_user_id,
        p_payment_destination_id,
        p_amount,
        'YER',
        trim(p_reference_number),
        p_proof_storage_path,
        'pending',
        v_key,
        jsonb_build_object(
            'id', v_destination.id,
            'provider_type', v_destination.provider_type,
            'display_name', v_destination.display_name,
            'account_holder_name', v_destination.account_holder_name,
            'account_identifier', v_destination.account_identifier,
            'instructions', v_destination.instructions,
            'currency', v_destination.currency
        )
    ) RETURNING id INTO v_request_id;

    RETURN jsonb_build_object('id', v_request_id, 'status', 'pending');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.create_wallet_deposit_request(INTEGER, TEXT, UUID, TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_wallet_deposit_request(INTEGER, TEXT, UUID, TEXT, UUID) TO authenticated;

-- ============================================================================
-- 2. Platform commission configuration (OD-FIN-02)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.platform_commission_config (
    id SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    default_rate NUMERIC(5,4) NOT NULL DEFAULT 0.0300,
    effective_from TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    CONSTRAINT chk_platform_commission_config_rate_range CHECK (default_rate >= 0 AND default_rate <= 1)
);

COMMENT ON TABLE public.platform_commission_config IS
    'Singleton commission configuration. Changing the default rate affects only new purchases; historical records are immutable snapshots.';

INSERT INTO public.platform_commission_config (id, default_rate, effective_from, updated_at, updated_by)
VALUES (1, 0.0300, NOW(), NOW(), NULL)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.purchase_records
    ADD COLUMN IF NOT EXISTS gross_amount INTEGER,
    ADD COLUMN IF NOT EXISTS commission_rate_snapshot NUMERIC(5,4),
    ADD COLUMN IF NOT EXISTS commission_amount INTEGER,
    ADD COLUMN IF NOT EXISTS owner_net_amount INTEGER;

-- Backfill existing purchases with the old provisional 5% rate.
UPDATE public.purchase_records
SET gross_amount = amount_paid,
    commission_rate_snapshot = 0.0500,
    commission_amount = floor(amount_paid * 0.05)::INTEGER,
    owner_net_amount = amount_paid - floor(amount_paid * 0.05)::INTEGER
WHERE gross_amount IS NULL;

ALTER TABLE public.purchase_records
    ALTER COLUMN gross_amount SET NOT NULL,
    ALTER COLUMN commission_rate_snapshot SET NOT NULL,
    ALTER COLUMN commission_amount SET NOT NULL,
    ALTER COLUMN owner_net_amount SET NOT NULL;

ALTER TABLE public.purchase_records
    DROP CONSTRAINT IF EXISTS chk_purchase_records_commission_net,
    ADD CONSTRAINT chk_purchase_records_commission_net
        CHECK (owner_net_amount = gross_amount - commission_amount);

COMMENT ON COLUMN public.purchase_records.gross_amount IS 'Gross purchase amount (immutable snapshot).';
COMMENT ON COLUMN public.purchase_records.commission_rate_snapshot IS 'Commission rate in effect at time of purchase (immutable snapshot).';
COMMENT ON COLUMN public.purchase_records.commission_amount IS 'Platform commission amount in effect at time of purchase (immutable snapshot).';
COMMENT ON COLUMN public.purchase_records.owner_net_amount IS 'Owner net amount after commission at time of purchase (immutable snapshot).';

-- Restore owner settlement items to bound 3% accounting and drop the unbound policy hold.
DROP TRIGGER IF EXISTS trg_owner_settlement_policy_hold ON public.owner_settlement_items;
DROP FUNCTION IF EXISTS public.enforce_unbound_settlement_policy();

ALTER TABLE public.owner_settlement_items
    DROP CONSTRAINT IF EXISTS chk_owner_settlement_items_amounts_positive,
    DROP CONSTRAINT IF EXISTS chk_owner_settlement_items_net,
    DROP CONSTRAINT IF EXISTS chk_owner_settlement_items_status;

ALTER TABLE public.owner_settlement_items
    ADD COLUMN IF NOT EXISTS settlement_batch_id UUID;

-- Backfill legacy settlement rows using the immutable purchase snapshot.
UPDATE public.owner_settlement_items osi
SET platform_commission_amount = COALESCE(osi.platform_commission_amount, pr.commission_amount),
    net_settlement_amount = COALESCE(osi.net_settlement_amount, pr.owner_net_amount),
    settlement_status = 'pending'
FROM public.purchase_records pr
WHERE osi.purchase_id = pr.id
  AND osi.platform_commission_amount IS NULL;

ALTER TABLE public.owner_settlement_items
    ALTER COLUMN platform_commission_amount SET NOT NULL,
    ALTER COLUMN platform_commission_amount SET DEFAULT 0,
    ALTER COLUMN net_settlement_amount SET NOT NULL,
    ALTER COLUMN settlement_status SET DEFAULT 'pending';

ALTER TABLE public.owner_settlement_items
    ADD CONSTRAINT chk_owner_settlement_items_amounts_positive
        CHECK (gross_amount >= 0 AND platform_commission_amount >= 0 AND net_settlement_amount >= 0),
    ADD CONSTRAINT chk_owner_settlement_items_net
        CHECK (net_settlement_amount = gross_amount - platform_commission_amount),
    ADD CONSTRAINT chk_owner_settlement_items_status
        CHECK (settlement_status IN ('pending', 'included', 'paid', 'disputed'));

COMMENT ON TABLE public.owner_settlement_items IS
    'Settlement-ready accounting references per purchase with immutable commission/net snapshots (OD-FIN-02 / OD-SETTLE-01).';

-- ----------------------------------------------------------------------------
-- RPC: admin_update_default_commission_rate
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_update_default_commission_rate(
    p_rate NUMERIC
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.' USING ERRCODE = '28000';
    END IF;

    IF NOT public.has_platform_role('platform_admin') THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE: Only platform_admin can change commission rate.'
            USING ERRCODE = '42501';
    END IF;

    IF p_rate IS NULL OR p_rate < 0 OR p_rate > 1 THEN
        RAISE EXCEPTION 'INVALID_RATE: Rate must be between 0 and 1.' USING ERRCODE = '22000';
    END IF;

    UPDATE public.platform_commission_config
    SET default_rate = p_rate,
        effective_from = NOW(),
        updated_at = NOW(),
        updated_by = v_user_id
    WHERE id = 1;

    RETURN jsonb_build_object('id', 1, 'default_rate', p_rate, 'updated', TRUE);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.admin_update_default_commission_rate(NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_default_commission_rate(NUMERIC) TO authenticated;


-- ============================================================================
-- 3. Secure card vault (OD-CARD-01)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.card_vault (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    network_id UUID REFERENCES public.networks(id) ON DELETE CASCADE,
    package_id UUID REFERENCES public.network_packages(id) ON DELETE CASCADE,
    batch_id TEXT,
    state TEXT CHECK (state IN ('available', 'reserved', 'sold', 'quarantined', 'invalidated')),
    ciphertext BYTEA NOT NULL,
    nonce TEXT NOT NULL,
    auth_tag TEXT,
    key_version TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    sold_at TIMESTAMPTZ,
    purchase_id UUID REFERENCES public.purchase_records(id) ON DELETE SET NULL,
    revealed_at TIMESTAMPTZ,
    first_revealed_at TIMESTAMPTZ,
    last_revealed_at TIMESTAMPTZ,
    reveal_count INTEGER NOT NULL DEFAULT 0,
    dispute_deadline TIMESTAMPTZ,
    invalidated_at TIMESTAMPTZ,
    invalidated_reason TEXT,
    CONSTRAINT chk_card_vault_state_not_null CHECK (state IS NOT NULL),
    CONSTRAINT chk_card_vault_reveal_count_non_negative CHECK (reveal_count >= 0)
);

COMMENT ON TABLE public.card_vault IS
    'Server-side encrypted card vault. Plaintext secrets are NEVER stored here; only ciphertext, nonce, auth_tag, and non-secret metadata.';

CREATE INDEX IF NOT EXISTS idx_card_vault_package_state ON public.card_vault (package_id, state);
CREATE INDEX IF NOT EXISTS idx_card_vault_purchase ON public.card_vault (purchase_id);
CREATE INDEX IF NOT EXISTS idx_card_vault_network_state ON public.card_vault (network_id, state);

ALTER TABLE public.card_vault ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.card_vault FORCE ROW LEVEL SECURITY;

-- Helper: vault empty check for tests and diagnostics (never exposes secrets).
CREATE OR REPLACE FUNCTION public.is_card_vault_empty()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN NOT EXISTS (SELECT 1 FROM public.card_vault);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.is_card_vault_empty() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_card_vault_empty() TO authenticated;

-- ----------------------------------------------------------------------------
-- RPC: admin_ingest_card_vault_batch
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_ingest_card_vault_batch(
    p_network_id UUID,
    p_package_id UUID,
    p_cards JSONB[],
    p_key_version TEXT DEFAULT 'v1-test'
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_batch_id TEXT;
    v_card JSONB;
    v_inserted INTEGER := 0;
    v_expires TIMESTAMPTZ;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.' USING ERRCODE = '28000';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.profiles WHERE id = v_user_id AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'INACTIVE_PROFILE' USING ERRCODE = '42501';
    END IF;

    IF NOT public.has_platform_role('platform_admin')
       AND NOT public.can_manage_network(p_network_id) THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE: Only platform_admin or network_owner can ingest card batches.'
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.network_packages
        WHERE id = p_package_id AND network_id = p_network_id
    ) THEN
        RAISE EXCEPTION 'INVALID_PACKAGE_REFERENCE' USING ERRCODE = '22000';
    END IF;

    IF p_cards IS NULL OR array_length(p_cards, 1) IS NULL THEN
        RAISE EXCEPTION 'INVALID_CARDS: Non-empty card array required.' USING ERRCODE = '22000';
    END IF;

    v_batch_id := 'batch-' || gen_random_uuid()::TEXT;

    FOREACH v_card IN ARRAY p_cards
    LOOP
        IF v_card->>'ciphertext' IS NULL OR length(trim(v_card->>'ciphertext')) = 0 THEN
            RAISE EXCEPTION 'INVALID_CARD: ciphertext is required.' USING ERRCODE = '22000';
        END IF;
        IF v_card->>'nonce' IS NULL OR length(trim(v_card->>'nonce')) = 0 THEN
            RAISE EXCEPTION 'INVALID_CARD: nonce is required.' USING ERRCODE = '22000';
        END IF;

        v_expires := NULLIF(v_card->>'expires_at', '')::TIMESTAMPTZ;

        INSERT INTO public.card_vault (
            network_id,
            package_id,
            batch_id,
            state,
            ciphertext,
            nonce,
            auth_tag,
            key_version,
            expires_at
        ) VALUES (
            p_network_id,
            p_package_id,
            v_batch_id,
            'available',
            decode(v_card->>'ciphertext', 'base64'),
            v_card->>'nonce',
            v_card->>'auth_tag',
            COALESCE(p_key_version, 'v1-test'),
            v_expires
        );
        v_inserted := v_inserted + 1;
    END LOOP;

    RETURN jsonb_build_object('batch_id', v_batch_id, 'ingested_count', v_inserted);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.admin_ingest_card_vault_batch(UUID, UUID, JSONB[], TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_ingest_card_vault_batch(UUID, UUID, JSONB[], TEXT) TO authenticated;

-- ----------------------------------------------------------------------------
-- RPC: admin_list_card_vault_metadata
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_list_card_vault_metadata(
    p_network_id UUID,
    p_state TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_result JSONB;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.' USING ERRCODE = '28000';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.profiles WHERE id = v_user_id AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'INACTIVE_PROFILE' USING ERRCODE = '42501';
    END IF;

    IF NOT public.has_platform_role('platform_admin')
       AND NOT public.can_manage_network(p_network_id) THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE: Only platform_admin or network_owner can list vault metadata.'
            USING ERRCODE = '42501';
    END IF;

    IF p_state IS NOT NULL AND p_state NOT IN ('available', 'reserved', 'sold', 'quarantined', 'invalidated') THEN
        RAISE EXCEPTION 'INVALID_STATE_FILTER' USING ERRCODE = '22000';
    END IF;

    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY created_at), '[]'::jsonb)
    INTO v_result
    FROM (
        SELECT
            id,
            network_id,
            package_id,
            batch_id,
            state,
            key_version,
            created_at,
            expires_at,
            sold_at,
            purchase_id,
            reveal_count
        FROM public.card_vault
        WHERE network_id = p_network_id
          AND (p_state IS NULL OR state = p_state)
    ) t;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.admin_list_card_vault_metadata(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_card_vault_metadata(UUID, TEXT) TO authenticated;

-- ============================================================================
-- 4. Secure card reveal (OD-CARD-01 / OD-CARD-02)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- RPC: reveal_purchase_card_secret
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reveal_purchase_card_secret(
    p_purchase_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_purchase public.purchase_records%ROWTYPE;
    v_card public.card_vault%ROWTYPE;
    v_now TIMESTAMPTZ := NOW();
    v_deadline TIMESTAMPTZ;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.' USING ERRCODE = '28000';
    END IF;

    SELECT * INTO v_purchase
    FROM public.purchase_records
    WHERE id = p_purchase_id;

    IF v_purchase.id IS NULL OR v_purchase.user_id != v_user_id THEN
        RAISE EXCEPTION 'NOT_FOUND: Purchase not found.' USING ERRCODE = '42501';
    END IF;

    IF v_purchase.status != 'completed' THEN
        RAISE EXCEPTION 'INVALID_STATE: Purchase is not completed.' USING ERRCODE = '22000';
    END IF;

    SELECT * INTO v_card
    FROM public.card_vault
    WHERE purchase_id = p_purchase_id
    FOR UPDATE;

    IF v_card.id IS NULL THEN
        RAISE EXCEPTION 'CARD_NOT_ASSIGNED: No card is assigned to this purchase.' USING ERRCODE = '42501';
    END IF;

    IF v_card.state != 'sold' THEN
        RAISE EXCEPTION 'INVALID_CARD_STATE: Card is not available for reveal.' USING ERRCODE = '22000';
    END IF;

    IF v_card.state IN ('quarantined', 'invalidated') THEN
        RAISE EXCEPTION 'CARD_BLOCKED: Card has been quarantined or invalidated.' USING ERRCODE = '22000';
    END IF;

    IF v_card.first_revealed_at IS NULL THEN
        v_deadline := v_now + INTERVAL '30 minutes';
        UPDATE public.card_vault
        SET first_revealed_at = v_now,
            last_revealed_at = v_now,
            revealed_at = v_now,
            dispute_deadline = v_deadline,
            reveal_count = 1
        WHERE id = v_card.id;
    ELSE
        v_deadline := v_card.dispute_deadline;
        UPDATE public.card_vault
        SET last_revealed_at = v_now,
            revealed_at = v_now,
            reveal_count = reveal_count + 1
        WHERE id = v_card.id;
    END IF;

    -- Keep the provider-neutral fulfillment boundary in sync.
    UPDATE public.card_fulfillment_records
    SET dispute_window_ends_at = v_deadline,
        status = 'fulfilled',
        fulfilled_at = COALESCE(fulfilled_at, v_now),
        updated_at = v_now
    WHERE purchase_id = p_purchase_id;

    PERFORM public.record_audit_event(
        'CARD_REVEALED',
        'card_vault',
        v_card.id::TEXT,
        'success',
        'REVEAL',
        jsonb_build_object('purchase_id', p_purchase_id, 'reveal_count', COALESCE(v_card.reveal_count, 0) + 1)
    );

    RETURN jsonb_build_object(
        'purchase_id', p_purchase_id,
        'status', 'revealed',
        'key_version', v_card.key_version,
        'ciphertext_b64', encode(v_card.ciphertext, 'base64'),
        'nonce', v_card.nonce,
        'auth_tag_b64', v_card.auth_tag
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.reveal_purchase_card_secret(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reveal_purchase_card_secret(UUID) TO authenticated;

-- ============================================================================
-- 5. Card dispute binding (OD-CARD-02)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Helper: is_card_dispute_eligible
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_card_dispute_eligible(
    p_purchase_id UUID
)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM public.card_vault cv
        JOIN public.purchase_records pr ON pr.id = cv.purchase_id
        WHERE cv.purchase_id = p_purchase_id
          AND pr.user_id = auth.uid()
          AND cv.state = 'sold'
          AND cv.first_revealed_at IS NOT NULL
          AND cv.dispute_deadline IS NOT NULL
          AND NOW() <= cv.dispute_deadline
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.is_card_dispute_eligible(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_card_dispute_eligible(UUID) TO authenticated;

-- ----------------------------------------------------------------------------
-- RPC: submit_invalid_card_dispute
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_invalid_card_dispute(
    p_purchase_id UUID,
    p_reason TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_purchase public.purchase_records%ROWTYPE;
    v_case_id UUID;
    v_number BIGINT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.' USING ERRCODE = '28000';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.profiles WHERE id = v_user_id AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'INACTIVE_PROFILE' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_purchase
    FROM public.purchase_records
    WHERE id = p_purchase_id;

    IF v_purchase.id IS NULL OR v_purchase.user_id != v_user_id THEN
        RAISE EXCEPTION 'NOT_FOUND: Purchase not found.' USING ERRCODE = '42501';
    END IF;

    IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
        RAISE EXCEPTION 'REASON_REQUIRED: Dispute reason is required.' USING ERRCODE = '22000';
    END IF;

    IF NOT public.is_card_dispute_eligible(p_purchase_id) THEN
        RAISE EXCEPTION 'DISPUTE_WINDOW_CLOSED: The 30-minute invalid-card dispute window has closed. Please open a normal support case.'
            USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.support_cases (
        case_type,
        customer_user_id,
        network_id,
        package_id,
        purchase_id,
        category,
        priority,
        subject,
        description,
        due_at
    ) VALUES (
        'dispute',
        v_user_id,
        v_purchase.network_id,
        v_purchase.package_id,
        v_purchase.id,
        'service',
        'high',
        'Invalid card dispute',
        trim(p_reason),
        NOW() + INTERVAL '12 hours'
    ) RETURNING id, case_number INTO v_case_id, v_number;

    INSERT INTO public.support_case_events (case_id, actor_user_id, event_type, to_status, metadata)
    VALUES (v_case_id, v_user_id, 'created', 'open', jsonb_build_object('purchase_id', p_purchase_id));

    PERFORM public.record_audit_event(
        'INVALID_CARD_DISPUTE_CREATED',
        'support_case',
        v_case_id::TEXT,
        'success',
        'CREATE',
        jsonb_build_object('purchase_id', p_purchase_id)
    );

    RETURN jsonb_build_object('id', v_case_id, 'case_number', v_number, 'purchase_id', p_purchase_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.submit_invalid_card_dispute(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_invalid_card_dispute(UUID, TEXT) TO authenticated;


-- ============================================================================
-- Update purchase_package to bind commission, card vault, and fulfillment
-- ============================================================================

CREATE OR REPLACE FUNCTION public.purchase_package(
    p_package_id UUID,
    p_idempotency_key UUID
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_package public.network_packages%ROWTYPE;
    v_network public.networks%ROWTYPE;
    v_balance public.wallet_accounts%ROWTYPE;
    v_inventory public.package_inventory_balances%ROWTYPE;
    v_existing_purchase public.purchase_records%ROWTYPE;
    v_ledger_id UUID;
    v_purchase_id UUID;
    v_fulfillment_id UUID;
    v_new_balance INTEGER;
    v_settlement_item_id UUID;
    v_owner_user_id UUID;
    v_commission_rate NUMERIC;
    v_commission_amount INTEGER;
    v_net_amount INTEGER;
    v_card_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.' USING ERRCODE = '28000';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.profiles WHERE id = v_user_id AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'INACTIVE_PROFILE: Account is not active.' USING ERRCODE = '42501';
    END IF;

    IF p_idempotency_key IS NULL THEN
        RAISE EXCEPTION 'MISSING_IDEMPOTENCY: Idempotency key is required.' USING ERRCODE = '22000';
    END IF;

    -- 1. Validate package and network (server-trusted price)
    SELECT * INTO v_package
    FROM public.network_packages
    WHERE id = p_package_id;

    IF v_package.id IS NULL THEN
        RAISE EXCEPTION 'NOT_FOUND: Package not found.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_network
    FROM public.networks
    WHERE id = v_package.network_id;

    IF v_network.status != 'active' OR v_network.verification_status != 'verified' THEN
        RAISE EXCEPTION 'NETWORK_UNAVAILABLE: Network is not active or verified.' USING ERRCODE = '42501';
    END IF;

    IF v_package.status != 'active' OR v_package.is_public != TRUE THEN
        RAISE EXCEPTION 'PACKAGE_UNAVAILABLE: Package is not active or public.' USING ERRCODE = '42501';
    END IF;

    IF v_package.price <= 0 THEN
        RAISE EXCEPTION 'INVALID_PRICE: Package price must be positive.' USING ERRCODE = '22000';
    END IF;

    -- 2. Idempotency: replay returns original purchase without double inventory/card consumption
    SELECT * INTO v_existing_purchase
    FROM public.purchase_records
    WHERE user_id = v_user_id AND idempotency_key = p_idempotency_key;

    IF v_existing_purchase.id IS NOT NULL THEN
        RETURN jsonb_build_object(
            'purchase_id', v_existing_purchase.id,
            'status', v_existing_purchase.status,
            'amount_paid', v_existing_purchase.amount_paid,
            'replayed', TRUE
        );
    END IF;

    -- 3. Lock wallet account and verify balance
    SELECT * INTO v_balance
    FROM public.wallet_accounts
    WHERE user_id = v_user_id
    FOR UPDATE;

    IF v_balance.user_id IS NULL THEN
        RAISE EXCEPTION 'WALLET_ACCOUNT_MISSING: Customer wallet account not found.' USING ERRCODE = '42501';
    END IF;

    IF v_balance.cached_balance < v_package.price THEN
        RAISE EXCEPTION 'INSUFFICIENT_BALANCE: Wallet balance is insufficient.' USING ERRCODE = '22000';
    END IF;

    -- 4. Lock inventory and verify stock
    SELECT * INTO v_inventory
    FROM public.package_inventory_balances
    WHERE package_id = p_package_id
    FOR UPDATE;

    IF v_inventory.package_id IS NULL THEN
        RAISE EXCEPTION 'INVENTORY_NOT_FOUND: Inventory balance not found.' USING ERRCODE = '42501';
    END IF;

    IF v_inventory.available_units <= 0 THEN
        RAISE EXCEPTION 'OUT_OF_STOCK: Package is out of stock.' USING ERRCODE = '22000';
    END IF;

    -- 5. Atomically reserve one available card from the encrypted vault
    SELECT id INTO v_card_id
    FROM public.card_vault
    WHERE package_id = p_package_id
      AND state = 'available'
      AND (expires_at IS NULL OR expires_at > NOW())
    ORDER BY created_at
    FOR UPDATE SKIP LOCKED
    LIMIT 1;

    IF v_card_id IS NULL THEN
        RAISE EXCEPTION 'OUT_OF_STOCK: No available card in vault for this package.' USING ERRCODE = '22000';
    END IF;

    -- 6. Calculate post-transaction balance and commission
    v_new_balance := v_balance.cached_balance - v_package.price;

    SELECT COALESCE(default_rate, 0.0300) INTO v_commission_rate
    FROM public.platform_commission_config
    WHERE id = 1;

    v_commission_amount := floor(v_package.price * v_commission_rate)::INTEGER;
    v_net_amount := v_package.price - v_commission_amount;

    -- 7. Insert debit ledger entry (trigger updates cached balance)
    INSERT INTO public.customer_wallet_ledger (
        user_id,
        entry_type,
        amount,
        balance_after,
        reference_type,
        reference_id,
        idempotency_key,
        actor_user_id,
        reason_code,
        metadata
    ) VALUES (
        v_user_id,
        'DEBIT',
        v_package.price,
        v_new_balance,
        'PURCHASE',
        gen_random_uuid(),
        gen_random_uuid(),
        v_user_id,
        'PACKAGE_PURCHASE',
        jsonb_build_object('package_id', p_package_id, 'network_id', v_package.network_id)
    ) RETURNING id INTO v_ledger_id;

    -- 8. Insert purchase record with immutable commission snapshot
    INSERT INTO public.purchase_records (
        user_id,
        package_id,
        network_id,
        amount_paid,
        gross_amount,
        commission_rate_snapshot,
        commission_amount,
        owner_net_amount,
        currency,
        units_purchased,
        status,
        idempotency_key,
        ledger_entry_id
    ) VALUES (
        v_user_id,
        p_package_id,
        v_package.network_id,
        v_package.price,
        v_package.price,
        v_commission_rate,
        v_commission_amount,
        v_net_amount,
        v_package.currency,
        1,
        'completed',
        p_idempotency_key,
        v_ledger_id
    ) RETURNING id INTO v_purchase_id;

    -- 9. Consume inventory atomically
    INSERT INTO public.package_inventory_movements (
        package_id,
        network_id,
        quantity_change,
        previous_total,
        new_total,
        previous_available,
        new_available,
        reason,
        actor_user_id,
        idempotency_key
    ) VALUES (
        p_package_id,
        v_package.network_id,
        -1,
        v_inventory.total_units,
        v_inventory.total_units - 1,
        v_inventory.available_units,
        v_inventory.available_units - 1,
        'Customer purchase',
        v_user_id,
        gen_random_uuid()
    );

    UPDATE public.package_inventory_balances
    SET total_units = v_inventory.total_units - 1,
        available_units = v_inventory.available_units - 1,
        is_available = (v_inventory.available_units - 1 > 0),
        updated_at = NOW()
    WHERE package_id = p_package_id;

    -- 10. Mark the reserved card as sold
    UPDATE public.card_vault
    SET state = 'sold',
        purchase_id = v_purchase_id,
        sold_at = NOW()
    WHERE id = v_card_id;

    -- 11. Create fulfilled fulfillment record (dispute window computed on reveal)
    INSERT INTO public.card_fulfillment_records (
        purchase_id,
        network_id,
        package_id,
        status,
        fulfilled_at,
        dispute_window_ends_at
    ) VALUES (
        v_purchase_id,
        v_package.network_id,
        p_package_id,
        'fulfilled',
        NOW(),
        NULL
    ) RETURNING id INTO v_fulfillment_id;

    -- 12. Settlement-ready accounting reference
    SELECT nm.user_id INTO v_owner_user_id
    FROM public.network_memberships nm
    JOIN public.user_roles ur ON ur.user_id = nm.user_id AND ur.role = 'network_owner'
    WHERE nm.network_id = v_package.network_id
      AND nm.membership_role = 'owner'
      AND nm.status = 'active'
    LIMIT 1;

    INSERT INTO public.owner_settlement_items (
        network_id,
        owner_user_id,
        purchase_id,
        gross_amount,
        platform_commission_amount,
        net_settlement_amount,
        settlement_status
    ) VALUES (
        v_package.network_id,
        COALESCE(v_owner_user_id, v_network.created_by),
        v_purchase_id,
        v_package.price,
        v_commission_amount,
        v_net_amount,
        'pending'
    ) RETURNING id INTO v_settlement_item_id;

    RETURN jsonb_build_object(
        'purchase_id', v_purchase_id,
        'fulfillment_id', v_fulfillment_id,
        'status', 'completed',
        'amount_paid', v_package.price,
        'new_balance', v_new_balance,
        'settlement_item_id', v_settlement_item_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.purchase_package(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.purchase_package(UUID, UUID) TO authenticated;


-- ============================================================================
-- 6. Weekly settlement batches (OD-SETTLE-01)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.settlement_batches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    network_id UUID REFERENCES public.networks(id) ON DELETE SET NULL,
    owner_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    gross_sales INTEGER NOT NULL DEFAULT 0,
    total_commission INTEGER NOT NULL DEFAULT 0,
    total_refunds INTEGER NOT NULL DEFAULT 0,
    total_adjustments INTEGER NOT NULL DEFAULT 0,
    net_settlement INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'ready_for_review', 'approved', 'paid', 'cancelled', 'corrected')),
    reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMPTZ,
    notes TEXT,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_settlement_batches_net
        CHECK (net_settlement = gross_sales - total_commission - total_refunds + total_adjustments),
    CONSTRAINT chk_settlement_batches_period_order CHECK (period_start <= period_end)
);

COMMENT ON TABLE public.settlement_batches IS
    'Weekly owner settlement batches with finance review/approval. No automatic bank payout is performed.';

CREATE INDEX IF NOT EXISTS idx_settlement_batches_owner_status
    ON public.settlement_batches (owner_user_id, status);
CREATE INDEX IF NOT EXISTS idx_settlement_batches_network_status
    ON public.settlement_batches (network_id, status);
CREATE INDEX IF NOT EXISTS idx_settlement_batches_period
    ON public.settlement_batches (period_start, period_end);

CREATE TRIGGER trg_settlement_batches_set_updated_at
    BEFORE UPDATE ON public.settlement_batches
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.settlement_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.settlement_batches FORCE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.settlement_batch_lines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    settlement_batch_id UUID NOT NULL REFERENCES public.settlement_batches(id) ON DELETE CASCADE,
    line_type TEXT NOT NULL CHECK (line_type IN ('sale', 'refund', 'adjustment')),
    reference_id UUID,
    gross_amount INTEGER,
    commission_amount INTEGER,
    net_amount INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.settlement_batch_lines IS
    'Immutable line items within a settlement batch: sales, refunds, and adjustments.';

CREATE INDEX IF NOT EXISTS idx_settlement_batch_lines_batch
    ON public.settlement_batch_lines (settlement_batch_id);
CREATE INDEX IF NOT EXISTS idx_settlement_batch_lines_reference
    ON public.settlement_batch_lines (line_type, reference_id);

ALTER TABLE public.settlement_batch_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.settlement_batch_lines FORCE ROW LEVEL SECURITY;

-- Add the deferred FK from owner_settlement_items now that settlement_batches exists.
ALTER TABLE public.owner_settlement_items
    ADD CONSTRAINT fk_owner_settlement_items_batch
        FOREIGN KEY (settlement_batch_id) REFERENCES public.settlement_batches(id) ON DELETE SET NULL;

-- ----------------------------------------------------------------------------
-- RPC: finance_create_settlement_batch
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.finance_create_settlement_batch(
    p_period_start DATE,
    p_period_end DATE,
    p_network_id UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_group RECORD;
    v_batch_id UUID;
    v_batch_count INTEGER := 0;
    v_total_sales INTEGER := 0;
    v_total_refunds INTEGER := 0;
    v_gross INTEGER;
    v_commission INTEGER;
    v_net INTEGER;
    v_refunds INTEGER := 0;
    v_purchase RECORD;
    v_refund RECORD;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.' USING ERRCODE = '28000';
    END IF;

    IF NOT public.is_finance_or_admin() THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE: Only finance_officer or platform_admin can create settlement batches.'
            USING ERRCODE = '42501';
    END IF;

    IF p_period_start IS NULL OR p_period_end IS NULL OR p_period_start > p_period_end THEN
        RAISE EXCEPTION 'INVALID_PERIOD: period_start must be <= period_end.' USING ERRCODE = '22000';
    END IF;

    -- Process each network/owner group that has eligible activity in the period.
    FOR v_group IN
        SELECT
            osi.network_id,
            osi.owner_user_id
        FROM public.owner_settlement_items osi
        JOIN public.purchase_records pr ON pr.id = osi.purchase_id
        WHERE osi.settlement_batch_id IS NULL
          AND osi.settlement_status = 'pending'
          AND pr.status = 'completed'
          AND pr.created_at::DATE BETWEEN p_period_start AND p_period_end
          AND (p_network_id IS NULL OR osi.network_id = p_network_id)
        GROUP BY osi.network_id, osi.owner_user_id
    LOOP
        v_gross := 0;
        v_commission := 0;
        v_net := 0;
        v_refunds := 0;

        INSERT INTO public.settlement_batches (
            period_start,
            period_end,
            network_id,
            owner_user_id,
            status,
            created_by
        ) VALUES (
            p_period_start,
            p_period_end,
            v_group.network_id,
            v_group.owner_user_id,
            'draft',
            v_user_id
        ) RETURNING id INTO v_batch_id;

        -- Sale lines
        FOR v_purchase IN
            SELECT
                osi.id AS settlement_item_id,
                pr.id AS purchase_id,
                pr.gross_amount,
                pr.commission_amount,
                pr.owner_net_amount
            FROM public.owner_settlement_items osi
            JOIN public.purchase_records pr ON pr.id = osi.purchase_id
            WHERE osi.network_id = v_group.network_id
              AND osi.owner_user_id = v_group.owner_user_id
              AND osi.settlement_batch_id IS NULL
              AND osi.settlement_status = 'pending'
              AND pr.status = 'completed'
              AND pr.created_at::DATE BETWEEN p_period_start AND p_period_end
            FOR UPDATE OF osi
        LOOP
            INSERT INTO public.settlement_batch_lines (
                settlement_batch_id,
                line_type,
                reference_id,
                gross_amount,
                commission_amount,
                net_amount
            ) VALUES (
                v_batch_id,
                'sale',
                v_purchase.purchase_id,
                v_purchase.gross_amount,
                v_purchase.commission_amount,
                v_purchase.owner_net_amount
            );

            UPDATE public.owner_settlement_items
            SET settlement_batch_id = v_batch_id,
                settlement_status = 'included',
                updated_at = NOW()
            WHERE id = v_purchase.settlement_item_id;

            v_gross := v_gross + v_purchase.gross_amount;
            v_commission := v_commission + v_purchase.commission_amount;
            v_net := v_net + v_purchase.owner_net_amount;
        END LOOP;

        -- Refund lines (approved refunds in period whose purchase is not already in another batch line)
        FOR v_refund IN
            SELECT
                rr.id AS refund_id,
                pr.id AS purchase_id,
                pr.amount_paid
            FROM public.refund_requests rr
            JOIN public.purchase_records pr ON pr.id = rr.purchase_id
            WHERE rr.status = 'approved_refund'
              AND rr.ledger_entry_id IS NOT NULL
              AND pr.network_id = v_group.network_id
              AND NOT EXISTS (
                  SELECT 1 FROM public.settlement_batch_lines sbl
                  WHERE sbl.line_type = 'refund' AND sbl.reference_id = rr.id
              )
              AND rr.updated_at::DATE BETWEEN p_period_start AND p_period_end
        LOOP
            INSERT INTO public.settlement_batch_lines (
                settlement_batch_id,
                line_type,
                reference_id,
                gross_amount,
                commission_amount,
                net_amount
            ) VALUES (
                v_batch_id,
                'refund',
                v_refund.refund_id,
                v_refund.amount_paid,
                0,
                -v_refund.amount_paid
            );

            v_refunds := v_refunds + v_refund.amount_paid;
        END LOOP;

        UPDATE public.settlement_batches
        SET gross_sales = v_gross,
            total_commission = v_commission,
            total_refunds = v_refunds,
            total_adjustments = 0,
            net_settlement = v_gross - v_commission - v_refunds + 0,
            updated_at = NOW()
        WHERE id = v_batch_id;

        v_total_sales := v_total_sales + v_gross;
        v_total_refunds := v_total_refunds + v_refunds;
        v_batch_count := v_batch_count + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'batches_created', v_batch_count,
        'total_gross_sales', v_total_sales,
        'total_refunds', v_total_refunds
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.finance_create_settlement_batch(DATE, DATE, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.finance_create_settlement_batch(DATE, DATE, UUID) TO authenticated;


-- ----------------------------------------------------------------------------
-- RPC: finance_approve_settlement_batch
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.finance_approve_settlement_batch(
    p_batch_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_batch public.settlement_batches%ROWTYPE;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.' USING ERRCODE = '28000';
    END IF;

    IF NOT public.is_finance_or_admin() THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_batch
    FROM public.settlement_batches
    WHERE id = p_batch_id
    FOR UPDATE;

    IF v_batch.id IS NULL THEN
        RAISE EXCEPTION 'NOT_FOUND: Settlement batch not found.' USING ERRCODE = '42501';
    END IF;

    IF v_batch.status NOT IN ('draft', 'ready_for_review') THEN
        RAISE EXCEPTION 'INVALID_STATE: Batch cannot be approved from status %.', v_batch.status
            USING ERRCODE = '22000';
    END IF;

    IF v_batch.created_by = v_user_id THEN
        RAISE EXCEPTION 'FORBIDDEN_SELF_APPROVAL: Cannot approve a batch you created.'
            USING ERRCODE = '42501';
    END IF;

    UPDATE public.settlement_batches
    SET status = 'approved',
        reviewed_by = v_user_id,
        reviewed_at = NOW(),
        updated_at = NOW()
    WHERE id = p_batch_id;

    RETURN jsonb_build_object('id', p_batch_id, 'status', 'approved');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.finance_approve_settlement_batch(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.finance_approve_settlement_batch(UUID) TO authenticated;

-- ----------------------------------------------------------------------------
-- RPC: finance_mark_settlement_paid
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.finance_mark_settlement_paid(
    p_batch_id UUID,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_batch public.settlement_batches%ROWTYPE;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.' USING ERRCODE = '28000';
    END IF;

    IF NOT public.is_finance_or_admin() THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_batch
    FROM public.settlement_batches
    WHERE id = p_batch_id
    FOR UPDATE;

    IF v_batch.id IS NULL THEN
        RAISE EXCEPTION 'NOT_FOUND: Settlement batch not found.' USING ERRCODE = '42501';
    END IF;

    IF v_batch.status != 'approved' THEN
        RAISE EXCEPTION 'INVALID_STATE: Batch must be approved before marking paid.' USING ERRCODE = '22000';
    END IF;

    UPDATE public.settlement_batches
    SET status = 'paid',
        notes = COALESCE(p_notes, notes),
        updated_at = NOW()
    WHERE id = p_batch_id;

    UPDATE public.owner_settlement_items
    SET settlement_status = 'paid',
        updated_at = NOW()
    WHERE settlement_batch_id = p_batch_id
      AND settlement_status = 'included';

    RETURN jsonb_build_object('id', p_batch_id, 'status', 'paid');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.finance_mark_settlement_paid(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.finance_mark_settlement_paid(UUID, TEXT) TO authenticated;

-- ----------------------------------------------------------------------------
-- RPC: get_owner_settlements
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_owner_settlements(
    p_network_id UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_result JSONB;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.' USING ERRCODE = '28000';
    END IF;

    IF NOT public.has_platform_role('network_owner') THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE: Only network_owner can view settlements.'
            USING ERRCODE = '42501';
    END IF;

    IF p_network_id IS NOT NULL AND NOT public.can_manage_network(p_network_id) THEN
        RAISE EXCEPTION 'FORBIDDEN: Not authorized to view settlements for this network.'
            USING ERRCODE = '42501';
    END IF;

    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY created_at DESC), '[]'::jsonb)
    INTO v_result
    FROM (
        SELECT
            sb.id,
            sb.period_start,
            sb.period_end,
            sb.network_id,
            sb.gross_sales,
            sb.total_commission,
            sb.total_refunds,
            sb.total_adjustments,
            sb.net_settlement,
            sb.status,
            sb.reviewed_at,
            sb.notes,
            sb.created_at,
            (
                SELECT COALESCE(jsonb_agg(row_to_json(l)), '[]'::jsonb)
                FROM public.settlement_batch_lines l
                WHERE l.settlement_batch_id = sb.id
            ) AS lines
        FROM public.settlement_batches sb
        WHERE sb.owner_user_id = v_user_id
          AND (p_network_id IS NULL OR sb.network_id = p_network_id)
    ) t;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.get_owner_settlements(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_owner_settlements(UUID) TO authenticated;

-- ----------------------------------------------------------------------------
-- RPC: get_finance_settlement_batches
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_finance_settlement_batches(
    p_status TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_result JSONB;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.' USING ERRCODE = '28000';
    END IF;

    IF NOT public.is_finance_or_admin() THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE' USING ERRCODE = '42501';
    END IF;

    IF p_status IS NOT NULL AND p_status NOT IN ('draft', 'ready_for_review', 'approved', 'paid', 'cancelled', 'corrected') THEN
        RAISE EXCEPTION 'INVALID_STATUS_FILTER' USING ERRCODE = '22000';
    END IF;

    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY created_at DESC), '[]'::jsonb)
    INTO v_result
    FROM (
        SELECT
            sb.id,
            sb.period_start,
            sb.period_end,
            sb.network_id,
            n.commercial_name AS network_name,
            sb.owner_user_id,
            p.full_name AS owner_name,
            sb.gross_sales,
            sb.total_commission,
            sb.total_refunds,
            sb.total_adjustments,
            sb.net_settlement,
            sb.status,
            sb.reviewed_by,
            sb.reviewed_at,
            sb.created_by,
            sb.notes,
            sb.created_at
        FROM public.settlement_batches sb
        LEFT JOIN public.networks n ON n.id = sb.network_id
        LEFT JOIN public.profiles p ON p.id = sb.owner_user_id
        WHERE p_status IS NULL OR sb.status = p_status
    ) t;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.get_finance_settlement_batches(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_finance_settlement_batches(TEXT) TO authenticated;


-- ============================================================================
-- 7. Row-level security policies
-- ============================================================================

-- ----------------------------------------------------------------------------
-- payment_destinations
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS bank_directory_public_select_policy ON public.payment_destinations;
DROP POLICY IF EXISTS bank_directory_admin_manage_policy ON public.payment_destinations;
DROP POLICY IF EXISTS payment_destinations_public_select_policy ON public.payment_destinations;
DROP POLICY IF EXISTS payment_destinations_admin_manage_policy ON public.payment_destinations;

CREATE POLICY payment_destinations_public_select_policy ON public.payment_destinations
    FOR SELECT
    USING (is_active = TRUE);

CREATE POLICY payment_destinations_admin_manage_policy ON public.payment_destinations
    FOR ALL
    USING (public.is_finance_or_admin())
    WITH CHECK (public.is_finance_or_admin());

-- ----------------------------------------------------------------------------
-- platform_commission_config
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS platform_commission_config_admin_select ON public.platform_commission_config;

CREATE POLICY platform_commission_config_admin_select ON public.platform_commission_config
    FOR SELECT
    USING (
        public.has_platform_role('platform_admin')
        OR public.has_platform_role('system_auditor')
    );

-- ----------------------------------------------------------------------------
-- card_vault
-- No direct client access. All access is through SECURITY DEFINER RPCs.
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS card_vault_no_direct_access ON public.card_vault;
CREATE POLICY card_vault_no_direct_access ON public.card_vault
    FOR ALL
    USING (FALSE)
    WITH CHECK (FALSE);

-- ----------------------------------------------------------------------------
-- settlement_batches
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS settlement_batches_owner_select ON public.settlement_batches;
DROP POLICY IF EXISTS settlement_batches_finance_manage ON public.settlement_batches;

CREATE POLICY settlement_batches_owner_select ON public.settlement_batches
    FOR SELECT
    USING (
        owner_user_id = auth.uid()
        OR public.is_finance_or_admin()
        OR public.has_platform_role('system_auditor')
    );

CREATE POLICY settlement_batches_finance_manage ON public.settlement_batches
    FOR ALL
    USING (public.is_finance_or_admin())
    WITH CHECK (public.is_finance_or_admin());

-- ----------------------------------------------------------------------------
-- settlement_batch_lines
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS settlement_batch_lines_owner_select ON public.settlement_batch_lines;
DROP POLICY IF EXISTS settlement_batch_lines_finance_manage ON public.settlement_batch_lines;

CREATE POLICY settlement_batch_lines_owner_select ON public.settlement_batch_lines
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.settlement_batches sb
            WHERE sb.id = settlement_batch_id
              AND (sb.owner_user_id = auth.uid()
                   OR public.is_finance_or_admin()
                   OR public.has_platform_role('system_auditor'))
        )
    );

CREATE POLICY settlement_batch_lines_finance_manage ON public.settlement_batch_lines
    FOR ALL
    USING (public.is_finance_or_admin())
    WITH CHECK (public.is_finance_or_admin());

-- ============================================================================
-- 8. Least-privilege grants
-- ============================================================================

-- payment_destinations
REVOKE ALL ON TABLE public.payment_destinations FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.payment_destinations TO anon, authenticated;

-- platform_commission_config
REVOKE ALL ON TABLE public.platform_commission_config FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.platform_commission_config TO authenticated;

-- card_vault: no direct client access
REVOKE ALL ON TABLE public.card_vault FROM PUBLIC, anon, authenticated;

-- settlement_batches / lines
REVOKE ALL ON TABLE public.settlement_batches FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.settlement_batches TO authenticated;

REVOKE ALL ON TABLE public.settlement_batch_lines FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.settlement_batch_lines TO authenticated;

-- ============================================================================
-- 9. Lock down internal functions
-- ============================================================================
REVOKE EXECUTE ON FUNCTION public.enforce_wallet_deposit_destination_not_null() FROM PUBLIC, anon, authenticated;

