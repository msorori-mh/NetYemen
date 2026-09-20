# NetYemen V1 External Pilot Binding & Release Candidate Report

**Task ID:** NY-V1-EXTERNAL-PILOT-BINDING-001  
**Report Code:** `NY-V1-EXTERNAL-PILOT-BINDING-001-KIMI-REPORT.md`  
**Branch:** `kimi/NY-V1-EXTERNAL-PILOT-BINDING-001`  
**Starting SHA:** `ca61c24e37a8e5f9f7e70161fd98b59ea36853b5`  
**Ending SHA:** `678c779a3175c3ede4f774ffa077bbf31b91f882`  
**Report Date:** 2026-08-08

---

## Mission

Convert the already integrated NetYemen V1 source/local-pilot baseline into the final external-pilot-ready Release Candidate by binding all seven owner-approved V1 governance decisions.

---

## Owner Decisions

All seven owner decisions are recorded as `APPROVED` in `docs/NETYEMEN-DECISION-REGISTER-01.md` with `approved_by = OWNER` and `approved_date = 2026-08-08`.

| Decision | Status | Binding Location |
|---|---|---|
| OD-NOTIF-01 — FCM push transport | APPROVED | `supabase/functions/notification-transport-adapter/index.ts`, `public.notification_transport_config` |
| OD-FIN-01 — Manual deposit review | APPROVED | `public.wallet_deposit_requests`, `review_wallet_deposit_request` RPC |
| OD-FIN-02 — 3% platform commission | APPROVED | `public.platform_commission_config`, `purchase_records` commission snapshot columns |
| OD-FIN-03 — Admin-managed payment destination directory | APPROVED | `public.payment_destinations`, admin/finance RPCs |
| OD-CARD-01 — Server-side encrypted card vault | APPROVED | `public.card_vault`, Edge Function `decrypt_card_secret`, `admin_ingest_card_vault_batch` |
| OD-CARD-02 — 30-minute invalid-card dispute window | APPROVED | `public.card_vault.first_revealed_at/dispute_deadline`, `submit_invalid_card_dispute` |
| OD-SETTLE-01 — Weekly settlement batch | APPROVED | `public.settlement_batches`, `public.settlement_batch_lines`, finance RPCs |

No approved decision remains unresolved or marked `OPEN_DECISION`.

---

## FCM Binding

- Provider selected: **Firebase Cloud Messaging (FCM)**.
- Server-side Edge Function created at `supabase/functions/notification-transport-adapter/index.ts`.
- Supports HTTP v1 dispatch with service-account credentials from environment only (`FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, `FCM_PRIVATE_KEY`).
- Flutter fallback adapter `lib/features/notifications/data/fake_fcm_transport_adapter.dart` returns `credential_required` when real credentials are unavailable.
- Token registry (`public.device_push_tokens`) supports registration, refresh, deactivate, invalid-token retirement.
- Delivery status classification: `sent`, `transient_failure`, `permanent_failure`, `credential_required`.
- No service-account private key in Flutter source or repository.
- Source/local E2E does not require real FCM credentials; external push is classified `credential_required`.

---

## Payment Directory

- Legacy `public.bank_directory` renamed to `public.payment_destinations`.
- Supports `bank_account`, `mobile_wallet`, `manual_transfer`, `other`.
- Admin/Finance RPCs: `admin_create_payment_destination`, `admin_update_payment_destination`, `admin_set_payment_destination_active`, `admin_reorder_payment_destinations`.
- Customer RPC: `get_active_payment_destinations`.
- `create_wallet_deposit_request` requires a valid active payment destination and stores an immutable `destination_snapshot`.
- Existing deposits with NULL destination are preserved; new inserts require a destination.

---

## Commission

- Default V1 commission bound to **3.00%** in `public.platform_commission_config`.
- Commission computed server-side in `purchase_package`; client values are never trusted.
- `purchase_records` stores immutable snapshot: `gross_amount`, `commission_rate_snapshot`, `commission_amount`, `owner_net_amount`.
- `owner_settlement_items` restored to bound NOT NULL commission/net with status `pending`.
- Only `platform_admin` can update the default rate via `admin_update_default_commission_rate`; historical purchases are immutable.
- Rounding: integer floor.

---

## Card Vault

- `public.card_vault` stores only encrypted material: `ciphertext` (BYTEA), `nonce`, `auth_tag`, `key_version`.
- Plaintext secret never persisted in normal tables, logs, audit events, Flutter source, or notifications.
- Lifecycle states: `available`, `reserved`, `sold`, `quarantined`, `invalidated`.
- `purchase_package` atomically reserves exactly one available card with `FOR UPDATE SKIP LOCKED`.
- Ingestion RPC: `admin_ingest_card_vault_batch` (admin or network owner).
- Metadata list RPC: `admin_list_card_vault_metadata` returns only non-secret columns.
- Key versioning from day one; production key obtained from Edge Function environment.

---

## Card Reveal

- Authorized reveal RPC: `reveal_purchase_card_secret`.
- Validates authenticated user, purchase ownership, completed purchase, sold card state, not quarantined/invalidated.
- Returns only encrypted payload (`ciphertext_b64`, `nonce`, `auth_tag_b64`, `key_version`); plaintext decrypted server-side by Edge Function.
- Records `first_revealed_at`, `last_revealed_at`, `reveal_count`, `dispute_deadline` without storing plaintext.
- Cross-user reveal denied; direct `card_vault` SELECT denied to customers.
- Flutter `card_reveal_screen.dart` and `purchase_detail_screen.dart` provide Arabic RTL UX with 30-minute dispute warning.

---

## Dispute Window

- Direct invalid-card dispute window: **30 minutes** from first successful reveal.
- `submit_invalid_card_dispute` checks eligibility server-side using `first_revealed_at` and `dispute_deadline`.
- Within window: dedicated dispute case created with `case_type='dispute'`.
- Outside window: returns `DISPUTE_WINDOW_CLOSED` (SQLSTATE 22023); customer must use normal support.
- Boundary condition tested by manipulating `first_revealed_at` to be past the deadline.

---

## Settlements

- `public.settlement_batches` and `public.settlement_batch_lines` created.
- Lifecycle: `draft`, `ready_for_review`, `approved`, `paid`, `cancelled`, `corrected`.
- Finance RPCs: `finance_create_settlement_batch`, `finance_approve_settlement_batch`, `finance_mark_settlement_paid`.
- Self-approval blocked: creator cannot approve their own batch.
- No automatic bank payout; `paid` status records external manual confirmation.
- Immutable snapshots and line references preserved.
- Owner RPC: `get_owner_settlements`. Finance/admin RPC: `get_finance_settlement_batches`.

---

## Authorization Matrix

Verified in `supabase/tests/015_v1_external_pilot_authorization_and_crypto.sql`:

| Role | Restriction | Result |
|---|---|---|
| anon | Cannot call privileged RPCs | PASS |
| customer | Cannot insert/reveal cards directly | PASS |
| customer | Cannot cross-user reveal | PASS |
| network_owner | Cannot reveal customer cards | PASS |
| network_owner / operator | Cannot change commission | PASS |
| finance_officer | Direct `card_vault` SELECT denied | PASS |
| platform_admin | List endpoints omit ciphertext/nonce/auth_tag | PASS |
| support_agent | Cannot reveal secrets | PASS |
| system_auditor | Never receives decrypted secret | PASS |
| customer | Cannot approve deposit | PASS |
| network_owner | Cannot create/approve own settlement | PASS |
| customer | Settlement mutation denied | PASS |

---

## Crypto Validation

Verified in `supabase/tests/015_v1_external_pilot_authorization_and_crypto.sql`:

- Ciphertext is not equal to plaintext fixture. PASS
- Nonce uniqueness enforced. PASS
- No plaintext leak in `card_vault`, `audit_events`, `notification_events`. PASS
- Direct client `card_vault` SELECT denied. PASS
- Reveal returns ciphertext payload only, not plaintext. PASS
- Edge Function `crypto.ts` includes deterministic TEST_ONLY key path and tamper-detection tests in `test_crypto.ts`.

No real encryption key committed.

---

## Financial Invariants

Scans executed:

- `scripts/scan_netyemen_secrets.ps1` — PASS
- `scripts/scan_netyemen_card_secrets.ps1` — PASS
- `scripts/scan_netyemen_financial_invariants.ps1` — PASS
- `scripts/verify_netyemen_core_foundation.ps1` — PASS
- `scripts/verify_netyemen_commerce_v1.ps1` — PASS
- `scripts/test_commerce_concurrency.py` — PASS (exactly one of two concurrent purchasers succeeds)
- `git diff --check` — PASS (after trailing-whitespace fix)

---

## E2E Results

All flows from `supabase/tests/014_v1_integrated_pilot_e2e.sql` passed:

| Flow | Result |
|---|---|
| E2E-01 — Fresh customer auth identity | PASS |
| E2E-02 — Public network discovery | PASS |
| E2E-03 — Network request/admin review | PASS (covered by prior suites) |
| E2E-04/05 — Owner package and inventory operations | PASS |
| E2E-06 — Active package visible | PASS |
| E2E-07 — Deposit approval credits exactly once | PASS |
| E2E-08/10 — Purchase atomic/idempotent | PASS |
| E2E-09 — Concurrent last-unit behavior | PASS |
| E2E-11 — Fails closed when vault out of stock | PASS |
| E2E-12 — Support dispute linked to purchase | PASS |
| E2E-13 — Compensating refund hook | PASS |
| E2E-14 — Events/outbox created | PASS |
| E2E-15 — Admin audit visibility | PASS |
| E2E-16 — Admin creates payment destination | PASS |
| E2E-17 — Customer submits deposit against destination | PASS |
| E2E-18 — Finance approves once → wallet credited once | PASS |
| E2E-19 — 3% commission purchase calculation | PASS |
| E2E-20 — Encrypted card available → purchase consumes exactly one | PASS |
| E2E-21 — Authorized purchaser reveals card | PASS |
| E2E-22 — Other customer reveal denied | PASS |
| E2E-23 — Invalid-card dispute within 30 min accepted | PASS |
| E2E-24 — Direct invalid-card dispute after 30 min rejected | PASS |
| E2E-25 — Weekly settlement batch calculation | PASS |
| E2E-26 — Finance settlement approval | PASS |
| E2E-27 — Notification FCM dispatch adapter contract | PASS |

---

## Flutter

- `flutter pub get` — PASS
- `flutter analyze` — PASS (no issues)
- `flutter test` — PASS (109 tests)
- `flutter build apk --debug` — PASS

---

## SQL

- `npx supabase start` — PASS
- `npx supabase db reset --no-seed` — PASS
- Sequential test suite `001`–`015` with `ON_ERROR_STOP=1` — ALL PASS

---

## Verifiers

- `scripts/verify_netyemen_core_foundation.ps1` — PASS
- `scripts/verify_netyemen_commerce_v1.ps1` — PASS
- `scripts/test_commerce_concurrency.py` — PASS
- Secret scan — PASS
- Card-secret scan — PASS
- Financial invariant scan — PASS
- ACL scan (via SQL test 015) — PASS
- `git diff --check` — PASS

---

## APK

- Path: `build/app/outputs/flutter-apk/app-debug.apk`
- SHA-256: `93ca7ffa9f8d27ed81a7de49700eef980055fadd536ce4dc9d1280601568f7bd`
- Size: ~147 MB (debug build)
- Type: Debug/pilot APK (not a signed production release)

---

## ADB

- `adb` command not found in environment.
- No Android device/emulator detected.
- Status: **PHYSICAL_DEVICE_REQUIRED**
- Source closure is not blocked; no invented device PASS.

---

## External Credential Checklist

| Credential | Where Owner Obtains/Configures | Secret? | Where Stored | Required For |
|---|---|---|---|---|
| Firebase Android project configuration | Firebase Console → Project settings → Android app | Non-secret (package name, app ID) | `android/app/google-services.json` (not committed) | Physical pilot & production |
| FCM server service account | Firebase Console → Project settings → Service accounts | **Secret** | Supabase Edge Function secrets only (`FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, `FCM_PRIVATE_KEY`) | Physical pilot & production |
| Card encryption master key v1 | KMS / HSM / secure secret generator | **Secret** | Supabase Edge Function secrets only (`CARD_MASTER_KEY_v1`) | Physical pilot & production |
| Supabase project URL & anon key | Supabase Dashboard → API | Non-secret (anon key) | Flutter environment config (not committed) | Physical pilot & production |
| Supabase service role key | Supabase Dashboard → API | **Secret** | Supabase Edge Function runtime / deployment secrets (auto-provided) | Physical pilot & production |
| Android code signing keystore | Owner certificate authority / Play Store | **Secret** | Owner secure build pipeline; not in repo | Production release only |
| Real payment destination accounts | Owner finance / banking providers | Non-secret (account numbers are operational data) | `public.payment_destinations` table | Physical pilot & production |

No credential values are included in this report or in repository source.

---

## Remaining External Actions

1. Create/obtain Firebase Android project and download `google-services.json`; place in `android/app/` for physical pilot builds (do not commit).
2. Generate FCM service account and inject `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, `FCM_PRIVATE_KEY` into Supabase Edge Function secrets.
3. Generate or import a 32-byte AES-256 key and inject `CARD_MASTER_KEY_v1` into Supabase Edge Function secrets.
4. Configure real payment destinations via admin/finance UI or RPC.
5. Obtain Android code-signing keystore for production release (not required for debug pilot APK).
6. Connect an Android device/emulator and run smoke flow when `adb` is available.

---

## Production Readiness

- V1 governance decisions are bound and documented.
- Source validation passes (Flutter analyze/test/build, SQL tests, verifiers, scans).
- Debug pilot APK built.
- No production credentials committed.
- No plaintext card secrets in source or tests.
- Physical device smoke test pending availability of `adb`/hardware.
- External credential injection pending owner provisioning.

---

## Final Decision

**PASS_WITH_EXTERNAL_CREDENTIAL_REQUIREMENTS**

The V1 external-pilot binding and Release Candidate source path is closed. The repository is ready for physical pilot deployment once the owner provisions the external credentials listed above. No governance hold applies to the seven approved owner decisions.
