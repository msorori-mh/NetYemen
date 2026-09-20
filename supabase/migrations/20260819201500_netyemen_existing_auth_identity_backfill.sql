-- WASEL NET existing authentication identity backfill
-- Migration: 20260819201500_netyemen_existing_auth_identity_backfill.sql
--
-- V1 provisioning triggers cover new signups. This migration idempotently
-- provisions identities that existed in auth.users before the V1 schema was
-- installed, without changing existing profiles, roles or wallet balances.

INSERT INTO public.profiles (
    id,
    full_name,
    account_status,
    created_at,
    updated_at
)
SELECT
    au.id,
    COALESCE(
        NULLIF(trim(au.raw_user_meta_data->>'full_name'), ''),
        NULLIF(trim(au.raw_user_meta_data->>'name'), ''),
        ''
    ),
    'active',
    COALESCE(au.created_at, NOW()),
    NOW()
FROM auth.users AS au
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.user_roles (
    user_id,
    role,
    created_at
)
SELECT
    au.id,
    'customer',
    NOW()
FROM auth.users AS au
JOIN public.profiles AS p ON p.id = au.id
ON CONFLICT (user_id, role) DO NOTHING;

-- Covers both profiles inserted above and any profile that predated the wallet
-- module. Existing balances and account states are preserved by ON CONFLICT.
INSERT INTO public.wallet_accounts (
    user_id,
    currency,
    cached_balance,
    account_status,
    created_at,
    updated_at
)
SELECT
    p.id,
    'YER',
    0,
    'active',
    NOW(),
    NOW()
FROM public.profiles AS p
ON CONFLICT (user_id) DO NOTHING;
