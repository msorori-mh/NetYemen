# NETYEMEN THREAT & FRAUD MODEL CATALOG (V1.0)

**Task ID:** NY-PRODUCT-001  
**Document Code:** `NETYEMEN-THREAT-AND-FRAUD-MODEL-01.md`  
**Classification:** `PROPOSED_CONTRACT`  
**Scope:** Security Threat Vectors, Attack Paths, Mitigating Controls, and Verification Tests  

---

## Executive Overview

This document establishes the formal Threat and Fraud Model for the NetYemen platform, systematically addressing 30 distinct security threat vectors spanning application API vulnerabilities, financial fraud, authorization bypasses, data privacy leaks, and infrastructure attacks.

---

## Complete Threat & Control Catalog

### 1. THR-01: Insecure Direct Object Reference (IDOR) on Customer Wallet & Purchases
* **Actor:** Malicious Customer / External Attacker
* **Asset:** Customer Wallet Balances and Purchased Card History
* **Attack Path:** Attacker modifies `user_id` query parameters in API calls to fetch another user's purchases.
* **Impact:** Critical — Unauthorized exposure of customer card PINs and financial data.
* **Preventive Control:** Strict PostgreSQL RLS policies checking `user_id = auth.uid()`.
* **Detective Control:** Anomaly detection alert on API requests where payload `user_id != JWT auth.uid()`.
* **Recovery Control:** Invalidate compromised JWT session; notify affected customer.
* **Required Test:** `TEST-AUTHORIZATION-001` (Attempt fetching User B data with User A token).
* **Residual Risk:** Low.

---

### 2. THR-02: Row-Level Security (RLS) Policy Bypass
* **Actor:** External Attacker / Compromised Client SDK
* **Asset:** PostgreSQL Database Tables
* **Attack Path:** Attacker crafts raw SQL or Supabase REST queries bypassing table restrictions.
* **Impact:** Critical — Full database compromise.
* **Preventive Control:** Enable `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` on 100% of tables with `DEFAULT DENY`.
* **Detective Control:** Supabase Security Advisor daily RLS audit scans.
* **Recovery Control:** Immediate hotfix deployment of missing RLS rules.
* **Required Test:** `TEST-SECURITY-001` (Execute REST query on un-owned table).
* **Residual Risk:** Low.

---

### 3. THR-03: Administrative Commercial Logic Bypass
* **Actor:** Rogue Administrator / Compromised Admin Credentials
* **Asset:** Internet Cards & Customer Wallets
* **Attack Path:** Admin invokes purchase RPC or reveals card PINs outside authorized workflow.
* **Impact:** High — Unauthorized stock theft or balance inflation.
* **Preventive Control:** Hardcode non-bypass checks in commercial RPCs (`auth.uid()` checks apply to all roles).
* **Detective Control:** Immutable audit logging of all administrative actions.
* **Recovery Control:** Revoke admin credentials; audit administrative actions.
* **Required Test:** `TEST-AUTHORIZATION-002` (Admin attempts purchasing card without wallet funds).
* **Residual Risk:** Medium.

---

### 4. THR-04: Client-Side Card Price Tampering
* **Actor:** Malicious Buyer
* **Asset:** Platform Revenue & Card Sales
* **Attack Path:** Attacker alters HTTP request payload changing card price from 1,000 YER to 1 YER.
* **Impact:** High — Financial loss for network owners.
* **Preventive Control:** Server-side price lookup from `network_prices` table within purchase RPC.
* **Detective Control:** Validation check comparing ledger debit with database price tier.
* **Recovery Control:** Transaction abort on price mismatch.
* **Required Test:** `TEST-SECURITY-002` (Pass client-modified price parameter to purchase RPC).
* **Residual Risk:** Zero.

---

### 5. THR-05: User Identity Parameter Spoofing
* **Actor:** Malicious Buyer
* **Asset:** Target Customer Wallet
* **Attack Path:** Attacker passes another customer's `user_id` as `p_user_id` in purchase RPC call.
* **Impact:** Critical — Purchasing cards using another user's wallet funds.
* **Preventive Control:** Hardcode `p_user_id := auth.uid()` inside `purchase_card` RPC.
* **Detective Control:** RPC execution validation rejecting explicit client `p_user_id` overrides.
* **Recovery Control:** Immediate RPC transaction rollback.
* **Required Test:** `TEST-AUTHORIZATION-003` (Supply victim `user_id` to purchase RPC).
* **Residual Risk:** Zero.

---

### 6. THR-06: Double Purchase / Replay Attack
* **Actor:** Malicious Buyer / Unstable Mobile Network
* **Attack Path:** Client sends duplicate purchase HTTP requests in rapid succession.
* **Impact:** High — Customer charged twice for a single intended purchase.
* **Preventive Control:** Mandatory client `idempotency_key` header enforced by unique constraint.
* **Detective Control:** Idempotency key lookup check in database.
* **Recovery Control:** Return cached first transaction result without re-executing debit.
* **Required Test:** `TEST-IDEMPOTENCY-001` (Submit identical idempotency key twice concurrently).
* **Residual Risk:** Low.

---

### 7. THR-07: Double Debit Ledger Flaw
* **Actor:** System Error / Flawed RPC Script
* **Attack Path:** Financial ledger writes debit entry twice during purchase execution.
* **Impact:** High — Incorrect customer wallet balance reduction.
* **Preventive Control:** Single atomic SQL transaction block enclosing debit write and card state update.
* **Detective Control:** Daily wallet balance reconciliation formula check.
* **Recovery Control:** Automated compensating credit entry issuance.
* **Required Test:** `TEST-WALLET-002` (Audit purchase ledger debit count per purchase ID).
* **Residual Risk:** Zero.

---

### 8. THR-08: Race Condition on Last Available Card Stock
* **Actor:** Multiple Buyers Competing for 1 Card
* **Attack Path:** Two buyers simultaneously attempt purchasing the final remaining card in a network.
* **Impact:** High — One card sold to two different customers (Over-selling).
* **Preventive Control:** PostgreSQL `SELECT ... FOR UPDATE SKIP LOCKED` row locking inside purchase RPC.
* **Detective Control:** Database unique constraint on `cards (sold_to)` for sold cards.
* **Recovery Control:** Second transaction receives "Stock Unavailable" response and rolls back cleanly.
* **Required Test:** `TEST-CONCURRENCY-001` (Simulate 10 concurrent purchase requests for 1 card).
* **Residual Risk:** Low.

---

### 9. THR-09: Deposit Receipt Reference Forgery
* **Actor:** Fraudulent Customer
* **Attack Path:** Customer submits fake or previously used bank deposit reference numbers.
* **Impact:** High — Wallet balance credited without real money deposited.
* **Preventive Control:** Mandatory manual verification of bank reference in official bank portal by Finance Officer.
* **Detective Control:** Unique database index on `wallet_deposit_requests (reference_number)`.
* **Recovery Control:** Reject deposit request; mark user account for fraud review.
* **Required Test:** `TEST-WALLET-003` (Submit duplicate deposit reference number).
* **Residual Risk:** Low.

---

### 10. THR-10: Fake Payment Evidence Image Upload
* **Actor:** Fraudulent Customer
* **Attack Path:** Customer uploads photoshopped or irrelevant receipt images.
* **Impact:** Medium — Operational burden on Finance Officers.
* **Preventive Control:** High-resolution receipt image preview UI for Finance Officers with zoom & pan.
* **Detective Control:** Finance Officer verification protocol before deposit approval.
* **Recovery Control:** Reject deposit request with reason code "Unreadable / Fake Receipt".
* **Required Test:** `TEST-WALLET-004` (Submit invalid receipt image file).
* **Residual Risk:** Medium.

---

### 11. THR-11: Owner Uploading Duplicate Cards Within Network
* **Actor:** Malicious or Careless Network Owner
* **Attack Path:** Owner uploads a batch file containing duplicate card PINs already present in database.
* **Impact:** High — Customers receiving identical card PINs.
* **Preventive Control:** Pre-import batch file validation & unique index `cards (network_id, card_number)`.
* **Detective Control:** Batch import preview rendering duplicate count.
* **Recovery Control:** Import process rejects duplicate lines while importing valid ones.
* **Required Test:** `TEST-CARD-001` (Upload batch containing existing card PINs).
* **Residual Risk:** Zero.

---

### 12. THR-12: Owner Uploading Cards Belonging to Another Network
* **Actor:** Fraudulent Network Owner
* **Attack Path:** Owner obtains card PINs from a competitor network and uploads them to their own network.
* **Impact:** High — Cross-network card collision and customer failure.
* **Preventive Control:** Global card uniqueness check or hashed card lookup across system.
* **Detective Control:** Cross-network duplicate detection alert.
* **Recovery Control:** Quarantine suspicious batch; suspend owner pending investigation.
* **Required Test:** `TEST-CARD-002` (Upload card PIN belonging to Network B into Network A).
* **Residual Risk:** Medium.

---

### 13. THR-13: Unsold Card Number Scraping / Enumeration
* **Actor:** External Attacker / Rogue Owner Staff
* **Attack Path:** Attacker queries Supabase API to harvest unsold card PINs.
* **Impact:** Critical — Mass theft of unpurchased internet card stock.
* **Preventive Control:** RLS policies restrict unsold card visibility to `NONE` (Client API returns empty).
* **Detective Control:** API rate limiting & security alert on bulk queries targeting `cards` table.
* **Recovery Control:** Emergency rotation of exposed database keys.
* **Required Test:** `TEST-SECURITY-003` (Query `cards` table with active customer token).
* **Residual Risk:** Zero.

---

### 14. THR-14: Mobile Clipboard Data Exposure
* **Actor:** Malicious Background Android Application
* **Attack Path:** Malware reads copied card PIN from mobile device clipboard after user taps "Copy PIN".
* **Impact:** Medium — Unauthorized local card PIN interception.
* **Preventive Control:** Auto-clear clipboard memory after 45 seconds; display security notification.
* **Detective Control:** N/A (Client OS level).
* **Recovery Control:** User advises prompt card redemption on local Wi-Fi hotspot.
* **Required Test:** `TEST-CUSTOMER-001` (Verify clipboard clearing behavior).
* **Residual Risk:** Medium.

---

### 15. THR-15: Mobile Screen Capture / Screenshot Leakage
* **Actor:** Local Device Physical Attacker
* **Attack Path:** Attacker takes screenshot of customer device displaying purchased card PIN.
* **Impact:** Low — Local physical privacy compromise.
* **Preventive Control:** Optional Android `FLAG_SECURE` window flag on card reveal screen.
* **Detective Control:** N/A.
* **Recovery Control:** Mask card numbers by default in purchase list views.
* **Required Test:** `TEST-CUSTOMER-002` (Verify FLAG_SECURE window status).
* **Residual Risk:** Low.

---

### 16. THR-16: Application Log Confidentiality Leakage
* **Actor:** Internal Developer / Log File Unauthorized Viewer
* **Attack Path:** Plaintext card PINs or OTP codes are written to application log files or crash traces.
* **Impact:** High — Confidential data exposure in telemetry.
* **Preventive Control:** Strict log scrubbing rules filtering out card numbers, PINs, and OTP tokens.
* **Detective Control:** Automated log pattern scanner for 10+ digit numeric patterns.
* **Recovery Control:** Purge non-compliant log files immediately.
* **Required Test:** `TEST-AUDIT-001` (Inspect output of app logs during card purchase flow).
* **Residual Risk:** Zero.

---

### 17. THR-17: Push Notification Payload Information Leakage
* **Actor:** Malicious App on Device / Lockscreen Viewer
* **Attack Path:** FCM push notification displays plaintext card PIN on lock screen preview.
* **Impact:** Medium — Privacy exposure to shoulder surfers.
* **Preventive Control:** Exclude card PIN from push notification payloads (Send "Purchase Successful" only).
* **Detective Control:** Code review of FCM notification payload templates.
* **Recovery Control:** Update FCM notification dispatch function.
* **Required Test:** `TEST-CUSTOMER-003` (Inspect FCM notification JSON payload).
* **Residual Risk:** Zero.

---

### 18. THR-18: SMS OTP Brute Force Attack
* **Actor:** Automated Botnet
* **Attack Path:** Attacker attempts all 6-digit combinations (000000-999999) to hijack a user account.
* **Impact:** Critical — User account takeover.
* **Preventive Control:** Maximum 5 failed OTP attempts allowed per phone number per hour before lock.
* **Detective Control:** Alert on high-frequency failed OTP verification attempts.
* **Recovery Control:** Invalidate active OTP token; block phone number for 60 minutes.
* **Required Test:** `TEST-AUTH-004` (Submit 6 incorrect OTPs sequentially).
* **Residual Risk:** Low.

---

### 19. THR-19: Phone Number OTP Enumeration
* **Actor:** Malicious Actor
* **Attack Path:** Attacker submits phone numbers rapidly to check registered user presence.
* **Impact:** Medium — User phone number enumeration privacy leak.
* **Preventive Control:** Generic response message ("OTP sent if number valid") for all auth requests.
* **Detective Control:** Rate limit SMS OTP requests to 1 per 60 seconds per IP / Phone.
* **Recovery Control:** IP rate limiting block.
* **Required Test:** `TEST-AUTH-005` (Submit 10 phone auth requests in 10 seconds).
* **Residual Risk:** Low.

---

### 20. THR-20: Stolen Customer Device Account Hijacking
* **Actor:** Physical Thief
* **Attack Path:** Thief opens NetYemen app on stolen unlocked Android phone and spends wallet funds.
* **Impact:** High — Unauthorized wallet balance depletion.
* **Preventive Control:** App biometric / PIN lock option before confirming card purchases.
* **Detective Control:** User remote account freeze option via support.
* **Recovery Control:** User contacts support to immediately revoke active sessions.
* **Required Test:** `TEST-CUSTOMER-004` (Verify biometric purchase confirmation setting).
* **Residual Risk:** Medium.

---

### 21. THR-21: Session Replay / Stale JWT Continuation
* **Actor:** Attacker possessing intercepted JWT token
* **Attack Path:** Attacker reuses captured JWT session token after user has been suspended.
* **Impact:** High — Suspended user continuing commercial operations.
* **Preventive Control:** Database user status check (`is_active = true`) inside RLS and RPC execution.
* **Detective Control:** Invalidate session token on administrative account status change.
* **Recovery Control:** Revoke JWT refresh tokens in Supabase Auth service.
* **Required Test:** `TEST-AUTH-006` (Execute API call with token of suspended account).
* **Residual Risk:** Low.

---

### 22. THR-22: Abuse of Card Complaint Refund Mechanism
* **Actor:** Malicious Customer
* **Attack Path:** Customer purchases card, redeems PIN on Wi-Fi hotspot, then files fake dispute.
* **Impact:** High — Financial loss for network owner; free internet usage for attacker.
* **Preventive Control:** Require detailed complaint rationale; track customer complaint history ratio.
* **Detective Control:** High dispute frequency alert (> 2 complaints per 5 purchases).
* **Recovery Control:** Suspend customer account if fraudulent complaint pattern confirmed.
* **Required Test:** `TEST-REFUND-001` (Submit multiple card complaints consecutively).
* **Residual Risk:** Medium.

---

### 23. THR-23: Collusion Between Finance Officer & Customer
* **Actor:** Rogue Finance Officer + External Customer accomplice
* **Attack Path:** Finance Officer approves fake deposit requests created by accomplice without bank funds.
* **Impact:** Critical — Fraudulent inflation of customer wallet balances.
* **Preventive Control:** Four-eyes principle on deposits > 50,000 YER; randomized deposit review audit queue.
* **Detective Control:** Daily financial balance reconciliation comparing bank statements to deposit logs.
* **Recovery Control:** Immediate revocation of Finance Officer role; reversal of fraudulent ledger credits.
* **Required Test:** `TEST-WALLET-005` (Audit high-value deposit review logs).
* **Residual Risk:** Medium.

---

### 24. THR-24: Owner Settlement Payout Manipulation
* **Actor:** Rogue Finance Officer
* **Attack Path:** Finance Officer alters net payout amount in settlement voucher to overpay owner.
* **Impact:** High — Unauthorized platform funds disbursement.
* **Preventive Control:** Automated SQL voucher calculation script; manual override prohibited without Admin sign-off.
* **Detective Control:** Automated settlement audit script comparing sales volume to payout voucher.
* **Recovery Control:** Hold payout transfer; adjust voucher to true calculated net payable.
* **Required Test:** `TEST-SETTLEMENT-001` (Verify settlement voucher calculation accuracy).
* **Residual Risk:** Low.

---

### 25. THR-25: Audit Log Tampering / Deletion
* **Actor:** Compromised Admin / Database Attacker
* **Attack Path:** Attacker attempts modifying or purging `audit_logs` table to hide malicious activity.
* **Impact:** Critical — Loss of forensic traceability.
* **Preventive Control:** REVOKE `UPDATE` and `DELETE` privileges on `audit_logs` for ALL database roles.
* **Detective Control:** Write-only database trigger monitoring `audit_logs`.
* **Recovery Control:** Restore audit log state from encrypted PITR backups.
* **Required Test:** `TEST-AUDIT-002` (Attempt SQL UPDATE on `audit_logs` table).
* **Residual Risk:** Zero.

---

### 26. THR-26: Malicious File Upload in Deposit / ID Verification
* **Actor:** External Attacker
* **Attack Path:** Attacker uploads executable scripts or malware disguised as PNG/JPG receipt images.
* **Impact:** High — Web server or Admin portal compromise.
* **Preventive Control:** File MIME-type strict validation (`image/jpeg`, `image/png` only); max 5 MB file size limit.
* **Detective Control:** Storage bucket file extension and Content-Type inspection.
* **Recovery Control:** Delete non-compliant file from storage bucket immediately.
* **Required Test:** `TEST-SECURITY-004` (Attempt uploading `.php` / `.exe` file to storage bucket).
* **Residual Risk:** Low.

---

### 27. THR-27: CSV / Excel Injection in Batch Uploads
* **Actor:** Malicious Network Owner
* **Attack Path:** Owner inserts CSV formula payloads (`=CMD|' /C ...'!A1`) into card batch files.
* **Impact:** Medium — Remote code execution on Admin desktop when inspecting CSVs in Excel.
* **Preventive Control:** Sanitize all text fields starting with `=`, `+`, `-`, or `@` during batch parse.
* **Detective Control:** Batch text sanitization parser.
* **Recovery Control:** Strip formula characters during import processing.
* **Required Test:** `TEST-CARD-003` (Import batch file containing Excel formula strings).
* **Residual Risk:** Zero.

---

### 28. THR-28: API Denial of Service (DoS) / Request Flooding
* **Actor:** External Botnet
* **Attack Path:** Attacker floods `getNetworks` or `purchase_card` endpoints with 10,000 req/sec.
* **Impact:** High — Platform downtime for legitimate Yemeni users.
* **Preventive Control:** Cloudflare / Supabase API rate limiting (Max 100 req/min per IP).
* **Detective Control:** Cloudflare WAF traffic anomaly detection.
* **Recovery Control:** Automated IP blocking & Cloudflare Under Attack mode activation.
* **Required Test:** `TEST-SECURITY-005` (Simulate API request flood).
* **Residual Risk:** Medium.

---

### 29. THR-29: Push Notification Flooding
* **Actor:** Compromised Staff Account
* **Attack Path:** Attacker dispatches spam push notifications to all registered mobile app users.
* **Impact:** Medium — User annoyance and app uninstalls.
* **Preventive Control:** Restrict broadcast notification dispatch to `PLATFORM_ADMIN` role only.
* **Detective Control:** Push dispatch rate limit (Max 1 broadcast per hour).
* **Recovery Control:** Revoke notification dispatch access.
* **Required Test:** `TEST-ADMIN-001` (Attempt broadcast push with Support role).
* **Residual Risk:** Low.

---

### 30. THR-30: Suspended Network Card Sale Continuation
* **Actor:** Suspended Network Owner
* **Attack Path:** Suspended owner attempts issuing card sales via direct API calls.
* **Impact:** High — Unauthorized sales for unapproved networks.
* **Preventive Control:** Network status check (`networks.is_active = true AND networks.is_approved = true`) enforced inside purchase RPC.
* **Detective Control:** Purchase RPC validation rejection.
* **Recovery Control:** Immediate RPC transaction abort.
* **Required Test:** `TEST-PURCHASE-002` (Attempt purchasing card from suspended network).
* **Residual Risk:** Zero.
