# ADR-004: IMMUTABLE AUDIT FOUNDATION

**Status:** APPROVED  
**Date:** 2026-07-27  
**Task ID:** NY-GOV-BE-001  
**Author:** NetYemen Core Architecture Team  

---

## 1. Context

NetYemen financial and security contracts mandate complete, tamper-proof audit trails for all sensitive system events, authentication state changes, authorization failures, and administrative operations.

Prior implementations lacked a centralized append-only audit mechanism, exposing system event logs to potential client-side tampering or accidental deletion.

---

## 2. Decision

We establish an immutable audit trail architecture centered on `public.audit_events`:

1. **Append-Only Invariant:**
   * Direct `UPDATE` and `DELETE` operations on `public.audit_events` are strictly FORBIDDEN for all roles, including `platform_admin`.
   * Direct `INSERT` operations by client applications (`authenticated`, `anon`) are FORBIDDEN via default-deny RLS policies.
2. **Centralized Logging Function (`public.record_audit_event`):**
   * All audit records must be generated via the trusted `SECURITY DEFINER` function `public.record_audit_event(...)`.
   * Function parameters: `p_action`, `p_entity_type`, `p_entity_id`, `p_result`, `p_reason_code`, `p_metadata`, `p_correlation_id`.
   * Identity extraction: Actor user ID (`actor_user_id`) is automatically extracted from `auth.uid()`, preventing client identity spoofing.
3. **Payload Sanitization & Size Constraints:**
   * Sensitive values (passwords, OTPs, secret keys, service-role keys, card PINs, financial account numbers, JWT tokens) MUST NEVER be passed or recorded in `metadata` payloads.
   * `metadata` size is bounded to a maximum of 8,192 bytes per event payload to prevent database storage denial-of-service.
4. **Access Control:**
   * Read access to `audit_events` is restricted strictly to `platform_admin` and `system_auditor` roles.
   * `system_auditor` holds read-only access to audit logs and platform state but is denied all mutation capabilities across operational tables.

---

## 3. Alternatives Considered

* **Option A: Client-Side Audit Event Emission via REST.**  
  * *Rejected:* Vulnerable to client tampering, dropped logs, and identity spoofing.
* **Option B: Application Server Middleware Logging Only.**  
  * *Rejected:* Bypasses database-level RPC execution and direct RLS access attempts.
* **Option C: Database Trigger & Security Definer Append-Only Table (Chosen).**

---

## 4. Security Consequences

* **Positive:** Guaranteed append-only audit integrity; complete forensic audit trail for system admins and auditors; elimination of secret leaks in audit payloads.
* **Negative:** Audit log volume will grow continuously over time, requiring a 5-year retention and archiving cron strategy (`NY-BE-008`).

---

## 5. Operational Consequences

* Audit trails provide immediate visibility into security events, failed login attempts, and unauthorized RLS access attempts.
* Compliance reporting for `system_auditor` role is simplified.

---

## 6. Deferred Concerns

* Automated long-term cold storage archiving for audit logs beyond 5 years (`NY-BE-008`).

---

## 7. Migration Impact

* Implemented in `20260727091000_netyemen_core_rls_and_audit.sql`.

---

## 8. Rollback Strategy

* Audit events cannot be dropped individually. In non-production test resets, table drop script drops `audit_events` cleanly.

---

## 9. Verification Evidence

* Immutable audit tests in `supabase/tests/004_core_invariants.sql` (verifying UPDATE and DELETE rejection on audit rows).
* Auditor role negative mutation tests in `supabase/tests/003_core_authorization_negative.sql`.
