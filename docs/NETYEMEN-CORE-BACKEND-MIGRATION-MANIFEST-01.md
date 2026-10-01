# NETYEMEN CORE BACKEND MIGRATION MANIFEST 01

**Task ID:** NY-GOV-BE-001  
**Document Code:** `NETYEMEN-CORE-BACKEND-MIGRATION-MANIFEST-01.md`  
**Classification:** `TECHNICAL_MANIFEST`  
**Status:** Pre-Implementation Specification Approved  

---

## 1. Migration Execution Order

The core backend foundation (`NY-GOV-BE-001`) defines exactly two sequential migration files:

```
1. 20260727090000_netyemen_core_identity_and_networks.sql
2. 20260727091000_netyemen_core_rls_and_audit.sql
```

---

## 2. Detailed Migration Specifications

### 2.1 Migration 001: Core Identity and Networks Schema
* **Filename:** `supabase/migrations/20260727090000_netyemen_core_identity_and_networks.sql`
* **Remote Apply Status:** `NOT_AUTHORIZED`
* **Objects Created:**
  * Extensions: `pgcrypto`
  * Helper Functions: `public.set_updated_at()`, `public.handle_new_user()`
  * Tables:
    * `public.profiles`
    * `public.user_roles`
    * `public.networks`
    * `public.network_memberships`
    * `public.network_ssid_aliases`
  * Triggers:
    * `set_updated_at` on `profiles`, `networks`, `network_memberships`, `network_ssid_aliases`
    * `on_auth_user_created` on `auth.users` (inserts profile and default `customer` role)
  * Indexes:
    * `idx_profiles_account_status`
    * `idx_user_roles_role`
    * `idx_networks_status_verification`
    * `idx_networks_created_by`
    * `idx_network_memberships_user`
    * `idx_network_memberships_role`
    * `idx_network_ssid_aliases_network`
    * `idx_network_ssid_aliases_normalized`
    * `idx_network_ssid_aliases_unique_active_normalized` (Partial UNIQUE index)
* **Dependencies:** Supabase Auth schema (`auth.users`).
* **Grants & Revokes:** Minimum necessary table grants (`SELECT`, `INSERT`, `UPDATE`) to `authenticated` and `anon`. Direct `DELETE` or `ALL` grants are revoked.
* **RLS Policies:** RLS is enabled (`ALTER TABLE ... ENABLE ROW LEVEL SECURITY`) on all created tables in Migration 001; policies are declared in Migration 002.
* **Idempotency Assumptions:** Uses `CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`, and `OR REPLACE` for triggers and functions. Safe on a clean or reset database.
* **Rollback Approach:** Local test teardown script drops tables in reverse order (`network_ssid_aliases`, `network_memberships`, `networks`, `user_roles`, `profiles`).
* **Local Test Requirements:** Validate schema contract in `supabase/tests/001_core_schema_contract.sql`.

---

### 2.2 Migration 002: Core RLS, Authorization Helpers, and Audit
* **Filename:** `supabase/migrations/20260727091000_netyemen_core_rls_and_audit.sql`
* **Remote Apply Status:** `NOT_AUTHORIZED`
* **Objects Created:**
  * Tables:
    * `public.audit_events`
  * Security Definer Helper Functions:
    * `public.has_platform_role(p_role text)`
    * `public.is_network_member(p_network_id uuid)`
    * `public.can_manage_network(p_network_id uuid)`
    * `public.normalize_ssid(p_ssid text)`
    * `public.record_audit_event(p_action text, p_entity_type text, p_entity_id text, p_result text, p_reason_code text, p_metadata jsonb, p_correlation_id uuid)`
  * Triggers:
    * `prevent_audit_events_mutation` on `public.audit_events` (blocks `UPDATE` and `DELETE`)
  * Indexes:
    * `idx_audit_events_actor`
    * `idx_audit_events_action`
    * `idx_audit_events_occurred_at`
    * `idx_audit_events_entity`
  * RLS Policies:
    * `profiles`: `profiles_select_policy`, `profiles_update_policy`
    * `user_roles`: `user_roles_select_policy`, `user_roles_admin_manage_policy`
    * `networks`: `networks_select_policy`, `networks_insert_policy`, `networks_update_policy`
    * `network_memberships`: `memberships_select_policy`, `memberships_owner_manage_policy`
    * `network_ssid_aliases`: `ssid_aliases_select_policy`, `ssid_aliases_owner_manage_policy`
    * `audit_events`: `audit_events_select_policy` (No INSERT/UPDATE/DELETE policies for clients)
* **Dependencies:** Migration 001 (`20260727090000_netyemen_core_identity_and_networks.sql`).
* **Grants & Revokes:**
  * Function execution explicitly granted to `authenticated` (and `anon` for `normalize_ssid` and `networks_select`).
  * `REVOKE EXECUTE ON FUNCTION public.record_audit_event FROM PUBLIC`.
  * RLS default-deny enforced across all core tables.
* **Idempotency Assumptions:** Safe to re-run with `CREATE OR REPLACE FUNCTION` and `DROP POLICY IF EXISTS ... CREATE POLICY`.
* **Rollback Approach:** Teardown script drops policies and helper functions.
* **Local Test Requirements:** Validate positive authorization (`002`), negative authorization (`003`), and invariants (`004`).

---

## 3. Object Inventory Summary

| Migration File | Tables | Functions | Triggers | RLS Policies | Indexes |
|---|---|---|---|---|---|
| `20260727090000_...` | 5 | 2 | 5 | 0 (RLS Enabled) | 9 |
| `20260727091000_...` | 1 | 5 | 1 | 12 | 4 |
| **Total Core Foundation** | **6** | **7** | **6** | **12** | **13** |

---

## 4. Environment Authorization Guard

```
+-----------------------------------------------------------------------------------+
|               REMOTE DATABASE OPERATIONS ARE STRICTLY FORBIDDEN                   |
+-----------------------------------------------------------------------------------+
| - supabase link         : PROHIBITED                                              |
| - supabase db push     : PROHIBITED                                              |
| - Remote Staging       : PROHIBITED                                              |
| - Remote Production    : PROHIBITED                                              |
| - Remote SQL Execution : PROHIBITED                                              |
+-----------------------------------------------------------------------------------+
```

All migrations are source-only declarations for inclusion in the repository and testing on disposable local Supabase instances.
