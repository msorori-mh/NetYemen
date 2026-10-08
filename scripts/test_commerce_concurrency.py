#!/usr/bin/env python3
"""
NetYemen Commerce Core Concurrency Harness
Task ID: NY-V1-COMMERCE-CORE-001

Verifies that two concurrent purchasers cannot both buy the last available
package unit.

Connection (LOCAL / disposable databases only -- the test inserts synthetic
users, a network, a package, wallet credit and a card):

  * default: `docker exec` into the local Supabase Postgres container
    (override the container name with NETYEMEN_DB_CONTAINER);
  * if DATABASE_URL is set: a host `psql` connects to that URL instead, e.g.
    DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres
    A non-loopback host is refused unless NETYEMEN_ALLOW_REMOTE_TEST_DB=1.

The setup is not idempotent: run it once against a freshly reset database that
has the `card_master_key` vault secret (as scripts/verify_netyemen_v1_pilot.ps1
does).
"""

import os
import subprocess
import threading
import sys
from urllib.parse import urlsplit

DB_CONTAINER = os.environ.get("NETYEMEN_DB_CONTAINER", "supabase_db_netyemen-local")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
LOOPBACK_HOSTS = {"127.0.0.1", "localhost", "::1"}


def psql_command(*extra_args: str) -> list:
    """psql invocation for the configured target (URL via host psql, else docker exec)."""
    if DATABASE_URL:
        return ["psql", DATABASE_URL, "-v", "ON_ERROR_STOP=1", *extra_args]
    return [
        "docker", "exec", "-i", DB_CONTAINER,
        "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", *extra_args,
    ]


def refuse_remote_database() -> None:
    """This harness writes synthetic rows; never point it at a hosted project."""
    if not DATABASE_URL:
        return
    host = (urlsplit(DATABASE_URL).hostname or "").lower()
    if host in LOOPBACK_HOSTS:
        return
    if os.environ.get("NETYEMEN_ALLOW_REMOTE_TEST_DB") == "1":
        print(f"WARNING: running against non-loopback database host {host!r}.")
        return
    print(
        f"REFUSED: DATABASE_URL host {host!r} is not loopback. This test inserts "
        "synthetic data and must only run against a local disposable database."
    )
    sys.exit(2)


SETUP_SQL = r"""
DO $$
DECLARE
    v_customer_a UUID := 'a1a1a1a1-a1a1-4a1a-aa1a-a1a1a1a1a1a1';
    v_customer_b UUID := 'a2a2a2a2-a2a2-4a2a-aa2a-a2a2a2a2a2a2';
    v_owner_id   UUID := 'b1b1b1b1-b1b1-4b1b-bb1b-b1b1b1b1b1b1';
    v_admin_id   UUID := 'd1d1d1d1-d1d1-4d1d-dd1d-d1d1d1d1d1d1';
    v_net_id     UUID := 'e1e1e1e1-e1e1-4e1e-ee1e-e1e1e1e1e1e1';
    v_pkg_id     UUID := 'f1f1f1f1-f1f1-4f1f-ff1f-f1f1f1f1f1f1';
BEGIN
    -- Users & profiles
    INSERT INTO auth.users (id, email) VALUES
        (v_customer_a, 'conc_a@netyemen.local'),
        (v_customer_b, 'conc_b@netyemen.local'),
        (v_owner_id, 'conc_owner@netyemen.local'),
        (v_admin_id, 'conc_admin@netyemen.local')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.profiles (id, full_name, account_status) VALUES
        (v_customer_a, 'Customer A', 'active'),
        (v_customer_b, 'Customer B', 'active'),
        (v_owner_id, 'Owner', 'active'),
        (v_admin_id, 'Admin', 'active')
    ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name;

    INSERT INTO public.user_roles (user_id, role) VALUES
        (v_customer_a, 'customer'),
        (v_customer_b, 'customer'),
        (v_owner_id, 'network_owner'),
        (v_admin_id, 'platform_admin')
    ON CONFLICT (user_id, role) DO NOTHING;

    INSERT INTO public.networks (id, commercial_name, status, verification_status, created_by, approved_by, approved_at)
    VALUES (v_net_id, 'Concurrency Network', 'active', 'verified', v_owner_id, v_admin_id, NOW())
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.network_memberships (network_id, user_id, membership_role, status, created_by)
    VALUES (v_net_id, v_owner_id, 'owner', 'active', v_admin_id)
    ON CONFLICT (network_id, user_id) DO NOTHING;

    INSERT INTO public.network_packages (id, network_id, name, price, package_type, status, is_public, created_by)
    VALUES (v_pkg_id, v_net_id, 'Concurrency Package', 1000, 'time', 'active', TRUE, v_owner_id)
    ON CONFLICT (id) DO NOTHING;

    -- Credit both customers via immutable ledger (postgres-only setup)
    -- Start with zero cached balance; ledger trigger will compute the final balance.
    INSERT INTO public.wallet_accounts (user_id, currency, cached_balance, account_status) VALUES
        (v_customer_a, 'YER', 0, 'active'),
        (v_customer_b, 'YER', 0, 'active')
    ON CONFLICT (user_id) DO UPDATE SET cached_balance = 0;

    INSERT INTO public.customer_wallet_ledger (
        user_id, entry_type, amount, balance_after, reference_type,
        reference_id, idempotency_key, actor_user_id, reason_code
    ) VALUES
        (v_customer_a, 'CREDIT', 5000, 5000, 'DEPOSIT', gen_random_uuid(), gen_random_uuid(), v_admin_id, 'CONCURRENCY_SETUP'),
        (v_customer_b, 'CREDIT', 5000, 5000, 'DEPOSIT', gen_random_uuid(), gen_random_uuid(), v_admin_id, 'CONCURRENCY_SETUP');

    -- Seed exactly 1 unit as owner
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_owner_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner_id::text, 'role', 'authenticated')::text, true);
    PERFORM public.adjust_package_inventory(v_pkg_id, 1, 'Single unit for concurrency test', gen_random_uuid());

    -- Seed exactly 1 pgcrypto-encrypted card for the package (postgres test setup).
    EXECUTE 'SET LOCAL ROLE postgres';
    INSERT INTO public.card_vault (network_id, package_id, batch_id, state, ciphertext)
    VALUES (
        v_net_id,
        v_pkg_id,
        'conc-batch-1',
        'available',
        extensions.pgp_sym_encrypt(
            'TEST_ONLY_CARD_SECRET_FOR_CONCURRENCY_TEST',
            public.get_card_master_key()
        )
    )
    ON CONFLICT DO NOTHING;
END $$;
"""

RESULTS = {"success": [], "failure": [], "errors": []}
LOCK = threading.Lock()


def run_psql(role: str, user_id: str, pkg_id: str, key: str):
    """Run purchase_package in its own psql session."""
    sql = f"""
BEGIN;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '{user_id}', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', '{user_id}', 'role', 'authenticated')::text, true);
SELECT public.purchase_package('{pkg_id}'::UUID, '{key}'::UUID);
COMMIT;
"""
    proc = subprocess.run(
        psql_command("-t", "-A"),
        input=sql,
        text=True,
        capture_output=True,
    )
    return proc


def worker(name: str, user_id: str, key: str, pkg_id: str, barrier: threading.Barrier):
    barrier.wait()
    proc = run_psql("authenticated", user_id, pkg_id, key)
    with LOCK:
        if proc.returncode == 0:
            RESULTS["success"].append(name)
            RESULTS["errors"].append(f"{name}: {proc.stdout.strip()}")
        else:
            RESULTS["failure"].append(name)
            RESULTS["errors"].append(f"{name}: {proc.stderr.strip()}")


def main():
    pkg_id = "f1f1f1f1-f1f1-4f1f-ff1f-f1f1f1f1f1f1"
    customer_a = "a1a1a1a1-a1a1-4a1a-aa1a-a1a1a1a1a1a1"
    customer_b = "a2a2a2a2-a2a2-4a2a-aa2a-a2a2a2a2a2a2"
    key_a = "d1d1d1d1-d1d1-4d1d-dd1d-d1d1d1d1d1d1"
    key_b = "d2d2d2d2-d2d2-4d2d-dd2d-d2d2d2d2d2d2"

    refuse_remote_database()

    # Run setup
    setup = subprocess.run(
        psql_command(),
        input=SETUP_SQL,
        text=True,
        capture_output=True,
    )
    if setup.returncode != 0:
        print("SETUP FAILED")
        print(setup.stderr)
        sys.exit(1)

    barrier = threading.Barrier(2)
    threads = [
        threading.Thread(target=worker, args=("customer_a", customer_a, key_a, pkg_id, barrier)),
        threading.Thread(target=worker, args=("customer_b", customer_b, key_b, pkg_id, barrier)),
    ]

    for t in threads:
        t.start()
    for t in threads:
        t.join()

    print("=== Results ===")
    print(f"Success: {RESULTS['success']}")
    print(f"Failure: {RESULTS['failure']}")
    for err in RESULTS["errors"]:
        print(err)

    if len(RESULTS["success"]) == 1 and len(RESULTS["failure"]) == 1:
        print("PASS: Exactly one purchase succeeded; race condition is prevented.")
        sys.exit(0)
    else:
        print("FAIL: Expected exactly one success and one failure.")
        sys.exit(1)


if __name__ == "__main__":
    main()
