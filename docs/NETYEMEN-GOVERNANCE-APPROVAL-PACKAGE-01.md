# NETYEMEN GOVERNANCE APPROVAL PACKAGE 01

**Task ID:** NY-GOV-BE-001  
**Document Code:** `NETYEMEN-GOVERNANCE-APPROVAL-PACKAGE-01.md`  
**Classification:** `PROPOSED_GOVERNANCE_PACKAGE`  
**Status:** Open-Decision Dependency Closure for Core Backend Foundation  

---

## 1. Executive Summary

This governance approval package provides dependency closure for the 11 open business and architectural decisions (`OD-AUTH-01` through `OD-NOTIF-01`) identified in `docs/NETYEMEN-DECISION-REGISTER-01.md`.

Every open decision has been systematically evaluated against the core backend foundation (`NY-GOV-BE-001`). Safe design boundaries have been established to allow core identity, role management, network catalog, network membership, SSID alias normalization, and immutable audit infrastructure to proceed autonomously without locking financial, encryption, or gateway decisions that require explicit human management approval.

---

## 2. Open Decision Classification Matrix

| Decision ID | Title | Status | Classification | Blocks Core Foundation? | Safe Design Boundary |
|---|---|---|---|---|---|
| `OD-AUTH-01` | SMS OTP Gateway Provider Selection | `OPEN_DECISION` | `BLOCKS_PRODUCTION_LAUNCH` | No | Default Supabase Auth handles core authentication & profile creation. Custom SMS gateway can be integrated via Edge Functions without database schema changes. |
| `OD-FIN-01` | Customer Deposit Verification & Proof Method | `OPEN_DECISION` | `BLOCKS_WALLET_AND_FINANCE` | No | Deposit requests and manual review queues remain decoupled from core identity and network schemas. |
| `OD-FIN-02` | Platform Commission Architecture | `OPEN_DECISION` | `BLOCKS_WALLET_AND_FINANCE` | No | Commission rates and settlement vouchers are excluded from core network tables. |
| `OD-FIN-03` | Deposit Bank Directory Accounts Selection | `OPEN_DECISION` | `BLOCKS_WALLET_AND_FINANCE` | No | Bank directory lookup tables are separate configuration entities not required for core identity or network membership. |
| `OD-CARD-01` | Internet Card Encryption & Storage Architecture | `OPEN_DECISION` | `BLOCKS_CARD_SECURITY` | No | Card inventory (`cards`, `card_batches`) tables are completely omitted from core foundation. |
| `OD-CARD-02` | Customer Card Dispute & Quarantine Window | `OPEN_DECISION` | `BLOCKS_CARD_SECURITY` | No | Support tickets and card complaints are omitted from core foundation. |
| `OD-SETTLE-01` | Network Owner Settlement Payout Schedule | `OPEN_DECISION` | `BLOCKS_WALLET_AND_FINANCE` | No | Settlement payout calculation engine is omitted from core foundation. |
| `OD-PRIV-01` | User Data Retention & Account Anonymization Policy | `OPEN_DECISION` | `NON_BLOCKING_FOR_CORE_FOUNDATION` | No | `account_status` supports `'anonymized'` state while retention cron policies remain configurable in V2 tasks. |
| `OD-ARCH-01` | Administration Web Portal Technology Stack | `OPEN_DECISION` | `NON_BLOCKING_FOR_CORE_FOUNDATION` | No | Supabase REST/RPC APIs and RLS policies are client-agnostic. |
| `OD-WALLET-01` | Wallet Balance Storage: Cached vs Real-Time Aggregation | `OPEN_DECISION` | `BLOCKS_WALLET_AND_FINANCE` | No | Wallet balance columns are strictly omitted from `public.profiles`. |
| `OD-NOTIF-01` | Push Notification Infrastructure & Gateway | `OPEN_DECISION` | `BLOCKS_NOTIFICATIONS` | No | Immutable audit trail records system events independently of external push notification gateways. |

---

## 3. Detailed Open Decision Specifications

### 3.1 OD-AUTH-01: SMS OTP Gateway Provider Selection
* **Current Status:** `OPEN_DECISION`
* **Provisional Recommendation:** Option A (ALAWAEL SMS API for V1 launch).
* **Blocks Core Foundation:** No.
* **Classification:** `BLOCKS_PRODUCTION_LAUNCH`
* **First Implementation Task Blocked:** `NY-BE-007` (SMS / OTP Gateway Edge Function Integration).
* **Database Objects Affected:** `profiles` (auth metadata / phone verification flags).
* **UI Surfaces Affected:** Mobile OTP Verification Screen.
* **Security Impact:** Authentication delivery channel integrity & phone ownership verification.
* **Financial Impact:** SMS gateway per-message operational costs.
* **Safe Design Boundary:** Core `profiles` table references `auth.users(id)` created by Supabase Auth natively. Custom gateway integration remains isolated to Edge Functions.
* **Human Approval Required:** Yes — Final selection of local SMS gateway provider and credentials.

### 3.2 OD-FIN-01: Customer Deposit Verification & Proof Method
* **Current Status:** `OPEN_DECISION`
* **Provisional Recommendation:** Option 1 (Manual Verification Queue).
* **Blocks Core Foundation:** No.
* **Classification:** `BLOCKS_WALLET_AND_FINANCE`
* **First Implementation Task Blocked:** `NY-BE-003` (Wallet & Ledger Schema & RPC).
* **Database Objects Affected:** `deposit_requests`, `wallet_ledger_entries`, `profiles`.
* **UI Surfaces Affected:** Mobile Deposit Screen, Admin Finance Verification Queue.
* **Security Impact:** Proof of payment verification and fraud prevention on deposit approvals.
* **Financial Impact:** Direct impact on platform liquidity, wallet balance credits, and manual review labor costs.
* **Safe Design Boundary:** Core foundation includes zero deposit tables or financial functions.
* **Human Approval Required:** Yes — Approval of deposit workflow and manual queue SLAs.

### 3.3 OD-FIN-02: Platform Commission Architecture
* **Current Status:** `OPEN_DECISION`
* **Provisional Recommendation:** Option A (Flat Percentage Commission - 5%).
* **Blocks Core Foundation:** No.
* **Classification:** `BLOCKS_WALLET_AND_FINANCE`
* **First Implementation Task Blocked:** `NY-BE-004` (Card Purchase RPC) / `NY-BE-005` (Settlement Engine).
* **Database Objects Affected:** `settlements`, `wallet_ledger_entries`, `network_payouts`.
* **UI Surfaces Affected:** Admin Finance Dashboard, Network Owner Earnings Screen.
* **Security Impact:** Financial integrity of fee deductions and settlement vouchers.
* **Financial Impact:** Core platform business model revenue and network owner margins.
* **Safe Design Boundary:** Networks and memberships operate independently of commission rates.
* **Human Approval Required:** Yes — Approval of platform commission percentage.

### 3.4 OD-FIN-03: Deposit Bank Directory Accounts Selection
* **Current Status:** `OPEN_DECISION`
* **Provisional Recommendation:** Option 1 (Configuration-Driven Bank Directory).
* **Blocks Core Foundation:** No.
* **Classification:** `BLOCKS_WALLET_AND_FINANCE`
* **First Implementation Task Blocked:** `NY-BE-003` (Wallet & Ledger Schema) / Admin Finance UI.
* **Database Objects Affected:** `bank_directory` / `financial_channels`.
* **UI Surfaces Affected:** Mobile Deposit Screen (Bank Directory List).
* **Security Impact:** Exposure of official platform deposit receiving channels.
* **Financial Impact:** Routing customer deposits to correct platform bank/exchange accounts.
* **Safe Design Boundary:** Bank directory configuration tables are isolated from identity, roles, and network schema.
* **Human Approval Required:** Yes — Confirmation of official bank and exchange account numbers.

### 3.5 OD-CARD-01: Internet Card Encryption & Storage Architecture
* **Current Status:** `OPEN_DECISION`
* **Provisional Recommendation:** Option 1 (pgcrypto Column-Level Encryption).
* **Blocks Core Foundation:** No.
* **Classification:** `BLOCKS_CARD_SECURITY`
* **First Implementation Task Blocked:** `NY-BE-004` (Card Inventory & Purchase RPC).
* **Database Objects Affected:** `cards`, `card_batches`.
* **UI Surfaces Affected:** Network Owner Card Upload, Customer Card Inventory / Purchase Screen.
* **Security Impact:** Confidentiality of internet card numbers/PINs in database.
* **Financial Impact:** Mitigation of inventory theft and card leaks.
* **Safe Design Boundary:** Card inventory tables are excluded from core foundation (`NY-GOV-BE-001`).
* **Human Approval Required:** Yes — Confirmation of encryption key management approach.

### 3.6 OD-CARD-02: Customer Card Dispute & Quarantine Window
* **Current Status:** `OPEN_DECISION`
* **Provisional Recommendation:** Option B (24-Hour Standard Dispute Window).
* **Blocks Core Foundation:** No.
* **Classification:** `BLOCKS_CARD_SECURITY`
* **First Implementation Task Blocked:** `NY-BE-006` (Support & Dispute Resolution System).
* **Database Objects Affected:** `card_complaints`, `settlements`.
* **UI Surfaces Affected:** Customer Dispute Screen, Support Agent Dashboard.
* **Security Impact:** Fraud prevention on invalid card complaints and owner payout holds.
* **Financial Impact:** Settlement hold duration and dispute refund liability.
* **Safe Design Boundary:** Support and complaint tables are omitted from core foundation.
* **Human Approval Required:** Yes — Confirmation of dispute window duration.

### 3.7 OD-SETTLE-01: Network Owner Settlement Payout Schedule
* **Current Status:** `OPEN_DECISION`
* **Provisional Recommendation:** Option 1 (Weekly Settlement Batch).
* **Blocks Core Foundation:** No.
* **Classification:** `BLOCKS_WALLET_AND_FINANCE`
* **First Implementation Task Blocked:** `NY-BE-005` (Settlement Engine & Payout Batch).
* **Database Objects Affected:** `settlement_batches`, `network_payouts`.
* **UI Surfaces Affected:** Network Owner Payout Screen, Admin Finance Settlement Dashboard.
* **Security Impact:** Automated vs manual payout authorization and payout audit trails.
* **Financial Impact:** Cash flow timing for hotspot owners and platform liquidity management.
* **Safe Design Boundary:** Networks and network memberships operate without settlement payout infrastructure.
* **Human Approval Required:** Yes — Approval of payout schedule and minimum payout thresholds.

### 3.8 OD-PRIV-01: User Data Retention & Account Anonymization Policy
* **Current Status:** `OPEN_DECISION`
* **Provisional Recommendation:** Option A (5-Year Financial Retention + Instant Profile Anonymization).
* **Blocks Core Foundation:** No.
* **Classification:** `NON_BLOCKING_FOR_CORE_FOUNDATION`
* **First Implementation Task Blocked:** `NY-BE-008` (Data Retention & Anonymization Cron Tasks).
* **Database Objects Affected:** `profiles`, `audit_events`, `wallet_ledger_entries`.
* **UI Surfaces Affected:** Customer Settings (Account Deletion).
* **Security Impact:** Privacy compliance, data scrubbing, and retention of forensic audit trails.
* **Financial Impact:** Legal compliance and storage infrastructure cost.
* **Safe Design Boundary:** Core `profiles` table contains `account_status` supporting `'anonymized'` state. Data scrubbing policies remain deferred.
* **Human Approval Required:** Yes — Legal confirmation of retention durations.

### 3.9 OD-ARCH-01: Administration Web Portal Technology Stack
* **Current Status:** `OPEN_DECISION`
* **Provisional Recommendation:** Option 1 (React + Vite + TailwindCSS + Shadcn UI).
* **Blocks Core Foundation:** No.
* **Classification:** `NON_BLOCKING_FOR_CORE_FOUNDATION`
* **First Implementation Task Blocked:** `NY-FE-002` (Admin Web Portal Setup).
* **Database Objects Affected:** None (Consumes Supabase REST/RPC APIs).
* **UI Surfaces Affected:** Admin Web Portal.
* **Security Impact:** Web portal authentication, RBAC session management, desktop security headers.
* **Financial Impact:** Frontend development speed and maintenance overhead.
* **Safe Design Boundary:** Supabase database schema and RLS policies are completely frontend-agnostic.
* **Human Approval Required:** Yes — Selection of admin web framework stack.

### 3.10 OD-WALLET-01: Wallet Balance Storage: Cached vs Real-Time Aggregation
* **Current Status:** `OPEN_DECISION`
* **Provisional Recommendation:** Option A (Cached Column updated via Database Trigger).
* **Blocks Core Foundation:** No.
* **Classification:** `BLOCKS_WALLET_AND_FINANCE`
* **First Implementation Task Blocked:** `NY-BE-003` (Wallet & Ledger Schema & RPC).
* **Database Objects Affected:** `profiles`, `wallet_ledger_entries`.
* **UI Surfaces Affected:** Mobile Wallet Balance Screen.
* **Security Impact:** Atomicity and consistency of financial balance calculations.
* **Financial Impact:** Prevention of double-spending or wallet calculation drift.
* **Safe Design Boundary:** `public.profiles` excludes `wallet_balance` fields entirely to maintain zero financial coupling in core foundation.
* **Human Approval Required:** Yes — Approval of wallet balance architecture.

### 3.11 OD-NOTIF-01: Push Notification Infrastructure & Gateway
* **Current Status:** `OPEN_DECISION`
* **Provisional Recommendation:** Option 1 (Firebase Cloud Messaging via Supabase Edge Functions).
* **Blocks Core Foundation:** No.
* **Classification:** `BLOCKS_NOTIFICATIONS`
* **First Implementation Task Blocked:** `NY-BE-007` (Push Notification Service & Edge Functions).
* **Database Objects Affected:** `user_device_tokens`, `notification_logs`.
* **UI Surfaces Affected:** Mobile App Notification Tray / In-App Alerts.
* **Security Impact:** Token security, notification channel spoofing prevention.
* **Financial Impact:** FCM infrastructure operational cost.
* **Safe Design Boundary:** Immutable audit trail records system events independently of notification delivery channels.
* **Human Approval Required:** Yes — Setup of Firebase project and FCM credentials.

---

## 4. Architectural Dependency Summary

```
+-----------------------------------------------------------------------------------+
|               CORE BACKEND FOUNDATION (NY-GOV-BE-001) — UNBLOCKED                 |
|  - public.profiles                                                                |
|  - public.user_roles                                                              |
|  - public.networks                                                                |
|  - public.network_memberships                                                     |
|  - public.network_ssid_aliases                                                    |
|  - public.audit_events                                                            |
|  - RLS Policies & Security Definer Helpers                                        |
+-----------------------------------------------------------------------------------+
                                      |
       +------------------------------+------------------------------+
       |                              |                              |
       v                              v                              v
[BLOCKS_WALLET_AND_FINANCE]   [BLOCKS_CARD_SECURITY]      [BLOCKS_NOTIFICATIONS]
  - OD-FIN-01 (Deposits)        - OD-CARD-01 (Encryption)    - OD-NOTIF-01 (FCM)
  - OD-FIN-02 (Commissions)     - OD-CARD-02 (Disputes)      [BLOCKS_PRODUCTION_LAUNCH]
  - OD-SETTLE-01 (Payouts)                                     - OD-AUTH-01 (SMS OTP)
  - OD-WALLET-01 (Balance)
  - OD-FIN-03 (Bank Dir)
```

No open decision is marked `APPROVED` without explicit human authorization. Core backend foundation source implementation is fully authorized to proceed under these boundaries.
