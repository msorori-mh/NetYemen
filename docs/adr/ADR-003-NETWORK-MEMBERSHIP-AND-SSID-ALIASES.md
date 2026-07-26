# ADR-003: NETWORK MEMBERSHIP AND SSID ALIASES

**Status:** APPROVED  
**Date:** 2026-07-27  
**Task ID:** NY-GOV-BE-001  
**Author:** NetYemen Core Architecture Team  

---

## 1. Context

NetYemen hotspot networks operate across multiple governorates, cities, and districts in Yemen. A commercial network may broadcast under multiple SSID Wi-Fi names across different access points or branch locations. Furthermore, network management requires explicit delegation: network owners may delegate operational duties (such as uploading card stock) to staff operators without granting administrative rights (such as changing payout bank details or approving network terms).

Prior prototypes suffered from:
1. Hardcoded single-owner columns on network models as the sole authorization source.
2. Storing raw BSSID MAC addresses or device hardware serial numbers in public catalogs, creating privacy and hardware-tracking risks.

---

## 2. Decision

We establish the following network, membership, and SSID alias model:

1. **Network Commercial Parent Entity (`public.networks`):**
   * Represents the business entity. Contains geographic metadata (`governorate`, `city`, `district`), status (`pending_approval`, `active`, `suspended`, `rejected`), and verification status (`unverified`, `verified`, `rejected`).
   * Only active, verified networks are visible to the public or anonymous users.
2. **Explicit Network Memberships (`public.network_memberships`):**
   * Decouples network ownership and management from single-column table references.
   * Supported membership roles: `owner` and `operator`.
   * Owners hold full administrative control over the network, staff operators, and SSID aliases.
   * Operators hold operational access (e.g. inventory upload) but CANNOT manage memberships, approve networks, or view settlement payouts.
   * Operational Invariant: Every active network must have at least one active `owner` membership.
   * Concurrency Serialization: `protect_final_active_owner` trigger executes `SELECT 1 FROM public.networks WHERE id = OLD.network_id FOR UPDATE;` to lock the parent network row, preventing concurrent race conditions where two simultaneous transactions could delete different owners and leave zero active owners.
3. **SSID Alias Normalization & Verification Integrity (`public.network_ssid_aliases`):**
   * Multiple SSID aliases can map to a single parent network.
   * Function `public.normalize_ssid(p_ssid text)` standardizes SSIDs using `unicode_normalize(p_ssid, 'NFC')` (preserving Arabic characters, lowercasing English, trimming surrounding whitespace, and replacing internal whitespace with hyphens).
   * Verification Lifecycle: Owners create aliases in `pending_verification` status only. Owners may edit display names only while pending. Owners cannot self-activate aliases or modify display names of active verified aliases.
   * Administrative Activation: Admin activation requires explicit `verified_by` UUID and `verified_at` timestamp metadata (`chk_ssid_aliases_verification_coherence`).
   * Uniqueness Constraint: A normalized active SSID alias (`ssid_normalized`) MUST be globally unique across all active networks via partial unique index.
   * Privacy Protection: Raw BSSID (MAC addresses), access point hardware serial numbers, and customer device scan locations are strictly EXCLUDED from the schema.

---

## 3. Alternatives Considered

* **Option A: Single `owner_id` Column on `networks` Table without Memberships.**  
  * *Rejected:* Cannot support multi-operator staff delegations or multi-owner enterprise hotspot businesses.
* **Option B: Storing BSSID Scanning Tables in Public Catalog.**  
  * *Rejected:* Violates user privacy guidelines and creates hardware fingerprinting vulnerabilities.
* **Option C: Explicit Memberships + Normalized SSID Aliases (Chosen).**

---

## 4. Security Consequences

* **Positive:** Strict separation between network owners and operators; prevents unauthorized operator actions; prevents SSID spoofing via unique normalized active alias constraints.
* **Negative:** Queries checking user network access must join `network_memberships`, requiring optimal index coverage on `(network_id, user_id, status, membership_role)`.

---

## 5. Operational Consequences

* Hotspot owners can register multiple SSIDs under one umbrella network name.
* Hotspot owners can easily add or revoke operator staff accounts without sharing owner credentials.

---

## 6. Deferred Concerns

* Network card package catalog (`NY-BE-004`).

---

## 7. Migration Impact

* Implemented in `20260727090000_netyemen_core_identity_and_networks.sql` and `20260727091000_netyemen_core_rls_and_audit.sql`.

---

## 8. Rollback Strategy

* Drop `network_ssid_aliases` and `network_memberships` before dropping `networks`.

---

## 9. Verification Evidence

* Normalization and unique alias constraint tests in `supabase/tests/004_core_invariants.sql`.
* Operator boundary negative tests in `supabase/tests/003_core_authorization_negative.sql`.
