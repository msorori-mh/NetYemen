# NETYEMEN OPEN DECISION REGISTER (V1.0)

**Task ID:** NY-PRODUCT-001  
**Document Code:** `NETYEMEN-DECISION-REGISTER-01.md`  
**Classification:** `OPEN_DECISION`  
**Status:** Provisional Recommendations Recorded for Architecture & Governance Review  

---

## Executive Overview

Where business rules or technical parameters cannot be definitively established from the existing repository prototype (`VERIFIED_CURRENT_STATE`), they are formally registered as `OPEN_DECISION`. Each decision presents 2–4 realistic operational options, evaluates advantages and risks, assesses operational/technical impact, and provides a clearly labeled `PROVISIONAL_RECOMMENDATION`.

---

## Decision Register Index

| Decision ID | Decision Title | Category | Impact Level | Status |
|---|---|---|---|---|
| `OD-AUTH-01` | SMS OTP Gateway Provider Selection | Auth & Infrastructure | High | `OPEN_DECISION` |
| `OD-FIN-01` | Customer Deposit Verification & Proof Method | Wallet & Finance | Critical | `OPEN_DECISION` |
| `OD-FIN-02` | Platform Commission Architecture | Business Model | High | `OPEN_DECISION` |
| `OD-CARD-01` | Internet Card Encryption & Storage Architecture | Security & Data | Critical | `OPEN_DECISION` |
| `OD-CARD-02` | Customer Card Dispute & Quarantine Window | Operations & Support | Medium | `OPEN_DECISION` |
| `OD-SETTLE-01` | Network Owner Settlement Payout Schedule | Finance & Operations | High | `OPEN_DECISION` |
| `OD-PRIV-01` | User Data Retention & Account Anonymization Policy | Privacy & Governance | Medium | `OPEN_DECISION` |
| `OD-ARCH-01` | Administration Web Portal Technology Stack | Frontend Architecture | High | `OPEN_DECISION` |
| `OD-WALLET-01` | Wallet Balance Storage: Cached vs Real-Time Aggregation | Database Architecture | Critical | `OPEN_DECISION` |
| `OD-NOTIF-01` | Push Notification Infrastructure & Gateway | Mobile Architecture | Medium | `OPEN_DECISION` |

---

## Detailed Decision Specifications

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

### 2. OD-FIN-01: Customer Deposit Verification & Proof Method

* **Context:** The prototype includes `wallet_deposit_requests` with `payment_method` and `amount`, but lacks automated banking API links.
* **Options:**
  * **Option 1:** Manual Verification Queue — Customer uploads receipt screenshot and reference number; Finance Officer verifies in bank portal and approves manually.
  * **Option 2:** Semi-Automated OCR — Uploaded receipt screenshot is parsed by OCR service to extract reference number and amount for automated comparison, requiring manual approval only on mismatch.
  * **Option 3:** Direct API Integration with Yemeni Financial Institutions (Kuraimi / OneCash API).
* **Advantages & Risks:**
  * *Option 1:* Zero financial institution integration dependencies; zero API integration risk. Risk: Operational bottleneck during peak deposit hours.
  * *Option 2:* Reduces manual review workload by 70%. Risk: Image quality variations in Yemen leading to false negatives.
  * *Option 3:* Real-time instant wallet credit. Risk: Complex institutional approvals, long integration lead times, high compliance barrier.
* **Operational Impact:** Determines initial finance staffing requirements and deposit processing turnaround time (Target: < 15 minutes).
* **PROVISIONAL_RECOMMENDATION:** **Option 1 (Manual Verification Queue)** for V1 launch to achieve rapid market deployment without banking API blockers, transitioning to Option 2 in post-launch phase.

---

### 3. OD-FIN-02: Platform Commission Architecture

* **Context:** Code models track `price` and `denomination`, but no platform commission calculation logic exists in current codebase.
* **Options:**
  * **Option A:** Flat Percentage Commission (e.g., 5% retained by platform on every card purchase).
  * **Option B:** Tiered Fixed Fee per Card Denomination (e.g., 20 YER on 500 YER card, 50 YER on 1,000 YER card).
  * **Option C:** Owner Subscription Fee + 2% Low Margin Commission.
* **Advantages & Risks:**
  * *Option A:* Simple calculation; scales linearly with revenue. Risk: High denomination cards incur higher nominal platform fee.
  * *Option B:* Predictable costs for network owners. Risk: Requires ongoing maintenance of commission tier lookup tables.
  * *Option C:* Attractive for large network owners. Risk: Higher barrier to entry for small neighborhood hotspot owners.
* **Operational Impact:** Core business model driver affecting owner margin and platform profitability.
* **PROVISIONAL_RECOMMENDATION:** **Option A (Flat Percentage Commission - 5%)** for simplicity, mathematical clarity, and automated settlement calculations.

---

### 4. OD-CARD-01: Internet Card Encryption & Storage Architecture

* **Context:** Current prototype stores `card_number` in plaintext in `cards` table model.
* **Options:**
  * **Option 1:** PostgreSQL Column Encryption via `pgcrypto` using a database master key.
  * **Option 2:** Vault Storage / KMS Encryption managed outside main table space, releasing plaintext only via specific RPC execution.
  * **Option 3:** Application-level AES-256 encryption before inserting into Supabase tables.
* **Advantages & Risks:**
  * *Option 1:* Built natively into Supabase PostgreSQL; straightforward SQL RPC decryption during purchase. Risk: Key management within database context.
  * *Option 2:* Maximum security isolation; database leak does not expose plaintext cards. Risk: Latency penalty during bulk card batch imports.
  * *Option 3:* Plaintext cards never touch database unencrypted. Risk: Client key distribution and rotation complexity across mobile apps.
* **Operational Impact:** Critical security control mitigating `SEC-01` and preventing unauthorized card inventory theft.
* **PROVISIONAL_RECOMMENDATION:** **Option 1 (pgcrypto Column-Level Encryption)** within Supabase, decrypted exclusively inside the security-definer `purchase_card` RPC function for the verified buyer.

---

### 5. OD-CARD-02: Customer Card Dispute & Quarantine Window

* **Context:** No dispute window timeframe is defined in existing code.
* **Options:**
  * **Option A:** 12-Hour Strict Dispute Window post-purchase.
  * **Option B:** 24-Hour Standard Dispute Window post-purchase.
  * **Option C:** 48-Hour Extended Dispute Window post-purchase.
* **Advantages & Risks:**
  * *Option A:* Limits owner payout holds; minimizes fraudulent complaint attempts after using card internet volume. Risk: Customer may not test card immediately.
  * *Option B:* Balanced protection for both customer and network owner. Risk: Standard operational workload for support.
  * *Option C:* Maximum customer satisfaction. Risk: High exposure to abuse by customers consuming card quota then filing fake complaints.
* **Operational Impact:** Governs settlement hold duration and support ticket SLA requirements.
* **PROVISIONAL_RECOMMENDATION:** **Option B (24-Hour Standard Dispute Window)** with mandatory requirement for customer to specify failure reason.

---

### 6. OD-SETTLE-01: Network Owner Settlement Payout Schedule

* **Context:** Owner payout frequency is un-specified in current repository.
* **Options:**
  * **Option 1:** Fixed Weekly Automated Settlement Batch (e.g., Every Sunday).
  * **Option 2:** Threshold-Triggered Settlement (e.g., Automatic voucher generation when net payable reaches 25,000 YER).
  * **Option 3:** Manual Owner Payout Request (Owner requests payout via app; processed within 48 business hours).
* **Advantages & Risks:**
  * *Option 1:* Highly predictable cash flow and administrative processing schedule. Risk: Small owners may wait up to 7 days.
  * *Option 2:* Favorable for high-volume network owners. Risk: Variable workload for finance staff.
  * *Option 3:* Flexible for owners. Risk: Spikes in payout requests causing finance operational overload.
* **Operational Impact:** Directly impacts platform liquidity management and finance officer operational workflows.
* **PROVISIONAL_RECOMMENDATION:** **Option 1 (Weekly Settlement Batch)** combined with a minimum payout threshold of 10,000 YER.

---

### 7. OD-PRIV-01: User Data Retention & Account Anonymization Policy

* **Context:** No data retention policy exists in codebase or documentation.
* **Options:**
  * **Option A:** 5-Year Financial Record Retention with Immediate Profile Anonymization upon Account Deletion.
  * **Option B:** Indefinite Retention of all activity logs for fraud monitoring.
  * **Option C:** 1-Year Retention followed by hard purging of completed transaction logs.
* **Advantages & Risks:**
  * *Option A:* Fully compliant with standard financial auditing practices while respecting user privacy deletion rights. Risk: Requires automated data scrubbing cron tasks.
  * *Option B:* Maximum historical forensic capability. Risk: Privacy non-compliance and unnecessary database storage growth.
  * *Option C:* Low storage footprint. Risk: Violates Yemeni commercial record-keeping norms for tax and audit compliance.
* **Operational Impact:** Controls database growth, backup storage sizes, and privacy compliance posture.
* **PROVISIONAL_RECOMMENDATION:** **Option A (5-Year Financial Retention with Instant Profile Anonymization)**.

---

### 8. OD-ARCH-01: Administration Web Portal Technology Stack

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

### 9. OD-WALLET-01: Wallet Balance Storage: Cached vs Real-Time Aggregation

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

### 10. OD-NOTIF-01: Push Notification Infrastructure & Gateway

* **Context:** README notes "Firebase Cloud Messaging (later)", but no notification setup exists in code.
* **Options:**
  * **Option 1:** Firebase Cloud Messaging (FCM) integrated directly via Supabase Database Webhooks & Edge Functions.
  * **Option 2:** OneSignal Push Notification Platform.
  * **Option 3:** Local in-app polling without external push gateway in V1.
* **Advantages & Risks:**
  * *Option 1:* Industry standard, free tier scalability, native Android background integration. Risk: Requires FCM service account key setup in Edge Functions.
  * *Option 2:* Turnkey web dashboard and push segmentation. Risk: External third-party SDK dependency and subscription cost.
  * *Option 3:* Zero external dependencies. Risk: Poor user experience for deposit approvals and card complaint updates.
* **Operational Impact:** Essential for user engagement, instant deposit approval alerts, and purchase verification receipts.
* **PROVISIONAL_RECOMMENDATION:** **Option 1 (Firebase Cloud Messaging via Supabase Edge Functions)**.
