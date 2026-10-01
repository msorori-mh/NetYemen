-- Card PIN uniqueness (review finding M-2).
--
-- admin_ingest_card_vault_batch (20260908120000_card_pgcrypto.sql) stores
-- each PIN only as pgp_sym_encrypt(pin, master_key). pgcrypto randomizes the
-- ciphertext, so the same PIN ingested twice (within one batch, or in a
-- later batch) produced two distinct, indistinguishable rows: two customers
-- could buy the same hotspot login. Batches were also unbounded in size.
--
-- This migration:
--   1. adds card_vault.pin_fingerprint = hex(HMAC-SHA256(btrim(pin), K_fp)),
--      where K_fp = hex(HMAC-SHA256('netyemen:card-pin-fingerprint:v1',
--      card_master_key)). K_fp is derived from the existing Vault secret with
--      a distinct context string, so the encryption passphrase itself is
--      never used as the HMAC key, and the fingerprint is useless without
--      the Vault secret (a plain SHA-256 of a short numeric PIN would be
--      brute-forced instantly);
--   2. adds a UNIQUE index on (network_id, pin_fingerprint). The scope is
--      the network, not global: each network's PINs are logins on that
--      network's own hotspot controller, so two networks may legitimately
--      issue the same short code, and a global index would also let one
--      network owner probe whether a PIN exists in another network's vault
--      (cross-tenant oracle). Within a network the same PIN in two packages
--      is the same router login, so package scope would be too narrow.
--      NULL fingerprints (rows that could not be fingerprinted) are ignored
--      by the index;
--   3. backfills fingerprints for existing rows by decrypting them with the
--      Vault key when the key is configured. If the key is NOT configured,
--      existing rows keep pin_fingerprint NULL (reported by a WARNING);
--      admin_ingest_card_vault_batch fingerprints the network's remaining
--      NULL rows on its next run, when the key is necessarily present;
--   4. re-creates admin_ingest_card_vault_batch so that it rejects, before
--      inserting anything, a batch larger than 5000 cards (BATCH_TOO_LARGE),
--      a PIN repeated inside the batch, or a PIN already present in the
--      network's vault (DUPLICATE_CARD_PIN); the whole batch is aborted.
--      Authorization checks, input shape, return value and grants are
--      unchanged.
--
-- Rotating card_master_key (see 20260908120000_card_pgcrypto.sql) changes
-- K_fp: re-compute every pin_fingerprint in the same transaction that
-- re-encrypts the ciphertexts.

-- ----------------------------------------------------------------------------
-- 1. Column + index
-- ----------------------------------------------------------------------------
ALTER TABLE public.card_vault
    ADD COLUMN IF NOT EXISTS pin_fingerprint TEXT;

COMMENT ON COLUMN public.card_vault.pin_fingerprint IS
    'hex(HMAC-SHA256(btrim(pin), K_fp)), K_fp derived from Vault card_master_key with context netyemen:card-pin-fingerprint:v1. Unique per network; NULL only for legacy rows not yet fingerprinted.';

CREATE UNIQUE INDEX IF NOT EXISTS uq_card_vault_network_pin_fingerprint
    ON public.card_vault (network_id, pin_fingerprint);

-- ----------------------------------------------------------------------------
-- 2. Internal helpers (never callable by client roles)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._card_pin_fingerprint(
    p_pin TEXT,
    p_master_key TEXT
)
RETURNS TEXT AS $$
    SELECT encode(
        hmac(
            btrim(p_pin),
            encode(hmac('netyemen:card-pin-fingerprint:v1', p_master_key, 'sha256'), 'hex'),
            'sha256'
        ),
        'hex'
    );
$$ LANGUAGE sql IMMUTABLE STRICT SECURITY DEFINER SET search_path = public, extensions, pg_temp;

REVOKE EXECUTE ON FUNCTION public._card_pin_fingerprint(TEXT, TEXT) FROM PUBLIC, anon, authenticated;

-- Fingerprints rows that still have pin_fingerprint NULL (optionally only
-- for one network). A row that cannot be decrypted, or whose PIN collides
-- with an already-fingerprinted row of the same network, is left NULL.
-- Returns the number of rows left NULL for one of those reasons.
CREATE OR REPLACE FUNCTION public._backfill_card_pin_fingerprints(
    p_network_id UUID,
    p_master_key TEXT
)
RETURNS INTEGER AS $$
DECLARE
    v_row RECORD;
    v_skipped INTEGER := 0;
BEGIN
    FOR v_row IN
        SELECT id, ciphertext
        FROM public.card_vault
        WHERE pin_fingerprint IS NULL
          AND network_id IS NOT NULL
          AND (p_network_id IS NULL OR network_id = p_network_id)
        ORDER BY created_at, id
        FOR UPDATE
    LOOP
        BEGIN
            UPDATE public.card_vault
            SET pin_fingerprint = public._card_pin_fingerprint(
                    pgp_sym_decrypt(v_row.ciphertext, p_master_key),
                    p_master_key
                )
            WHERE id = v_row.id;
        EXCEPTION WHEN OTHERS THEN
            v_skipped := v_skipped + 1;
        END;
    END LOOP;

    RETURN v_skipped;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions, pg_temp;

REVOKE EXECUTE ON FUNCTION public._backfill_card_pin_fingerprints(UUID, TEXT) FROM PUBLIC, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 3. Backfill existing rows
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_key TEXT;
    v_pending INTEGER;
    v_skipped INTEGER;
BEGIN
    -- Block concurrent ingestion until the new function is in place.
    LOCK TABLE public.card_vault IN SHARE ROW EXCLUSIVE MODE;

    SELECT count(*) INTO v_pending FROM public.card_vault WHERE pin_fingerprint IS NULL;
    IF v_pending = 0 THEN
        RETURN;
    END IF;

    BEGIN
        SELECT decrypted_secret INTO v_key
        FROM vault.decrypted_secrets
        WHERE name = 'card_master_key'
        LIMIT 1;
    EXCEPTION WHEN undefined_table OR invalid_schema_name THEN
        v_key := NULL;
    END;

    IF v_key IS NULL THEN
        RAISE WARNING 'CARD_PIN_FINGERPRINT_BACKFILL_SKIPPED: Vault secret "card_master_key" is not configured; % existing card_vault row(s) keep pin_fingerprint NULL until the next admin_ingest_card_vault_batch call for their network.', v_pending;
        RETURN;
    END IF;

    v_skipped := public._backfill_card_pin_fingerprints(NULL, v_key);
    IF v_skipped > 0 THEN
        RAISE WARNING 'CARD_PIN_FINGERPRINT_BACKFILL_INCOMPLETE: % existing card_vault row(s) could not be decrypted or repeat the PIN of another card in the same network; they keep pin_fingerprint NULL and must be investigated.', v_skipped;
    END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- 4. RPC: admin_ingest_card_vault_batch
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_ingest_card_vault_batch(
    p_network_id UUID,
    p_package_id UUID,
    p_cards JSONB[]
)
RETURNS JSONB AS $$
DECLARE
    c_max_batch_size CONSTANT INTEGER := 5000;
    v_user_id UUID;
    v_batch_id TEXT;
    v_card JSONB;
    v_inserted INTEGER := 0;
    v_expires TIMESTAMPTZ;
    v_master_key TEXT;
    v_count INTEGER;
    v_fingerprints TEXT[];
    v_first INTEGER;
    v_second INTEGER;
    v_idx INTEGER;
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

    v_count := array_length(p_cards, 1);
    IF p_cards IS NULL OR v_count IS NULL THEN
        RAISE EXCEPTION 'INVALID_CARDS: Non-empty card array required.' USING ERRCODE = '22000';
    END IF;

    IF v_count > c_max_batch_size THEN
        RAISE EXCEPTION 'BATCH_TOO_LARGE: A batch may contain at most % cards (got %). Split the upload.',
            c_max_batch_size, v_count
            USING ERRCODE = '22000';
    END IF;

    -- Fail before touching any row if the vault secret isn't provisioned yet.
    v_master_key := public.get_card_master_key();

    -- One ingestion per network at a time, so the duplicate check below
    -- sees every committed card of this network.
    PERFORM pg_advisory_xact_lock(hashtext('public.admin_ingest_card_vault_batch:' || p_network_id::TEXT));

    -- Legacy rows created before fingerprints existed (or while the key was
    -- missing at migration time) are fingerprinted now so they are checked.
    PERFORM public._backfill_card_pin_fingerprints(p_network_id, v_master_key);

    -- Validate every card and fingerprint its PIN before inserting anything.
    IF EXISTS (
        SELECT 1 FROM unnest(p_cards) AS c(card)
        WHERE c.card->>'pin' IS NULL OR length(trim(c.card->>'pin')) = 0
    ) THEN
        RAISE EXCEPTION 'INVALID_CARD: pin is required.' USING ERRCODE = '22000';
    END IF;

    SELECT array_agg(public._card_pin_fingerprint(c.card->>'pin', v_master_key) ORDER BY c.ord)
    INTO v_fingerprints
    FROM unnest(p_cards) WITH ORDINALITY AS c(card, ord);

    SELECT min(f.ord), max(f.ord) INTO v_first, v_second
    FROM unnest(v_fingerprints) WITH ORDINALITY AS f(fp, ord)
    WHERE f.fp = (
        SELECT d.fp
        FROM unnest(v_fingerprints) WITH ORDINALITY AS d(fp, ord)
        GROUP BY d.fp
        HAVING count(*) > 1
        ORDER BY min(d.ord)
        LIMIT 1
    );
    IF v_first IS NOT NULL THEN
        RAISE EXCEPTION 'DUPLICATE_CARD_PIN: Card #% repeats the PIN of card #% in this batch. No cards were ingested.',
            v_second, v_first
            USING ERRCODE = '23505';
    END IF;

    SELECT min(f.ord) INTO v_first
    FROM unnest(v_fingerprints) WITH ORDINALITY AS f(fp, ord)
    JOIN public.card_vault cv
      ON cv.network_id = p_network_id
     AND cv.pin_fingerprint = f.fp;
    IF v_first IS NOT NULL THEN
        RAISE EXCEPTION 'DUPLICATE_CARD_PIN: Card #% has a PIN that already exists in this network''s card vault. No cards were ingested.',
            v_first
            USING ERRCODE = '23505';
    END IF;

    v_batch_id := 'batch-' || gen_random_uuid()::TEXT;

    BEGIN
        FOR v_idx IN 1 .. v_count
        LOOP
            v_card := p_cards[array_lower(p_cards, 1) + v_idx - 1];
            v_expires := NULLIF(v_card->>'expires_at', '')::TIMESTAMPTZ;

            INSERT INTO public.card_vault (
                network_id,
                package_id,
                batch_id,
                state,
                ciphertext,
                expires_at,
                pin_fingerprint
            ) VALUES (
                p_network_id,
                p_package_id,
                v_batch_id,
                'available',
                pgp_sym_encrypt(v_card->>'pin', v_master_key),
                v_expires,
                v_fingerprints[v_idx]
            );
            v_inserted := v_inserted + 1;
        END LOOP;
    EXCEPTION WHEN unique_violation THEN
        -- Backstop (uq_card_vault_network_pin_fingerprint) for a writer
        -- that inserted the same PIN without taking the advisory lock.
        RAISE EXCEPTION 'DUPLICATE_CARD_PIN: A PIN in this batch already exists in this network''s card vault. No cards were ingested.'
            USING ERRCODE = '23505';
    END;

    RETURN jsonb_build_object('batch_id', v_batch_id, 'ingested_count', v_inserted);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions, pg_temp;

REVOKE EXECUTE ON FUNCTION public.admin_ingest_card_vault_batch(UUID, UUID, JSONB[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_ingest_card_vault_batch(UUID, UUID, JSONB[]) TO authenticated;
