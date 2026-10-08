-- Purchase, card ingest and commission configuration integrity.
--
--  * purchase_package takes the price the customer confirmed and refuses to
--    charge a different one (PRICE_CHANGED); enforces the wallet status
--    (WALLET_FROZEN); serializes concurrent calls with the same idempotency
--    key; and rejects a key reused for a different package.
--  * Card ingest is idempotent per batch key and never stores the same card
--    twice for a network (a retried upload used to sell one card to two
--    customers).
--  * The commission rate is readable through an RPC so consoles can show the
--    current value before changing it, and every change is audited.

-- purchase_package ---------------------------------------------------------
DROP FUNCTION IF EXISTS public.purchase_package(UUID, UUID);

CREATE OR REPLACE FUNCTION public.purchase_package(p_package_id uuid, p_idempotency_key uuid, p_expected_price integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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

    -- 2. Idempotency: replay returns original purchase without double inventory/card consumption.
    -- Two concurrent calls with the same key serialize here, so the second one
    -- sees the first purchase and replays instead of failing on the unique index.
    PERFORM pg_advisory_xact_lock(
        hashtextextended('netyemen.purchase:' || v_user_id::TEXT || ':' || p_idempotency_key::TEXT, 0)
    );

    SELECT * INTO v_existing_purchase
    FROM public.purchase_records
    WHERE user_id = v_user_id AND idempotency_key = p_idempotency_key;

    IF v_existing_purchase.id IS NOT NULL THEN
        IF v_existing_purchase.package_id IS DISTINCT FROM p_package_id THEN
            RAISE EXCEPTION 'IDEMPOTENCY_KEY_REUSED: This key was already used for another package.'
                USING ERRCODE = '22000';
        END IF;
        RETURN jsonb_build_object(
            'purchase_id', v_existing_purchase.id,
            'status', v_existing_purchase.status,
            'amount_paid', v_existing_purchase.amount_paid,
            'replayed', TRUE
        );
    END IF;

    -- The customer confirmed a specific price; never charge a different one.
    IF p_expected_price IS NOT NULL AND p_expected_price <> v_package.price THEN
        RAISE EXCEPTION 'PRICE_CHANGED: The package price changed from % to %.', p_expected_price, v_package.price
            USING ERRCODE = '22000';
    END IF;

    -- 3. Lock wallet account and verify balance
    SELECT * INTO v_balance
    FROM public.wallet_accounts
    WHERE user_id = v_user_id
    FOR UPDATE;

    IF v_balance.user_id IS NULL THEN
        RAISE EXCEPTION 'WALLET_ACCOUNT_MISSING: Customer wallet account not found.' USING ERRCODE = '42501';
    END IF;

    IF v_balance.account_status <> 'active' THEN
        RAISE EXCEPTION 'WALLET_FROZEN: Wallet is not active.' USING ERRCODE = '42501';
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
$function$;

REVOKE EXECUTE ON FUNCTION public.purchase_package(UUID, UUID, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.purchase_package(UUID, UUID, INTEGER) TO authenticated;

-- Wallet freeze control ----------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_set_wallet_status(
    p_user_id UUID,
    p_status TEXT,
    p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_previous TEXT;
    v_reason TEXT := NULLIF(trim(COALESCE(p_reason, '')), '');
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.' USING ERRCODE = '28000';
    END IF;
    IF NOT public.is_finance_or_admin() THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE: Only finance_officer or platform_admin can change a wallet status.'
            USING ERRCODE = '42501';
    END IF;
    IF p_status NOT IN ('active', 'frozen') THEN
        RAISE EXCEPTION 'INVALID_STATUS: Wallet status must be active or frozen.' USING ERRCODE = '22000';
    END IF;
    IF v_reason IS NULL OR char_length(v_reason) > 500 THEN
        RAISE EXCEPTION 'REASON_REQUIRED: A reason of at most 500 characters is required.' USING ERRCODE = '22000';
    END IF;
    IF p_user_id = v_actor THEN
        RAISE EXCEPTION 'SELF_CHANGE_FORBIDDEN: Staff cannot change their own wallet status.' USING ERRCODE = '42501';
    END IF;

    SELECT account_status INTO v_previous
    FROM public.wallet_accounts
    WHERE user_id = p_user_id
    FOR UPDATE;

    IF v_previous IS NULL THEN
        RAISE EXCEPTION 'NOT_FOUND: Wallet account not found.' USING ERRCODE = '42501';
    END IF;
    IF v_previous = 'closed' THEN
        RAISE EXCEPTION 'INVALID_STATE: A closed wallet cannot be reopened.' USING ERRCODE = '22000';
    END IF;

    UPDATE public.wallet_accounts
    SET account_status = p_status,
        updated_at = NOW()
    WHERE user_id = p_user_id;

    PERFORM public.record_audit_event(
        'ADMIN_SET_WALLET_STATUS', 'wallet_account', p_user_id::TEXT, 'success', 'FINANCE_CONTROL',
        jsonb_build_object('previous_status', v_previous, 'new_status', p_status, 'reason', v_reason)
    );

    RETURN jsonb_build_object('user_id', p_user_id, 'previous_status', v_previous, 'status', p_status);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_set_wallet_status(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_wallet_status(UUID, TEXT, TEXT) TO authenticated;

-- Card ingest --------------------------------------------------------------
-- Keyed fingerprint of the card PIN: lets the database refuse a duplicate
-- without being able to read the PIN. It is an HMAC under a key derived from
-- the vault master key, so it is useless without that key.
ALTER TABLE public.card_vault ADD COLUMN IF NOT EXISTS pin_fingerprint BYTEA;
COMMENT ON COLUMN public.card_vault.pin_fingerprint IS
    'HMAC-SHA256 of the trimmed PIN under a key derived from the vault master key. '
    'NULL only for legacy rows that could not be fingerprinted.';

CREATE OR REPLACE FUNCTION public.card_pin_fingerprint(p_pin TEXT, p_master_key TEXT)
RETURNS BYTEA
LANGUAGE sql
IMMUTABLE
SET search_path = public, extensions, pg_temp
AS $$
    SELECT hmac(convert_to(trim(p_pin), 'UTF8'), convert_to('card-fingerprint-v1:' || p_master_key, 'UTF8'), 'sha256');
$$;
REVOKE EXECUTE ON FUNCTION public.card_pin_fingerprint(TEXT, TEXT) FROM PUBLIC, anon, authenticated;

-- Fingerprint the cards that already exist. Within a network only the oldest
-- copy of a PIN gets the fingerprint, so the unique index below can always be
-- built; later copies are reported so an operator can quarantine them.
DO $$
DECLARE
    v_key TEXT;
    v_done INTEGER := 0;
    v_duplicates INTEGER := 0;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.card_vault WHERE pin_fingerprint IS NULL) THEN
        RETURN;
    END IF;
    BEGIN
        v_key := public.get_card_master_key();
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'card_vault fingerprint backfill skipped: card master key is not available (%).', SQLERRM;
        RETURN;
    END;

    WITH decrypted AS (
        SELECT id, network_id, created_at,
               public.card_pin_fingerprint(pgp_sym_decrypt(ciphertext, v_key), v_key) AS fp
        FROM public.card_vault
        WHERE pin_fingerprint IS NULL
    ), ranked AS (
        SELECT id, fp, row_number() OVER (PARTITION BY network_id, fp ORDER BY created_at, id) AS rn
        FROM decrypted
    ), updated AS (
        UPDATE public.card_vault cv
        SET pin_fingerprint = r.fp
        FROM ranked r
        WHERE r.id = cv.id AND r.rn = 1
        RETURNING cv.id
    )
    SELECT (SELECT count(*) FROM updated), (SELECT count(*) FROM ranked WHERE rn > 1)
    INTO v_done, v_duplicates;

    RAISE NOTICE 'card_vault fingerprint backfill: % card(s) fingerprinted, % duplicate card(s) left without one.',
        v_done, v_duplicates;
    IF v_duplicates > 0 THEN
        RAISE WARNING 'card_vault holds % duplicate card(s) from before this migration; review rows with pin_fingerprint IS NULL.',
            v_duplicates;
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'card_vault fingerprint backfill failed and was skipped: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;

CREATE UNIQUE INDEX IF NOT EXISTS idx_card_vault_network_pin_fingerprint
    ON public.card_vault (network_id, pin_fingerprint)
    WHERE pin_fingerprint IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.card_vault_ingest_batches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    batch_key UUID NOT NULL,
    network_id UUID NOT NULL REFERENCES public.networks(id) ON DELETE CASCADE,
    package_id UUID NOT NULL REFERENCES public.network_packages(id) ON DELETE CASCADE,
    result JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_card_vault_ingest_batches_actor_key UNIQUE (actor_user_id, batch_key)
);
ALTER TABLE public.card_vault_ingest_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.card_vault_ingest_batches FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.card_vault_ingest_batches FROM PUBLIC, anon, authenticated;
COMMENT ON TABLE public.card_vault_ingest_batches IS
    'Idempotency record of card uploads. RPC-only: no client role has any privilege.';

DROP FUNCTION IF EXISTS public.admin_ingest_card_vault_batch(UUID, UUID, JSONB[]);

CREATE OR REPLACE FUNCTION public.admin_ingest_card_vault_batch(
    p_network_id UUID,
    p_package_id UUID,
    p_cards JSONB[],
    p_batch_key UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_user_id UUID;
    v_batch_id TEXT;
    v_card JSONB;
    v_pin TEXT;
    v_inserted INTEGER := 0;
    v_duplicates INTEGER := 0;
    v_rows INTEGER;
    v_expires TIMESTAMPTZ;
    v_master_key TEXT;
    v_previous public.card_vault_ingest_batches%ROWTYPE;
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

    IF array_length(p_cards, 1) > 5000 THEN
        RAISE EXCEPTION 'TOO_MANY_CARDS: At most 5000 cards per batch.' USING ERRCODE = '22000';
    END IF;

    -- A retried upload (timeout, double tap) returns the first result.
    IF p_batch_key IS NOT NULL THEN
        PERFORM pg_advisory_xact_lock(
            hashtextextended('netyemen.card_ingest:' || v_user_id::TEXT || ':' || p_batch_key::TEXT, 0)
        );
        SELECT * INTO v_previous
        FROM public.card_vault_ingest_batches
        WHERE actor_user_id = v_user_id AND batch_key = p_batch_key;
        IF v_previous.id IS NOT NULL THEN
            IF v_previous.network_id <> p_network_id OR v_previous.package_id <> p_package_id THEN
                RAISE EXCEPTION 'BATCH_KEY_REUSED: This batch key was already used for another package.'
                    USING ERRCODE = '22000';
            END IF;
            RETURN v_previous.result || jsonb_build_object('replayed', TRUE);
        END IF;
    END IF;

    -- Fail before touching any row if the vault secret isn't provisioned yet.
    v_master_key := public.get_card_master_key();
    v_batch_id := 'batch-' || gen_random_uuid()::TEXT;

    FOREACH v_card IN ARRAY p_cards
    LOOP
        v_pin := trim(COALESCE(v_card->>'pin', ''));
        IF length(v_pin) = 0 THEN
            RAISE EXCEPTION 'INVALID_CARD: pin is required.' USING ERRCODE = '22000';
        END IF;
        IF char_length(v_pin) > 64 OR v_pin ~ '[[:space:][:cntrl:]]' THEN
            RAISE EXCEPTION 'INVALID_CARD: pin must be at most 64 characters without spaces or control characters.'
                USING ERRCODE = '22000';
        END IF;

        v_expires := NULLIF(v_card->>'expires_at', '')::TIMESTAMPTZ;

        INSERT INTO public.card_vault (
            network_id, package_id, batch_id, state, ciphertext, expires_at, pin_fingerprint
        ) VALUES (
            p_network_id, p_package_id, v_batch_id, 'available',
            pgp_sym_encrypt(v_pin, v_master_key),
            v_expires,
            public.card_pin_fingerprint(v_pin, v_master_key)
        )
        ON CONFLICT (network_id, pin_fingerprint) WHERE pin_fingerprint IS NOT NULL DO NOTHING;
        GET DIAGNOSTICS v_rows = ROW_COUNT;

        IF v_rows = 1 THEN
            v_inserted := v_inserted + 1;
        ELSE
            v_duplicates := v_duplicates + 1;
        END IF;
    END LOOP;

    v_result := jsonb_build_object(
        'batch_id', v_batch_id,
        'ingested_count', v_inserted,
        'duplicates_skipped', v_duplicates,
        'replayed', FALSE
    );

    IF p_batch_key IS NOT NULL THEN
        INSERT INTO public.card_vault_ingest_batches (actor_user_id, batch_key, network_id, package_id, result)
        VALUES (v_user_id, p_batch_key, p_network_id, p_package_id, v_result);
    END IF;

    -- Counts only: the audit log never sees a PIN.
    PERFORM public.record_audit_event(
        'CARD_BATCH_INGESTED', 'card_vault_batch', v_batch_id, 'success', 'CARD_INVENTORY',
        jsonb_build_object(
            'network_id', p_network_id,
            'package_id', p_package_id,
            'ingested_count', v_inserted,
            'duplicates_skipped', v_duplicates
        )
    );

    RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_ingest_card_vault_batch(UUID, UUID, JSONB[], UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_ingest_card_vault_batch(UUID, UUID, JSONB[], UUID) TO authenticated;

-- Commission configuration -------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_platform_commission_config()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_config public.platform_commission_config%ROWTYPE;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.' USING ERRCODE = '28000';
    END IF;
    IF NOT public.is_finance_or_admin() THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE: Only finance_officer or platform_admin can read the commission configuration.'
            USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_config FROM public.platform_commission_config WHERE id = 1;
    IF v_config.id IS NULL THEN
        RAISE EXCEPTION 'NOT_FOUND: Commission configuration is missing.' USING ERRCODE = 'P0002';
    END IF;

    -- default_rate is a FRACTION between 0 and 1 (0.03 = 3%).
    RETURN jsonb_build_object(
        'default_rate', v_config.default_rate,
        'effective_from', v_config.effective_from,
        'updated_at', v_config.updated_at
    );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_platform_commission_config() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_platform_commission_config() TO authenticated;

COMMENT ON FUNCTION public.admin_update_default_commission_rate(NUMERIC) IS
    'p_rate is a FRACTION between 0 and 1 (0.03 = 3%), never a percentage.';

-- Every change to the money-routing configuration leaves an audit event,
-- whichever function or role made it.
CREATE OR REPLACE FUNCTION public.audit_finance_configuration_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_id TEXT;
BEGIN
    IF TG_OP = 'UPDATE' AND to_jsonb(NEW) - 'updated_at' = to_jsonb(OLD) - 'updated_at' THEN
        RETURN NEW;
    END IF;

    v_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.id::TEXT ELSE NEW.id::TEXT END;

    PERFORM public.record_audit_event(
        upper(TG_TABLE_NAME) || '_' || TG_OP,
        TG_TABLE_NAME,
        v_id,
        'success',
        'FINANCE_CONFIGURATION',
        jsonb_build_object(
            'before', CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE to_jsonb(OLD) END,
            'after', CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE to_jsonb(NEW) END
        )
    );

    RETURN COALESCE(NEW, OLD);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.audit_finance_configuration_change() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_payment_destinations_audit ON public.payment_destinations;
CREATE TRIGGER trg_payment_destinations_audit
    AFTER INSERT OR UPDATE OR DELETE ON public.payment_destinations
    FOR EACH ROW EXECUTE FUNCTION public.audit_finance_configuration_change();

DROP TRIGGER IF EXISTS trg_platform_commission_config_audit ON public.platform_commission_config;
CREATE TRIGGER trg_platform_commission_config_audit
    AFTER INSERT OR UPDATE OR DELETE ON public.platform_commission_config
    FOR EACH ROW EXECUTE FUNCTION public.audit_finance_configuration_change();
