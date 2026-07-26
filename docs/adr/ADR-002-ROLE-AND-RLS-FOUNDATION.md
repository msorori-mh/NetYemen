# ADR-002: ROLE AND RLS FOUNDATION

**Status:** APPROVED  
**Date:** 2026-07-27  
**Task ID:** NY-GOV-BE-001  
**Author:** NetYemen Core Architecture Team  

---

## 1. Context

NetYemen enforces strict Role-Based Access Control (RBAC) integrated with PostgreSQL Row-Level Security (RLS). The system must support eight active V1 platform roles while enforcing default-deny policies on all tables, ensuring client applications can never supply or spoof identity or administrative privileges.

Prior design discussions highlighted the risk of putting role parameters in user profiles or relying on client-supplied `userId` parameters.

---

## 2. Decision

We establish the following RBAC and RLS architectural rules:

1. **Role Storage Separation:** Roles are stored in a dedicated `public.user_roles` table, separate from `public.profiles`. A user can hold one or more roles assigned strictly by system triggers or authorized administrators.
2. **Active V1 Roles Only (8 Roles):**
   * `customer`
   * `network_owner`
   * `network_operator`
   * `finance_officer`
   * `support_agent`
   * `platform_admin`
   * `system_auditor`
   * `system_service`
   *(Note: `unauthenticated` is an access context for public endpoints; deferred roles such as merchant, distributor, reseller are strictly forbidden in V1).*
3. **No Role in Client Inputs:** Client applications cannot set or update roles. `system_service` cannot be assigned via any client-facing operation.
4. **Default-Deny RLS:** Every core table (`profiles`, `user_roles`, `networks`, `network_memberships`, `network_ssid_aliases`, `audit_events`) has RLS explicitly enabled (`ENABLE ROW LEVEL SECURITY`). Access is granted only via explicit SQL policies.
5. **Untrusted Identity:** Identifiers are evaluated via `auth.uid()`. Client-supplied user IDs in query bodies or parameters are strictly untrusted.
6. **No Superuser Bypass in Commercial Functions:** `platform_admin` roles do not bypass commercial validation or ownership checks in business operations.
7. **Security Definer Helper Scoping:** Helper functions (`has_platform_role`, `is_network_member`, `can_manage_network`) are defined with `SECURITY DEFINER` and fixed `search_path = public, pg_temp`.

---

## 3. Alternatives Considered

* **Option A: Storing Roles inside `public.profiles` Column.**  
  * *Rejected:* High risk of privilege escalation through profile update endpoints or mass-assignment vulnerabilities.
* **Option B: JWT Custom Claims Only.**  
  * *Rejected:* Requires complex token invalidation on role revocation and lacks immediate database-level query capability.
* **Option C: Dedicated `user_roles` Table + RLS Helper Functions (Chosen).**

---

## 4. Security Consequences

* **Positive:** Prevents role tampering; guarantees default-deny state on all core tables; isolates helper function execution context safely.
* **Negative:** Requires careful indexing on `user_roles` and `network_memberships` to prevent RLS query latency.

---

## 5. Operational Consequences

* Role changes take immediate effect in database queries without waiting for JWT token expiration.
* Clean auditing of role assignments via `created_by` tracking in `user_roles`.

---

## 6. Deferred Concerns

* Role management UI in Admin Web Portal (`NY-FE-002`).

---

## 7. Migration Impact

* Implemented in `20260727090000_netyemen_core_identity_and_networks.sql` (schema & constraints) and `20260727091000_netyemen_core_rls_and_audit.sql` (RLS policies & helper functions).

---

## 8. Rollback Strategy

* Revoke policies and drop helper functions prior to table drop scripts.

---

## 9. Verification Evidence

* Positive authorization tests in `supabase/tests/002_core_authorization_positive.sql`.
* Negative authorization tests in `supabase/tests/003_core_authorization_negative.sql` (testing role escalation failure, unauthorized profile updates, cross-tenant network management prevention).
