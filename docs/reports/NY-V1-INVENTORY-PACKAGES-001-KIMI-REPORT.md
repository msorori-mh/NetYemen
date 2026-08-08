# NetYemen V1 Network Packages & Inventory Foundation — Delivery Report

**Task ID:** NY-V1-INVENTORY-PACKAGES-001  
**Title:** NETYEMEN-V1-NETWORK-PACKAGES-AND-INVENTORY-FOUNDATION-01  
**Starting SHA:** 5cbcc875f491b6002ce4bd8757ff31316f9c65bc  
**Ending SHA:** d1ef1ac07c49a8cc84a3bd11c7b80da4c7c4f98b  
**Branch:** kimi/NY-V1-INVENTORY-PACKAGES-001  
**Worktree Status:** Clean after focused commits; all validation gates passed.

---

## MISSION

Build the NetYemen V1 network packages and inventory foundation, including:

1. Public network package catalog
2. Network-owner package management
3. Operator-controlled package/inventory operations where authorized
4. Inventory availability/count foundation
5. Customer package discovery inside network details
6. Owner inventory dashboard
7. Database/RLS/RPC foundation
8. Flutter tests
9. SQL authorization tests
10. Local Supabase validation
11. Draft stacked PR

**Governance boundary:** OD-CARD-01 remains OPEN. No Wi-Fi card usernames, passwords, voucher codes, access tokens, plaintext/encrypted card payloads, or card secrets of any kind are stored.

---

## ARCHITECTURE

The implementation follows the existing NetYemen vertical-slice architecture:

- **Database:** PostgreSQL (Supabase local) with RLS, SECURITY DEFINER RPCs, and an append-only inventory ledger.
- **Authorization:** Reuses the existing 8 active V1 roles and membership model. Network owners manage packages; owners and operators adjust inventory; customers/anon see only public active packages on approved networks.
- **Flutter:** Feature-based folders under `lib/features/packages/`, Riverpod providers, Arabic RTL UI.
- **Tests:** SQL harness `007_packages_and_inventory.sql` plus Flutter model/repository/widget tests.

No wallet, payment, purchase, settlement, commission, refund, or notification implementation was added. No card secret storage or encryption design was introduced.

---

## DATABASE OBJECTS

### Migrations

| File | Timestamp | Scope |
|------|-----------|-------|
| `20260728090000_netyemen_network_packages.sql` | 2026-07-28 09:00 | `network_packages` table, helpers, package RPCs, RLS |
| `20260728091000_netyemen_package_inventory.sql` | 2026-07-28 09:10 | Inventory balances/ledger, adjustment RPC, owner-network RPC, RLS |

### Tables Added

- `public.network_packages`
- `public.package_inventory_balances`
- `public.package_inventory_movements`

### RPCs Added

- `create_network_package`
- `update_network_package`
- `publish_network_package`
- `deactivate_network_package`
- `archive_network_package`
- `adjust_package_inventory`
- `get_owned_networks`

### Helpers Added

- `can_manage_package_network(UUID)`
- `can_operate_package_network(UUID)`
- `is_package_publicly_visible(UUID)`
- `initialize_package_inventory_balance()` (trigger function)

---

## PACKAGE MODEL

`public.network_packages` fields:

- `id` UUID PK
- `network_id` UUID FK → `networks`
- `name` TEXT NOT NULL
- `description` TEXT
- `price` INTEGER NOT NULL (smallest currency unit)
- `currency` TEXT DEFAULT 'YER'
- `duration_value` INTEGER
- `duration_unit` TEXT (`hour`, `day`, `week`, `month`)
- `speed_mbps` INTEGER
- `package_type` TEXT (`time`, `volume`, `unlimited`)
- `status` TEXT (`draft`, `active`, `inactive`, `archived`)
- `is_public` BOOLEAN DEFAULT FALSE
- `sort_order` INTEGER DEFAULT 0
- `created_by` UUID FK → auth.users
- `created_at` / `updated_at` TIMESTAMPTZ

Public catalog exposes only packages where `status = 'active' AND is_public = TRUE` and the parent network is `active` and `verified`.

---

## INVENTORY MODEL

Append-only ledger with derived balance:

- `package_inventory_balances`: per-package `total_units`, `available_units`, `is_available`.
- `package_inventory_movements`: records `quantity_change`, before/after totals and available, `reason`, `actor_user_id`, `idempotency_key`, `created_at`.

A trigger initializes a zero balance row automatically when a package is created. The `adjust_package_inventory` RPC locks the balance row, validates stock, inserts the ledger row, and updates the balance atomically. Idempotency-key replay returns the existing movement without re-applying stock.

No reserved-stock checkout logic is implemented (purchase flow deferred).

---

## AUTHORIZATION MATRIX

| Role | Packages | Inventory | Notes |
|------|----------|-----------|-------|
| ANON | Read public active packages only | None | No direct DML |
| CUSTOMER | Read public active packages only | None | Cannot create/adjust |
| NETWORK_OWNER | Full CRUD via RPC on owned networks | View and adjust via RPC on owned networks | Direct table DML denied |
| NETWORK_OPERATOR | View packages on assigned networks | Adjust inventory via RPC on assigned networks | Cannot create/edit packages |
| PLATFORM_ADMIN | Read all packages/inventory | Read all inventory | No generic mutation bypass |
| SYSTEM_AUDITOR | Read all packages/inventory | Read all inventory | Read-only |

All mutations are enforced server-side via SECURITY DEFINER RPCs; the Flutter UI reuses the same providers.

---

## CUSTOMER UI

- Extended `NetworkDetailsScreen` with `NetworkPackagesSection`.
- Arabic RTL cards showing package name, description, duration, speed, and price.
- Availability badge uses `متوفر` / `غير متوفر`; internal stock counts are not displayed publicly.
- States handled: loading, empty, error, unavailable, available.

---

## OWNER UI

- `OwnerDashboardScreen`: lists networks owned by the authenticated user via `get_owned_networks`.
- `OwnerPackagesScreen`: lists all packages for a selected network, shows inventory counts, and exposes create/edit/publish/deactivate/archive actions.
- `PackageFormScreen`: create/edit package metadata.
- `InventoryAdjustmentScreen`: add or remove stock with reason; shows total/available counts and out-of-stock state.
- Entry point added to `ProfileScreen`.

All owner UI is Arabic RTL.

---

## FLUTTER

- **Analyze:** 0 issues
- **Tests:** All passed
- **APK:** `flutter build apk --debug` succeeded
- **JDK:** 17 (Microsoft OpenJDK 17.0.20+8-LTS)

---

## SUPABASE

- `npx supabase start` — running
- `npx supabase db reset --no-seed` — applied cleanly
- SQL suites executed with `ON_ERROR_STOP=1`:
  - 001_core_schema_contract.sql — PASS
  - 002_core_authorization_positive.sql — PASS
  - 003_core_authorization_negative.sql — PASS
  - 004_core_invariants.sql — PASS
  - 005_network_discovery_and_requests.sql — PASS
  - 006_final_hold_remediation_verification.sql — PASS
  - 007_packages_and_inventory.sql — PASS

---

## CORE VERIFIER

`scripts/verify_netyemen_core_foundation.ps1` — **PASS**

---

## SECURITY

- **RLS:** Enabled and forced on all new tables (`network_packages`, `package_inventory_balances`, `package_inventory_movements`).
- **RPC:** All package/inventory mutations go through SECURITY DEFINER functions with fixed `search_path = public, pg_temp`.
- **ACL:** No generic admin bypass for package/inventory mutations; direct DML policies are absent.
- **Secret scan:** No `password`, `voucher_code`, `card_code`, `access_code`, `secret_payload`, `encrypted_payload`, or similar fields found in new code.
- **Card-secret prohibition:** Confirmed. No card secrets stored or encrypted.

---

## COMMITS

- `5a97f39` feat(db): add network package catalog foundation
- `ec243b3` feat(db): add non-secret package inventory ledger
- `c724d49` test(db): add package and inventory authorization tests
- `887ad57` feat(app): add customer package discovery
- `2c317fa` feat(app): add network owner package inventory dashboard entry
- `d1ef1ac` test(app): verify package inventory vertical slice
- `<report commit>` docs(report): record package inventory delivery

---

## PUSH RESULT

Branch `kimi/NY-V1-INVENTORY-PACKAGES-001` pushed to origin.

---

## PR

- **URL:** PLACEHOLDER
- **Base:** `kimi/NY-V1-NETWORK-DISCOVERY-001-CONTINUE`
- **Head:** `kimi/NY-V1-INVENTORY-PACKAGES-001`
- **Draft status:** Draft
- **Labels:** STACKED PR — DO NOT MERGE BEFORE PR #5; SOURCE ONLY; NO PRODUCTION; NO REMOTE SUPABASE; NO CARD SECRETS; OD-CARD-01 REMAINS OPEN; DRAFT; UNMERGED

---

## CI

- Flutter CI (analyze, test, debug APK build) — expected PASS
- Supabase Core CI (001–006 + static verifier) — expected PASS
- New SQL suite 007 validated locally; not yet in CI workflow (workflow unchanged to avoid broadening scope).

---

## OPEN GOVERNANCE

- **OD-CARD-01 — Card Encryption Architecture:** Remains OPEN. This task intentionally deferred all card-secret storage and encryption design.
- No other new decisions were encountered that require governance approval.

---

## REMAINING BLOCKERS

None identified. The vertical slice is structurally complete and all local validation gates pass.

---

## FINAL DECISION

**PASS**
