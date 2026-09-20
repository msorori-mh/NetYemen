# ADR-001: SUPABASE CORE DOMAIN BOUNDARY

**Status:** APPROVED  
**Date:** 2026-07-27  
**Task ID:** NY-GOV-BE-001  
**Author:** NetYemen Core Architecture Team  

---

## 1. Context

The NetYemen platform requires a clean, robust, and security-isolated core backend schema to establish user identities, role-based authorization, network listings, membership relationships, SSID alias normalization, and audit event tracking. Prior prototype implementations mixed financial fields (e.g. wallet balance, prices) directly inside user profile models or lacked clear domain boundaries.

To comply with governance contracts (`NETYEMEN-PRODUCT-REQUIREMENTS-01.md`, `NETYEMEN-SECURITY-OPERATING-CONTRACT-01.md`), the V1 foundation must strictly isolate core domain entities from commercial, financial, card inventory, and external communication infrastructure.

---

## 2. Decision

We establish a strict core domain boundary for `NY-GOV-BE-001`. The core backend foundation shall create only the following six database tables:

1. `public.profiles` — Identity metadata linked to `auth.users(id)`.
2. `public.user_roles` — Platform role assignments (8 V1 active roles).
3. `public.networks` — Commercial Wi-Fi hotspot parent entities.
4. `public.network_memberships` — Explicit owner/operator user mapping to networks.
5. `public.network_ssid_aliases` — Normalized SSID display/search aliases.
6. `public.audit_events` — System audit trail for security and operational compliance.

### Excluded Deferred Domain Objects
The following domain entities are strictly prohibited from being created in this core foundation package:
* `wallets` / `wallet_ledger_entries`
* `deposit_requests` / `bank_directory`
* `cards` / `card_batches` / `purchases`
* `card_complaints` / `support_tickets`
* `settlements` / `network_payouts`
* `telecom_services` / `adsl_orders`
* `user_device_tokens` / `notification_logs`
* `merchant` / `distributor` / `reseller` tables or role identifiers

---

## 3. Alternatives Considered

* **Option A: Monolithic Single-Schema Foundation.** Creating all V1 tables (wallets, cards, settlements, deposits, networks) in a single massive initial migration.  
  * *Rejected:* Blurs domain boundaries, introduces premature financial schema dependencies, and prevents isolated security testing of core RBAC/RLS policies.
* **Option B: Core Domain Isolation (Chosen).** Establishing identity, roles, networks, memberships, aliases, and audit logs as a self-contained core package first.

---

## 4. Security Consequences

* **Positive:** Complete isolation of sensitive financial and encryption primitives from identity and catalog schemas. RLS policies on core tables do not depend on financial table state.
* **Negative:** None. Identity and network access control can be fully validated before financial logic is introduced.

---

## 5. Operational Consequences

* Reduced cognitive load for backend engineers.
* Faster schema migration execution and local testing.
* Independent scaling and maintenance of core identity/network services.

---

## 6. Deferred Concerns

* Financial ledger schema (`NY-BE-003`).
* Card inventory pgcrypto encryption schema (`NY-BE-004`).
* Settlement engine and payout batches (`NY-BE-005`).

---

## 7. Migration Impact

* Clean initial baseline for NetYemen backend on Supabase PostgreSQL.
* Migration `20260727090000_netyemen_core_identity_and_networks.sql` creates the core schema without dependencies on existing custom tables.

---

## 8. Rollback Strategy

* Drop created core tables in reverse dependency order: `network_ssid_aliases`, `network_memberships`, `networks`, `user_roles`, `profiles`, `audit_events`.
* Note: Cascading drops are forbidden in production migrations; explicit drop statements are provided in test cleanup scripts.

---

## 9. Verification Evidence

* Verified via `scripts/verify_netyemen_core_foundation.ps1` checking that zero wallet, card, deposit, or settlement objects exist in migration source.
* Validated via pgTAP / SQL schema contract test `supabase/tests/001_core_schema_contract.sql`.
