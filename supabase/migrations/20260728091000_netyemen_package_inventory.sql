-- NetYemen Non-Secret Package Inventory Ledger
-- Migration: 20260728091000_netyemen_package_inventory.sql
-- Task ID: NY-V1-INVENTORY-PACKAGES-001
-- Scope: Inventory balance and append-only ledger for network packages (NO card secrets)
-- Governance: OD-CARD-01 remains OPEN; this migration MUST NOT store Wi-Fi credentials, voucher codes, card payloads, or secrets.

-- ============================================================================
-- 1. Table: public.package_inventory_balances
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.package_inventory_balances (
    package_id UUID PRIMARY KEY REFERENCES public.network_packages(id) ON DELETE CASCADE,
    network_id UUID NOT NULL REFERENCES public.networks(id) ON DELETE CASCADE,
    total_units INTEGER NOT NULL DEFAULT 0,
    available_units INTEGER NOT NULL DEFAULT 0,
    is_available BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_package_inventory_balances_total_non_negative CHECK (total_units >= 0),
    CONSTRAINT chk_package_inventory_balances_available_non_negative CHECK (available_units >= 0),
    CONSTRAINT chk_package_inventory_balances_available_lte_total CHECK (available_units <= total_units)
);

COMMENT ON TABLE public.package_inventory_balances IS 'Derived, non-secret inventory balance per package. Maintained exclusively by the adjust_package_inventory RPC.';
COMMENT ON COLUMN public.package_inventory_balances.total_units IS 'Total units owned by the network for this package (sold + unsold). No secret payloads.';
COMMENT ON COLUMN public.package_inventory_balances.available_units IS 'Units currently available for sale. Purchase reservation/checkout is deferred; this is not a reservation ledger.';

CREATE INDEX IF NOT EXISTS idx_package_inventory_balances_network ON public.package_inventory_balances (network_id);

ALTER TABLE public.package_inventory_balances ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 2. Table: public.package_inventory_movements
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.package_inventory_movements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    package_id UUID NOT NULL REFERENCES public.network_packages(id) ON DELETE CASCADE,
    network_id UUID NOT NULL REFERENCES public.networks(id) ON DELETE CASCADE,
    quantity_change INTEGER NOT NULL,
    previous_total INTEGER NOT NULL,
    new_total INTEGER NOT NULL,
    previous_available INTEGER NOT NULL,
    new_available INTEGER NOT NULL,
    reason TEXT NOT NULL,
    actor_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    idempotency_key UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_package_inventory_movements_quantity_non_zero CHECK (quantity_change <> 0),
    CONSTRAINT chk_package_inventory_movements_reason_non_empty CHECK (length(trim(reason)) > 0),
    CONSTRAINT chk_package_inventory_movements_coherence CHECK (
        new_total = previous_total + quantity_change
        AND new_available = previous_available + quantity_change
        AND new_total >= 0
        AND new_available >= 0
        AND new_available <= new_total
    )
);

COMMENT ON TABLE public.package_inventory_movements IS 'Append-only, non-secret inventory ledger. Every stock change is recorded with before/after balances, actor, and reason.';

CREATE INDEX IF NOT EXISTS idx_package_inventory_movements_package ON public.package_inventory_movements (package_id);
CREATE INDEX IF NOT EXISTS idx_package_inventory_movements_network ON public.package_inventory_movements (network_id);
CREATE INDEX IF NOT EXISTS idx_package_inventory_movements_idempotency ON public.package_inventory_movements (package_id, idempotency_key);

ALTER TABLE public.package_inventory_movements ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 3. Trigger: Initialize zero balance when a package is created
-- ============================================================================

CREATE OR REPLACE FUNCTION public.initialize_package_inventory_balance()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.package_inventory_balances (
        package_id,
        network_id,
        total_units,
        available_units,
        is_available
    ) VALUES (
        NEW.id,
        NEW.network_id,
        0,
        0,
        TRUE
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_initialize_package_inventory_balance') THEN
        CREATE TRIGGER trg_initialize_package_inventory_balance
            AFTER INSERT ON public.network_packages
            FOR EACH ROW
            EXECUTE FUNCTION public.initialize_package_inventory_balance();
    END IF;
END $$;

REVOKE EXECUTE ON FUNCTION public.initialize_package_inventory_balance() FROM PUBLIC;

-- ============================================================================
-- 4. Controlled Inventory RPCs
-- ============================================================================

-- ----------------------------------------------------------------------------
-- RPC: adjust_package_inventory
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.adjust_package_inventory(
    p_package_id UUID,
    p_quantity_change INTEGER,
    p_reason TEXT,
    p_idempotency_key UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_network_id UUID;
    v_existing_movement_id UUID;
    v_balance public.package_inventory_balances%ROWTYPE;
    v_new_total INTEGER;
    v_new_available INTEGER;
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

    IF p_quantity_change = 0 THEN
        RAISE EXCEPTION 'INVALID_QUANTITY: Quantity change cannot be zero.'
            USING ERRCODE = '22000';
    END IF;

    IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
        RAISE EXCEPTION 'INVALID_REASON: Adjustment reason is required.'
            USING ERRCODE = '22000';
    END IF;

    SELECT network_id INTO v_network_id
    FROM public.network_packages
    WHERE id = p_package_id;

    IF v_network_id IS NULL THEN
        RAISE EXCEPTION 'NOT_FOUND: Package not found.'
            USING ERRCODE = '42501';
    END IF;

    IF NOT public.can_operate_package_network(v_network_id) THEN
        RAISE EXCEPTION 'FORBIDDEN: Not authorized to adjust inventory for this network.'
            USING ERRCODE = '42501';
    END IF;

    -- Idempotency: if same package + key already processed, return the existing result without mutation
    IF p_idempotency_key IS NOT NULL THEN
        SELECT id INTO v_existing_movement_id
        FROM public.package_inventory_movements
        WHERE package_id = p_package_id AND idempotency_key = p_idempotency_key;

        IF v_existing_movement_id IS NOT NULL THEN
            RETURN jsonb_build_object(
                'idempotency_key', p_idempotency_key,
                'movement_id', v_existing_movement_id,
                'replayed', TRUE
            );
        END IF;
    END IF;

    -- Lock the balance row to serialize concurrent adjustments for this package
    SELECT * INTO v_balance
    FROM public.package_inventory_balances
    WHERE package_id = p_package_id
    FOR UPDATE;

    IF v_balance.package_id IS NULL THEN
        RAISE EXCEPTION 'NOT_FOUND: Inventory balance not found for package.'
            USING ERRCODE = '42501';
    END IF;

    v_new_total := v_balance.total_units + p_quantity_change;
    v_new_available := v_balance.available_units + p_quantity_change;

    IF v_new_total < 0 THEN
        RAISE EXCEPTION 'INSUFFICIENT_TOTAL_STOCK: Adjustment would make total stock negative.'
            USING ERRCODE = '22000';
    END IF;

    IF v_new_available < 0 THEN
        RAISE EXCEPTION 'INSUFFICIENT_AVAILABLE_STOCK: Adjustment would make available stock negative.'
            USING ERRCODE = '22000';
    END IF;

    -- Insert immutable ledger row
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
        v_network_id,
        p_quantity_change,
        v_balance.total_units,
        v_new_total,
        v_balance.available_units,
        v_new_available,
        trim(p_reason),
        v_user_id,
        p_idempotency_key
    );

    -- Update derived balance
    UPDATE public.package_inventory_balances
    SET
        total_units = v_new_total,
        available_units = v_new_available,
        updated_at = NOW()
    WHERE package_id = p_package_id;

    RETURN jsonb_build_object(
        'package_id', p_package_id,
        'quantity_change', p_quantity_change,
        'new_total', v_new_total,
        'new_available', v_new_available
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.adjust_package_inventory(UUID, INTEGER, TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.adjust_package_inventory(UUID, INTEGER, TEXT, UUID) TO authenticated;

-- ----------------------------------------------------------------------------
-- RPC: get_owned_networks
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_owned_networks()
RETURNS TABLE (
    id UUID,
    commercial_name TEXT,
    description TEXT,
    governorate TEXT,
    city TEXT,
    district TEXT,
    status TEXT,
    verification_status TEXT
) AS $$
DECLARE
    v_user_id UUID;
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

    RETURN QUERY
    SELECT
        n.id,
        n.commercial_name,
        n.description,
        n.governorate,
        n.city,
        n.district,
        n.status,
        n.verification_status
    FROM public.networks n
    JOIN public.network_memberships nm ON nm.network_id = n.id
    JOIN public.profiles p ON p.id = nm.user_id
    JOIN public.user_roles ur ON ur.user_id = nm.user_id AND ur.role = 'network_owner'
    WHERE nm.user_id = v_user_id
      AND nm.membership_role = 'owner'
      AND nm.status = 'active'
      AND p.account_status = 'active'
    ORDER BY n.commercial_name;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.get_owned_networks() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_owned_networks() TO authenticated;

-- ============================================================================
-- 5. Row-Level Security Policies for Inventory Tables
-- ============================================================================

-- Least-privilege table grants
REVOKE ALL ON TABLE public.package_inventory_balances FROM PUBLIC;
GRANT SELECT ON TABLE public.package_inventory_balances TO authenticated;

REVOKE ALL ON TABLE public.package_inventory_movements FROM PUBLIC;
GRANT SELECT ON TABLE public.package_inventory_movements TO authenticated;

-- ----------------------------------------------------------------------------
-- Policies for public.package_inventory_balances
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS package_inventory_balances_owner_select_policy ON public.package_inventory_balances;
CREATE POLICY package_inventory_balances_owner_select_policy ON public.package_inventory_balances
    FOR SELECT
    USING (
        public.can_operate_package_network(network_id)
        OR public.has_platform_role('platform_admin')
        OR public.has_platform_role('system_auditor')
    );

-- Note: No direct INSERT/UPDATE policy. Balance maintenance is controlled via adjust_package_inventory RPC only.

-- ----------------------------------------------------------------------------
-- Policies for public.package_inventory_movements
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS package_inventory_movements_owner_select_policy ON public.package_inventory_movements;
CREATE POLICY package_inventory_movements_owner_select_policy ON public.package_inventory_movements
    FOR SELECT
    USING (
        public.can_operate_package_network(network_id)
        OR public.has_platform_role('platform_admin')
        OR public.has_platform_role('system_auditor')
    );

-- Note: No direct INSERT policy. Inventory movements are created exclusively by adjust_package_inventory RPC.

-- Force RLS
ALTER TABLE public.package_inventory_balances FORCE ROW LEVEL SECURITY;
ALTER TABLE public.package_inventory_movements FORCE ROW LEVEL SECURITY;
