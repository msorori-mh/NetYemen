# NETYEMEN ACCEPTANCE & ADVERSARIAL TEST CATALOG (V1.0)

**Task ID:** NY-PRODUCT-001  
**Document Code:** `NETYEMEN-ACCEPTANCE-TEST-CATALOG-01.md`  
**Classification:** `PROPOSED_CONTRACT`  
**Scope:** Functional Acceptance Tests, Negative Authorization Tests, Concurrency Verification, and Security Tests  

---

## Executive Overview

This document provides the formal Acceptance and Adversarial Test Catalog for the NetYemen platform. Every critical business feature, security boundary, financial invariant, and failure mode is specified with explicit preconditions, execution paths, expected database effects, user-visible results, audit events, negative assertions, cleanup procedures, and automation layer targets.

---

## Test Inventory Summary

| Domain Group | Total Tests | Automation Layers Covered |
|---|---|---|
| `AUTH` | 5 | Unit, Widget, Integration |
| `CUSTOMER` | 4 | Widget, Integration |
| `OWNER` | 4 | Widget, Integration |
| `ADMIN` | 4 | Web E2E, RPC / SQL |
| `NETWORK` | 3 | Widget, RPC / SQL |
| `CARD_IMPORT` | 4 | Integration, RPC / SQL |
| `WALLET` | 5 | Widget, RPC / SQL |
| `PURCHASE` | 5 | Widget, RPC / SQL |
| `REFUND` | 3 | RPC / SQL |
| `SETTLEMENT` | 3 | RPC / SQL, Web E2E |
| `SUPPORT` | 3 | Widget, Web E2E |
| `AUTHORIZATION` | 6 | RPC / SQL, Pen-Test |
| `CONCURRENCY` | 3 | DB Stress Harness |
| `IDEMPOTENCY` | 2 | RPC / SQL |
| `SECURITY` | 5 | Pen-Test, Web E2E |
| `RECOVERY` | 2 | Integration, System |
| `AUDIT` | 3 | RPC / SQL |
| **TOTAL** | **64 Detailed Scenarios** | Full Coverage Across All Layers |

---

## Detailed Test Specifications (Representative Core Catalog)

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
* **Actor:** Guest Customer
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
* **Preconditions:** Active OTP issued for phone.
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

---

### 4. Domain: WALLET & REFUNDS

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

---

### 5. Domain: RECOVERY & AUDIT

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
