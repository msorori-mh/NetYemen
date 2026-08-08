# NetYemen V1 Operational Closure — Delivery Report

**Task ID:** NY-V1-OPERATIONS-CLOSURE-001  
**Title:** NETYEMEN-V1-PACKAGES-INVENTORY-ADMIN-OPERATIONS-CLOSURE-01  
**Starting SHA:** `2b8a6e25bee675e24803b42cec7703c33c144797`  
**Ending SHA:** `0476a367019552cb98ef22b90b6920609c2dba41`  
**Branch:** `kimi/NY-V1-OPERATIONS-CLOSURE-001`  
**Repository:** `C:\projects\NetYemen-ops-closure`

---

## MISSION

Close the complete NetYemen V1 operational path containing:

1. Network Packages
2. Non-secret Inventory
3. Network Owner Operations
4. Platform Admin Operations
5. Request Review Operations
6. ACL / RLS / RPC hardening
7. Operational Audit Visibility
8. All currently known Inventory/Admin blocking findings
9. Reconciliation of the latest stacked branches
10. One final validated operational baseline

The closure focused on two independent blocking findings from independent Codex reviews:

- **HIGH** — Inventory adjustment idempotency was not concurrency-safe.
- **BLOCKER** — Anonymous and authenticated roles retained destructive `TRUNCATE` on application tables.

No wallet, deposit, purchase, settlement, card-secret, notification, or production deployment work was performed.

---

## INTEGRATED_BRANCHES

- `origin/kimi/NY-V1-INVENTORY-PACKAGES-001` — already merged into the closure branch via `origin/kimi/NY-V1-ADMIN-OPS-001`.
- `origin/kimi/NY-V1-ADMIN-OPS-001` — direct base of the closure branch.

No additional branch reconciliation was required. No force push or history rewrite was performed.

---

## INVENTORY_CLOSURE

### Package catalog

- `public.network_packages` exposes only `status = 'active'` and `is_public = TRUE` packages on networks that are `active` and `verified`.
- Owner/operator package lifecycle RPCs (`create/update/publish/deactivate/archive`) remain scoped to owned/operated networks.
- Direct DML on `network_packages` is denied.

### Inventory

- `public.package_inventory_balances` and `public.package_inventory_movements` remain append-only, non-secret ledgers.
- All inventory mutations flow through `adjust_package_inventory`.

### Idempotency

- `package_inventory_movements.idempotency_key` is now `NOT NULL`.
- Unique index `idx_package_inventory_movements_idempotency (package_id, idempotency_key)` provides the final database-level guarantee.
- `adjust_package_inventory` now:
  - Rejects `NULL` keys with `MISSING_IDEMPOTENCY`.
  - Acquires the balance row lock (`FOR UPDATE`) **before** the replay check.
  - Binds the UUID to the payload (`quantity_change` + `reason`); mismatched replays raise `IDEMPOTENCY_PAYLOAD_MISMATCH`.
  - Returns `{replayed: true, movement_id}` for identical replays.

### Concurrency

- The lock-first replay check serializes concurrent adjustments per package.
- The unique index ensures that even a race that escapes the lock cannot double-apply stock.
- Negative stock is rejected atomically under the lock.

### Flutter binding

- `InventoryAdjustmentScreen` now binds a payload-fingerprinted idempotency key so retries of the same logical adjustment reuse the same UUID, while any material change mints a fresh key.

---

## ADMIN_CLOSURE

### Dashboard

- `admin_dashboard_kpis()` remains available to `platform_admin`, `support_agent`, and `system_auditor`.

### Review

- Network addition request review continues to use the atomic `resolve_network_addition_request` RPC.
- `support_agent` scope is limited to read/review; `platform_admin` can resolve to terminal states.

### Network management

- `admin_approve_network` and `admin_suspend_network` remain `platform_admin`-only.
- SSID alias verification/rejection remains `platform_admin`-only.

### Audit

- `audit_events` SELECT is restricted to `platform_admin` and `system_auditor`.
- Direct `UPDATE`/`DELETE` on `audit_events` is blocked by trigger and by revoked privileges.

### Users/roles visibility

- Admin users/membership surfaces remain read-only; no role-assignment UI/RPC was added.

---

## ACL_MATRIX_BEFORE

Effective table ACLs before the hardening migration:

```text
audit_events              anon=Dxt  authenticated=rDxt
network_addition_requests anon=Dxt  authenticated=rDxt
network_memberships       anon=Dxt  authenticated=arwdDxt
network_packages          anon=rDxt authenticated=rDxt
network_ssid_aliases                authenticated=arwdDxt
networks                            authenticated=rw
package_inventory_balances anon=Dxt authenticated=rDxt
package_inventory_movements anon=Dxt authenticated=rDxt
profiles                  anon=Dxt  authenticated=r
user_roles                anon=Dxt  authenticated=arwdDxt
```

(`D` = TRUNCATE, `x` = REFERENCES, `t` = TRIGGER.)

## ACL_MATRIX_AFTER

Effective table ACLs after the hardening migration:

```text
audit_events                authenticated=r
network_addition_requests   authenticated=r
network_memberships         authenticated=arwd
network_packages            anon=r  authenticated=r
network_ssid_aliases        anon=column-SELECT  authenticated=arwd
networks                    authenticated=rw
package_inventory_balances  authenticated=r
package_inventory_movements authenticated=r
profiles                    authenticated=r / column-UPDATE
user_roles                  authenticated=arwd
```

No `PUBLIC`, `anon`, or `authenticated` entry retains `D` (TRUNCATE), `x` (REFERENCES), or `t` (TRIGGER) on any NetYemen application table.

---

## DEFAULT_PRIVILEGES

Before:

```text
postgres       public  r  postgres=arwdDxt, anon=Dxt, authenticated=Dxt, service_role=Dxt
supabase_admin public  r  anon=arwdDxt, authenticated=arwdDxt, service_role=arwdDxt
```

After:

```text
postgres       public  r  service_role=arwdDxt
```

`ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES FROM PUBLIC, anon, authenticated;` was applied. `supabase_admin` defaults could not be altered by the migration role because `postgres` is not a member of `supabase_admin`; existing and future NetYemen tables are protected by the explicit per-table revokes above.

---

## AUTHORIZATION_MATRIX

| Role | Packages | Inventory | Dashboard | Requests | Networks | Aliases | Audit | Users/Roles |
|---|---|---|---|---|---|---|---|---|
| anon | public read | none | none | none | public read | public read | none | none |
| customer | public read | none | none | own requests | public read | public read | none | own profile |
| network_owner | own network CRUD | own network view/adjust | none | own requests | own networks | own pending aliases | none | own profile |
| network_operator | assigned network read | assigned network adjust | none | none | assigned networks | none | none | own profile |
| support_agent | read all | read all | read/KPIs | read/review | read all | read all | none | read all |
| system_auditor | read all | read all | read/KPIs | read all | read all | read all | read all | read all |
| platform_admin | read/admin | read/admin | full | full | approve/suspend | verify/reject | read all | read/admin |

All mutations are enforced server-side via SECURITY DEFINER RPCs and RLS.

---

## SECURITY_DEFINER_REVIEW

- All 34 SECURITY DEFINER functions in `public` schema set `search_path = public, pg_temp`.
- All mutation RPCs use `auth.uid()` and active-profile checks; no caller-supplied `actor_user_id` parameter exists.
- `record_audit_event` is granted only to `service_role`.
- `initialize_package_inventory_balance` trigger function is revoked from client roles.
- Admin RPCs (`admin_*`) are granted only to `authenticated` and check platform roles internally.

---

## FLUTTER

| Check | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | All 93 tests passed |
| `flutter build apk --debug` | Built `build\app\outputs\flutter-apk\app-debug.apk` |
| JDK | 17 (Microsoft OpenJDK 17.0.20+8-LTS) |

---

## SUPABASE

| Step | Result |
|---|---|
| `npx supabase start` | Running locally |
| `npx supabase db reset --no-seed` | All migrations applied cleanly |
| SQL 001 core_schema_contract.sql | PASS |
| SQL 002 core_authorization_positive.sql | PASS |
| SQL 003 core_authorization_negative.sql | PASS |
| SQL 004 core_invariants.sql | PASS |
| SQL 005 network_discovery_and_requests.sql | PASS |
| SQL 006 final_hold_remediation_verification.sql | PASS |
| SQL 007 packages_and_inventory.sql | PASS |
| SQL 008 admin_operations.sql | PASS |
| SQL 009 client_truncate_acl_hardening.sql | PASS |
| SQL 010 operational_closure.sql | PASS |

All SQL suites executed with `ON_ERROR_STOP=1`.

---

## CORE_VERIFIER

`powershell -ExecutionPolicy Bypass -File scripts/verify_netyemen_core_foundation.ps1`

**Result: PASS** — Static verification satisfied all rules.

---

## SECRET_SCAN

- No private-key headers, AWS/Google/GitHub/OpenAI/Supabase live keys, or JWT-shaped tokens found in new/modified tracked files.
- `service_role` references are limited to RLS/audit infrastructure and tests.
- Local Supabase keys printed during `npx supabase start` were never committed.

**Result: PASS**

## CARD_SECRET_SCAN

- No `voucher_code`, `card_code`, `access_code`, `secret_payload`, `encrypted_payload`, Wi-Fi password, or card credential columns implemented.
- All references to card secrets are in governance documents (OD-CARD-01) only.

**Result: PASS**

---

## COMMITS

| SHA | Message |
|---|---|
| `35bd85e` | fix(db): close inventory idempotency and concurrency |
| `38cae7f` | fix(db): harden client table ACLs and default privileges |
| `84d67c3` | test(db): verify operational authorization and destructive privilege denial |

---

## PUSH_RESULT

Branch `kimi/NY-V1-OPERATIONS-CLOSURE-001` pushed to origin successfully.

## PR

| Item | Value |
|---|---|
| PR | #10 |
| URL | https://github.com/msorori-mh/NetYemen/pull/10 |
| Base | `kimi/NY-V1-INVENTORY-PACKAGES-001` |
| Head | `kimi/NY-V1-OPERATIONS-CLOSURE-001` |
| Title | `NETYEMEN-V1-OPERATIONS-CLOSURE-01` |
| State | Draft / OPEN |
| Labels/Disclaimers | `V1 OPERATIONS CLOSURE`, `SOURCE ONLY`, `NO PRODUCTION`, `NO REMOTE SUPABASE`, `NO CARD SECRETS`, `DRAFT`, `UNMERGED` |

---

## OPEN_GOVERNANCE

- **OD-CARD-01 — Card Encryption Architecture:** Remains OPEN. This closure intentionally deferred all card-secret storage and encryption design.
- **OD-AUTH-01:** Not applicable to this closure.

## REMAINING_BLOCKERS

None identified. Both the Inventory HIGH finding and the Admin BLOCKER finding are closed.

## FINAL_DECISION

**PASS** — The NetYemen V1 operational path is closed, hardened, and validated locally. The branch is ready for review as a stacked draft PR.
