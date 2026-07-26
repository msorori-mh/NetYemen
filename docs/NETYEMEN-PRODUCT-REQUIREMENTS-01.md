# NETYEMEN PRODUCT REQUIREMENTS SPECIFICATION (V1.0)

**Task ID:** NY-PRODUCT-001  
**Document Code:** `NETYEMEN-PRODUCT-REQUIREMENTS-01.md`  
**Classification:** `PROPOSED_CONTRACT`  
**Target Platform:** NetYemen Platform (Customer Mobile, Network Owner Mobile, Administration Web)  
**Status:** Approved for Design Baseline  

---

## 1. Executive Summary & Current-State Audit Inventory

This document defines the product baseline and requirements for **NetYemen**, a digital marketplace and wallet platform designed to connect Wi-Fi local network owners in Yemen with retail customers purchasing internet scratch cards.

Based on the forensic audit of the existing codebase (`VERIFIED_CURRENT_STATE`), the repository currently contains a prototype Flutter customer mobile application. The audit established that the codebase is non-functional in its current un-restored baseline and lacks all database artifacts, administrative web apps, network owner management surfaces, and formal security contracts.

### 1.1 Verified Current-State Inventory Matrix

| Feature / Artifact Area | Current Repository Implementation State | Audit Status | Required V1 Contract Classification |
|---|---|---|---|
| **Phone Authentication & OTP** | `signInWithPhone` & `verifyOTP` present in `SupabaseService`; direct upsert to `users` table post-login | `VERIFIED_CURRENT_STATE` (Incomplete) | `PROPOSED_CONTRACT` (Require DB Trigger & SMS gateway integration) |
| **Network Discovery** | `getNetworks()` fetches active networks; governorate filter UI present | `VERIFIED_CURRENT_STATE` (Partial) | `PROPOSED_CONTRACT` (Dynamic search query integration & geolocation support) |
| **Network Details & Prices** | Static hardcoded price buttons `[200, 500, 1000, 5000]` in UI; `getNetworkPrices` exists in service | `VERIFIED_CURRENT_STATE` (Buggy) | `PROPOSED_CONTRACT` (Dynamic server-driven `network_prices` rendering) |
| **Atomic Card Purchase** | UI invokes `purchase_card` RPC with client-supplied `userId` and denomination | `VERIFIED_CURRENT_STATE` (Security risk) | `PROPOSED_CONTRACT` (Atomic RPC with implicit `auth.uid()`, balance check & locking) |
| **Card Reveal & Copy** | Plaintext card reveal in UI (`purchases_screen.dart`); copy to clipboard supported | `VERIFIED_CURRENT_STATE` | `PROPOSED_CONTRACT` (Strict Purchaser-Only RLS & reveal audit logging) |
| **Wallet Deposit Request** | Simple form in `deposit_screen.dart` inserting into `wallet_deposit_requests` | `VERIFIED_CURRENT_STATE` (Basic) | `PROPOSED_CONTRACT` (Include payment receipt image upload & admin review workflow) |
| **Network Owner Surface** | Absent from repository | `VERIFIED_CURRENT_STATE` (Missing) | `PROPOSED_CONTRACT` (Dedicated Owner Mobile Application) |
| **Administration Web Surface** | Absent from repository | `VERIFIED_CURRENT_STATE` (Missing) | `PROPOSED_CONTRACT` (Dedicated React/Vite Admin Web Portal) |
| **Database Schema & RLS** | `sql/netyemen_schema_fixed.sql` missing from version control | `VERIFIED_CURRENT_STATE` (Missing) | `PROPOSED_CONTRACT` (Supabase Postgres Schema with strict RLS) |
| **Audit & Governance** | No audit tables, ledger tables, or security tracking | `VERIFIED_CURRENT_STATE` (Missing) | `PROPOSED_CONTRACT` (Immutable append-only ledger & audit log) |

---

## 2. Product Purpose & Target User Persona Architecture

NetYemen functions as a secure, low-bandwidth, Arabic-first mobile marketplace facilitating digital Wi-Fi card distribution across Yemeni governorates.

```
+-----------------------------------------------------------------------------------+
|                                 NETYEMEN PLATFORM                                 |
+-----------------------------------------------------------------------------------+
                                          |
     +------------------------------------+------------------------------------+
     |                                    |                                    |
     v                                    v                                    v
+-----------------------+    +-----------------------+    +-----------------------+
|  CUSTOMER ANDROID APP |    |   OWNER ANDROID APP   |    |  ADMINISTRATION WEB   |
| (Retail Card Buyers)  |    | (Local Wi-Fi Vendors) |    | (Finance & Ops Team)  |
+-----------------------+    +-----------------------+    +-----------------------+
```

### 2.1 Ecosystem Participants

1. **Customers (Card Purchasers):** Individual users in Yemen who connect to local community Wi-Fi networks and require rapid, reliable purchase of network access cards using prepaid wallet balances.
2. **Network Owners & Operators:** Local Wi-Fi network proprietors who manage hotspot infrastructure, set card pricing/denominations, upload card batches, and receive periodic financial payouts.
3. **Platform Finance & Support Personnel:** NetYemen administrative staff responsible for approving owner onboarding, reviewing wallet deposit payment proofs, handling card disputes/refunds, executing owner payouts, and monitoring system integrity.
4. **System Auditors & Administrators:** Operations leads managing security settings, platform role assignments, dispute escalation, and regulatory compliance.

---

## 3. V1 Product Surfaces Requirements

### 3.1 Surface 1: Customer Android Mobile Application

`PROPOSED_CONTRACT` — Primary mobile channel for retail customers.

* **F-CUST-01: Phone Authentication & OTP:**
  * Support Yemen mobile numbers (`+967` prefix; 9-digit local numbers starting with `77`, `78`, `73`, `71`, or `70`).
  * 6-digit OTP verification with 60-second resend cooldown timer and 5-minute expiration.
  * Backend database trigger (`on auth.users create`) automatically initializes `users` profile with `wallet_balance = 0`.
* **F-CUST-02: User Profile Management:**
  * Capture user full name, default governorate, city, and optional district preference.
  * View current wallet balance and account status (`active`, `suspended`).
* **F-CUST-03: Network Discovery & Search:**
  * Browse active, approved networks filtered by Governorate and City.
  * Search networks by name, SSID, or locality with dynamic debounced client query.
  * Display network status (Online/Active), customer service contact numbers, and optional map location coordinates.
* **F-CUST-04: Dynamic Card Pricing & Denominations:**
  * Fetch real-time active price tiers (`network_prices`) per network.
  * Display card denomination (e.g., 500 YER, 1,000 YER, 2,000 YER, 5,000 YER) alongside selling price and stock availability indicator (In Stock / Out of Stock).
* **F-CUST-05: Prepaid Customer Wallet:**
  * Display immutable closing wallet balance calculated from valid ledger entries.
  * Render transaction history (Deposits, Card Purchases, Refund Credits, Adjustments).
  * Request wallet deposit by selecting payment channel (e.g., Kuraimi, OneCash, Al-Amqi, Floosak), entering transaction reference number, and uploading receipt screenshot image.
* **F-CUST-06: Atomic Card Purchase & Reveal Contract:**
  * Require explicit purchase confirmation modal displaying network name, card denomination, and wallet deduction amount.
  * Execute atomic `purchase_card` RPC transaction ensuring zero race conditions on the last available card in stock.
  * Upon transaction success, immediately display complete card number in plaintext with a one-tap "Copy Card Number" action.
  * Provide direct button to launch local Wi-Fi Hotspot login page if configured by the network.
* **F-CUST-07: Purchase History & Card Storage:**
  * Persistent purchase history listing all historically acquired cards.
  * Mask card numbers in list views (`12****89`); allow purchaser to tap to reveal/copy.
  * Filter purchases by date, network, or card status.
* **F-CUST-08: Support & Card Complaints:**
  * Submit card complaint (e.g., "Card already used", "Invalid PIN") within 24 hours of purchase.
  * Attach dispute explanation; track ticket resolution status.
* **F-CUST-09: Account Lifecycle & Notifications:**
  * Receive push notifications for deposit approvals, purchase confirmations, and support responses.
  * Secure logout clearing local session and tokens.
  * Request account suspension or formal closure.

---

### 3.2 Surface 2: Network Owner Android Mobile Application

`PROPOSED_CONTRACT` — Operations mobile app for Wi-Fi network owners and delegated operators.

* **F-OWN-01: Owner Registration & Identity Verification:**
  * Owner account registration requiring commercial identity details, network business name, and identity document upload.
  * Application state held in `pending_verification` until Platform Admin approval.
* **F-OWN-02: Network Profile & Location Management:**
  * Configure network name, broadcast SSIDs, operating governorate, city, district, and contact numbers.
  * Set geographic location (latitude/longitude) for network discovery.
* **F-OWN-03: Denomination & Price Catalog:**
  * Define available card denominations and retail selling prices.
  * Enable or disable specific price tiers based on inventory availability.
* **F-OWN-04: Secure Card Batch Upload & Import Validation:**
  * Import internet card batches via text paste or CSV file.
  * Mandatory pre-import validation: inspect file for duplicate card numbers against existing database inventory.
  * Quarantine invalid or duplicate lines prior to database commit.
  * Render batch import summary (Total lines, Valid cards imported, Duplicates rejected).
* **F-OWN-05: Real-Time Inventory Control:**
  * Dashboard displaying total stock count broken down by status: `available`, `sold`, `quarantined`, `invalid`, `cancelled`.
  * Ability to manual quarantine or void specific unsold card inventory.
* **F-OWN-06: Sales Analytics & Settlement Reporting:**
  * Daily, weekly, and monthly sales volume and revenue summaries.
  * View net payable balances post platform commission deduction.
  * View historical payout settlement records and payment vouchers.
* **F-OWN-07: Operator Staff Delegation:**
  * Owner can invite secondary `NETWORK_OPERATOR` accounts with restricted permissions (e.g., card upload allowed, settlement payout view denied).

---

### 3.3 Surface 3: Administration & Finance Web Application

`PROPOSED_CONTRACT` — Operations web portal built using modern Web technology (React/Vite) for internal platform management.

* **F-ADM-01: Administrative Authentication & RBAC:**
  * Multi-factor administrative login for platform personnel.
  * Strict role assignment (`FINANCE_OFFICER`, `SUPPORT_AGENT`, `PLATFORM_ADMIN`, `SYSTEM_AUDITOR`).
* **F-ADM-02: Owner & Network Verification Approval:**
  * Queue for reviewing submitted network owner verification documents.
  * Approve or reject network submissions with explicit rejection reason log.
* **F-ADM-03: Wallet Deposit Verification Queue:**
  * Review pending customer deposit requests, uploaded payment receipts, and bank reference numbers.
  * Approve deposit (automatically triggering wallet credit ledger entry) or reject deposit with customer notification.
* **F-ADM-04: Purchase Monitoring & Anomaly Detection:**
  * Real-time stream of platform purchases, velocity monitoring, and high-frequency purchase alerts.
* **F-ADM-05: Refund & Dispute Processing:**
  * Review customer card complaints; verify card validity with network owner.
  * Approve refund (triggering compensating wallet credit ledger entry and card quarantine) or reject complaint.
* **F-ADM-06: Network Owner Settlement Processing:**
  * Calculate eligible net settlement amounts for network owners.
  * Generate settlement vouchers, record payout bank reference, and transition settlement state to `paid`.
* **F-ADM-07: User & Network Suspension Controls:**
  * Instantly suspend compromised customer accounts or fraudulent network owners, invalidating active sessions.
* **F-ADM-08: Audit Log & Financial Ledger Inspector:**
  * Read-only interface to query immutable platform audit logs and system financial balance ledger.

---

## 4. Explicit V1 Exclusions & Scope Boundaries

To guarantee security, architectural stability, and rapid execution, the following features are explicitly categorized:

### 4.1 Out of Scope for V1 (`OUT_OF_SCOPE_V1`)

1. **Flutter Web Administration Portal:** Admin portal will be built as a standalone React/Vite web application, not compiled from Flutter Web codebase.
2. **Direct Telecom / Mobile Money API Integration:** Wallet deposits will rely on manual receipt upload and administrative verification queue rather than automated bank API callbacks in V1.
3. **Multi-Country / Currency Operations:** V1 is strictly restricted to Yemeni network cards and Yemeni Rial (YER) financial accounting.
4. **Offline Card Purchases:** Customer app requires active internet connectivity to execute atomic card purchases via backend RPC.

### 4.2 Deferred Post-Launch (`DEFERRED_POST_LAUNCH`)

1. **iOS Customer & Owner Applications:** iOS release builds and App Store submission are deferred until Android market launch stabilizes.
2. **Automated OCR Receipt Scanning:** Automated image text recognition for deposit receipt processing deferred to V2.
3. **In-App Live Chat Support:** Customer support in V1 relies on ticket submission and WhatsApp integration rather than real-time custom socket chat.

### 4.3 Strictly Forbidden Features (`FORBIDDEN_BEHAVIOR`)

1. **Negative Wallet Balances:** Wallet balances must never drop below 0 under any circumstance.
2. **Direct Database Wallet Balance Updates:** Updating `wallet_balance` via `UPDATE users SET wallet_balance = ...` is strictly forbidden; balance MUST derive from append-only ledger entries.
3. **Public Marketplace Unverified Selling:** Unverified network owners cannot list or sell cards on the platform.
4. **Manual Modification of Financial Ledger:** Deleting or editing completed ledger rows or audit logs is impossible by schema design and RLS.
5. **Plaintext Card Number Exposure to Uninvolved Parties:** Network owners cannot view full card numbers once sold; third-party customers cannot view cards belonging to other users.

---

## 5. Nonfunctional Requirements (NFR)

```
+-----------------------------------------------------------------------------------+
|                            NONFUNCTIONAL REQUIREMENTS                             |
+-----------------------------------------------------------------------------------+
|  1. Arabic-First RTL Layout & Typography (Cairo / Tajawal / Inter)                |
|  2. Yemen Phone Standard (+967 7X XXX XXXX Normalization)                        |
|  3. Resilient Connectivity (Network Retries, Exponential Backoff, Idempotency)    |
|  4. Strict Transactional Integrity (ACID Purchase RPC & Row Locking)             |
|  5. Auditability & Immutable Event Logs (Append-only Ledger & Security Logs)      |
+-----------------------------------------------------------------------------------+
```

### 5.1 Arabic-First RTL Interface
* Native Right-to-Left (RTL) layout enforcement across all Flutter mobile screens and React web portals.
* Primary typography using Google Fonts `Cairo` or `Tajawal` for Arabic text and `Inter` for numeric/code displays.

### 5.2 Yemen Mobile Telecommunications Standards
* Strict normalization of all phone numbers to E.164 standard format (`+9677XXXXXXXX`).
* Support for all Yemeni telecom operators: Yemen Mobile (`77`, `78`), You/MTN (`73`), Sabafon (`71`), Y-Telecom (`70`).

### 5.3 Low-Bandwidth & Network Resilience
* Designed for 2G/3G network conditions prevalent in Yemen.
* Request payload minimization (< 10 KB per API transaction).
* Automated client-side HTTP retry with exponential backoff for read operations.
* Idempotency header / key required for all financial and mutation RPC requests to prevent double submission during network drops.

### 5.4 Performance & Availability Targets
* Atomic card purchase RPC execution latency: `< 800ms` at 95th percentile database execution.
* Mobile app screen cold start time: `< 2.0s` on standard Android hardware.
* Availability SLA: 99.5% uptime for card purchase API endpoints.

### 5.5 Data Minimization & Privacy
* No collection of sensitive personal telemetry beyond phone number, full name, locality, and device push token.
* Plaintext card numbers stored encrypted at rest using database column-level encryption or vault storage.

---

## 6. Document Governance & Traceability

| Requirement Item | Primary Verification Method | Traceability Matrix Target |
|---|---|---|
| Customer Authentication | Automated Integration Test | `TEST-AUTH-001`, `TEST-AUTH-002` |
| Atomic Purchase RPC | Database Stress & Concurrency Test | `TEST-CONCURRENCY-001` |
| Zero Negative Wallet | Financial Ledger Invariant Audit | `TEST-WALLET-001` |
| Data Isolation (RLS) | Security RLS Penetration Suite | `TEST-AUTHORIZATION-001` |
