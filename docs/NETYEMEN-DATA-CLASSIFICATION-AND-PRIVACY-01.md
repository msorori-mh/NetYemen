# NETYEMEN DATA CLASSIFICATION & PRIVACY SPECIFICATION (V1.0 + V1.1 REMEDIATED)

**Task ID:** NY-PRODUCT-001F  
**Document Code:** `NETYEMEN-DATA-CLASSIFICATION-AND-PRIVACY-01.md`  
**Classification:** `PROPOSED_CONTRACT`  
**Scope:** Data Governance, Sensitivity Classification, User-Triggered Scan Privacy, and Compliance  

---

## 1. Data Classification Scheme

All data artifacts, database columns, API responses, and client state properties within the NetYemen platform are strictly categorized into 7 security levels:

```
+-----------------------------------------------------------------------------------+
|                            DATA CLASSIFICATION LEVELS                             |
+-----------------------------------------------------------------------------------+
|  1. PUBLIC               - Unrestricted public information                        |
|  2. INTERNAL             - Platform operational metadata                          |
|  3. CONFIDENTIAL         - Customer & Owner Personally Identifiable Information   |
|  4. HIGHLY_SENSITIVE     - Identity verification files & support evidence         |
|  5. FINANCIAL            - Wallet balances, ledger rows, payout vouchers          |
|  6. AUTHENTICATION_SECRET - OTP tokens, JWT session keys, password hashes         |
|  7. CARD_SECRET          - Unsold & sold internet card PIN numbers                |
+-----------------------------------------------------------------------------------+
```

---

## 2. Complete Data Asset Classification Inventory

| Data Asset / Field Name | Classification Level | Owner Entity | Allowed Access Roles | Client Exposure Scoping | Logging & Analytics Policy |
|---|---|---|---|---|---|
| **Network Name / SSID / City** | `PUBLIC` | Network | All (Including Unauthenticated) | Public API endpoints | Allowed in analytics & logs |
| **Network Price Catalog** | `PUBLIC` | Network | All (Including Unauthenticated) | Public API endpoints | Allowed in analytics & logs |
| **Customer Phone Number** | `CONFIDENTIAL` | Customer | Customer (Self), Finance, Admin | Masked in UI (`+967 77****123`) | Masked in logs (`+967 77****123`) |
| **Customer Full Name** | `CONFIDENTIAL` | Customer | Customer (Self), Finance, Admin | Full view to self and staff | Allowed in operational logs |
| **Customer Locality Choice** | `CONFIDENTIAL` | Customer | Customer (Self), Admin | Used for manual network filter | Aggregated stats allowed |
| **Wi-Fi SSID Scan Filter** | `CONFIDENTIAL` | Customer | Customer (Self Only) | User-Triggered local scan only | NEVER uploaded to backend |
| **Hardware BSSID Address** | `HIGHLY_SENSITIVE` | Customer | NONE (Local Device Only) | NEVER exposed or sent via API | STRICTLY FORBIDDEN IN LOGS |
| **Wallet Balance** | `FINANCIAL` | Customer | Customer (Self), Finance, Admin | Visible on customer wallet surface | Logged as numeric balance |
| **Ledger Entry Records** | `FINANCIAL` | System | Customer (Self entries), Finance, Admin | Accessible via authenticated ledger API| Transaction ID & amount logged |
| **Deposit Receipt Images** | `HIGHLY_SENSITIVE` | Customer | Customer (Self), Finance Officer | Private Storage Bucket URL | Never logged or cached in CDN |
| **Owner National ID Images** | `HIGHLY_SENSITIVE` | Owner | Owner (Self), Platform Admin | Restricted Admin Reviewer UI | Strictly excluded from logs |
| **Unsold Card Numbers (PINs)** | `CARD_SECRET` | Network | NONE (Database Internal / Vault) | NEVER exposed to any client | STRICTLY FORBIDDEN IN LOGS |
| **Purchased Card Number (PIN)**| `CARD_SECRET` | Customer | Purchaser (Self), Support (Context) | Disclosed ONLY to purchasing buyer | MASKED IN LOGS (`12****89`) |
| **SMS OTP Token Code** | `AUTHENTICATION_SECRET` | System | SMS Gateway Service Only | Sent via SMS API payload only | STRICTLY FORBIDDEN IN LOGS |
| **Device FCM Push Token** | `INTERNAL` | Customer | Customer (Self), Push Gateway | System push background dispatch | Token hash logged |
| **Platform Audit Logs** | `INTERNAL` | System | Platform Admin, System Auditor | Admin Portal Audit Surface | System execution logs |

---

## 3. User-Triggered Nearby Scan & Location Privacy Contract (`NY-PRODUCT-001F`)

1. **User-Triggered Scanning Only:** Nearby Wi-Fi hotspot scanning MUST execute ONLY when explicitly triggered by a user button tap (*"Scan Nearby Networks"*).
2. **Prohibition of Background Scanning:** Continuous, background, or silent Wi-Fi scanning without explicit user interaction is strictly `FORBIDDEN_BEHAVIOR`.
3. **BSSID & Device Tracking Protection:** BSSID hardware MAC addresses and raw device identifiers MUST NOT be uploaded to backend servers, logged in telemetry, or shared with network owners.
4. **Location Consent & Fallback:** Precise GPS coordinates MUST NOT be uploaded without explicit user consent. If location permission is denied or revoked, the application MUST provide a seamless fallback to manual governorate/city dropdown search.
5. **Anonymized Lead Suggestions:** Customer-submitted "Suggest New Network" leads strip the requester's identity and precise location. Network owners see aggregate demand counts only.

---

## 4. Account Deletion & Data Retention Classification

When a customer requests account deletion under `BR-AUTH-007`:

1. Account state transitions to `closure_pending` for 30 days.
2. Following 30 days, personal identifiers (`full_name`, `phone`, `device_tokens`) are overwritten with anonymized cryptographic hashes (`deleted_user_hash_123`).
3. Historical financial ledger rows and purchase transaction counts are retained to comply with financial auditing practices.
4. **Retention Duration Classification:** The precise data retention period is classified as `OPEN_DECISION` (`PROVISIONAL_RECOMMENDATION` 5 years). Hard deletion of ledger entries is strictly forbidden.

---

## 5. Logging & Analytics Restrictions (`FORBIDDEN_BEHAVIOR`)

To prevent accidental data exposure in application telemetry, crash reports, or server logs:

```text
FORBIDDEN IN LOGS:
1. Plaintext Internet Card Numbers / PINs (MUST be masked as XX****XX)
2. Hardware BSSID MAC Addresses (MUST be scrubbed)
3. SMS OTP Code Tokens (MUST be scrubbed)
4. User JWT Refresh Tokens (MUST be scrubbed)
5. Full Credit Card / Payment Receipt Image Payload Data
```
