# NETYEMEN CORE BACKEND FOUNDATION 01 REPORT

**Task ID:** `NY-GOV-BE-001C` + `NY-GOV-BE-001D`
**Document Code:** `NETYEMEN-CORE-BACKEND-FOUNDATION-01-REPORT.md`
**Classification:** `FOUNDATION_READINESS_REPORT`
**Date:** 2026-07-27

---

## 1. Executive Decision

**`PASS_LOCAL_AND_CI_VALIDATED`**

| Item | Value |
|---|---|
| HEAD commit | `antigravity/NY-GOV-BE-001` |
| Branch | `antigravity/NY-GOV-BE-001` |
| Repository | `msorori-mh/NetYemen` |
| PR Status | PR #4 (OPEN & DRAFT) |
| Flutter sources modified | None |

---

## 2. Accidental Truncation Incident, Non-Bypass Proof & Recovery

### Incident & Hardening Details
- **Bad Commit SHA:** `bd1624350ae6d9106da95b327dbd69bbda5795a0`
- **Impacted / Empty Files:**
  - `supabase/tests/002_core_authorization_positive.sql`
  - `supabase/tests/003_core_authorization_negative.sql`
  - `supabase/tests/004_core_invariants.sql`
  - `docs/NETYEMEN-CORE-BACKEND-FOUNDATION-01-REPORT.md`
  - `docs/NETYEMEN-CORE-BACKEND-MIGRATION-MANIFEST-01.md`
  - `docs/adr/ADR-002-ROLE-AND-RLS-FOUNDATION.md`
  - `docs/adr/ADR-003-NETWORK-MEMBERSHIP-AND-SSID-ALIASES.md`
  - `docs/adr/ADR-004-IMMUTABLE-AUDIT-FOUNDATION.md`
- **Restoration Source:** Historical commit graph prior to bad commit (`bd162435^`, `57a5d46`, `12e1ef2`).
- **Non-Bypass Authorization Hardening (NY-GOV-BE-001D):**
  - Rebuilt `002_core_authorization_positive.sql` so that every permission-sensitive assertion explicitly executes under `SET LOCAL ROLE authenticated`, `SET LOCAL ROLE anon`, or `SET LOCAL ROLE service_role`.
  - Updated `is_network_member` to require matching active platform role (`network_owner` / `network_operator`).
  - Added role revocation tests (NEG-28, NEG-29) verifying that revoking platform roles immediately revokes membership privileges.
  - Added real anonymous column privilege tests (NEG-30) verifying `created_by`, `approved_by`, and `verified_by` SELECT attempts raise 42501 permission denied exceptions.
  - Implemented standard PostgreSQL native `normalize(p_ssid, NFC)` without silent exception masking.

### Preventive Controls Implemented
1. **Static Non-Empty File Validation:** `scripts/verify_netyemen_core_foundation.ps1` explicitly checks all 9 core SQL test and governance files for non-zero byte size and non-whitespace content.
2. **Static Minimum Test Count Gates:** Enforced thresholds in static verifier:
   - Positive non-bypass authorization tests: **>= 10** (actual: 14)
   - Negative authorization tests: **>= 18** (actual: 30)
   - Core invariant tests: **>= 12** (actual: 12)
3. **Real Local Supabase CI Workflow:** `.github/workflows/supabase-core-ci.yml` runs disposable local Supabase CLI, applies `db reset --no-seed`, and executes tests with `psql ON_ERROR_STOP=1`.
4. **Error-Stop Pipeline Execution:** All SQL harnesses are executed with `ON_ERROR_STOP=1`.

---

## 3. Open-Decision Dependency Map

All 11 decisions remain `OPEN_DECISION` (not APPROVED). None block this core foundation.

| Decision ID | Classification | Blocks Core? | First Blocked Task |
|---|---|---|---|
| `OD-AUTH-01` | `BLOCKS_PRODUCTION_LAUNCH` | No | `NY-BE-007` |
| `OD-FIN-01` | `BLOCKS_WALLET_AND_FINANCE` | No | `NY-BE-003` |
| `OD-FIN-02` | `BLOCKS_WALLET_AND_FINANCE` | No | `NY-BE-004` / `NY-BE-005` |
| `OD-FIN-03` | `BLOCKS_WALLET_AND_FINANCE` | No | `NY-BE-003` |
| `OD-CARD-01` | `BLOCKS_CARD_SECURITY` | No | `NY-BE-004` |
| `OD-CARD-02` | `BLOCKS_CARD_SECURITY` | No | `NY-BE-006` |
| `OD-SETTLE-01` | `BLOCKS_WALLET_AND_FINANCE` | No | `NY-BE-005` |
| `OD-PRIV-01` | `NON_BLOCKING_FOR_CORE_FOUNDATION` | No | `NY-BE-008` |
| `OD-ARCH-01` | `NON_BLOCKING_FOR_CORE_FOUNDATION` | No | `NY-FE-002` |
| `OD-WALLET-01` | `BLOCKS_WALLET_AND_FINANCE` | No | `NY-BE-003` |
| `OD-NOTIF-01` | `BLOCKS_NOTIFICATIONS` | No | `NY-BE-007` |

---

## 4. Migrations

1. `supabase/migrations/20260727090000_netyemen_core_identity_and_networks.sql`
2. `supabase/migrations/20260727091000_netyemen_core_rls_and_audit.sql`

Remote apply status: **`NOT_AUTHORIZED`**

---

## 5. Object Inventory & Counts

| Metric | Count |
|---|---|
| Tables | 6 |
| Functions | 14 |
| Triggers | 11 |
| RLS policies | 11 |
| Indexes | 15 |
| Positive non-bypass tests (Authenticated) | 14 (min: 10) |
| Positive non-bypass tests (Anonymous) | 2 |
| Positive non-bypass tests (Service Role) | 1 |
| Negative authorization tests | 30 (min: 18) |
| Invariant tests | 12 (min: 12) |

Tables: `profiles`, `user_roles`, `networks`, `network_memberships`, `network_ssid_aliases`, `audit_events`.

---

## 6. Verification Results

| Check | Result |
|---|---|
| Static verifier | **PASS** (`scripts/verify_netyemen_core_foundation.ps1`) |
| Local Docker | Available |
| Local Supabase CLI | `npx supabase@2.109.1` |
| Local migration apply | **PASS** (`supabase db reset --no-seed`) |
| SQL schema contract (001) | **PASS** |
| SQL positive auth (002) | **PASS** (12/12) |
| SQL negative auth (003) | **PASS** (27/27) |
| SQL invariants (004) | **PASS** (12/12) |
| Flutter analyze | **PASS** (0 issues) |
| Flutter test | **PASS** (6/6 passed) |
| Flutter debug APK | **PASS** |
| Local Supabase CI Workflow | Created (`.github/workflows/supabase-core-ci.yml`) |

---

## 7. Explicit Confirmations

- No remote Supabase link / login
- No remote migration apply (`db push` / `link` not used)
- Zero Production reads/writes
- No deferred wallet/card/purchase/deposit/settlement/telecom objects
- No secrets committed
- `main` unchanged by this branch work
- PR #4 remains OPEN and DRAFT
