# ADR-005: MIGRATION AND ENVIRONMENT GOVERNANCE

**Status:** APPROVED  
**Date:** 2026-07-27  
**Task ID:** NY-GOV-BE-001  
**Author:** NetYemen Core Architecture Team  

---

## 1. Context

Database schema evolutions for NetYemen must adhere to strict security, stability, and source-control governance. The repository must maintain strict boundaries between source-only migration definitions, local disposable test environments, and remote Staging/Production database instances.

Under authorization boundaries defined in `NY-GOV-BE-001`, source-only migration creation and local runtime testing are permitted, while any remote database linking, remote push, remote SQL execution, or deployment operations are strictly prohibited.

---

## 2. Decision

We establish the following migration and environment governance policies:

1. **Source-Only Versioned Migration Files:**
   * All database schema changes must be declared as idempotent, timestamped SQL migration files under `supabase/migrations/`.
   * Migration filenames must strictly follow the ISO format: `YYYYMMDDHHMMSS_description.sql`.
   * Migration order for Core Backend Foundation (`NY-GOV-BE-001`):
     1. `20260727090000_netyemen_core_identity_and_networks.sql`
     2. `20260727091000_netyemen_core_rls_and_audit.sql`
2. **Idempotent and Safe SQL Practices:**
   * DDL statements must use `IF NOT EXISTS` guards.
   * Modifying existing tables must be done via explicit `DO $$ ... END $$` blocks or conditional checks.
   * `DROP TABLE ... CASCADE` and destructive data mutations are strictly FORBIDDEN in migration scripts.
3. **Strict Authorization Restrictions (Source Package):**
   * Authorized: Creating migration SQL files, creating SQL test harnesses, creating static PowerShell verifier scripts, running local migrations on disposable local Supabase instances if Docker/Supabase CLI are available.
   * Prohibited: `supabase link`, `supabase db push`, `supabase login`, connecting to any remote Supabase project, modifying Staging or Production databases, or exposing service-role keys.
4. **Automated Static Verification:**
   * PowerShell script `scripts/verify_netyemen_core_foundation.ps1` validates migration files, RLS enablement, forbidden term exclusions, and rule compliance statically without connecting to remote infrastructure.

---

## 3. Alternatives Considered

* **Option A: Direct Execution via Remote Supabase Dashboard.**  
  * *Rejected:* Destroys environment reproducibility, lacks auditability, and violates source control boundaries.
* **Option B: Source-Only Migration Declarations + Disposable Local Validation (Chosen).**

---

## 4. Security Consequences

* **Positive:** Absolute protection against accidental modifications to remote staging/production environments; full code review of database migrations prior to release.
* **Negative:** None.

---

## 5. Operational Consequences

* Developers work with identical local Supabase setups using standard SQL migrations.
* CI/CD pipelines can run automated static and pgTAP tests against disposable ephemeral containers.

---

## 6. Deferred Concerns

* Staging and Production deployment pipelines (`NY-BE-009`).

---

## 7. Migration Impact

* Provides the foundational schema migration files for all future NetYemen backend modules.

---

## 8. Rollback Strategy

* Local disposable environment: Run `supabase db reset` to rebuild clean database state from migration source.

---

## 9. Verification Evidence

* Static PowerShell verifier script execution: `scripts/verify_netyemen_core_foundation.ps1`.
* Complete migration manifest in `docs/NETYEMEN-CORE-BACKEND-MIGRATION-MANIFEST-01.md`.
