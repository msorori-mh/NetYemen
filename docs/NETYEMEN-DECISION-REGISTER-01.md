# NETYEMEN OPEN DECISION REGISTER (V1.0 + V1.1 REMEDIATED)

**Task ID:** NY-PRODUCT-001F / NY-V1-EXTERNAL-PILOT-BINDING-001
**Document Code:** `NETYEMEN-DECISION-REGISTER-01.md`
**Classification:** `V1_GOVERNANCE_REGISTER`
**Status:** Owner Approved Decisions Bound — Remaining Items Provisional

---

## Executive Overview

Where business rules or technical parameters cannot be definitively established from the existing repository prototype (`VERIFIED_CURRENT_STATE`), they are formally registered as `OPEN_DECISION`. Each decision presents 2–4 realistic operational options, evaluates advantages and risks, assesses operational/technical impact, and provides a clearly labeled `PROVISIONAL_RECOMMENDATION`.

Effective `2026-08-08`, the OWNER has approved the seven V1 binding decisions listed below. These decisions are authoritative, recorded here, and implemented in the external-pilot release candidate. They must not be reopened, replaced by alternative policy choices, or silently unbound in V1 source.

---

## Approved Owner Decisions (V1 Binding)

| Decision ID | Decision Title | Category | Impact Level | Status | Approved By | Approved Date |
|---|---|---|---|---|---|---|
| `OD-NOTIF-01` | Push Notification Infrastructure & Gateway | Mobile Architecture | Medium | **APPROVED** | OWNER | 2026-08-08 |
| `OD-FIN-01` | Customer Deposit Verification & Proof Method | Wallet & Finance | Critical | **APPROVED** | OWNER | 2026-08-08 |
| `OD-FIN-02` | Platform Commission Architecture | Business Model | High | **APPROVED** | OWNER | 2026-08-08 |
| `OD-FIN-03` | Deposit Bank Directory Accounts Selection | Financial Operations | High | **APPROVED** | OWNER | 2026-08-08 |
| `OD-CARD-01` | Internet Card Encryption & Storage Architecture | Security & Data | Critical | **APPROVED** | OWNER | 2026-08-08 |
| `OD-CARD-02` | Customer Card Dispute & Quarantine Window | Operations & Support | Medium | **APPROVED** | OWNER | 2026-08-08 |
| `OD-SETTLE-01` | Network Owner Settlement Payout Schedule | Finance & Operations | High | **APPROVED** | OWNER | 2026-08-08 |

---

## Decision Register Index (Remaining Open Decisions)

| Decision ID | Decision Title | Category | Impact Level | Status |
|---|---|---|---|---|
| `OD-AUTH-01` | SMS OTP Gateway Provider Selection | Auth & Infrastructure | High | `OPEN_DECISION` |
| `OD-PRIV-01` | User Data Retention & Anonymization Policy | Privacy & Governance | Medium | `OPEN_DECISION` |
| `OD-ARCH-01` | Administration Web Portal Technology Stack | Frontend Architecture | High | `OPEN_DECISION` |
| `OD-WALLET-01` | Wallet Balance Storage: Cached vs Real-Time Aggregation | Database Architecture | Critical | `OPEN_DECISION` |

---

## Approved Decision Specifications

### OD-NOTIF-01: Push Notification Infrastructure & Gateway — APPROVED

* **Decision:** Bind Firebase Cloud Messaging (FCM) as the V1 Android push transport.
* **Rationale:** Industry-standard, free-tier scalable, native Android background integration; aligns with README placeholder and avoids third-party subscription lock-in.
* **Approved By:** OWNER
* **Approved Date:** 2026-08-08
* **Implementation Binding:**
  * Existing provider-neutral notification adapter in Flutter/Supabase is retained.
  * FCM is bound as the V1 Android transport implementation via a server-side Edge Function adapter.
  * Flutter obtains and registers the FCM device token; token refresh and Android notification permission are handled client-side.
  * Backend token registry supports safe registration, logout/device unlink, and invalid token retirement.
  * Delivery responses are recorded; transient/permanent failures classified; bounded retries; idempotent dispatch; no duplicate domain event generation.
  * FCM server credentials remain server-side only; no service-account private key in Flutter or in repository.
* **Production Implications:** Physical pilot requires a real Firebase Android project configuration and server-side credentials deployed to the Edge Function secret configuration. Source/local E2E uses a fake/local transport adapter and does not require real FCM credentials.

---

### OD-FIN-01: Customer Deposit Verification & Proof Method — APPROVED

* **Decision:** Manual finance review for V1 deposit verification.
* **Rationale:** Zero banking API integration dependencies; removes the longest compliance/integration blocker from the V1 critical path while preserving an immutable, auditable approval flow.
* **Approved By:** OWNER
* **Approved Date:** 2026-08-08
* **Implementation Binding:**
  * Customer submits: amount, selected payment destination, transfer/reference identifier, and proof via the existing safe evidence/storage mechanism.
  * Finance officer reviews manually and approves or rejects.
  * Approval atomically credits the customer wallet exactly once using an idempotent ledger entry.
  * No automatic bank API integration is built or assumed for V1.
* **Production Implications:** Finance staffing must cover deposit review SLAs. Operational target remains < 15 minutes during business hours.

---

### OD-FIN-02: Platform Commission Architecture — APPROVED

* **Decision:** Default platform commission = 3.00% of successful purchase value.
* **Rationale:** Simple, mathematically transparent, scales linearly with revenue, and leaves a clear migration path to network-specific overrides without rewriting historical records.
* **Approved By:** OWNER
* **Approved Date:** 2026-08-08
* **Implementation Binding:**
  * Commission is computed server-side; client-provided commission values are never trusted.
  * Purchase record stores immutable snapshot: gross amount, commission rate snapshot, commission amount, owner net amount.
  * Deterministic currency rounding rules applied (half-even / banker's rounding or integer floor as documented in code).
  * Configuration architecture supports a future network-specific override without changing purchase domain contracts.
  * Commission cannot be set by customers, network operators, or network owners.
  * Historical purchases remain immutable when the central rate changes; refunds/accounting use the original snapshot.
* **Production Implications:** A central commission configuration row controls the default. Changing the default affects only new purchases; existing settlement lines and purchase records are never retroactively recalculated.

---

### OD-FIN-03: Deposit Bank Directory Accounts Selection — APPROVED

* **Decision:** Admin-managed payment destination directory.
* **Rationale:** Instant operational flexibility to add, update, reorder, or disable accounts without mobile app releases; eliminates hardcoded-account risk.
* **Approved By:** OWNER
* **Approved Date:** 2026-08-08
* **Implementation Binding:**
  * Directory supports: bank account, mobile wallet/payment account, and other explicitly supported manual transfer destinations.
  * Fields include only operationally necessary values: provider type, display name, account holder, account identifier/number, instructions, display ordering, active/inactive flag.
  * Customer sees active destinations and chooses one when creating a deposit request.
  * Admin/Finance can create, edit, activate/deactivate, and reorder.
  * Authorization is enforced server-side.
  * Existing deposits preserve a destination snapshot/reference even if the directory later changes.
  * No bank API integration in V1.
* **Production Implications:** Real provider accounts (Kuraimi, OneCash, Al-Amqi, Floosak, Al-Najm, etc.) must be configured through the admin directory before customers can select them. Provider names in earlier documents remain illustrative until configured.

---

### OD-CARD-01: Internet Card Encryption & Storage Architecture — APPROVED

* **Decision:** Server-side encrypted card vault using authenticated AES-256-GCM encryption.
* **Rationale:** Plaintext voucher/card secret is isolated from normal application tables and never exposed through client APIs, logs, audit events, or notifications; key versioning and a narrow provider boundary allow future migration to a managed KMS without domain contract changes.
* **Approved By:** OWNER
* **Approved Date:** 2026-08-08
* **Implementation Binding:**
  * Plaintext voucher/card secret is NEVER persisted in normal application tables, logs, audit events, Admin list APIs, push notifications, or Flutter source/assets.
  * Encrypted secret material persisted: ciphertext, unique nonce/IV, authentication tag, key_version, and non-secret card metadata.
  * Encryption master key / KEK remains outside the card data table and is obtained only from server-side environment/secret configuration.
  * Key is never returned to Flutter, never committed, and never hard-coded for production.
  * Web Crypto / authenticated encryption is used server-side.
  * For LOCAL tests only, a clearly `TEST_ONLY` generated key is used through ignored local environment configuration.
  * Key versioning is implemented from day one.
  * Boundary is designed so a future managed KMS can replace the secret provider without changing card/purchase domain contracts.
* **Production Implications:** A production encryption master key (or KMS configuration) must be provisioned server-side before card ingestion. Loss of the key is irrecoverable; backup/recovery procedures are out of V1 scope but must be documented before production go-live.

---

### OD-CARD-02: Customer Card Dispute & Quarantine Window — APPROVED

* **Decision:** Direct invalid-card dispute window = 30 minutes from first successful card reveal.
* **Rationale:** Short enough to materially reduce abuse after card consumption; long enough for a customer to test a freshly revealed card; server-time authoritative.
* **Approved By:** OWNER
* **Approved Date:** 2026-08-08
* **Implementation Binding:**
  * A purchased card can be decrypted/revealed only through an authenticated server-side operation after validating: authenticated user, purchase ownership, successful purchase, fulfillment/card assignment, reveal eligibility, and dispute/security state.
  * Reveal metadata is recorded without recording the secret itself.
  * Cross-user card reveal is prevented; direct ciphertext table access by customers is prevented.
  * `first_revealed_at` and `dispute_deadline` are stored; `dispute_deadline = first_revealed_at + 30 minutes`.
  * Server time is authoritative; client clock does not control eligibility.
  * Within 30 minutes: customer can open the dedicated invalid-card dispute path.
  * After 30 minutes: normal support ticket remains available, but automatic/direct refund eligibility is not assumed.
* **Production Implications:** Support workflow must prioritize invalid-card disputes within the 30-minute window. Settlement batches should exclude or hold purchases with open disputes until resolved.

---

### OD-SETTLE-01: Network Owner Settlement Payout Schedule — APPROVED

* **Decision:** Weekly settlement batch with finance review/approval in V1; no automatic bank payout.
* **Rationale:** Predictable cash flow and administrative schedule; keeps payout execution manual in V1 to avoid production banking automation risk while preserving immutable accounting.
* **Approved By:** OWNER
* **Approved Date:** 2026-08-08
* **Implementation Binding:**
  * Settlement accounting: eligible successful sales MINUS platform commission MINUS completed refunds PLUS/MINUS approved accounting adjustments = owner net settlement.
  * Settlement batches require finance review/approval in V1.
  * No automatic bank payout is built.
  * Immutable settlement snapshots and line references are stored.
  * Batch lifecycle supports at minimum: `draft`, `ready_for_review`, `approved`, `paid`/`manual_external_confirmation`, `cancelled`/`corrected`.
* **Production Implications:** Finance must run and approve batches weekly. Actual payout remains an external manual process recorded via batch status transition.

---

## Open Decision Specifications (Unchanged)

### 1. OD-AUTH-01: SMS OTP Gateway Provider Selection

* **Context:** The README mentions "ALAWAEL SMS API (later)", but the codebase currently relies on Supabase Auth default OTP handling without explicit Yemeni SMS gateway credentials configured.
* **Options:**
  * **Option A:** Direct Integration with ALAWAEL SMS API via custom Supabase Edge Function / Webhook.
  * **Option B:** Twilio / Sms77 international SMS gateway via native Supabase Auth provider integration.
  * **Option C:** Dual-provider approach (ALAWAEL as primary for local Yemen networks, WhatsApp OTP via official API as fallback).
* **Advantages & Risks:**
  * *Option A:* Lower cost per SMS in Yemen; high deliverability on Yemen Mobile/MTN/Sabafon. Risk: Requires custom Edge Function code and API retry maintenance.
  * *Option B:* Turnkey setup in Supabase dashboard. Risk: High cost per SMS to Yemen; potential carrier blocking of international SMS routes.
  * *Option C:* Highest deliverability and user convenience. Risk: Added API complexity and dual subscription costs.
* **Operational Impact:** Directly affects user onboarding conversion, login reliability, and monthly operational telecommunications expenditure.
* **PROVISIONAL_RECOMMENDATION:** **Option A (ALAWAEL SMS API)** for V1 launch due to cost efficiency and local carrier reliability, with Option C as a V2 enhancement.

---

### 2. OD-PRIV-01: User Data Retention & Account Anonymization Policy (NY-PRODUCT-001F)

* **Context:** Data retention duration is unconfirmed by official legal references and is registered as `OPEN_DECISION`.
* **Options:**
  * **Option A:** 5-Year Financial Record Retention with Immediate Profile Anonymization upon Account Deletion (`PROVISIONAL_RECOMMENDATION`).
  * **Option B:** Indefinite Retention of all activity logs for fraud monitoring.
  * **Option C:** 1-Year Retention followed by hard purging of completed transaction logs.
* **Advantages & Risks:**
  * *Option A:* Aligns with standard financial auditing practices while respecting user privacy deletion rights. Risk: Requires automated data scrubbing cron tasks.
  * *Option B:* Maximum historical forensic capability. Risk: Privacy non-compliance and unnecessary database storage growth.
  * *Option C:* Low storage footprint. Risk: Insufficient historical records for long-term dispute or tax auditing.
* **Operational Impact:** Controls database growth, backup storage sizes, and privacy compliance posture.
* **PROVISIONAL_RECOMMENDATION:** **Option A (5-Year Financial Retention + Instant Profile Anonymization)**. Financial history is preserved; PII is anonymized upon account deletion. Hard deletion of ledger entries is forbidden.

---

### 3. OD-ARCH-01: Administration Web Portal Technology Stack

* **Context:** The README lists "Lovable (Web)" as a placeholder, but audit confirmed no Web application code exists.
* **Options:**
  * **Option 1:** React + Vite + TailwindCSS + Shadcn UI (SPA architecture).
  * **Option 2:** Next.js App Router (SSG/SSR web framework).
  * **Option 3:** Flutter Web compiled from main repository.
* **Advantages & Risks:**
  * *Option 1:* Ultra-fast development, lightweight bundle, clean separation of concerns, native Supabase JS client compatibility. Risk: None for internal admin dashboards.
  * *Option 2:* SSR capabilities. Risk: Over-complex infrastructure for an authenticated operational back-office portal.
  * *Option 3:* Code sharing with mobile app. Risk: Large bundle size, poor accessibility, sluggish desktop table UX (confirmed by audit as bad choice).
* **Operational Impact:** Dictates admin portal performance, development speed, and deployment architecture.
* **PROVISIONAL_RECOMMENDATION:** **Option 1 (React + Vite + TailwindCSS + Shadcn UI)** for maximum back-office responsiveness and rapid component development.

---

### 4. OD-WALLET-01: Wallet Balance Storage: Cached vs Real-Time Aggregation

* **Context:** Prototype model `user_model.dart` contains `walletBalance` field, while financial best practices mandate append-only ledger entries.
* **Options:**
  * **Option A:** Cached `wallet_balance` integer column on `users` table, updated strictly via trusted PostgreSQL database triggers on `wallet_ledger_entries`.
  * **Option B:** Pure Real-Time Aggregation (`SELECT SUM(amount) FROM wallet_ledger_entries WHERE user_id = ...`) executed on every query.
* **Advantages & Risks:**
  * *Option A:* Sub-millisecond reads for UI display and purchase validation; low database CPU overhead. Risk: Requires strict trigger sync integrity.
  * *Option B:* Mathematically impossible for cache drift to occur. Risk: High CPU and I/O overhead on high-frequency transactions.
* **Operational Impact:** Directly affects purchase RPC speed and database scaling performance.
* **PROVISIONAL_RECOMMENDATION:** **Option A (Cached Column updated via Database Trigger)** backed by a daily automated ledger balance reconciliation audit script.

---

## Change Log

| Date | Change | Author |
|---|---|---|
| 2026-08-08 | Owner approved OD-NOTIF-01, OD-FIN-01, OD-FIN-02, OD-FIN-03, OD-CARD-01, OD-CARD-02, OD-SETTLE-01; documented binding and production implications. | OWNER / Release Candidate Binding |
