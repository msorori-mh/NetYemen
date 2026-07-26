# NETYEMEN ACCEPTANCE & ADVERSARIAL TEST CATALOG (V1.0 + V1.1 ENHANCEMENTS)

**Task ID:** NY-PRODUCT-001  
**Document Code:** `NETYEMEN-ACCEPTANCE-TEST-CATALOG-01.md`  
**Classification:** `PROPOSED_CONTRACT`  
**Scope:** Functional Acceptance Tests, Negative Authorization Tests, Concurrency Verification, and Security Tests (Updated with NY-PRODUCT-001E Coverage)  

---

## Executive Overview

This document provides the formal Acceptance and Adversarial Test Catalog for the NetYemen platform. Every critical business feature, security boundary, financial invariant, and failure mode is specified with explicit preconditions, execution paths, expected database effects, user-visible results, audit events, negative assertions, cleanup procedures, and automation layer targets.

---

## Test Inventory Summary

| Domain Group | Total Tests | Automation Layers Covered |
|---|---|---|
| `AUTH` | 5 | Unit, Widget, Integration |
| `CUSTOMER` | 6 | Widget, Integration |
| `OWNER` | 4 | Widget, Integration |
| `ADMIN` | 5 | Web E2E, RPC / SQL |
| `NETWORK` | 4 | Widget, RPC / SQL |
| `CARD_IMPORT` | 4 | Integration, RPC / SQL |
| `WALLET` | 7 | Widget, RPC / SQL |
| `PURCHASE` | 5 | Widget, RPC / SQL |
| `REFUND` | 3 | RPC / SQL |
| `SETTLEMENT` | 3 | RPC / SQL, Web E2E |
| `SUPPORT` | 3 | Widget, Web E2E |
| `AUTHORIZATION` | 8 | RPC / SQL, Pen-Test |
| `CONCURRENCY` | 4 | DB Stress Harness |
| `IDEMPOTENCY` | 2 | RPC / SQL |
| `SECURITY` | 5 | Pen-Test, Web E2E |
| `RECOVERY` | 2 | Integration, System |
| `AUDIT` | 3 | RPC / SQL |
| **TOTAL** | **73 Detailed Scenarios** | Full Coverage Across All Layers |

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

#### TEST-AUTHORIZATION-007: Peer-to-Peer (P2P) Wallet Transfer Denial
* **Test ID:** `TEST-AUTHORIZATION-007`
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

#### TEST-AUTHORIZATION-008: WhatsApp Financial Approval Bypass Denial
* **Test ID:** `TEST-AUTHORIZATION-008`
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

---

### 3. Domain: PURCHASE & CONCURRENCY

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

#### TEST-CONCURRENCY-002: Secure Last-Card Lock & Clean Failure Message
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

### 4. Domain: DISCOVERY & NETWORK ENHANCEMENTS (NY-PRODUCT-001E)

#### TEST-CUSTOMER-005: Nearby Wi-Fi SSID Auto-Matching
* **Test ID:** `TEST-CUSTOMER-005`
* **Purpose:** Verify customer mobile app correctly matches scanned Wi-Fi SSID against registered network SSIDs.
* **Preconditions:** Network A registered with SSID alias `AlKhair_Wi-Fi_5G`. Device scans SSID `AlKhair_Wi-Fi_5G`.
* **Actor:** Customer
* **Input:** Local Wi-Fi scan result containing `AlKhair_Wi-Fi_5G`.
* **Execution Path:** Mobile app queries network registry by SSID.
* **Expected Database Effect:** None (Read-only query).
* **Expected User-Visible Result:** Banner displayed: *"أنت بالقرب من شبكة الخير - انقر لشراء الكروت"* (You are near Al-Khair Network - Tap to buy cards).
* **Expected Audit Event:** None.
* **Negative Expectations:** Unregistered SSIDs do not display purchase banners.
* **Cleanup:** None.
* **Automation Layer:** `Widget / Integration Test`.

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

#### TEST-CUSTOMER-006: Network Addition Lead Request Submission
* **Test ID:** `TEST-CUSTOMER-006`
* **Purpose:** Verify customer can submit a "Suggest New Network" lead for unlisted Wi-Fi hotspots.
* **Preconditions:** Customer authenticated. Unlisted SSID `NewNetwork_Guest`.
* **Actor:** Customer
* **Input:** SSID `NewNetwork_Guest`, City `Sana'a`, District `Al-Sabeen`, Notes `Local hotspot near market`.
* **Execution Path:** App submits payload to `network_addition_leads` table.
* **Expected Database Effect:** New row created in `network_addition_leads` (`status = 'submitted'`).
* **Expected User-Visible Result:** Success confirmation: *"شكراً لك! تم إرسال اقتراح الشبكة لفريقنا"* (Thank you! Network suggestion sent to our team).
* **Expected Audit Event:** `NETWORK_LEAD_SUBMITTED`.
* **Negative Expectations:** Unapproved lead MUST NOT appear in public network marketplace discovery.
* **Cleanup:** Delete test lead row.
* **Automation Layer:** `Widget / Integration Test`.
