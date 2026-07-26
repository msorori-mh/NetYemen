# NETYEMEN COMPETITOR BENCHMARK & STRATEGIC ANALYSIS (V1.0)

**Task ID:** NY-PRODUCT-001F  
**Document Code:** `NETYEMEN-COMPETITOR-BENCHMARK-01.md`  
**Classification:** `PROPOSED_CONTRACT`  
**Scope:** Forensic Visual Analysis of Regional Competitors and Architectural Translation  
**Data Origin Note:** Information regarding competitors is derived strictly from user-provided application screenshots. No access to competitor backends, private API contracts, database schemas, or commercial agreements was obtained or claimed.

---

## 1. Methodology & Classification Definitions

To maintain absolute intellectual property compliance and security integrity, analysis of competing applications is strictly categorized using the following explicit labels:

* **`OBSERVED_FROM_SCREENSHOT`:** Features, UI elements, or visual flows explicitly visible in user-provided screenshot artifacts.
* **`INFERRED_RISK`:** Potential security, privacy, operational, or business vulnerabilities inferred from visual observation.
* **`APPROVED_NETYEMEN_REQUIREMENT`:** Formal product requirements adopted into NetYemen design contracts.
* **`NOT_OBSERVED`:** Features or mechanisms not visible in screenshot evidence and unconfirmed.

---

## 2. Competitor A — كرت نت Analysis

### 2.1 Screenshot Observations Matrix

| Functional Area | Competitor A Observed Behavior | Classification Label | NetYemen Strategic Translation |
|---|---|---|---|
| **Nearby Wi-Fi Discovery** | Shows nearby Wi-Fi network cards list based on user location / SSIDs | `OBSERVED_FROM_SCREENSHOT` | Adopted as **User-Triggered Nearby Wi-Fi Scan Only** (`F-CUST-10`). Silent/background scans forbidden. |
| **Network Addition Request** | Form allowing users to suggest unlisted networks in their locality | `OBSERVED_FROM_SCREENSHOT` | Adopted as **Network Addition Lead Queue** (`F-CUST-11`, `F-ADM-09`). Captures demand without revealing user identity. |
| **Purchase Call-to-Action** | Direct "Buy Card" action button on network listing | `OBSERVED_FROM_SCREENSHOT` | Adopted into atomic purchase confirmation modal (`F-CUST-06`). |
| **Stock & Price Transparency** | Limited visual indicator of remaining card stock or detailed package terms | `OBSERVED_FROM_SCREENSHOT` / `INFERRED_RISK` | NetYemen mandates explicit package specs (GB quota, validity, speed cap, stock availability). |
| **Last-Card Warning Area** | Highlighting when card availability is low | `OBSERVED_FROM_SCREENSHOT` | Adopted with **Secure Last-Card Lock** (`BR-CARD-009`) using `SELECT ... FOR UPDATE SKIP LOCKED`. |
| **Favorites & Banners** | Favorites list and promotional network banners | `OBSERVED_FROM_SCREENSHOT` | Admin-managed featured networks (`BR-NETWORK-006`). |
| **Support & Dispute Flow** | Unclear dispute resolution mechanism in visible UI | `INFERRED_RISK` | NetYemen implements 24h card dispute quarantine and refund flow (`BR-REFUND-001`). |

---

## 3. Competitor B — Unnamed Wallet & Network Card Application Analysis

### 3.1 Screenshot Observations Matrix

| Functional Area | Competitor B Observed Behavior | Classification Label | NetYemen Strategic Translation |
|---|---|---|---|
| **Prepaid Wallet & Balance** | Internal customer wallet balance display with account ID | `OBSERVED_FROM_SCREENSHOT` | Adopted as **Cached Ledger Balance** (`BR-WALLET-001`, `BR-WALLET-002`). |
| **Deposit Request & Receipt** | In-app deposit request form requiring receipt image upload | `OBSERVED_FROM_SCREENSHOT` | Adopted as **In-App Deposit Queue** (`F-CUST-05`, `F-ADM-03`). |
| **Deposit Status Tracking** | Status tracking screen (`pending`, `approved`, `rejected`) | `OBSERVED_FROM_SCREENSHOT` | Adopted into Customer Deposit Lifecycle (`BR-WALLET-008`). |
| **Deposit Account Directory** | Directory of bank/exchange deposit accounts displayed in UI | `OBSERVED_FROM_SCREENSHOT` | Adopted as **Configuration-Driven Bank Directory** (`F-CUST-12`). Provider names remain illustrative examples (`OPEN_DECISION`). |
| **WhatsApp Activation/Support**| WhatsApp links used for account activation & financial approvals | `OBSERVED_FROM_SCREENSHOT` / `INFERRED_RISK` | NetYemen adopts WhatsApp EXCLUSIVELY for text support. WhatsApp financial approvals are `FORBIDDEN_BEHAVIOR`. |
| **Distributor / Shop Positioning**| Sub-distributor or merchant shop-owner agent portal | `OBSERVED_FROM_SCREENSHOT` | Merchant/Distributor role classified as `V1.5` (`DEFERRED_POST_LAUNCH`). |
| **Detailed Package Specs** | Card package details showing validity hours/days and quota | `OBSERVED_FROM_SCREENSHOT` | Adopted as mandatory package attributes (`BR-CARD-008`). |
| **Telecom Balance Recharge** | Mobile operator balance recharge catalog (Yemen Mobile, MTN, Sabafon) | `OBSERVED_FROM_SCREENSHOT` | Explicitly deferred to `V2` (`OUT_OF_SCOPE_V1`). V1 focuses 100% on Wi-Fi hotspot cards. |
| **Account Deletion** | Settings option for account closure | `OBSERVED_FROM_SCREENSHOT` | Adopted as **30-Day Deletion Grace Period** with PII anonymization and financial data retention (`OD-PRIV-01`). |
| **Verified Account Badge** | Verification checkmark icon on approved vendor accounts | `OBSERVED_FROM_SCREENSHOT` | Adopted as **Verified Network Owner Shield** (`BR-NETWORK-010`). |

---

## 4. Architectural Insulation & Non-Infringement Policy

1. **Clean-Room Design:** NetYemen source code and documentation are created independently. No visual assets, icons, brand names, layout templates, or copyrighted strings from competitors are used.
2. **Backend Non-Assumption:** NetYemen makes zero assumptions regarding competitor backend implementations. All NetYemen contracts (ACID purchase RPCs, append-only ledgers, PostgreSQL RLS) are designed from first principles.
