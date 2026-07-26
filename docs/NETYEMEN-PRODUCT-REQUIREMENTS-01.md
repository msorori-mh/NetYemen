# NETYEMEN PRODUCT REQUIREMENTS SPECIFICATION (V1.0 + V1.1 ENHANCEMENTS)

**Task ID:** NY-PRODUCT-001  
**Document Code:** `NETYEMEN-PRODUCT-REQUIREMENTS-01.md`  
**Classification:** `PROPOSED_CONTRACT`  
**Target Platform:** NetYemen Platform (Customer Mobile, Network Owner Mobile, Administration Web)  
**Status:** Approved for Design Baseline (Updated with NY-PRODUCT-001E Competitor & Discovery Specs)  

---

## 1. Executive Summary & Current-State Audit Inventory

This document defines the product baseline and requirements for **NetYemen**, a digital marketplace and wallet platform designed to connect Wi-Fi local network owners in Yemen with retail customers purchasing internet scratch cards.

Based on the forensic audit of the existing codebase (`VERIFIED_CURRENT_STATE`), the repository currently contains a prototype Flutter customer mobile application. The audit established that the codebase is non-functional in its current un-restored baseline and lacks all database artifacts, administrative web apps, network owner management surfaces, and formal security contracts.

### 1.1 Verified Current-State Inventory Matrix

| Feature / Artifact Area | Current Repository Implementation State | Audit Status | Required V1 Contract Classification |
|---|---|---|---|
| **Phone Authentication & OTP** | `signInWithPhone` & `verifyOTP` present in `SupabaseService`; direct upsert to `users` table post-login | `VERIFIED_CURRENT_STATE` (Incomplete) | `PROPOSED_CONTRACT` (Require DB Trigger & SMS gateway integration) |
| **Network Discovery** | `getNetworks()` fetches active networks; governorate filter UI present | `VERIFIED_CURRENT_STATE` (Partial) | `PROPOSED_CONTRACT` (Dynamic search query integration, nearby Wi-Fi scan & geolocation support) |
| **Network Details & Prices** | Static hardcoded price buttons `[200, 500, 1000, 5000]` in UI; `getNetworkPrices` exists in service | `VERIFIED_CURRENT_STATE` (Buggy) | `PROPOSED_CONTRACT` (Dynamic server-driven `network_prices` rendering with package GB/validity metadata) |
| **Atomic Card Purchase** | UI invokes `purchase_card` RPC with client-supplied `userId` and denomination | `VERIFIED_CURRENT_STATE` (Security risk) | `PROPOSED_CONTRACT` (Atomic RPC with implicit `auth.uid()`, balance check & secure last-card locking) |
| **Card Reveal & Copy** | Plaintext card reveal in UI (`purchases_screen.dart`); copy to clipboard supported | `VERIFIED_CURRENT_STATE` | `PROPOSED_CONTRACT` (Strict Purchaser-Only RLS & reveal audit logging) |
| **Wallet Deposit Request** | Simple form in `deposit_screen.dart` inserting into `wallet_deposit_requests` | `VERIFIED_CURRENT_STATE` (Basic) | `PROPOSED_CONTRACT` (Include payment receipt image upload, bank directory & admin status review workflow) |
| **Network Owner Surface** | Absent from repository | `VERIFIED_CURRENT_STATE` (Missing) | `PROPOSED_CONTRACT` (Dedicated Owner Mobile Application with Multi-SSID mapping) |
| **Administration Web Surface** | Absent from repository | `VERIFIED_CURRENT_STATE` (Missing) | `PROPOSED_CONTRACT` (Dedicated React/Vite Admin Web Portal with Lead Queue & Bank Directory management) |
| **Database Schema & RLS** | `sql/netyemen_schema_fixed.sql` missing from version control | `VERIFIED_CURRENT_STATE` (Missing) | `PROPOSED_CONTRACT` (Supabase Postgres Schema with strict RLS) |
| **Audit & Governance** | No audit tables, ledger tables, or security tracking | `VERIFIED_CURRENT_STATE` (Missing) | `PROPOSED_CONTRACT` (Immutable append-only ledger & audit log) |

---

### 1.2 Competitor Benchmarking & Strategic Positioning Analysis

An extensive forensic product benchmark was conducted against existing local Yemeni Wi-Fi card applications and digital payment platforms (Competitor A & Competitor B):

| Feature Benchmark Area | Competitor A (Legacy Local App) | Competitor B (Regional Market App) | NetYemen Proposed V1 Architecture |
|---|---|---|---|
| **Wallet Account & Visible Balance** | Static balance string; manual sync | Visible real-time ledger balance | Immutable cached `wallet_balance` synced via append-only triggers |
| **In-App Deposit Request** | Plain SMS text reference | In-app form with receipt image upload | In-app deposit request + high-res receipt screenshot + bank ref validation |
| **Deposit Status Tracking** | None (User checks balance later) | Basic status text (`pending`/`approved`) | Full lifecycle tracking (`pending` -> `under_review` -> `approved`/`rejected`) + reason log |
| **Bank & Exchange Directory** | Static text pinned in social media | Static in-app list | Dynamic, admin-managed Bank Directory UI (Kuraimi, OneCash, Al-Amqi, Floosak, Al-Najm) |
| **Verified Account Badges** | None | Basic checkmark icon | Strict Owner Identity Verification + Verified Network Shield Badges |
| **Package / Card Metadata** | Price only | Price + Validity days | Full package specs: Denomination, Selling Price, GB Quota, Validity (Hours/Days), Speed Cap |
| **Transaction History** | Simple purchase list | Categorized transaction history | Filterable ledger timeline (Deposits, Purchases, Refunds, Adjustments) with receipt view |
| **Account Deletion & Data** | Immediate hard delete / none | No self-serve deletion | 30-day grace period, PII anonymization, 5-year statutory financial retention (`OD-PRIV-01`) |
| **Merchant / Sub-Distributor Role**| Manual unmonitored resellers | Dedicated agent tier | Classified as `V1.5` (`DEFERRED_POST_LAUNCH`) for local retail kiosks |
| **Telecom Recharge Services** | Integrated mobile top-up | Integrated multi-service top-up | Explicitly deferred to `V2` (`OUT_OF_SCOPE_V1`) to focus 100% on Wi-Fi hotspot card distribution |
| **WhatsApp Integration Policy** | Financial approvals via WhatsApp | Support & manual approval | WhatsApp used EXCLUSIVELY for support routing; Financial approvals over WhatsApp are `FORBIDDEN_BEHAVIOR` |
| **P2P Wallet Transfers** | Unrestricted user-to-user transfers | Restricted transfer tier | P2P transfers between ordinary users are `FORBIDDEN_BEHAVIOR` in V1 to prevent illicit clearing |

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
5. **Merchant Sub-Distributors (V1.5):** Local neighborhood retail kiosks authorized to perform cash top-ups for walk-in customers (`DEFERRED_POST_LAUNCH`).

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
* **F-CUST-03: Network Discovery & Filtering:**
  * Browse active, approved networks filtered by Governorate, City, and District.
  * Search networks by name, SSID, or locality with dynamic debounced client query.
  * Display verified network indicators (Verified Shield Badge for Admin-approved networks).
  * Display network status (Online/Active), customer service contact numbers, and optional map location coordinates.
* **F-CUST-04: Dynamic Card Pricing & Package Details:**
  * Fetch real-time active price tiers (`network_prices`) per network.
  * Display card denomination (e.g., 500 YER, 1,000 YER, 2,000 YER, 5,000 YER) alongside selling price and stock availability indicator (In Stock / Out of Stock / Only 1 Left!).
  * Render detailed package specs: Data Quota (GB / MB), Validity Duration (Hours / Days), Speed Limits (Mbps), and expiration terms.
* **F-CUST-05: Prepaid Customer Wallet & Deposit Workflow:**
  * Display immutable closing wallet balance calculated from valid ledger entries.
  * Render comprehensive transaction history (Deposits, Card Purchases, Refund Credits, Adjustments) with status filters.
  * Request wallet deposit by selecting target bank/exchange, entering transaction reference number, and uploading receipt screenshot image.
  * Real-time deposit review status tracking (`pending` -> `under_review` -> `approved` / `rejected`).
* **F-CUST-06: Atomic Card Purchase & Secure Last-Card Behavior:**
  * Require explicit purchase confirmation modal displaying network name, card package details, and wallet deduction amount.
  * Execute atomic `purchase_card` RPC transaction ensuring zero race conditions on the last available card in stock.
  * **Secure Last-Card Behavior:** When stock = 1, row locking (`FOR UPDATE SKIP LOCKED`) ensures first buyer acquires lock; second buyer receives clean failure notification: *"تم شراء آخر كرت متوفر من قِبل مستخدم آخر"* without double-debit.
  * Upon transaction success, immediately display complete card number in plaintext with a one-tap "Copy Card Number" action.
  * Provide direct button to launch local Wi-Fi Hotspot login page if configured by the network.
* **F-CUST-07: Purchase History & Card Storage:**
  * Persistent purchase history listing all historically acquired cards.
  * Mask card numbers in list views (`12****89`); allow purchaser to tap to reveal/copy.
  * Filter purchases by date, network, or card status.
* **F-CUST-08: Support & Card Complaints:**
  * Submit card complaint (e.g., "Card already used", "Invalid PIN") within 24 hours of purchase.
  * Attach dispute explanation; track ticket resolution status.
  * WhatsApp customer support link integration (strictly for text support inquiries).
* **F-CUST-09: Account Lifecycle & Secure Deletion:**
  * Receive push notifications for deposit approvals, purchase confirmations, and support responses.
  * Secure logout clearing local session and tokens.
  * Request account suspension or formal closure with 30-day grace period and statutory 5-year financial data retention.
* **F-CUST-10: Nearby Wi-Fi Hotspot Discovery & Multi-SSID Auto-Matching (NY-PRODUCT-001E):**
  * Auto-scan active Wi-Fi SSIDs in range (with Android Wi-Fi scan permissions) or match typed SSIDs against platform network registry.
  * Highlight "Connected to [Network Name]" or "Nearby Network Found" banners on home screen for 1-tap card purchasing.
* **F-CUST-11: Network Addition Request Submission (NY-PRODUCT-001E):**
  * Allow customers to submit a "Suggest New Network" request if their local Wi-Fi hotspot is unlisted.
  * Capture network SSID, approximate location/city, and optional owner contact details to feed Admin lead queue.
* **F-CUST-12: Bank & Exchange Account Directory (NY-PRODUCT-001E):**
  * Dedicated in-app Directory of official platform deposit accounts (Kuraimi Bank, OneCash, Al-Amqi Exchange, Floosak, Al-Najm Exchange).
  * One-tap copy action for account numbers and IBANs to facilitate error-free mobile banking transfers.

---

### 3.2 Surface 2: Network Owner Android Mobile Application

`PROPOSED_CONTRACT` — Operations mobile app for Wi-Fi network owners and delegated operators.

* **F-OWN-01: Owner Registration & Identity Verification:**
  * Owner account registration requiring commercial identity details, network business name, and identity document upload.
  * Application state held in `pending_verification` until Platform Admin approval.
* **F-OWN-02: Network Profile & Location Management:**
  * Configure network name, broadcast SSIDs, operating governorate, city, district, and contact numbers.
  * Set geographic location (latitude/longitude) for network discovery.
* **F-OWN-03: Denomination & Package Catalog:**
  * Define available card packages: Denomination, retail selling price, GB quota, and validity duration.
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
* **F-OWN-08: Multi-SSID Alias Mapping (NY-PRODUCT-001E):**
  * Register multiple broadcast SSIDs under a single unified network entity (e.g., `NetYemen-North-1`, `NetYemen-North-2`, `NetYemen-5G`).
  * All card purchases across mapped SSIDs draw from the same central card inventory batch.
* **F-OWN-09: Verified Owner Badge & Reputation Shield (NY-PRODUCT-001E):**
  * Verified owners receive a prominent "Verified Network Owner" badge on marketplace cards, increasing customer trust.

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
* **F-ADM-09: Bank Directory & Network Lead Queue Management (NY-PRODUCT-001E):**
  * Manage official platform deposit bank/exchange accounts (Add, edit, toggle visibility).
  * Review customer-submitted network addition leads, assign sales reps, and convert leads into network onboarding invitations.

---

## 4. Explicit V1 Exclusions & Scope Boundaries

To guarantee security, architectural stability, and rapid execution, the following features are explicitly categorized:

### 4.1 Out of Scope for V1 (`OUT_OF_SCOPE_V1`)

1. **Flutter Web Administration Portal:** Admin portal will be built as a standalone React/Vite web application.
2. **Direct Telecom / Mobile Money API Integration:** Wallet deposits will rely on manual receipt upload and administrative verification queue rather than automated bank API callbacks in V1.
3. **Telecom Balance Recharge Services (Yemen Mobile / MTN / Sabafon):** Explicitly deferred to `V2`. NetYemen V1 focuses strictly on local Wi-Fi hotspot cards.
4. **Multi-Country / Currency Operations:** V1 is strictly restricted to Yemeni network cards and Yemeni Rial (YER) financial accounting.
5. **Offline Card Purchases:** Customer app requires active internet connectivity to execute atomic card purchases via backend RPC.

### 4.2 Deferred Post-Launch (`DEFERRED_POST_LAUNCH`)

1. **Merchant / Sub-Distributor Application Surface (V1.5):** Dedicated portal for local retail kiosks to act as cash top-up agents or bulk sub-distributors deferred to `V1.5`.
2. **iOS Customer & Owner Applications:** iOS release builds and App Store submission are deferred until Android market launch stabilizes.
3. **Automated OCR Receipt Scanning:** Automated image text recognition for deposit receipt processing deferred to V2.
4. **In-App Live Chat Support:** Customer support in V1 relies on ticket submission and WhatsApp link integration rather than real-time custom socket chat.

### 4.3 Strictly Forbidden Features (`FORBIDDEN_BEHAVIOR`)

1. **Negative Wallet Balances:** Wallet balances must never drop below 0 under any circumstance.
2. **Financial Approvals over WhatsApp:** Approving deposits, issuing refunds, or updating ledger balances via WhatsApp messages is strictly FORBIDDEN. All financial approvals MUST occur inside the Admin Web portal.
3. **P2P Wallet Transfers Between Ordinary Users:** Direct wallet balance transfers between customer accounts are FORBIDDEN in V1 to prevent unverified financial clearing.
4. **Direct Database Wallet Balance Updates:** Updating `wallet_balance` via `UPDATE users SET wallet_balance = ...` is strictly forbidden; balance MUST derive from append-only ledger entries.
5. **Public Marketplace Unverified Selling:** Unverified network owners cannot list or sell cards on the platform.
6. **Manual Modification of Financial Ledger:** Deleting or editing completed ledger rows or audit logs is impossible by schema design and RLS.
7. **Plaintext Card Number Exposure to Uninvolved Parties:** Network owners cannot view full card numbers once sold; third-party customers cannot view cards belonging to other users.

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
| Atomic Purchase & Last-Card Lock | Database Stress & Concurrency Test | `TEST-CONCURRENCY-001`, `TEST-CONCURRENCY-002` |
| Zero Negative Wallet & No P2P Transfer | Financial Ledger Invariant Audit | `TEST-WALLET-001`, `TEST-WALLET-007` |
| Data Isolation (RLS) | Security RLS Penetration Suite | `TEST-AUTHORIZATION-001` |
| WhatsApp Financial Approval Exclusion | Security Policy Audit | `TEST-AUTHORIZATION-007` |
