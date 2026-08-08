# NetYemen V1 Commerce Core Path Closure Report

**Task ID:** NY-V1-COMMERCE-CORE-001  
**Mission:** NETYEMEN-V1-COMMERCE-WALLET-DEPOSIT-PURCHASE-CARD-DELIVERY-CLOSURE-01  
**Branch:** `kimi/NY-V1-COMMERCE-CORE-001`  
**STARTING_SHA:** `5e15eea833da018ed6e782b157e44da68d204a76`  
**ENDING_SHA:** `97fbe52ecbd0ad25300822dc1195bda952aef84d`  

---

## Executive Summary

This mission closed the provider-neutral, source-only V1 commerce path for NetYemen:

- Wallet foundation with immutable ledger and trigger-maintained cached balance.
- Deposit request/review workflow with idempotent approval and exactly-once credit.
- Atomic package purchase with server-side price authority, wallet debit, and inventory consumption.
- Provider-neutral card/voucher fulfillment boundary (no secrets stored; fails closed).
- Refund/dispute hook with compensating ledger entries.
- Settlement-ready accounting references for network owners.
- Role-based authorization, RLS hardening, and controlled RPCs.
- Flutter customer/finance commerce UX in Arabic RTL.
- SQL test suite plus concurrent last-unit race test.

The implementation deliberately does **not** bind production financial providers, card vaults, or settlement schedules because the governing open decisions remain unresolved. All such binding is surfaced in the consolidated `OWNER_DECISION_PACKAGE` below.

---

## WALLET

- Table: `public.wallet_accounts` (cached balance, currency, status).
- Immutable ledger: `public.customer_wallet_ledger` (append-only, no UPDATE/DELETE policies).
- Trigger `trg_update_wallet_account_balance` maintains `cached_balance` from ledger deltas.
- Constraints enforce non-negative balance and positive amounts.
- Idempotency via `UNIQUE INDEX idx_customer_wallet_ledger_idempotency (user_id, idempotency_key)`.
- Customer read via `get_customer_wallet()` RPC; no direct balance mutation permitted.

## DEPOSITS

- Table: `public.wallet_deposit_requests` with statuses `pending`, `under_review`, `approved`, `rejected`, `cancelled`.
- Customer creates request via `create_wallet_deposit_request()`.
- Finance officer reviews via `review_wallet_deposit_request()`.
- Approval atomically:
  1. Locks deposit row with `FOR UPDATE`.
  2. Verifies no pre-existing `ledger_entry_id`.
  3. Locks wallet and inserts one `CREDIT` ledger entry.
  4. Marks deposit `approved` with `ledger_entry_id`.
- Replay of an approved deposit returns `replayed: true` without double credit.
- Provider-neutral `bank_directory` stores deposit channels; no real bank API bound (OD-FIN-01 / OD-FIN-03).

## PURCHASE

- RPC `purchase_package(p_package_id, p_idempotency_key)` performs the atomic flow:
  1. Validates active/verified network and active/public package.
  2. Uses server-side `network_packages.price`; rejects any client price spoof (no `p_client_price` parameter).
  3. Locks wallet account and verifies sufficient balance.
  4. Locks inventory balance and verifies stock.
  5. Inserts `DEBIT` ledger entry.
  6. Creates `purchase_records` row.
  7. Consumes one inventory unit via `package_inventory_movements` and updates `package_inventory_balances`.
  8. Creates `card_fulfillment_records` row.
  9. Creates `owner_settlement_items` accounting reference.
- Idempotency via `UNIQUE INDEX idx_purchase_records_idempotency (user_id, idempotency_key)`.

## INVENTORY_ATOMICITY

- Inventory is locked with `SELECT ... FOR UPDATE` before consumption.
- Last-unit race verified by `scripts/test_commerce_concurrency.py`: exactly one of two concurrent purchasers succeeds.
- No negative inventory: `available_units <= 0` raises `OUT_OF_STOCK`.

## FULFILLMENT

- Table: `public.card_fulfillment_records` with `status`, `fulfilled_at`, `quarantined_at`, `dispute_window_ends_at`.
- **No card/voucher secrets are stored** (plaintext, encrypted, or otherwise) pending OD-CARD-01.
- `secret_payload_storage_path` and `secret_payload_retrieval_token` remain NULL in source builds.
- `reveal_purchase_fulfillment()` fails closed with `FULFILLMENT_VAULT_NOT_CONFIGURED` when no vault is configured.
- Purchase owner can read fulfillment status; secret reveal is RPC-only.

## REFUND_HOOK

- Table: `public.refund_requests` with statuses `submitted`, `investigating`, `refund_recommended`, `rejected_dispute`, `approved_refund`.
- Customer submits via `submit_refund_request()`.
- Support agent / admin resolves via `review_refund_request()`.
- Approved refund inserts a compensating `CREDIT` ledger entry; original `DEBIT` is never modified.
- Idempotent: replay returns `replayed: true` without duplicate credit.

## SETTLEMENT_HOOK

- Table: `public.owner_settlement_items` tracks per-purchase:
  - `gross_amount`
  - `platform_commission_amount` (provisional 5% pending OD-FIN-02)
  - `net_settlement_amount`
  - `settlement_status` (`pending`, `included`, `paid`, `disputed`)
- No payout schedule or batch implemented pending OD-SETTLE-01.

---

## AUTHORIZATION_MATRIX

| Role | Wallet | Deposits | Purchases | Fulfillment | Finance Queue | Refunds | Settlement Summary | Admin Summary |
|---|---|---|---|---|---|---|---|---|
| CUSTOMER | own read | own read/create | own read/create | own status read | — | own submit | — | — |
| FINANCE_OFFICER | read (audit) | read/review | — | — | read/review | — | — | — |
| NETWORK_OWNER | — | — | read for own network | — | — | — | own network summary | — |
| NETWORK_OPERATOR | — | — | read for own network | — | — | — | — | — |
| SUPPORT_AGENT | — | — | — | — | — | read/review | — | — |
| PLATFORM_ADMIN | read | read | read | read | read/review | read/review | read | read |
| SYSTEM_AUDITOR | read | read | read | read | read | read | read | read |
| ANON | denied | denied | denied | denied | denied | denied | denied | denied |

- No direct `UPDATE` policy on `wallet_accounts`; balance is trigger-only.
- No direct `INSERT/UPDATE/DELETE` on `customer_wallet_ledger`.
- `card_fulfillment_records` has no direct client mutation; secret reveal is RPC-only.

---

## FINANCIAL_INVARIANTS

1. Ledger entries are immutable (no UPDATE/DELETE policies or grants).
2. Wallet balance is non-negative (`cached_balance >= 0`, `balance_after >= 0`).
3. Deposit approval creates exactly one credit.
4. Purchase uses server-side price; client price is ignored/denied by RPC signature.
5. Wallet debit and inventory consumption are atomic.
6. Refund creates a compensating credit; historical ledger entries are never mutated.
7. Idempotency keys prevent duplicate deposits, purchases, and refunds.
8. Audit trail via `customer_wallet_ledger.actor_user_id`, `reason_code`, `metadata`, and `purchase_records`.

---

## CONCURRENCY_AND_IDEMPOTENCY

- Deposit creation: `UNIQUE (user_id, idempotency_key)`.
- Deposit approval: row lock + pre-existing `ledger_entry_id` check.
- Wallet credit/debit: user-level wallet row lock serializes balance changes.
- Purchase: `UNIQUE (user_id, idempotency_key)` + inventory row lock.
- Inventory consumption: `SELECT ... FOR UPDATE` on `package_inventory_balances`.
- Refund: refund row lock + pre-existing `ledger_entry_id` check.
- Fulfillment: single fulfillment record per purchase; secret reveal fails closed.
- Concurrent last-unit purchase test: **PASS** (exactly one buyer succeeds).

---

## FLUTTER

New feature directories under `lib/features/`:

- `wallet/`: `WalletScreen`, `DepositScreen`, `DepositHistoryScreen`, wallet/deposit providers, fake + Supabase repositories.
- `purchase/`: `PurchaseConfirmationScreen`, `PurchaseResultScreen`, `PurchaseHistoryScreen`, purchase providers, fake + Supabase repositories.
- `finance/`: `DepositReviewQueueScreen`, `DepositDetailScreen`, finance providers, fake + Supabase repositories.

All screens use Arabic RTL via `Directionality(textDirection: TextDirection.rtl)`.

Validation:
- `flutter analyze`: No issues found.
- `flutter test`: 98 tests passed.
- `flutter build apk --debug`: built `build\app\outputs\flutter-apk\app-debug.apk`.

---

## SUPABASE_SQL_RESULTS

Local Supabase reset:
- `npx supabase db reset --no-seed`: applied all migrations successfully.

SQL test suites run in order with `ON_ERROR_STOP=1`:
- `001_core_schema_contract.sql`: PASS
- `002_core_authorization_positive.sql`: PASS
- `003_core_authorization_negative.sql`: PASS
- `004_core_invariants.sql`: PASS
- `005_network_discovery_and_requests.sql`: PASS
- `006_final_hold_remediation_verification.sql`: PASS
- `007_packages_and_inventory.sql`: PASS
- `008_admin_operations.sql`: PASS
- `009_client_truncate_acl_hardening.sql`: PASS
- `010_operational_closure.sql`: PASS
- `011_commerce_core.sql`: PASS

Concurrency:
- `scripts/test_commerce_concurrency.py`: PASS (last unit sold exactly once).

---

## CORE_VERIFIER

- `scripts/verify_netyemen_core_foundation.ps1`: PASS
- `scripts/verify_netyemen_commerce_v1.ps1`: PASS (after report file created)

---

## SECURITY

- Security definer RPCs use `SET search_path = public, pg_temp`.
- `auth.uid()` is authoritative; no client actor spoofing.
- Explicit `REVOKE ... FROM PUBLIC, anon, authenticated` on commerce tables.
- `card_fulfillment_records` secret columns are NULL in source builds.
- Scans:
  - Secret scan: PASS
  - Card-secret prohibition scan: PASS
  - Financial invariant scan: PASS

---

## CARD_SECRET_BOUNDARY

OD-CARD-01 is **OPEN** and treated as a source blocker for real secret storage.

- `card_fulfillment_records.secret_payload_storage_path` and `secret_payload_retrieval_token` are nullable.
- No plaintext card numbers, voucher codes, Wi-Fi passwords, or PINs exist in source or migrations.
- `reveal_purchase_fulfillment()` raises `FULFILLMENT_VAULT_NOT_CONFIGURED` until a vault is configured.
- The source is intentionally "fail closed".

---

## OWNER_DECISION_PACKAGE

The following decisions remain open and prevent production binding. Source-only, provider-neutral foundations are implemented; no production gateway, bank, card vault, or settlement schedule is bound.

### OD-FIN-01: Customer Deposit Verification & Proof Method
- **Question:** How should customer deposit proof be verified before wallet credit?
- **Options:**
  1. **Manual Verification Queue** (Recommended): Finance officer reviews uploaded reference/proof against bank portal; approves in app. Lowest integration risk.
  2. Semi-Automated OCR: Receipt screenshots parsed by OCR for automated comparison; manual review on mismatch.
  3. Direct API Integration with Yemeni Financial Institutions: Real-time verification; highest compliance/integration barrier.
- **Security/Business Impact:** Determines deposit turnaround, finance staffing, and fraud surface.
- **Blocks:** PILOT binding (manual queue can start immediately); PRODUCTION automation depends on chosen option.
- **Current Source State:** Implemented as Option 1 (manual review queue with reference number and optional proof path).

### OD-FIN-02: Platform Commission Architecture
- **Question:** What commission model should the platform apply to card/package sales?
- **Options:**
  1. **Flat Percentage Commission (5%)** (Recommended): Simple, scales linearly; current source provisional default.
  2. Tiered Fixed Fee per Denomination: Predictable owner costs; requires tier maintenance.
  3. Owner Subscription Fee + Lower Commission: Attractive for large owners; barrier for small owners.
- **Security/Business Impact:** Core business model; affects owner margin and platform profitability.
- **Blocks:** PRODUCTION settlement calculations must use the final rate. Source uses 5% as a provisional placeholder.

### OD-FIN-03: Deposit Bank Directory Accounts Selection
- **Question:** Which real bank/payment accounts should appear in the customer deposit directory?
- **Options:**
  1. **Configuration-Driven Bank Directory** (Recommended): Admin portal manages live accounts; no app release required.
  2. Hardcoded In-App Accounts: Faster reads; requires app updates for account changes.
- **Security/Business Impact:** Controls liquidity routing and deposit UX.
- **Blocks:** PRODUCTION requires official account numbers. Source has a provider-neutral `bank_directory` table with illustrative provider names only.

### OD-CARD-01: Internet Card Encryption & Storage Architecture
- **Question:** How must card/voucher secrets be encrypted and stored?
- **Options:**
  1. **PostgreSQL Column Encryption (pgcrypto)** (Recommended): Decrypted only inside security-definer RPC.
  2. External Vault/KMS: Maximum isolation; adds latency/import complexity.
  3. Application-Level AES-256: Client key distribution complexity.
- **Security/Business Impact:** Critical security control; database leak must not expose plaintext cards.
- **Blocks:** SOURCE storage of real card secrets, PILOT fulfillment, and PRODUCTION. Source currently stores no secrets and fails closed.

### OD-CARD-02: Customer Card Dispute & Quarantine Window
- **Question:** How long after purchase can a customer dispute a card?
- **Options:**
  1. 12-Hour Strict Window.
  2. **24-Hour Standard Window** (Recommended): Balanced customer/owner protection.
  3. 48-Hour Extended Window.
- **Security/Business Impact:** Governs settlement hold duration and support SLA.
- **Blocks:** PRODUCTION settlement holds. Source provisional default is 24 hours (`dispute_window_ends_at = NOW() + INTERVAL '24 hours'`).

### OD-SETTLE-01: Network Owner Settlement Payout Schedule
- **Question:** When and how should network owners receive payouts?
- **Options:**
  1. **Weekly Automated Batch + 10,000 YER Minimum Threshold** (Recommended): Predictable cash flow.
  2. Threshold-Triggered Settlement (e.g., 25,000 YER).
  3. Manual Owner Payout Request.
- **Security/Business Impact:** Affects platform liquidity and finance operations.
- **Blocks:** PRODUCTION automated payouts. Source tracks immutable settlement items only; no payout schedule or batch.

### OD-WALLET-01: Wallet Balance Storage: Cached vs Real-Time Aggregation
- **Question:** Should wallet balance be cached or computed from ledger aggregation?
- **Options:**
  1. **Cached Column Updated by Database Trigger** (Recommended): Fast reads; trigger maintains integrity.
  2. Pure Real-Time Aggregation: Mathematically drift-free; higher CPU/I/O.
- **Security/Business Impact:** Affects purchase RPC speed and scaling.
- **Blocks:** None for source. Source implements Option A (`wallet_accounts.cached_balance` maintained by trigger on `customer_wallet_ledger`).

---

## COMMITS

- `95b8846d4bd3bd81476f39ac8b3701e22fab737e` — feat(commerce): close V1 wallet/deposit/purchase/fulfillment/refund/settlement path
- `cbf0b527fffa22dbe3f561fc6f4a68615e7cf870` — docs(report): record ending sha for commerce core closure
- `a6979245453bfc570b130962829bd3c97f9d457e` — docs(report): record commits, push and pr placeholders for commerce core closure
- `5f36a0d27ba7cb7025d149d562171fb5507ab1b0` — docs(report): update push and pr status for commerce core closure
- `97fbe52ecbd0ad25300822dc1195bda952aef84d` — docs(report): finalize ending sha for commerce core closure

## PUSH

- Pushed to: `origin/kimi/NY-V1-COMMERCE-CORE-001`
- Status: SUCCESS

## PR

- Draft stacked PR: https://github.com/msorori-mh/NetYemen/pull/13
- State: OPEN, isDraft: true
- No merge performed.

---

## REMAINING_BLOCKERS

1. Owner approval of `OD-FIN-01`, `OD-FIN-02`, `OD-FIN-03`, `OD-CARD-01`, `OD-CARD-02`, and `OD-SETTLE-01` before production binding.
2. Selection and configuration of real deposit bank accounts (OD-FIN-03).
3. Selection and configuration of secure card vault (OD-CARD-01).
4. Final commission rate confirmation (OD-FIN-02).
5. Settlement schedule and payout method confirmation (OD-SETTLE-01).

---

## FINAL_DECISION

**PASS_WITH_GOVERNANCE_HOLD**

The V1 commerce path is closed at the source/provider-neutral level. All mandatory financial invariants, authorization rules, idempotency, concurrency controls, Flutter UX, and SQL tests pass. Production binding of financial providers, card vaults, and settlement schedules is held pending the consolidated `OWNER_DECISION_PACKAGE` above.
