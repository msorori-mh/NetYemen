#!/usr/bin/env python3
"""
NetYemen Commerce Core Concurrency Harness
Task ID: NY-V1-COMMERCE-CORE-001

Runs real concurrent database sessions against the money RPCs and checks both
WHY the losing call failed and the FINAL state of the tables:

  A. last unit      two customers buy the last unit of a package at once
                    -> one purchase, the loser gets OUT_OF_STOCK, exactly one
                       card sold, exactly one DEBIT.
  B. one balance    one customer, two purchases (different idempotency keys),
                    balance for only one
                    -> one purchase, the loser gets INSUFFICIENT_BALANCE (or
                       OUT_OF_STOCK), the balance never goes negative.
  C. same key       one customer sends the SAME idempotency key twice at once
                    -> both calls succeed, one of them `replayed`, one purchase
                       row, one DEBIT.
  D. double approve two finance officers approve one deposit at once
                    -> both calls succeed, the wallet is credited exactly once.

Finally `finance_reconcile_wallets()` must report no drift for the wallets
used here (cached balance == ledger sum).

Each session keeps its transaction open for a short time (HOLD_SECONDS) before
COMMIT, so the other session really blocks on the row or advisory lock instead
of merely running after it.

Connection (LOCAL / disposable databases only -- the test inserts synthetic
users, a network, packages, wallet credit, cards and a deposit):

  * default: `docker exec` into the local Supabase Postgres container
    (override the container name with NETYEMEN_DB_CONTAINER);
  * if DATABASE_URL is set: a host `psql` connects to that URL instead, e.g.
    DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres
    A non-loopback host is refused unless NETYEMEN_ALLOW_REMOTE_TEST_DB=1.

Only the Python standard library and `psql` are used (no pip install).

Every run generates fresh identifiers, so it can be repeated on the same
database. The database needs all migrations and the `card_master_key` vault
secret (as scripts/verify_netyemen_v1_pilot.ps1 and the CI workflow create).
"""

import os
import subprocess
import sys
import threading
import uuid
from urllib.parse import urlsplit

DB_CONTAINER = os.environ.get("NETYEMEN_DB_CONTAINER", "supabase_db_netyemen-local")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
LOOPBACK_HOSTS = {"127.0.0.1", "localhost", "::1"}
HOLD_SECONDS = 0.4

PACKAGE_PRICE = 1000
OPENING_BALANCE = 5000
SINGLE_PURCHASE_BALANCE = 1500  # enough for exactly one PACKAGE_PRICE purchase
DEPOSIT_AMOUNT = 3000  # below deposit_dual_approval_threshold(): one approval credits


def psql_command(*extra_args: str) -> list:
    """psql invocation for the configured target (URL via host psql, else docker exec)."""
    if DATABASE_URL:
        return ["psql", DATABASE_URL, "-X", "-v", "ON_ERROR_STOP=1", *extra_args]
    return [
        "docker", "exec", "-i", DB_CONTAINER,
        "psql", "-X", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", *extra_args,
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


def run_sql(sql: str) -> subprocess.CompletedProcess:
    return subprocess.run(psql_command("-q", "-t", "-A"), input=sql, text=True, capture_output=True)


def scalar(sql: str) -> str:
    """Run a single-value query as the database owner and return it as text."""
    proc = run_sql(sql)
    if proc.returncode != 0:
        print("STATE QUERY FAILED")
        print(sql)
        print(proc.stderr)
        sys.exit(1)
    return proc.stdout.strip()


def new_id() -> str:
    return str(uuid.uuid4())


RUN = uuid.uuid4().hex[:8]
IDS = {
    name: new_id()
    for name in (
        "customer_a", "customer_b", "customer_c", "customer_d", "customer_e",
        "owner", "admin", "finance_1", "finance_2",
        "network", "pkg_last_unit", "pkg_stocked", "destination",
    )
}

SETUP_SQL = r"""
DO $$
DECLARE
    v_customer_a UUID := '{customer_a}';
    v_customer_b UUID := '{customer_b}';
    v_customer_c UUID := '{customer_c}';
    v_customer_d UUID := '{customer_d}';
    v_customer_e UUID := '{customer_e}';
    v_owner_id   UUID := '{owner}';
    v_admin_id   UUID := '{admin}';
    v_finance_1  UUID := '{finance_1}';
    v_finance_2  UUID := '{finance_2}';
    v_net_id     UUID := '{network}';
    v_pkg_last   UUID := '{pkg_last_unit}';
    v_pkg_stock  UUID := '{pkg_stocked}';
    v_dest_id    UUID := '{destination}';
BEGIN
    -- Users & profiles
    INSERT INTO auth.users (id, email) VALUES
        (v_customer_a, 'conc_a_{run}@netyemen.local'),
        (v_customer_b, 'conc_b_{run}@netyemen.local'),
        (v_customer_c, 'conc_c_{run}@netyemen.local'),
        (v_customer_d, 'conc_d_{run}@netyemen.local'),
        (v_customer_e, 'conc_e_{run}@netyemen.local'),
        (v_owner_id, 'conc_owner_{run}@netyemen.local'),
        (v_admin_id, 'conc_admin_{run}@netyemen.local'),
        (v_finance_1, 'conc_fin1_{run}@netyemen.local'),
        (v_finance_2, 'conc_fin2_{run}@netyemen.local')
    ON CONFLICT (id) DO NOTHING;

    -- Server-side PIN enforcement: the customers have a PIN verified in the
    -- (claim-less) test session, so purchase_package reaches its money logic.
    INSERT INTO public.account_pins (user_id, pin_hash)
    SELECT id, 'fixture-not-a-real-hash' FROM auth.users
    WHERE id IN (v_customer_a, v_customer_b, v_customer_c, v_customer_d, v_customer_e)
    ON CONFLICT (user_id) DO NOTHING;
    INSERT INTO public.account_pin_verifications (user_id, session_key)
    SELECT id, '' FROM auth.users
    WHERE id IN (v_customer_a, v_customer_b, v_customer_c, v_customer_d, v_customer_e)
    ON CONFLICT (user_id, session_key) DO UPDATE SET verified_at = now();

    INSERT INTO public.profiles (id, full_name, account_status) VALUES
        (v_customer_a, 'Customer A', 'active'),
        (v_customer_b, 'Customer B', 'active'),
        (v_customer_c, 'Customer C', 'active'),
        (v_customer_d, 'Customer D', 'active'),
        (v_customer_e, 'Customer E', 'active'),
        (v_owner_id, 'Owner', 'active'),
        (v_admin_id, 'Admin', 'active'),
        (v_finance_1, 'Finance 1', 'active'),
        (v_finance_2, 'Finance 2', 'active')
    ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, account_status = 'active';

    INSERT INTO public.user_roles (user_id, role) VALUES
        (v_customer_a, 'customer'),
        (v_customer_b, 'customer'),
        (v_customer_c, 'customer'),
        (v_customer_d, 'customer'),
        (v_customer_e, 'customer'),
        (v_owner_id, 'network_owner'),
        (v_admin_id, 'platform_admin'),
        (v_finance_1, 'finance_officer'),
        (v_finance_2, 'finance_officer')
    ON CONFLICT (user_id, role) DO NOTHING;

    INSERT INTO public.networks (id, commercial_name, status, verification_status, created_by, approved_by, approved_at)
    VALUES (v_net_id, 'Concurrency Network {run}', 'active', 'verified', v_owner_id, v_admin_id, NOW());

    INSERT INTO public.network_memberships (network_id, user_id, membership_role, status, created_by)
    VALUES (v_net_id, v_owner_id, 'owner', 'active', v_admin_id);

    INSERT INTO public.network_packages (id, network_id, name, price, package_type, status, is_public, created_by) VALUES
        (v_pkg_last, v_net_id, 'Concurrency Last Unit {run}', {price}, 'time', 'active', TRUE, v_owner_id),
        (v_pkg_stock, v_net_id, 'Concurrency Stocked {run}', {price}, 'time', 'active', TRUE, v_owner_id);

    -- Credit customers via the ledger (postgres-only setup).
    -- Start with zero cached balance; the ledger trigger computes the balance.
    INSERT INTO public.wallet_accounts (user_id, currency, cached_balance, account_status) VALUES
        (v_customer_a, 'YER', 0, 'active'),
        (v_customer_b, 'YER', 0, 'active'),
        (v_customer_c, 'YER', 0, 'active'),
        (v_customer_d, 'YER', 0, 'active'),
        (v_customer_e, 'YER', 0, 'active')
    ON CONFLICT (user_id) DO NOTHING;

    INSERT INTO public.customer_wallet_ledger (
        user_id, entry_type, amount, balance_after, reference_type,
        reference_id, idempotency_key, actor_user_id, reason_code
    ) VALUES
        (v_customer_a, 'CREDIT', {opening}, {opening}, 'DEPOSIT', gen_random_uuid(), gen_random_uuid(), v_admin_id, 'CONCURRENCY_SETUP'),
        (v_customer_b, 'CREDIT', {opening}, {opening}, 'DEPOSIT', gen_random_uuid(), gen_random_uuid(), v_admin_id, 'CONCURRENCY_SETUP'),
        (v_customer_c, 'CREDIT', {single}, {single}, 'DEPOSIT', gen_random_uuid(), gen_random_uuid(), v_admin_id, 'CONCURRENCY_SETUP'),
        (v_customer_d, 'CREDIT', {opening}, {opening}, 'DEPOSIT', gen_random_uuid(), gen_random_uuid(), v_admin_id, 'CONCURRENCY_SETUP');

    INSERT INTO public.payment_destinations (id, provider_type, display_name, account_holder_name, account_identifier, currency, is_active)
    VALUES (v_dest_id, 'bank_account', 'TEST_ONLY concurrency bank {run}', 'TEST_ONLY', 'TEST-ONLY-{run}', 'YER', TRUE);

    -- Inventory as the owner: 1 unit for the last-unit race, 5 for the others.
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_owner_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner_id::text, 'role', 'authenticated')::text, true);
    PERFORM public.adjust_package_inventory(v_pkg_last, 1, 'Single unit for concurrency test', gen_random_uuid());
    PERFORM public.adjust_package_inventory(v_pkg_stock, 5, 'Stock for concurrency test', gen_random_uuid());

    -- The deposit is created by the customer through the real RPC.
    PERFORM set_config('request.jwt.claim.sub', v_customer_e::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_customer_e::text, 'role', 'authenticated')::text, true);
    PERFORM public.create_wallet_deposit_request({deposit}, 'TEST-ONLY-CONC-{run}', v_dest_id, NULL, gen_random_uuid());

    -- pgcrypto-encrypted cards (postgres test setup): 1 + 5.
    EXECUTE 'SET LOCAL ROLE postgres';
    INSERT INTO public.card_vault (network_id, package_id, batch_id, state, ciphertext)
    VALUES (
        v_net_id, v_pkg_last, 'conc-last-{run}', 'available',
        extensions.pgp_sym_encrypt('TEST_ONLY_CARD_SECRET_FOR_CONCURRENCY_TEST', public.get_card_master_key())
    );
    INSERT INTO public.card_vault (network_id, package_id, batch_id, state, ciphertext)
    SELECT v_net_id, v_pkg_stock, 'conc-stock-{run}', 'available',
           extensions.pgp_sym_encrypt('TEST_ONLY_CARD_SECRET_' || n::text, public.get_card_master_key())
    FROM generate_series(1, 5) AS n;
END $$;
""".format(
    run=RUN,
    price=PACKAGE_PRICE,
    opening=OPENING_BALANCE,
    single=SINGLE_PURCHASE_BALANCE,
    deposit=DEPOSIT_AMOUNT,
    **IDS,
)


def session_sql(user_id: str, call: str) -> str:
    """One authenticated session calling `call`, holding its locks briefly before COMMIT."""
    return f"""
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '{user_id}', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', '{user_id}', 'role', 'authenticated')::text, true);
SELECT 'RESULT=' || ({call})::text;
SELECT pg_sleep({HOLD_SECONDS});
COMMIT;
"""


def purchase_call(package_id: str, key: str) -> str:
    # Two arguments on purpose: p_expected_price defaults to NULL.
    return f"public.purchase_package('{package_id}'::uuid, '{key}'::uuid)"


def race(calls: dict) -> dict:
    """Run every (user_id, call) at once in separate sessions. Returns name -> outcome."""
    barrier = threading.Barrier(len(calls))
    outcomes = {}
    lock = threading.Lock()

    def worker(name: str, user_id: str, call: str) -> None:
        barrier.wait()
        proc = run_sql(session_sql(user_id, call))
        result = ""
        for line in proc.stdout.splitlines():
            if line.startswith("RESULT="):
                result = line[len("RESULT="):]
        error_lines = [line for line in proc.stderr.splitlines() if "ERROR" in line]
        with lock:
            outcomes[name] = {
                "ok": proc.returncode == 0 and bool(result),
                "result": result,
                "error": error_lines[0] if error_lines else proc.stderr.strip(),
            }

    threads = [
        threading.Thread(target=worker, args=(name, user_id, call))
        for name, (user_id, call) in calls.items()
    ]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    return outcomes


FAILURES = []


def check(scenario: str, description: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  [OK] {description}")
    else:
        print(f"  [FAIL] {description} {detail}".rstrip())
        FAILURES.append(f"{scenario}: {description} {detail}".rstrip())


def describe(outcomes: dict) -> str:
    return "; ".join(
        f"{name}: {'ok ' + o['result'] if o['ok'] else o['error']}" for name, o in sorted(outcomes.items())
    )


def winners_and_losers(outcomes: dict):
    winners = [o for o in outcomes.values() if o["ok"]]
    losers = [o for o in outcomes.values() if not o["ok"]]
    return winners, losers


def is_replay(outcome: dict) -> bool:
    return '"replayed": true' in outcome["result"]


def user_list(*names: str) -> str:
    return ", ".join(f"'{IDS[name]}'" for name in names)


def scenario_last_unit() -> None:
    name = "A last-unit"
    print(f"=== {name}: two customers, one unit ===")
    pkg = IDS["pkg_last_unit"]
    outcomes = race({
        "customer_a": (IDS["customer_a"], purchase_call(pkg, new_id())),
        "customer_b": (IDS["customer_b"], purchase_call(pkg, new_id())),
    })
    print(f"  {describe(outcomes)}")
    winners, losers = winners_and_losers(outcomes)
    check(name, "exactly one purchase succeeded and one failed", len(winners) == 1 and len(losers) == 1)
    check(name, "the loser failed with OUT_OF_STOCK",
          len(losers) == 1 and "OUT_OF_STOCK" in losers[0]["error"],
          f"(got: {losers[0]['error'] if losers else 'no loser'})")
    users = user_list("customer_a", "customer_b")
    check(name, "exactly one card of the package is sold, none left available",
          scalar("SELECT count(*) FILTER (WHERE state = 'sold')::text || '/' || "
                 "count(*) FILTER (WHERE state = 'available')::text "
                 f"FROM public.card_vault WHERE package_id = '{pkg}'") == "1/0")
    check(name, "exactly one purchase row exists for the package",
          scalar(f"SELECT count(*) FROM public.purchase_records WHERE package_id = '{pkg}'") == "1")
    check(name, "exactly one DEBIT was written for the two customers",
          scalar("SELECT count(*) FROM public.customer_wallet_ledger "
                 f"WHERE entry_type = 'DEBIT' AND user_id IN ({users})") == "1")
    check(name, "inventory is exactly zero (not negative)",
          scalar(f"SELECT available_units FROM public.package_inventory_balances WHERE package_id = '{pkg}'") == "0")
    check(name, "one balance is untouched and one is debited once",
          scalar("SELECT string_agg(cached_balance::text, ',' ORDER BY cached_balance) "
                 f"FROM public.wallet_accounts WHERE user_id IN ({users})")
          == f"{OPENING_BALANCE - PACKAGE_PRICE},{OPENING_BALANCE}")


def scenario_single_balance() -> None:
    name = "B one-balance"
    print(f"=== {name}: one customer, two purchases, balance for one ===")
    pkg = IDS["pkg_stocked"]
    user = IDS["customer_c"]
    outcomes = race({
        "first": (user, purchase_call(pkg, new_id())),
        "second": (user, purchase_call(pkg, new_id())),
    })
    print(f"  {describe(outcomes)}")
    winners, losers = winners_and_losers(outcomes)
    check(name, "exactly one purchase succeeded and one failed", len(winners) == 1 and len(losers) == 1)
    check(name, "the loser failed with INSUFFICIENT_BALANCE or OUT_OF_STOCK",
          len(losers) == 1
          and ("INSUFFICIENT_BALANCE" in losers[0]["error"] or "OUT_OF_STOCK" in losers[0]["error"]),
          f"(got: {losers[0]['error'] if losers else 'no loser'})")
    check(name, "the balance is the opening balance minus exactly one price",
          scalar(f"SELECT cached_balance FROM public.wallet_accounts WHERE user_id = '{user}'")
          == str(SINGLE_PURCHASE_BALANCE - PACKAGE_PRICE))
    check(name, "no ledger entry of the customer has a negative balance_after",
          scalar("SELECT count(*) FROM public.customer_wallet_ledger "
                 f"WHERE user_id = '{user}' AND balance_after < 0") == "0")
    check(name, "exactly one DEBIT and one purchase row",
          scalar("SELECT (SELECT count(*) FROM public.customer_wallet_ledger "
                 f"WHERE user_id = '{user}' AND entry_type = 'DEBIT')::text || '/' || "
                 f"(SELECT count(*) FROM public.purchase_records WHERE user_id = '{user}')::text") == "1/1")


def scenario_same_key() -> None:
    name = "C same-key"
    print(f"=== {name}: one customer, the same idempotency key twice ===")
    pkg = IDS["pkg_stocked"]
    user = IDS["customer_d"]
    key = new_id()
    outcomes = race({
        "first": (user, purchase_call(pkg, key)),
        "second": (user, purchase_call(pkg, key)),
    })
    print(f"  {describe(outcomes)}")
    winners, losers = winners_and_losers(outcomes)
    check(name, "both calls succeeded", len(winners) == 2 and not losers)
    check(name, "exactly one of them is a replay", len([o for o in winners if is_replay(o)]) == 1)
    check(name, "exactly one purchase row for the key",
          scalar("SELECT count(*) FROM public.purchase_records "
                 f"WHERE user_id = '{user}' AND idempotency_key = '{key}'") == "1")
    check(name, "exactly one DEBIT and the balance is debited once",
          scalar("SELECT (SELECT count(*) FROM public.customer_wallet_ledger "
                 f"WHERE user_id = '{user}' AND entry_type = 'DEBIT')::text || '/' || "
                 f"(SELECT cached_balance FROM public.wallet_accounts WHERE user_id = '{user}')::text")
          == f"1/{OPENING_BALANCE - PACKAGE_PRICE}")
    check(name, "exactly one card was sold to the customer",
          scalar("SELECT count(*) FROM public.card_vault v "
                 "JOIN public.purchase_records p ON p.id = v.purchase_id "
                 f"WHERE p.user_id = '{user}' AND v.state = 'sold'") == "1")


def scenario_double_approval() -> None:
    name = "D double-approve"
    print(f"=== {name}: two finance officers approve one deposit ===")
    user = IDS["customer_e"]
    deposit_id = scalar(f"SELECT id FROM public.wallet_deposit_requests WHERE user_id = '{user}'")
    call = f"public.review_wallet_deposit_request('{deposit_id}'::uuid, 'approve', NULL)"
    outcomes = race({
        "finance_1": (IDS["finance_1"], call),
        "finance_2": (IDS["finance_2"], call),
    })
    print(f"  {describe(outcomes)}")
    winners, losers = winners_and_losers(outcomes)
    check(name, "both calls succeeded", len(winners) == 2 and not losers)
    check(name, "exactly one of them is a replay", len([o for o in winners if is_replay(o)]) == 1)
    check(name, "the deposit is approved",
          scalar(f"SELECT status FROM public.wallet_deposit_requests WHERE id = '{deposit_id}'") == "approved")
    check(name, "exactly one CREDIT references the deposit",
          scalar("SELECT count(*) FROM public.customer_wallet_ledger "
                 f"WHERE reference_type = 'DEPOSIT' AND reference_id = '{deposit_id}'") == "1")
    check(name, "the wallet was credited exactly once",
          scalar(f"SELECT cached_balance FROM public.wallet_accounts WHERE user_id = '{user}'")
          == str(DEPOSIT_AMOUNT))


def final_reconciliation() -> None:
    name = "reconciliation"
    print("=== reconciliation: cached balance equals the ledger sum ===")
    users = user_list("customer_a", "customer_b", "customer_c", "customer_d", "customer_e")
    check(name, "finance_reconcile_wallets() reports no drift for the test wallets",
          scalar(f"SELECT count(*) FROM public.finance_reconcile_wallets() r WHERE r.user_id IN ({users})") == "0")
    check(name, "no test wallet has a negative balance",
          scalar(f"SELECT count(*) FROM public.wallet_accounts WHERE user_id IN ({users}) AND cached_balance < 0") == "0")
    check(name, "cached balances equal the signed ledger sums",
          scalar(
              f"SELECT count(*) FROM public.wallet_accounts w WHERE w.user_id IN ({users}) "
              "AND w.cached_balance <> COALESCE(("
              "SELECT sum(CASE WHEN l.entry_type = 'DEBIT' THEN -l.amount ELSE l.amount END) "
              "FROM public.customer_wallet_ledger l WHERE l.user_id = w.user_id), 0)"
          ) == "0")


def main() -> None:
    refuse_remote_database()

    setup = subprocess.run(psql_command("-q"), input=SETUP_SQL, text=True, capture_output=True)
    if setup.returncode != 0:
        print("SETUP FAILED")
        print(setup.stderr)
        sys.exit(1)

    scenario_last_unit()
    scenario_single_balance()
    scenario_same_key()
    scenario_double_approval()
    final_reconciliation()

    if FAILURES:
        print(f"FAIL: {len(FAILURES)} concurrency check(s) failed.")
        for failure in FAILURES:
            print(f"  - {failure}")
        sys.exit(1)
    print("PASS: all concurrency scenarios held (last unit, single balance, same key, double approval).")
    sys.exit(0)


if __name__ == "__main__":
    main()
