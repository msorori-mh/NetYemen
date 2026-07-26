# NETYEMEN DATA CLASSIFICATION & PRIVACY SPECIFICATION (V1.0)

**Task ID:** NY-PRODUCT-001  
**Document Code:** `NETYEMEN-DATA-CLASSIFICATION-AND-PRIVACY-01.md`  
**Classification:** `PROPOSED_CONTRACT`  
**Scope:** Data Governance, Sensitivity Classification, Privacy Protection, and Compliance  

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
| **Customer Geographic Locality**| `CONFIDENTIAL` | Customer | Customer (Self), Admin | Used for network search filter | Aggregated stats allowed |
| **Wallet Balance** | `FINANCIAL` | Customer | Customer (Self), Finance, Admin | Visible on customer wallet surface | Logged as numeric balance |
| **Ledger Entry Records** | `FINANCIAL` | System | Customer (Self entries), Finance, Admin | Accessible via authenticated ledger API| Transaction ID & amount logged |
| **Deposit Receipt Images** | `HIGHLY_SENSITIVE` | Customer | Customer (Self), Finance Officer | Private Storage Bucket URL | Never logged or cached in CDN |
| **Owner National ID Images** | `HIGHLY_SENSITIVE` | Owner | Owner (Self), Platform Admin | Restricted Admin Reviewer UI | Strictly excluded from logs |
| **Unsold Card Numbers (PINs)** | `CARD_SECRET` | Network | NONE (Database Internal / Vault) | NEVER exposed to any client | STRICTLY FORBIDDEN IN LOGS |
| **Purchased Card Number (PIN)**| `CARD_SECRET` | Customer | Purchaser (Self), Support (Context) | Disclosed ONLY to purchasing buyer | MASKED IN LOGS (`12****89`) |
| **SMS OTP Token Code** | `AUTHENTICATION_SECRET` | System | SMS Gateway Service Only | Sent via SMS API payload only | STRICTLY FORBIDDEN IN LOGS |
| **Device FCM Push Token** | `INTERNAL` | Customer | Customer (Self), Push Gateway | System push background dispatch | Token hash logged |
| **Platform Audit Logs** | `INTERNAL` | System | Platform Admin, System Auditor | Admin Portal Audit Surface | System execution logs |
| **Client IP Address & UserAgent**| `INTERNAL` | System | Platform Admin, Auditor | Header metadata | Security logs for fraud detection |

---

## 3. Client Exposure & Access Control Rules

1. **Card PIN Confidentiality:** Unsold card numbers MUST NEVER be transmitted across any client API response. Card decryption occurs exclusively inside security-definer database functions during atomic purchase commit.
2. **Purchaser Isolation:** A purchased card PIN is accessible ONLY to the authenticated customer account (`auth.uid()`) that executed the purchase. Other users, network owners, and unassigned support agents receive masked PIN strings (`12****89`).
3. **Receipt Storage Bucket Security:** Customer deposit receipt screenshots and owner ID documents are stored in private Supabase Storage buckets protected by RLS policies. Signed URLs expire after 15 minutes.
4. **Export Restrictions:** Mass export of customer PII, phone numbers, or financial transaction logs is restricted to `PLATFORM_ADMIN` and `SYSTEM_AUDITOR` roles and triggers an immutable audit log entry.

---

## 4. Logging & Analytics Restrictions (`FORBIDDEN_BEHAVIOR`)

To prevent accidental data exposure in application telemetry, crash reports, or server logs:

```text
FORBIDDEN IN LOGS:
1. Plaintext Internet Card Numbers / PINs (MUST be masked as XX****XX)
2. SMS OTP Code Tokens (MUST be scrubbed)
3. User JWT Refresh Tokens (MUST be scrubbed)
4. Full Credit Card / Payment Receipt Image Payload Data
5. Owner National Identity Document Bytes
```

---

## 5. Account Deletion & Data Anonymization Contract

When a customer requests account deletion under `BR-AUTH-007`:

1. Account state transitions to `closure_pending` for 30 days.
2. Following 30 days, personal identifiers (`full_name`, `phone`, `device_tokens`) are overwritten with anonymized cryptographic hashes (`deleted_user_hash_123`).
3. Historical financial ledger rows and purchase transaction counts are retained for 5 years to comply with Yemeni tax and financial audit regulations (`OD-PRIV-01`).

---

## 6. Backup Security & Disaster Recovery

* **Database Backups:** Automated daily PostgreSQL backups are encrypted at rest using AES-256 encryption.
* **Point-in-Time Recovery (PITR):** Maintained for 7 days to recover from potential data corruption or transactional errors.
* **Access Control:** Backup files are accessible exclusively by platform infrastructure leads; production database secrets are never checked into version control.
