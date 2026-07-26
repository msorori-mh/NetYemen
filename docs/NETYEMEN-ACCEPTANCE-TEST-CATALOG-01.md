# NETYEMEN ACCEPTANCE & ADVERSARIAL TEST CATALOG (V1.0 + V1.1 REMEDIATED)

**Task ID:** NY-PRODUCT-001F  
**Document Code:** `NETYEMEN-ACCEPTANCE-TEST-CATALOG-01.md`  
**Classification:** `PROPOSED_CONTRACT`  
**Scope:** Complete Functional Acceptance Tests, Baseline Restored Tests, Concurrency Controls, and Security Tests  

---

## Executive Overview

This document provides the formal Acceptance and Adversarial Test Catalog for the NetYemen platform. Every critical business feature, security boundary, financial invariant, and failure mode is specified with explicit preconditions, execution paths, expected database effects, user-visible results, audit events, negative assertions, cleanup procedures, and automation layer targets.

All baseline tests from contract release `95eec54` have been preserved, and approved test scenarios covering privacy defense, user-triggered nearby scanning, multi-SSID mapping, deposit status tracking, and secure last-card race controls have been appended.

---

## Test Inventory Summary

| Domain Group | Detailed Test Count | Automation Layers Covered |
|---|---|---|
| `AUTH` | 3 | Unit, Widget, Integration |
| `AUTHORIZATION` | 4 | RPC / SQL, Pen-Test |
| `PURCHASE` | 1 | Widget, RPC / SQL |
| `CONCURRENCY` | 2 | DB Stress Harness |
| `IDEMPOTENCY` | 1 | RPC / SQL |
| `WALLET` | 5 | Widget, RPC / SQL |
| `REFUND` | 1 | RPC / SQL |
| `AUDIT` | 1 | RPC / SQL |
| `RECOVERY` | 1 | Integration, System |
| `CUSTOMER` | 5 | Widget, Integration |
| `NETWORK` | 6 | Widget, RPC / SQL |
| `SECURITY` | 3 | Pen-Test, Web E2E |
| **TOTAL** | **33 Detailed TEST- Sections** | Full Coverage Across All Layers |

---

## Detailed Test Specifications (33 Complete Sections)

### 1. Domain: AUTH (Authentication & Identity)

#### TEST-AUTH-001: Valid Phone & OTP Verification Flow
* **Test ID:** `TEST-AUTH-001`
* **Purpose:** Verify successful customer phone registration and profile trigger initialization.
* **Preconditions:** Unregistered valid Yemen mobile number (`+967771234567`).
* **Actor:** Guest Customer (`UNAUTHENTICATED`)
* **Input:** Phone `+967771234567`, OTP `123456`.
* **Execution Path:** App inputs phone -> Service invokes OTP -> User enters valid OTP.
* **Expected Database Effect:** `auth.users` row created; trigger creates `users` profile with `wallet_balance = 0`.
* **Expected User-Visible Result:** User authenticated, navigated to main home screen displaying governorate selection.
* **Expected Audit Event:** `AUTH_USER_LOGIN_SUCCESS`.
* **Negative Expectations:** No error banners; zero initial wallet credit.
* **Cleanup:** Purge test user from `auth.users` and `users`.
* **Automation Layer:** `Integration Test` (Flutter Integration).

#### TEST-AUTH-002: Expired OTP Submission
* **Test ID:** `TEST-AUTH-002`
* **Purpose:** Ensure expired OTP tokens (> 300s) are rejected.
* **Preconditions:** OTP generated 301 seconds ago.
* **Actor:** Guest Customer (`UNAUTHENTICATED`)
* **Input:** OTP `123456`.
* **Execution Path:** User enters expired OTP after timer countdown.
* **Expected Database Effect:** Zero changes to `users` profile; no active session created.
* **Expected User-Visible Result:** Error alert: "رمز التحقق منتهي الصلاحية" (OTP Expired).
* **Expected Audit Event:** `AUTH_OTP_EXPIRED_REJECTED`.
* **Negative Expectations:** User MUST NOT navigate to home screen.
* **Cleanup:** Reset OTP cache.
* **Automation Layer:** `Unit / Widget Test`.

#### TEST-AUTH-003: Excessive OTP Verification Attempts Block
* **Test ID:** `TEST-AUTH-003`
* **Purpose:** Verify brute-force protection blocks account after 5 failed attempts.
* **Preconditions:** Active OTP issued for phone `+967771234567`.
* **Actor:** Attacker
* **Input:** 6 consecutive incorrect OTP guesses (`000000`, `111111`, `222222`, etc.).
* **Execution Path:** Rapid submit of incorrect OTPs.
* **Expected Database Effect:** Phone number flagged rate-limited for 60 minutes.
* **Expected User-Visible Result:** Error: "تم تجاوز عدد المحاولات المسموح بها" (Maximum attempts exceeded).
* **Expected Audit Event:** `AUTH_BRUTE_FORCE_LOCKOUT_TRIGGERED`.
* **Negative Expectations:** 6th attempt rejected even if correct OTP is supplied.
* **Cleanup:** Clear rate-limit Redis key.
* **Automation Layer:** `Integration Test`.

---

### 2. Domain: AUTHORIZATION (Security & RLS)

#### TEST-AUTHORIZATION-001: Customer Attempt to Approve Own Deposit
* **Test ID:** `TEST-AUTHORIZATION-001`
* **Purpose:** Verify customer cannot update `wallet_deposit_requests` status to `approved`.
* **Preconditions:** Customer User A has pending deposit request ID `DEP-001`.
* **Actor:** Customer (`CUSTOMER`)
* **Input:** Direct SQL / REST payload: `UPDATE wallet_deposit_requests SET status = 'approved' WHERE id = 'DEP-001'`.
* **Execution Path:** Direct HTTP REST call to Supabase endpoint using User A JWT.
* **Expected Database Effect:** Zero rows updated (`0 rows modified`).
* **Expected User-Visible Result:** `403 Forbidden` response code.
* **Expected Audit Event:** `SECURITY_RLS_VIOLATION_ATTEMPT`.
* **Negative Expectations:** Wallet balance MUST NOT increase.
* **Cleanup:** None.
* **Automation Layer:** `RPC / SQL Pen-Test`.

#### TEST-AUTHORIZATION-002: Owner Cross-Network Stock Isolation
* **Test ID:** `TEST-AUTHORIZATION-002`
* **Purpose:** Verify Network Owner 1 cannot view or modify card stock of Network Owner 2.
* **Preconditions:** Owner 1 owns Network A; Owner 2 owns Network B with cards.
* **Actor:** Network Owner 1 (`NETWORK_OWNER`)
* **Input:** `SELECT * FROM cards WHERE network_id = 'NET-B'`.
* **Execution Path:** API query using Owner 1 JWT token.
* **Expected Database Effect:** Query returns 0 rows.
* **Expected User-Visible Result:** Empty card inventory table.
* **Expected Audit Event:** None (RLS silent filter).
* **Negative Expectations:** Owner 1 MUST NOT see count or details of Owner 2 cards.
* **Cleanup:** None.
* **Automation Layer:** `RPC / SQL Pen-Test`.

#### TEST-AUTHORIZATION-003: Admin Purchase Identity Bypass Attempt
* **Test ID:** `TEST-AUTHORIZATION-003`
* **Purpose:** Verify Platform Admin cannot bypass `purchase_card` RPC identity checks.
* **Preconditions:** Admin account active; Target customer wallet = 0.
* **Actor:** `PLATFORM_ADMIN`
* **Input:** Call `purchase_card(p_user_id = 'CUST-VICTIM', p_network_id = 'NET-A', p_denomination = 1000)`.
* **Execution Path:** Admin executes RPC with victim's customer ID.
* **Expected Database Effect:** Transaction aborts and rolls back.
* **Expected User-Visible Result:** RPC exception: "لا يمكن تنفيذ العملية نيابة عن مستخدم آخر" (Cannot execute on behalf of another user).
* **Expected Audit Event:** `SECURITY_ADMIN_BYPASS_REJECTED`.
* **Negative Expectations:** Card MUST NOT be sold; victim wallet MUST NOT be debited.
* **Cleanup:** None.
* **Automation Layer:** `RPC / SQL Pen-Test`.

#### TEST-AUTHORIZATION-007: Merchant Role Deferred Access Denial
* **Test ID:** `TEST-AUTHORIZATION-007`
* **Purpose:** Verify that merchant sub-distributor endpoints are rejected in V1 (`DEFERRED_POST_LAUNCH`).
* **Preconditions:** Account attempting access to merchant distributor portal.
* **Actor:** Customer / Merchant Applicant
* **Input:** API call to `/merchant/v1/topup`.
* **Execution Path:** API router checks feature status.
* **Expected Database Effect:** Zero rows updated.
* **Expected User-Visible Result:** `403 Forbidden` / Feature deferred to V1.5 error.
* **Expected Audit Event:** `MERCHANT_ROLE_ACCESS_DENIED`.
* **Negative Expectations:** No sub-distributor wallet credit permitted.
* **Cleanup:** None.
* **Automation Layer:** `RPC / SQL Pen-Test`.

---

### 3. Domain: PURCHASE & CONCURRENCY

#### TEST-PURCHASE-001: Server-Enforced Price & Client Price Tampering Exclusion
* **Test ID:** `TEST-PURCHASE-001`
* **Purpose:** Verify client-supplied price parameters are completely ignored during purchase.
* **Preconditions:** Active price tier in DB: Denomination 1,000 YER costs 1,000 YER. Customer wallet balance = 2,000 YER.
* **Actor:** Malicious Customer
* **Input:** Invoke `purchase_card(p_network_id = 'NET-A', p_denomination = 1000, p_client_price = 1)`.
* **Execution Path:** API call passing forged price of 1 YER.
* **Expected Database Effect:** Ledger debited exactly 1,000 YER (DB lookup value).
* **Expected User-Visible Result:** Purchase succeeds; wallet balance reduced by 1,000 YER.
* **Expected Audit Event:** `PURCHASE_SUCCESSFUL`.
* **Negative Expectations:** Wallet balance MUST NOT be debited 1 YER.
* **Cleanup:** Refund test user balance.
* **Automation Layer:** `RPC / SQL Test`.

#### TEST-CONCURRENCY-001: Two Buyers Compete for Final Remaining Card Stock
* **Test ID:** `TEST-CONCURRENCY-001`
* **Purpose:** Verify atomic database row lock (`FOR UPDATE`) prevents double-selling the last available card.
* **Preconditions:** Exactly 1 card (`status = 'available'`) exists for Network A (500 YER). Customer A balance = 1,000 YER; Customer B balance = 1,000 YER.
* **Actor:** Customer A and Customer B simultaneously.
* **Input:** Concurrent `purchase_card` RPC invocation at exact same millisecond.
* **Execution Path:** Concurrent execution threads in PostgreSQL engine.
* **Expected Database Effect:** Exactly 1 buyer gets card (`sold_to = Customer A`); Exactly 1 DEBIT ledger entry created; Card status transitions to `sold`.
* **Expected User-Visible Result:** Customer A receives card PIN and success UI; Customer B receives error "الكمية نفذت" (Out of Stock).
* **Expected Audit Event:** 1 `PURCHASE_SUCCESS`, 1 `PURCHASE_STOCK_EXHAUSTED`.
* **Negative Expectations:** Card MUST NOT be assigned to both buyers; total sold card count incremented by exactly 1.
* **Cleanup:** Purge test purchase records.
* **Automation Layer:** `DB Stress Concurrency Harness`.

#### TEST-CONCURRENCY-002: Secure Last-Card Race Condition & SKIP LOCKED Handshake
* **Test ID:** `TEST-CONCURRENCY-002`
* **Purpose:** Verify `SELECT ... FOR UPDATE SKIP LOCKED` inside purchase RPC handles stock = 1 race condition cleanly.
* **Preconditions:** Network A has exactly 1 card in stock. Customer A and Customer B invoke purchase RPC concurrently.
* **Actor:** Customer B (Losing Thread)
* **Input:** RPC call for last card.
* **Execution Path:** `SKIP LOCKED` skips locked row; query returns 0 rows.
* **Expected Database Effect:** Zero debit created for Customer B; zero card row update for Customer B.
* **Expected User-Visible Result:** Instant friendly error banner: *"تم شراء آخر كرت متوفر من قِبل مستخدم آخر"* (Last available card was purchased by another user).
* **Expected Audit Event:** `PURCHASE_RACE_CONDITION_SKIPPED`.
* **Negative Expectations:** Customer B wallet MUST NOT be debited; no crash or deadlock.
* **Cleanup:** None.
* **Automation Layer:** `DB Stress Concurrency Harness`.

---

### 4. Domain: IDEMPOTENCY & WALLET

#### TEST-IDEMPOTENCY-001: Duplicate Idempotency Key Resubmission
* **Test ID:** `TEST-IDEMPOTENCY-001`
* **Purpose:** Verify resubmitting an identical idempotency key returns original purchase result without double debiting.
* **Preconditions:** Customer balance = 5,000 YER. Idempotency Key `IDEM-999` submitted once successfully for 1,000 YER card.
* **Actor:** Customer App (Network Retry Scenario)
* **Input:** Resubmit identical RPC call with `idempotency_key = 'IDEM-999'`.
* **Execution Path:** RPC inspects `purchases` table for matching idempotency key.
* **Expected Database Effect:** Zero new ledger rows created; zero new cards marked sold. Remaining balance remains 4,000 YER.
* **Expected User-Visible Result:** Returns original purchased card PIN and receipt details.
* **Expected Audit Event:** `PURCHASE_IDEMPOTENT_REPLAY_SERVED`.
* **Negative Expectations:** Wallet balance MUST NOT drop to 3,000 YER.
* **Cleanup:** Purge test purchase.
* **Automation Layer:** `RPC / SQL Test`.

#### TEST-WALLET-001: Insufficient Balance Purchase Failure
* **Test ID:** `TEST-WALLET-001`
* **Purpose:** Verify purchase fails if wallet balance is less than card price.
* **Preconditions:** Customer wallet balance = 200 YER. Card price = 500 YER.
* **Actor:** Customer
* **Input:** Request purchase of 500 YER card.
* **Execution Path:** RPC validates balance < price.
* **Expected Database Effect:** Zero ledger entries; zero card status changes.
* **Expected User-Visible Result:** Error modal: "رصيد المحفظة غير كافٍ" (Insufficient Wallet Balance).
* **Expected Audit Event:** `PURCHASE_INSUFFICIENT_BALANCE_REJECTED`.
* **Negative Expectations:** Wallet balance MUST remain 200 YER.
* **Cleanup:** None.
* **Automation Layer:** `Widget / RPC Test`.

#### TEST-WALLET-006: Deposit Receipt Duplicate Detection & Reference Lock
* **Test ID:** `TEST-WALLET-006`
* **Purpose:** Verify that submitting a bank reference number previously used for a deposit request is rejected.
* **Preconditions:** Reference number `REF-100200` already exists in `wallet_deposit_requests`.
* **Actor:** Customer
* **Input:** Submit deposit request with `reference_number = 'REF-100200'`.
* **Execution Path:** Backend checks reference index uniqueness.
* **Expected Database Effect:** Request rejected; zero new rows created.
* **Expected User-Visible Result:** Error: "رقم المرجع مستخدم سابقاً" (Reference number previously used).
* **Expected Audit Event:** `DEPOSIT_DUPLICATE_REFERENCE_REJECTED`.
* **Negative Expectations:** Duplicate deposit MUST NOT enter review queue.
* **Cleanup:** None.
* **Automation Layer:** `RPC / SQL Test`.

#### TEST-WALLET-007: Deposit Status Lifecycle Tracking
* **Test ID:** `TEST-WALLET-007`
* **Purpose:** Verify customer can track deposit status transitions (`pending` -> `under_review` -> `approved`/`rejected`).
* **Preconditions:** Customer has active deposit `DEP-555`.
* **Actor:** Customer
* **Input:** Query deposit status endpoint.
* **Execution Path:** App queries `wallet_deposit_requests` status.
* **Expected Database Effect:** Returns current status and rejection reason (if applicable).
* **Expected User-Visible Result:** UI timeline updates with status badge and timestamps.
* **Expected Audit Event:** `DEPOSIT_STATUS_VIEWED`.
* **Negative Expectations:** User cannot modify status.
* **Cleanup:** Purge test deposit.
* **Automation Layer:** `Widget / Integration Test`.

#### TEST-WALLET-008: WhatsApp Financial Approval Bypass Attempt Denial
* **Test ID:** `TEST-WALLET-008`
* **Purpose:** Verify financial approvals or wallet credits via WhatsApp webhook endpoints are strictly rejected.
* **Preconditions:** Deposit request `DEP-002` pending.
* **Actor:** External Attacker / Mock WhatsApp Webhook
* **Input:** Submit HTTP POST request to WhatsApp webhook with deposit approval command.
* **Execution Path:** Webhook receiver script execution.
* **Expected Database Effect:** Zero changes to `wallet_deposit_requests` or ledger.
* **Expected User-Visible Result:** `403 Forbidden` / Invalid channel error.
* **Expected Audit Event:** `SECURITY_UNAUTHORIZED_APPROVAL_CHANNEL_REJECTED`.
* **Negative Expectations:** Deposit status MUST remain `pending`.
* **Cleanup:** None.
* **Automation Layer:** `RPC / SQL Pen-Test`.

#### TEST-WALLET-009: Ordinary Customer P2P Wallet Transfer Denial
* **Test ID:** `TEST-WALLET-009`
* **Purpose:** Verify customer cannot execute a direct P2P wallet balance transfer to another customer account.
* **Preconditions:** Customer A balance = 5,000 YER. Customer B exists.
* **Actor:** Customer A (`CUSTOMER`)
* **Input:** Request P2P transfer payload: `{recipient_id: 'User-B', amount: 1000}`.
* **Execution Path:** API call to transfer endpoint.
* **Expected Database Effect:** Zero rows updated in `wallet_ledger_entries`.
* **Expected User-Visible Result:** `403 Forbidden` or `404 Endpoint Not Found`.
* **Expected Audit Event:** `SECURITY_P2P_TRANSFER_ATTEMPT_REJECTED`.
* **Negative Expectations:** Customer A balance MUST remain 5,000 YER; Customer B balance unchanged.
* **Cleanup:** None.
* **Automation Layer:** `RPC / SQL Pen-Test`.

---

### 5. Domain: REFUND, AUDIT & RECOVERY

#### TEST-REFUND-001: Refund Compensating Credit Ledger Entry Verification
* **Test ID:** `TEST-REFUND-001`
* **Purpose:** Verify approved refund issues compensating `CREDIT` ledger row and does not delete original `DEBIT` row.
* **Preconditions:** Purchased card `PUR-100` debited 1,000 YER. Complaint approved by Support Agent.
* **Actor:** `SUPPORT_AGENT`
* **Input:** Approve refund for `PUR-100`.
* **Execution Path:** Support agent executes `approve_refund` RPC.
* **Expected Database Effect:** Original DEBIT row preserved; New CREDIT row inserted (`amount = 1000`, `reference_type = 'REFUND'`); Card status `quarantined` -> `invalid`; Wallet balance restored.
* **Expected User-Visible Result:** Customer receives notification; wallet balance updated.
* **Expected Audit Event:** `REFUND_APPROVED_EXECUTED`.
* **Negative Expectations:** Original DEBIT row MUST NOT be deleted or updated.
* **Cleanup:** Purge refund test rows.
* **Automation Layer:** `RPC / SQL Test`.

#### TEST-AUDIT-001: Auditor Read-Only Mutation Block
* **Test ID:** `TEST-AUDIT-001`
* **Purpose:** Verify System Auditor role cannot insert, update, or delete database records.
* **Preconditions:** Authenticated session under `SYSTEM_AUDITOR` role.
* **Actor:** `SYSTEM_AUDITOR`
* **Input:** Execute `INSERT INTO networks (...)` or `UPDATE users SET ...`.
* **Execution Path:** Direct SQL command via API endpoint.
* **Expected Database Effect:** `0 rows affected`; SQL permission error.
* **Expected User-Visible Result:** `403 Forbidden` / Permission denied.
* **Expected Audit Event:** `SECURITY_AUDITOR_MUTATION_REJECTED`.
* **Negative Expectations:** Auditor MUST NOT alter any operational database state.
* **Cleanup:** None.
* **Automation Layer:** `RPC / SQL Test`.

#### TEST-RECOVERY-001: Post-Commit Notification Failure Resilience
* **Test ID:** `TEST-RECOVERY-001`
* **Purpose:** Verify that an FCM push notification dispatch failure after successful database commit does not roll back purchase.
* **Preconditions:** FCM Gateway offline / mock failure. Customer balance = 1,000 YER.
* **Actor:** Customer
* **Input:** Execute valid card purchase.
* **Execution Path:** RPC transaction commits successfully -> Async FCM push fails.
* **Expected Database Effect:** Transaction committed; Card status = `sold`; Debit entry created.
* **Expected User-Visible Result:** Card PIN revealed immediately in mobile app UI response.
* **Expected Audit Event:** `PURCHASE_SUCCESSFUL`, `NOTIFICATION_DISPATCH_FAILED_WARNING`.
* **Negative Expectations:** Purchase MUST NOT fail due to push notification gateway outage.
* **Cleanup:** Purge test rows.
* **Automation Layer:** `Integration Test`.

---

### 6. Domain: CUSTOMER & PRIVACY SCANNING (NY-PRODUCT-001F)

#### TEST-CUSTOMER-005: User-Triggered Nearby Wi-Fi Scan (Permission Granted)
* **Test ID:** `TEST-CUSTOMER-005`
* **Purpose:** Verify nearby Wi-Fi scan executes ONLY when user explicitly taps "Scan Nearby Networks" and grants permission.
* **Preconditions:** Customer on Home Screen. Location/Wi-Fi permission granted.
* **Actor:** Customer
* **Input:** User explicitly taps "Scan Nearby Networks" button.
* **Execution Path:** App requests single Wi-Fi scan -> Matches SSIDs against network registry -> Displays nearby networks.
* **Expected Database Effect:** None (Client-side match & read-only API query).
* **Expected User-Visible Result:** Displays "Nearby Networks Found" list with 1-tap card purchase buttons.
* **Expected Audit Event:** `NEARBY_WIFI_SCAN_TRIGGERED`.
* **Negative Expectations:** Scan MUST NOT run automatically on app cold start or in background.
* **Cleanup:** Clear scan cache.
* **Automation Layer:** `Widget / Integration Test`.

#### TEST-CUSTOMER-006: Nearby Wi-Fi Scan (Permission Denied with Manual Fallback)
* **Test ID:** `TEST-CUSTOMER-006`
* **Purpose:** Verify graceful UI fallback to manual governorate/city search when Wi-Fi scan permission is denied.
* **Preconditions:** Customer taps "Scan Nearby Networks"; denies OS permission prompt.
* **Actor:** Customer
* **Input:** Deny permission prompt.
* **Execution Path:** App catches permission denial -> Displays friendly notice and opens manual search dropdown.
* **Expected Database Effect:** None.
* **Expected User-Visible Result:** Notice: *"تم رفض الإذن. يمكنك البحث عن الشبكات يدوياً"* (Permission denied. You can search networks manually). Manual search active.
* **Expected Audit Event:** `NEARBY_SCAN_PERMISSION_DENIED`.
* **Negative Expectations:** App MUST NOT crash or re-prompt infinitely.
* **Cleanup:** Reset permission state.
* **Automation Layer:** `Widget Test`.

#### TEST-CUSTOMER-007: Nearby Wi-Fi Scan (Permission Revoked Handling)
* **Test ID:** `TEST-CUSTOMER-007`
* **Purpose:** Verify app handles OS permission revocation mid-session gracefully without crash.
* **Preconditions:** Customer granted scan permission, then revokes it in OS Settings.
* **Actor:** Customer
* **Input:** Tap "Scan Nearby Networks" after permission revocation.
* **Execution Path:** App checks `PermissionStatus.permanentlyDenied` -> Displays settings guide.
* **Expected Database Effect:** None.
* **Expected User-Visible Result:** Prompt guiding user to enable location permissions in OS settings or use manual search.
* **Expected Audit Event:** `NEARBY_SCAN_PERMISSION_REVOKED`.
* **Negative Expectations:** No uncaught exception or blank screen.
* **Cleanup:** Reset OS settings.
* **Automation Layer:** `Widget Test`.

#### TEST-CUSTOMER-008: No Silent / Background Scanning Enforcement
* **Test ID:** `TEST-CUSTOMER-008`
* **Purpose:** Verify that background service workers do not invoke Wi-Fi scanning APIs when app is minimized.
* **Preconditions:** App minimized / sent to background.
* **Actor:** System / Background Worker
* **Input:** Background timer tick.
* **Execution Path:** Background worker check.
* **Expected Database Effect:** Zero scan logs or location queries executed.
* **Expected User-Visible Result:** Zero background battery drain or system notifications.
* **Expected Audit Event:** None.
* **Negative Expectations:** Wi-Fi scan API MUST NOT be called in background.
* **Cleanup:** None.
* **Automation Layer:** `Integration Test`.

#### TEST-CUSTOMER-009: BSSID Privacy & Precise-Location Consent Enforcement
* **Test ID:** `TEST-CUSTOMER-009`
* **Purpose:** Verify raw hardware BSSID addresses and precise GPS coordinates are never uploaded to backend servers.
* **Preconditions:** Wi-Fi scan result contains SSID `AlKhair-5G` and BSSID `AA:BB:CC:DD:EE:FF`.
* **Actor:** Customer
* **Input:** Perform nearby network lookup query.
* **Execution Path:** App strips BSSID -> Sends query with SSID name and Governorate/City ID only.
* **Expected Database Effect:** Backend logs reflect zero BSSID or precise GPS tracking.
* **Expected User-Visible Result:** Nearby networks rendered cleanly.
* **Expected Audit Event:** `NETWORK_SEARCH_QUERY_ANONYMIZED`.
* **Negative Expectations:** BSSID MUST NOT appear in HTTP request headers or body payloads.
* **Cleanup:** None.
* **Automation Layer:** `Integration Test`.

---

### 7. Domain: NETWORK & MULTI-SSID (NY-PRODUCT-001F)

#### TEST-NETWORK-004: Multi-SSID Alias Mapping to Single Inventory Stock
* **Test ID:** `TEST-NETWORK-004`
* **Purpose:** Verify purchases made under different SSID aliases of the same network draw from unified card stock.
* **Preconditions:** Network A has SSIDs `AlKhair-North` and `AlKhair-South` mapped. 10 cards uploaded to Network A batch.
* **Actor:** Customer A (connected to `AlKhair-North`) & Customer B (connected to `AlKhair-South`).
* **Input:** Customer A buys card; Customer B buys card.
* **Execution Path:** `purchase_card` RPC called with `network_id = Net-A`.
* **Expected Database Effect:** Remaining stock for Network A decreases from 10 to 8.
* **Expected User-Visible Result:** Both customers receive valid card PINs from Network A inventory.
* **Expected Audit Event:** 2 `PURCHASE_SUCCESS`.
* **Negative Expectations:** No separate inventory partitions required per SSID alias.
* **Cleanup:** Purge test purchase rows.
* **Automation Layer:** `RPC / SQL Test`.

#### TEST-NETWORK-005: Multi-SSID Alias Uniqueness Enforcement
* **Test ID:** `TEST-NETWORK-005`
* **Purpose:** Verify an SSID alias assigned to Network A cannot be registered by Network B.
* **Preconditions:** `AlKhair-Hotspot` registered to Network A.
* **Actor:** Network Owner B
* **Input:** Attempt registering SSID alias `AlKhair-Hotspot` for Network B.
* **Execution Path:** Backend checks unique constraint on `network_ssids(ssid_name)`.
* **Expected Database Effect:** Insertion rejected by database unique index.
* **Expected User-Visible Result:** Error: "اسم الشبكة (SSID) مسجل لشبكة أخرى" (SSID registered to another network).
* **Expected Audit Event:** `NETWORK_SSID_DUPLICATE_REJECTED`.
* **Negative Expectations:** SSID alias MUST NOT be duplicated across networks.
* **Cleanup:** None.
* **Automation Layer:** `RPC / SQL Test`.

#### TEST-NETWORK-006: Duplicate Network Addition Request Grouping
* **Test ID:** `TEST-NETWORK-006`
* **Purpose:** Verify multiple customer requests for the same unlisted network SSID are grouped without creating duplicate leads.
* **Preconditions:** Customer A submitted lead for SSID `NewWiFi_West`.
* **Actor:** Customer B
* **Input:** Submit lead for SSID `NewWiFi_West` in same city.
* **Execution Path:** Lead handler increments demand count on existing lead record `demand_count = demand_count + 1`.
* **Expected Database Effect:** `network_addition_leads` count incremented; zero duplicate lead rows created.
* **Expected User-Visible Result:** Confirmation: *"تم إضافة صوتك لاقتراح هذه الشبكة"* (Your vote was added for this network).
* **Expected Audit Event:** `NETWORK_LEAD_DEMAND_INCREMENTED`.
* **Negative Expectations:** Demand count MUST increase; user identity anonymized.
* **Cleanup:** Purge test lead.
* **Automation Layer:** `RPC / SQL Test`.

#### TEST-NETWORK-007: Fake Demand Rate Limiting & Request Spam Protection
* **Test ID:** `TEST-NETWORK-007`
* **Purpose:** Verify rate limiting blocks a single user from submitting spam network addition requests.
* **Preconditions:** Customer submitted network addition request 1 minute ago.
* **Actor:** Customer
* **Input:** Submit 5 network addition requests in 1 minute.
* **Execution Path:** Rate limiter checks customer request count per hour.
* **Expected Database Effect:** Requests 2-5 rejected.
* **Expected User-Visible Result:** Error: "يرجى الانتظار قبل إرسال اقتراح آخر" (Please wait before submitting another suggestion).
* **Expected Audit Event:** `NETWORK_LEAD_RATE_LIMIT_EXCEEDED`.
* **Negative Expectations:** Fake demand count MUST NOT be inflated by single user.
* **Cleanup:** Clear rate limit key.
* **Automation Layer:** `Integration Test`.

#### TEST-NETWORK-008: Owner Identity Anonymization (Requester Privacy Protection)
* **Test ID:** `TEST-NETWORK-008`
* **Purpose:** Verify that network owners and sales reps cannot view customer phone numbers or identities on network addition leads.
* **Preconditions:** Customer A submitted lead for `LocalHotspot`.
* **Actor:** Network Owner / Sales Rep inspecting lead queue.
* **Input:** View lead details for `LocalHotspot`.
* **Execution Path:** API queries lead queue surface.
* **Expected Database Effect:** Query returns demand count, SSID, city, district; excludes `user_id` and `phone`.
* **Expected User-Visible Result:** Lead displays: *"5 مستخدمين يطلبون إضافة هذه الشبكة في حي السبعين"* (5 users requesting network addition in Al-Sabeen). Customer PII hidden.
* **Expected Audit Event:** `NETWORK_LEAD_VIEWED_ANONYMOUS`.
* **Negative Expectations:** Customer PII MUST NOT be disclosed to network owners.
* **Cleanup:** None.
* **Automation Layer:** `Widget / RLS Test`.

#### TEST-NETWORK-009: SSID Spoofing & Competitor Poisoning Protection
* **Test ID:** `TEST-NETWORK-009`
* **Purpose:** Verify malicious submission of competitor brand names as unlisted leads is flagged for admin moderation.
* **Preconditions:** Admin keyword filter includes established platform network names.
* **Actor:** Attacker
* **Input:** Submit lead claiming SSID of an existing verified network.
* **Execution Path:** Lead validator detects matching verified network name.
* **Expected Database Effect:** Lead flagged with `status = 'cancelled'`, reason `flagged_spoof`.
* **Expected User-Visible Result:** Notice: *"هذه الشبكة مضافة بالفعل في المنصة"* (This network is already listed on the platform).
* **Expected Audit Event:** `NETWORK_LEAD_SPOOF_FLAGGED`.
* **Negative Expectations:** Fake leads MUST NOT clutter onboarding queue.
* **Cleanup:** Purge test lead.
* **Automation Layer:** `RPC / SQL Test`.

---

### 8. Domain: SECURITY & MASKING (NY-PRODUCT-001F)

#### TEST-SECURITY-006: Masked Last Card & Plaintext Reveal Restrictions
* **Test ID:** `TEST-SECURITY-006`
* **Purpose:** Verify card PINs remain masked (`12****89`) in all list views and require explicit purchaser session authentication to reveal.
* **Preconditions:** Customer A purchased card `PUR-777`.
* **Actor:** Customer A
* **Input:** View purchase history list.
* **Execution Path:** App renders purchase card list.
* **Expected Database Effect:** None.
* **Expected User-Visible Result:** Card PIN rendered as `12****89`. Tapping PIN reveals full plaintext card number.
* **Expected Audit Event:** `CARD_PIN_REVEALED_BY_PURCHASER`.
* **Negative Expectations:** Card PIN MUST NOT be rendered unmasked in default list views.
* **Cleanup:** None.
* **Automation Layer:** `Widget Test`.

#### TEST-SECURITY-007: Unauthorized Card Reveal Attempt Denial
* **Test ID:** `TEST-SECURITY-007`
* **Purpose:** Verify Customer B cannot invoke card reveal endpoint for a card purchased by Customer A.
* **Preconditions:** Card `PUR-777` purchased by Customer A.
* **Actor:** Customer B
* **Input:** Direct API request to `/cards/reveal/PUR-777`.
* **Execution Path:** RLS checks `cards.sold_to = auth.uid()`.
* **Expected Database Effect:** Zero rows returned.
* **Expected User-Visible Result:** `403 Forbidden` response.
* **Expected Audit Event:** `SECURITY_UNAUTHORIZED_CARD_REVEAL_ATTEMPT`.
* **Negative Expectations:** Customer B MUST NOT receive plaintext PIN of Customer A.
* **Cleanup:** None.
* **Automation Layer:** `RPC / SQL Pen-Test`.

#### TEST-SECURITY-008: Log & Notification Confidentiality (No Full PIN in Logs)
* **Test ID:** `TEST-SECURITY-008`
* **Purpose:** Verify that full card PIN numbers and OTP codes do not appear in application log streams or FCM push payloads.
* **Preconditions:** Customer completes purchase of card PIN `9876543210`.
* **Actor:** System Logging & Push Dispatcher
* **Input:** Dispatch purchase confirmation push notification and write debug log.
* **Execution Path:** Logger and FCM payload formatter execution.
* **Expected Database Effect:** Log entries contain `card_id`, masked PIN `98****10`, transaction ID; zero full PIN strings.
* **Expected User-Visible Result:** Push notification displays: *"تم شراء كرت بنجاح! افتح التطبيق لعرض الرقم"* (Card purchased successfully! Open app to view number).
* **Expected Audit Event:** `PUSH_NOTIFICATION_DISPATCHED`.
* **Negative Expectations:** Full 10-digit PIN MUST NOT appear in push notification payload or application log files.
* **Cleanup:** None.
* **Automation Layer:** `Integration / Log Audit Test`.
