-- NetYemen Card Vault — pgcrypto In-DB Encryption
-- Migration: 20260908120000_card_pgcrypto.sql
-- Task ID: CARD-PGCRYPTO
-- Scope: Bind OD-CARD-01's originally-recommended path (PostgreSQL column
--        encryption via pgcrypto, decrypted exclusively inside a
--        SECURITY DEFINER RPC) as the CHOSEN design, superseding the
--        envelope/Edge-Function alternative explored in
--        docs/CARD-ENCRYPTION-DESIGN.md (kept there as "considered, not
--        chosen"). See that document for the full reconciliation with
--        OD-CARD-01 and the CARD_SECRET security rules this migration must
--        keep satisfying.
--
-- Base schema assumed to already exist in the target database — card_vault,
-- admin_ingest_card_vault_batch, admin_list_card_vault_metadata, and
-- reveal_purchase_card_secret were created by
-- supabase/migrations/20260808210000_netyemen_v1_external_pilot_binding.sql
-- (branch kimi/NY-V1-EXTERNAL-PILOT-BINDING-001). card_vault has 0 rows in
-- every environment this has been applied to, so this migration ALTERs
-- columns directly instead of backfilling them.
--
-- ============================================================================
-- APPLY STEP — run ONCE, manually, by a human with DB access, AFTER this
-- migration file has been applied and BEFORE any card is ingested. This
-- migration does NOT create the secret itself, and no real key/passphrase
-- value is committed to this repository:
--
--   select vault.create_secret(
--     '<GENERATE-A-LONG-RANDOM-PASSPHRASE-HERE>',  -- e.g. output of `openssl rand -base64 48`
--     'card_master_key',
--     'AES passphrase for pgp_sym_encrypt/pgp_sym_decrypt on public.card_vault.ciphertext (CARD-PGCRYPTO).'
--   );
--
-- Rotating the key later: create a NEW secret under a new name, re-encrypt
-- every existing card_vault row in one transaction with
-- pgp_sym_encrypt(pgp_sym_decrypt(ciphertext, old_key), new_key), then point
-- get_card_master_key() at the new secret name. There is no per-row
-- key_version anymore (section 2 below) — pgcrypto keeps exactly one live
-- master key at a time.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================================
-- 1. Vault-backed key accessor
-- ============================================================================
-- Never GRANTed to anon/authenticated — only other SECURITY DEFINER
-- functions owned by this same role can call it, so the key value never
-- leaves the database, let alone reaches a client.
CREATE OR REPLACE FUNCTION public.get_card_master_key()
RETURNS TEXT AS $$
DECLARE
    v_key TEXT;
BEGIN
    SELECT decrypted_secret INTO v_key
    FROM vault.decrypted_secrets
    WHERE name = 'card_master_key'
    LIMIT 1;

    IF v_key IS NULL THEN
        RAISE EXCEPTION 'CARD_MASTER_KEY_NOT_CONFIGURED: Vault secret "card_master_key" is not set. Run the APPLY STEP documented in this migration file.'
            USING ERRCODE = '55000';
    END IF;

    RETURN v_key;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, vault, pg_temp;

REVOKE EXECUTE ON FUNCTION public.get_card_master_key() FROM PUBLIC, anon, authenticated;

-- ============================================================================
-- 2. card_vault — drop the now-unused envelope columns
-- ============================================================================
-- pgp_sym_encrypt/pgp_sym_decrypt self-contain their own salt/IV/MAC inside
-- the returned bytea, so a separate nonce/auth_tag pair is redundant. A
-- single live master key (see APPLY STEP) replaces per-row key_version.
ALTER TABLE public.card_vault
    DROP COLUMN IF EXISTS nonce,
    DROP COLUMN IF EXISTS auth_tag,
    DROP COLUMN IF EXISTS key_version;

COMMENT ON COLUMN public.card_vault.ciphertext IS
    'pgp_sym_encrypt(plaintext_pin, get_card_master_key()) — self-contained AES-encrypted blob; no separate nonce/auth_tag columns.';

-- ============================================================================
-- 3. RPC: admin_ingest_card_vault_batch — now accepts PLAINTEXT pins
-- ============================================================================
-- Signature changes (the TEXT key_version parameter is gone; the jsonb[]
-- element shape drops ciphertext/nonce/auth_tag in favor of a single `pin`
-- key), so the old 4-arg overload must be dropped explicitly rather than
-- replaced in place. The platform_admin / network_owner authorization check
-- is unchanged from the envelope-era version.
DROP FUNCTION IF EXISTS public.admin_ingest_card_vault_batch(UUID, UUID, JSONB[], TEXT);

CREATE OR REPLACE FUNCTION public.admin_ingest_card_vault_batch(
    p_network_id UUID,
    p_package_id UUID,
    p_cards JSONB[]
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_batch_id TEXT;
    v_card JSONB;
    v_inserted INTEGER := 0;
    v_expires TIMESTAMPTZ;
    v_master_key TEXT;
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

    -- Fail before touching any row if the vault secret isn't provisioned yet.
    v_master_key := public.get_card_master_key();
    v_batch_id := 'batch-' || gen_random_uuid()::TEXT;

    FOREACH v_card IN ARRAY p_cards
    LOOP
        IF v_card->>'pin' IS NULL OR length(trim(v_card->>'pin')) = 0 THEN
            RAISE EXCEPTION 'INVALID_CARD: pin is required.' USING ERRCODE = '22000';
        END IF;

        v_expires := NULLIF(v_card->>'expires_at', '')::TIMESTAMPTZ;

        INSERT INTO public.card_vault (
            network_id,
            package_id,
            batch_id,
            state,
            ciphertext,
            expires_at
        ) VALUES (
            p_network_id,
            p_package_id,
            v_batch_id,
            'available',
            pgp_sym_encrypt(v_card->>'pin', v_master_key),
            v_expires
        );
        v_inserted := v_inserted + 1;
    END LOOP;

    RETURN jsonb_build_object('batch_id', v_batch_id, 'ingested_count', v_inserted);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions, pg_temp;

REVOKE EXECUTE ON FUNCTION public.admin_ingest_card_vault_batch(UUID, UUID, JSONB[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_ingest_card_vault_batch(UUID, UUID, JSONB[]) TO authenticated;

-- ============================================================================
-- 4. RPC: admin_list_card_vault_metadata — drop key_version from the output
-- ============================================================================
-- Same signature as before (CREATE OR REPLACE is safe); only the SELECT
-- list changes because the key_version column no longer exists. The
-- admin/index.html list view only reads batch_id/state/created_at/
-- expires_at from this RPC, so it is unaffected.
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
-- 5. RPC: reveal_purchase_card_secret — now returns the PLAINTEXT pin
-- ============================================================================
-- Same signature as before (JSONB return type unchanged), so CREATE OR
-- REPLACE is safe. Purchaser-only authorization, purchase/card state
-- checks, dispute-deadline bookkeeping, fulfillment-record sync, and the
-- CARD_REVEALED audit event are UNCHANGED from the envelope-era version —
-- verbatim, same order except for one deliberate change: decryption now
-- happens BEFORE any state mutation or audit write. A card that cannot be
-- decrypted (corrupt row, wrong/rotated-out key) is therefore not recorded
-- as revealed and does not start its dispute-window clock — the whole
-- function call rolls back on decryption failure, which is the correct
-- behavior once decryption lives inside this transaction.
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
    v_pin TEXT;
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

    BEGIN
        v_pin := pgp_sym_decrypt(v_card.ciphertext, public.get_card_master_key());
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'DECRYPTION_FAILED: Unable to decrypt card secret.' USING ERRCODE = '22000';
    END;

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
        'card_pin', v_pin
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions, pg_temp;

REVOKE EXECUTE ON FUNCTION public.reveal_purchase_card_secret(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reveal_purchase_card_secret(UUID) TO authenticated;
