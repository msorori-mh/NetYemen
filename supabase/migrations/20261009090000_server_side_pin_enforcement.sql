-- Server-side enforcement of the account PIN.
--
-- Before: the 6-digit PIN was a client-side gate only (pin_gate plus a
-- "trusted device" flag in local storage). A stolen or replayed session could
-- buy packages, reveal card PINs and issue WASEL One credentials without ever
-- knowing the account PIN.
--
-- Now: a successful verify_account_pin() (or the first enrollment through
-- set_account_pin()) records a verification for the caller's auth session
-- (JWT claim `session_id`). The four RPCs that spend wallet money or return a
-- secret call require_recent_account_pin(), which raises
--   PIN_NOT_SET   the account has no PIN enrolled yet;
--   PIN_REQUIRED  this session has not verified the PIN within the window
--                 (account_pin_verification_window(), 15 minutes).
-- The client answers either one by asking for the PIN, then retrying.
-- An admin-approved PIN reset deletes the account_pins row, which drops every
-- recorded verification of that user (trigger below).

-- ---------------------------------------------------------------------------
-- 1. Verification records (RPC-only, like account_pins).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.account_pin_verifications (
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_key text NOT NULL,
  verified_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, session_key)
);

ALTER TABLE public.account_pin_verifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_pin_verifications FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Helpers.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.account_pin_verification_window()
RETURNS interval
LANGUAGE sql IMMUTABLE
SET search_path = pg_catalog
AS $$ SELECT interval '15 minutes' $$;

-- The auth session of the caller. Every Supabase user JWT carries
-- `session_id`; it changes on every sign-in, so a verification never outlives
-- the session it was made in.
CREATE OR REPLACE FUNCTION public._auth_session_key()
RETURNS text
LANGUAGE sql STABLE
SET search_path = public, pg_temp
AS $$ SELECT COALESCE(NULLIF(auth.jwt() ->> 'session_id', ''), '') $$;

CREATE OR REPLACE FUNCTION public._record_account_pin_verification(p_user uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO public.account_pin_verifications (user_id, session_key, verified_at)
  VALUES (p_user, public._auth_session_key(), now())
  ON CONFLICT (user_id, session_key) DO UPDATE SET verified_at = EXCLUDED.verified_at;

  -- Housekeeping: old sessions of the same user.
  DELETE FROM public.account_pin_verifications
  WHERE user_id = p_user AND verified_at < now() - interval '1 day';
END;
$$;

-- Raises unless the caller verified the PIN in this session recently.
CREATE OR REPLACE FUNCTION public.require_recent_account_pin()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.' USING ERRCODE = '28000';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.account_pins WHERE user_id = v_user) THEN
    RAISE EXCEPTION 'PIN_NOT_SET: Set an account PIN before this operation.'
      USING ERRCODE = 'PLK02';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.account_pin_verifications
    WHERE user_id = v_user
      AND session_key = public._auth_session_key()
      AND verified_at > now() - public.account_pin_verification_window()
  ) THEN
    RAISE EXCEPTION 'PIN_REQUIRED: Enter the account PIN to continue.'
      USING ERRCODE = 'PLK02';
  END IF;
END;
$$;

-- What the client asks before a protected operation, so it can prompt for the
-- PIN up front instead of failing the operation first.
CREATE OR REPLACE FUNCTION public.get_account_pin_verification()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_verified_at timestamptz;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.' USING ERRCODE = '28000';
  END IF;

  SELECT verified_at INTO v_verified_at
  FROM public.account_pin_verifications
  WHERE user_id = v_user AND session_key = public._auth_session_key();

  RETURN jsonb_build_object(
    'has_pin', EXISTS (SELECT 1 FROM public.account_pins WHERE user_id = v_user),
    'verified', v_verified_at IS NOT NULL
                AND v_verified_at > now() - public.account_pin_verification_window(),
    'verified_until', CASE WHEN v_verified_at IS NULL THEN NULL
                           ELSE v_verified_at + public.account_pin_verification_window() END
  );
END;
$$;

-- A PIN reset (row deleted) invalidates every open verification of the user.
CREATE OR REPLACE FUNCTION public._account_pin_deleted_drop_verifications()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  DELETE FROM public.account_pin_verifications WHERE user_id = OLD.user_id;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS account_pins_drop_verifications ON public.account_pins;
CREATE TRIGGER account_pins_drop_verifications
  AFTER DELETE ON public.account_pins
  FOR EACH ROW EXECUTE FUNCTION public._account_pin_deleted_drop_verifications();

-- ---------------------------------------------------------------------------
-- 3. Verification and enrollment record the session.
-- ---------------------------------------------------------------------------

-- verify_account_pin: from 20260913100000_account_pins.sql; a successful check now opens a
-- verification window for the caller's auth session.
CREATE OR REPLACE FUNCTION public.verify_account_pin(p_pin text)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_row public.account_pins%ROWTYPE;
  v_ok boolean;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING errcode = '28000';
  END IF;

  SELECT * INTO v_row FROM public.account_pins WHERE user_id = v_user FOR UPDATE;
  IF v_row.user_id IS NULL THEN
    RAISE EXCEPTION 'PIN_NOT_SET';
  END IF;

  -- Custom (non-standard) SQLSTATE: only used so this condition is
  -- distinguishable in DB-side logs/tooling. The frontend keys off the
  -- message text 'PIN_LOCKED' itself, same as every other RPC in this repo.
  IF v_row.locked_until IS NOT NULL AND v_row.locked_until > now() THEN
    RAISE EXCEPTION 'PIN_LOCKED' USING errcode = 'PLK01';
  END IF;

  v_ok := (crypt(p_pin, v_row.pin_hash) = v_row.pin_hash);

  IF v_ok THEN
    UPDATE public.account_pins
    SET failed_attempts = 0, locked_until = NULL, updated_at = now()
    WHERE user_id = v_user;
    PERFORM public._record_account_pin_verification(v_user);
  ELSIF v_row.failed_attempts + 1 >= 5 THEN
    UPDATE public.account_pins
    SET failed_attempts = 0, locked_until = now() + interval '15 minutes', updated_at = now()
    WHERE user_id = v_user;
  ELSE
    UPDATE public.account_pins
    SET failed_attempts = failed_attempts + 1, updated_at = now()
    WHERE user_id = v_user;
  END IF;

  RETURN v_ok;
END;
$$;

-- set_account_pin: from 20261008092000_identity_role_audit_hardening.sql; enrollment also opens the window.
CREATE OR REPLACE FUNCTION public.set_account_pin(p_pin text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING errcode = '28000';
  END IF;

  IF p_pin IS NULL OR p_pin !~ '^[0-9]{6}$' THEN
    RAISE EXCEPTION 'INVALID_PIN';
  END IF;

  IF EXISTS (SELECT 1 FROM public.account_pins WHERE user_id = v_user) THEN
    RAISE EXCEPTION 'PIN_ALREADY_SET';
  END IF;

  INSERT INTO public.account_pins (user_id, pin_hash)
  VALUES (v_user, crypt(p_pin, gen_salt('bf', 10)));

  -- Enrolling proves knowledge of the PIN for this session.
  PERFORM public._record_account_pin_verification(v_user);
END;
$function$;

-- ---------------------------------------------------------------------------
-- 4. The money/secret RPCs require a recent PIN verification.
-- ---------------------------------------------------------------------------

-- purchase_package: final definition from 20261008091000_purchase_card_ingest_commission_integrity.sql, unchanged except for the PIN check.
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

    -- Server-side PIN (20261009090000): the caller must have verified the
    -- account PIN in this auth session within the verification window.
    PERFORM public.require_recent_account_pin();

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

-- purchase_federated_access_plan: final definition from 20261007060000_wasel_one_plan_purchase.sql, unchanged except for the PIN check.
CREATE OR REPLACE FUNCTION public.purchase_federated_access_plan(
    p_plan_id UUID,
    p_idempotency_key UUID
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_plan public.federated_access_plans%ROWTYPE;
    v_wallet public.wallet_accounts%ROWTYPE;
    v_existing public.federated_access_purchases%ROWTYPE;
    v_purchase_id UUID := gen_random_uuid();
    v_entitlement_id UUID := gen_random_uuid();
    v_ledger_id UUID;
    v_starts_at TIMESTAMPTZ := NOW();
    v_expires_at TIMESTAMPTZ;
    v_new_balance INTEGER;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    -- Server-side PIN (20261009090000): the caller must have verified the
    -- account PIN in this auth session within the verification window.
    PERFORM public.require_recent_account_pin();

    IF p_idempotency_key IS NULL THEN
        RAISE EXCEPTION 'MISSING_IDEMPOTENCY: Idempotency key is required.'
            USING ERRCODE = '22000';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = v_user_id AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'INACTIVE_PROFILE: Account is not active.'
            USING ERRCODE = '42501';
    END IF;

    -- Serialize retries with the same customer/key before checking replay state.
    PERFORM pg_advisory_xact_lock(
        hashtextextended(v_user_id::TEXT || ':' || p_idempotency_key::TEXT, 0)
    );

    SELECT * INTO v_existing
    FROM public.federated_access_purchases
    WHERE user_id = v_user_id AND idempotency_key = p_idempotency_key;

    IF v_existing.id IS NOT NULL THEN
        RETURN jsonb_build_object(
            'purchase_id', v_existing.id,
            'entitlement_id', v_existing.entitlement_id,
            'status', v_existing.status,
            'amount_paid', v_existing.amount_paid,
            'currency', v_existing.currency,
            'new_balance', (
                SELECT balance_after FROM public.customer_wallet_ledger
                WHERE id = v_existing.ledger_entry_id
            ),
            'replayed', TRUE
        );
    END IF;

    SELECT * INTO v_plan
    FROM public.federated_access_plans
    WHERE id = p_plan_id;

    IF v_plan.id IS NULL
       OR v_plan.status <> 'active'
       OR NOT v_plan.is_public THEN
        RAISE EXCEPTION 'PLAN_UNAVAILABLE: WASEL One plan is not available.'
            USING ERRCODE = '42501';
    END IF;

    IF v_plan.retail_price <= 0 OR v_plan.currency <> 'YER' THEN
        RAISE EXCEPTION 'INVALID_PLAN_PRICE: Purchasable plan price is invalid.'
            USING ERRCODE = '22000';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.federated_plan_networks pn
        JOIN public.networks n ON n.id = pn.network_id
        WHERE pn.plan_id = v_plan.id
          AND pn.is_active
          AND pn.effective_from <= NOW()
          AND (pn.effective_until IS NULL OR pn.effective_until > NOW())
          AND n.status = 'active'
          AND n.verification_status = 'verified'
    ) THEN
        RAISE EXCEPTION 'PLAN_HAS_NO_ACTIVE_NETWORKS: Plan has no active partner networks.'
            USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_wallet
    FROM public.wallet_accounts
    WHERE user_id = v_user_id
    FOR UPDATE;

    IF v_wallet.user_id IS NULL OR v_wallet.account_status <> 'active' THEN
        RAISE EXCEPTION 'WALLET_UNAVAILABLE: Customer wallet is not active.'
            USING ERRCODE = '42501';
    END IF;

    IF v_wallet.currency <> v_plan.currency THEN
        RAISE EXCEPTION 'CURRENCY_MISMATCH: Wallet and plan currencies differ.'
            USING ERRCODE = '22000';
    END IF;

    IF v_wallet.cached_balance < v_plan.retail_price THEN
        RAISE EXCEPTION 'INSUFFICIENT_BALANCE: Wallet balance is insufficient.'
            USING ERRCODE = '22000';
    END IF;

    v_new_balance := v_wallet.cached_balance - v_plan.retail_price;
    v_expires_at := v_starts_at + make_interval(secs => v_plan.validity_seconds);

    INSERT INTO public.customer_wallet_ledger (
        user_id, entry_type, amount, balance_after, reference_type,
        reference_id, idempotency_key, actor_user_id, reason_code, metadata
    ) VALUES (
        v_user_id, 'DEBIT', v_plan.retail_price, v_new_balance, 'PURCHASE',
        v_purchase_id, p_idempotency_key, v_user_id, 'WASEL_ONE_PURCHASE',
        jsonb_build_object('plan_id', v_plan.id, 'purchase_id', v_purchase_id)
    ) RETURNING id INTO v_ledger_id;

    INSERT INTO public.access_entitlements (
        id, user_id, plan_id, status, starts_at, expires_at,
        allowance_bytes, consumed_bytes, speed_limit_kbps,
        max_concurrent_sessions, source_type, source_id, idempotency_key
    ) VALUES (
        v_entitlement_id, v_user_id, v_plan.id, 'active', v_starts_at, v_expires_at,
        v_plan.quota_bytes, 0, v_plan.speed_limit_kbps,
        v_plan.max_concurrent_sessions, 'purchase', v_purchase_id, p_idempotency_key
    );

    INSERT INTO public.federated_access_purchases (
        id, user_id, plan_id, entitlement_id, amount_paid,
        currency, status, idempotency_key, ledger_entry_id
    ) VALUES (
        v_purchase_id, v_user_id, v_plan.id, v_entitlement_id,
        v_plan.retail_price, v_plan.currency, 'completed',
        p_idempotency_key, v_ledger_id
    );

    RETURN jsonb_build_object(
        'purchase_id', v_purchase_id,
        'entitlement_id', v_entitlement_id,
        'status', 'completed',
        'amount_paid', v_plan.retail_price,
        'currency', v_plan.currency,
        'new_balance', v_new_balance,
        'starts_at', v_starts_at,
        'expires_at', v_expires_at,
        'replayed', FALSE
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- reveal_purchase_card_secret: final definition from 20260908120000_card_pgcrypto.sql, unchanged except for the PIN check.
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

    -- Server-side PIN (20261009090000): the caller must have verified the
    -- account PIN in this auth session within the verification window.
    PERFORM public.require_recent_account_pin();

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

-- issue_radius_access_credential: final definition from 20261008093000_wasel_one_accounting_hardening.sql, unchanged except for the PIN check.
CREATE OR REPLACE FUNCTION public.issue_radius_access_credential(p_entitlement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
    v_user_id UUID := auth.uid();
    v_entitlement public.access_entitlements%ROWTYPE;
    v_username TEXT;
    v_password TEXT;
    v_expires_at TIMESTAMPTZ;
    v_credential_id UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = '28000';
    END IF;

    -- Server-side PIN (20261009090000): the caller must have verified the
    -- account PIN in this auth session within the verification window.
    PERFORM public.require_recent_account_pin();
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles WHERE id = v_user_id AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'INACTIVE_PROFILE: Account is not active.' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_entitlement FROM public.access_entitlements
    WHERE id = p_entitlement_id AND user_id = v_user_id FOR UPDATE;
    IF v_entitlement.id IS NULL THEN
        RAISE EXCEPTION 'ENTITLEMENT_NOT_FOUND' USING ERRCODE = '42501';
    END IF;
    IF v_entitlement.status <> 'active' OR v_entitlement.starts_at > NOW()
       OR v_entitlement.expires_at <= NOW()
       OR (v_entitlement.allowance_bytes IS NOT NULL
           AND v_entitlement.consumed_bytes >= v_entitlement.allowance_bytes) THEN
        RAISE EXCEPTION 'ENTITLEMENT_NOT_ACTIVE' USING ERRCODE = '42501';
    END IF;

    UPDATE public.radius_access_credentials SET status = 'revoked', updated_at = NOW()
    WHERE entitlement_id = p_entitlement_id AND status = 'active';
    v_username := 'w1-' || substr(encode(gen_random_bytes(16), 'hex'), 1, 24);
    v_password := encode(gen_random_bytes(18), 'base64');
    v_expires_at := LEAST(v_entitlement.expires_at, NOW() + INTERVAL '24 hours');
    INSERT INTO public.radius_access_credentials (
        entitlement_id, user_id, username, secret_hash, expires_at
    ) VALUES (
        p_entitlement_id, v_user_id, v_username,
        crypt(v_password, gen_salt('bf', 10)), v_expires_at
    ) RETURNING id INTO v_credential_id;
    RETURN jsonb_build_object(
        'credential_id', v_credential_id, 'username', v_username,
        'password', v_password, 'expires_at', v_expires_at
    );
END;
$function$;
-- ---------------------------------------------------------------------------
-- 5. Privileges. Helpers are internal; the status RPC is for signed-in users.
-- (Supabase default privileges grant EXECUTE on new functions to anon and
-- authenticated, so every new function is revoked explicitly.)
-- ---------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public._auth_session_key() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._record_account_pin_verification(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.require_recent_account_pin() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._account_pin_deleted_drop_verifications() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.account_pin_verification_window() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.account_pin_verification_window() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.get_account_pin_verification() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_account_pin_verification() TO authenticated;
