# NY-V1-NETWORK-DISCOVERY-001 — Cursor Closure Security Review

## MISSION

`NY-V1-NETWORK-DISCOVERY-001-CURSOR-CLOSURE-SECURITY-REVIEW-01`

Independent security closure review after FINAL-HOLD-REMEDIATION-02. Verify that prior Codex HOLD findings (R-01–R-05) are closed and that authorization, RLS/ACL, SECURITY DEFINER, idempotency, state machine, Unicode parity, Wi-Fi privacy, and secrets posture remain sound.

Review-only. No runtime code changes. No Production. No remote Supabase. No merge.

## REVIEW_TARGET_SHA

`5cbcc875f491b6002ce4bd8757ff31316f9c65bc`

## REVIEW_BRANCH

`cursor/NY-V1-NETWORK-DISCOVERY-001-CLOSURE`

## WORKTREE_STATUS

- `git rev-parse HEAD` = `5cbcc875f491b6002ce4bd8757ff31316f9c65bc` (exact match)
- Worktree clean before report commit (Flutter `android/gradle.properties` migrator edit from `flutter build apk --debug` was reverted and not included)
- Prior inputs read:
  - Cursor security review (PASS on earlier SHA `b1da5c0…`)
  - Codex final re-review (HOLD on `b1da5c0…`; findings R-01–R-05)
  - FINAL-HOLD-REMEDIATION-02 report (claimed PASS; ending SHA `71fab3c…`, later docs update to this target)

## REVIEWED_OBJECTS

### Database

- `supabase/migrations/20260727090000_netyemen_core_identity_and_networks.sql` (`handle_new_user`, networks identity)
- `supabase/migrations/20260727091000_netyemen_core_rls_and_audit.sql` (`normalize_ssid`, RLS/FORCE, ACL helpers)
- `supabase/migrations/20260727130000_netyemen_network_addition_requests.sql` (table, RPCs, RLS, grants)
- RPCs: `submit_network_addition_request`, `cancel_network_addition_request`, `resolve_network_addition_request`
- Helpers: `has_platform_role`, `normalize_ssid`, `set_updated_at`, `handle_new_user`

### Flutter / Android

- Auth: `lib/screens/auth/otp_screen.dart`, `lib/services/supabase_service.dart`, `lib/features/auth/presentation/auth_required_gate.dart`
- Idempotency: `lib/features/network_requests/presentation/network_request_providers.dart`, `add_request_screen.dart`, `lib/core/utils/uuid_generator.dart`
- SSID: `lib/features/network_discovery/data/scan_matcher.dart` vs `public.normalize_ssid`
- Wi-Fi: `android_wifi_scan_service.dart`, `AndroidManifest.xml`

### Tests / verifiers

- `supabase/tests/001`–`006`
- Temporary local adversarial SQL (rolled back)
- `scripts/verify_netyemen_core_foundation.ps1`
- Flutter analyze / test / debug APK

---

## CODEX_HOLD_CLOSURE_MATRIX

| ID | Prior severity | Closure | Independent evidence |
|---|---|---|---|
| R-01 | HIGH | **CLOSED** | No `createOrUpdateUser` / `from('users')` in client; OTP success navigates to `AppShell`; `getUserProfile` reads `public.profiles`; `handle_new_user` provisions `profiles` + `customer` role; SQL 006 CHECK 1 + ADV-NO-PUBLIC-USERS |
| R-02 | HIGH | **CLOSED** | Client `IdempotencySession` binds UUID to payload fingerprint; `AddRequestScreen.initState` resets session; server raises `IDEMPOTENCY_PAYLOAD_MISMATCH`; unique `(requester_user_id, idempotency_key)`; Flutter notifier tests + SQL NEG-14 / 006 CHECK 2–3 + ADV-PAYLOAD-MISMATCH |
| R-03 | MEDIUM | **CLOSED** | Resolve uses single `UPDATE … WHERE status IN ('submitted','under_review')`; terminals (`approved`/`rejected`/`matched_existing`) and `cancelled` cannot be rewritten; metadata coherence for `matched_network_id`; NEG-12/13/15 + 006 CHECK 4–5 + ADV-TERMINAL / ADV-STALE |
| R-04 | MEDIUM | **CLOSED** | Explicit shared Unicode whitespace contract in Dart and PostgreSQL (incl. U+00A0); NFC + hyphen rules aligned; POS-09 + 006 CHECK 6 + Dart unicode tests |
| R-05 | LOW | **CLOSED** | OTP widget test, expanded notifier/scan tests, SQL 005 extensions, suite 006; Flutter tests 50/50 |

---

## FOCUS_AREA_MATRIX

| # | Focus | Result | Evidence |
|---|---|---|---|
| 1 | `auth.users` → `profiles` / `user_roles` fresh-user provisioning | **PASS** | Trigger `handle_new_user` on `auth.users` INSERT; SQL 006 AUTH_FRESH_USER_PASS |
| 2 | No `public.users` shadow identity | **PASS** | `to_regclass('public.users') IS NULL`; no client writes |
| 3 | UUID / payload idempotency binding | **PASS** | Client fingerprint + UUID v4; server conflict path compares payload fields |
| 4 | Mismatched payload replay rejection | **PASS** | `IDEMPOTENCY_PAYLOAD_MISMATCH`; ADV-PAYLOAD-MISMATCH PASS |
| 5 | Requester-scoped uniqueness | **PASS** | Unique index `(requester_user_id, idempotency_key)`; `requester_user_id := auth.uid()` |
| 6 | Concurrent replay protection | **PASS** | `INSERT … ON CONFLICT DO NOTHING` then validate/re-select (no check-then-insert race) |
| 7 | Atomic terminal state transitions | **PASS** | Guarded resolve UPDATE; terminal rewrite blocked |
| 8 | Stale / concurrent reviewer protection | **PASS** | Status predicate + row lock serialization; stale second resolve → `INVALID_TRANSITION` |
| 9 | Resolution metadata coherence | **PASS** | Table CHECK + RPC rules for `resolved_at`/`resolved_by`/`matched_network_id` |
| 10 | Dart / PostgreSQL Unicode normalization parity | **PASS** | Shared explicit whitespace set; NBSP and related vectors covered |
| 11 | RLS | **PASS** | ENABLE + FORCE RLS; SELECT policies only (owner/support/admin/auditor); no client DML policies |
| 12 | ACL / grants / revokes | **PASS** | `REVOKE ALL FROM PUBLIC`; SELECT to `authenticated` only; RPC EXECUTE revoked from PUBLIC, granted to `authenticated`; no anon on requests |
| 13 | SECURITY DEFINER / `search_path` | **PASS** | Request RPCs and core helpers use `SET search_path = public, pg_temp` |
| 14 | `auth.uid()` | **PASS** | Submit/cancel/resolve derive identity from `auth.uid()`; no client-supplied requester id |
| 15 | Cross-user isolation | **PASS** | RLS + ownership checks; ADV-CROSS-USER-REPLAY creates distinct scoped rows |
| 16 | Anon denial | **PASS** | Suites NEG-01/11; no request table/RPC grants to `anon` |
| 17 | Wi-Fi SSID-only privacy | **PASS** | Scanner extracts SSID only; schema excludes BSSID/MAC/coords/password; scan on explicit user action |
| 18 | Secrets / artifacts | **PASS** | No committed service-role/JWT/private-key values; `supabase/.temp` / build artifacts not staged; local demo JWT only from `supabase status` (not in git) |

---

## SECURITY_DEFINER_AND_AUTHZ

| Function | search_path | auth.uid() | Dynamic SQL | EXECUTE |
|---|---|---|---|---|
| `submit_network_addition_request` | `public, pg_temp` | Yes | None | PUBLIC revoked; authenticated granted |
| `cancel_network_addition_request` | `public, pg_temp` | Yes | None | PUBLIC revoked; authenticated granted |
| `resolve_network_addition_request` | `public, pg_temp` | Yes; `resolved_by` from caller | None | PUBLIC revoked; authenticated granted; role-gated admin/support |
| `handle_new_user` / `normalize_ssid` / `has_platform_role` | `public, pg_temp` | Trigger / helper | None | Least-privilege as in foundation |

---

## ADVERSARIAL_TESTS (temporary local, rolled back)

Executed via `docker exec … psql -v ON_ERROR_STOP=1` against local `supabase_db_netyemen-local` after `db reset --no-seed`. Transaction `ROLLBACK`.

| # | Case | Result |
|---|---|---|
| ADV-PAYLOAD-MISMATCH | Same UUID + different SSID payload | **PASS** (`IDEMPOTENCY_PAYLOAD_MISMATCH`) |
| ADV-TERMINAL-REWRITE | `approved` → `rejected` | **PASS** (`INVALID_TRANSITION`) |
| ADV-STALE-RESOLUTION | Second resolve after terminal approval | **PASS** (`INVALID_TRANSITION`) |
| ADV-CROSS-USER-REPLAY | User B reuses User A UUID | **PASS** (two distinct requester-scoped rows) |
| ADV-WRONG-ROLE | Customer calls resolve RPC | **PASS** (`FORBIDDEN_ROLE`) |
| ADV-NO-PUBLIC-USERS | `to_regclass('public.users')` | **PASS** (NULL) |

---

## SQL_TEST_RESULTS

| Suite | Result |
|---|---|
| 001_core_schema_contract.sql | **PASS** |
| 002_core_authorization_positive.sql | **PASS** (14 positive; ROLE_CONTEXT notices) |
| 003_core_authorization_negative.sql | **PASS** (30 negative) |
| 004_core_invariants.sql | **PASS** (12 invariants) |
| 005_network_discovery_and_requests.sql | **PASS** |
| 006_final_hold_remediation_verification.sql | **PASS** (AUTH / IDEMPOTENCY / STATE_MACHINE / UNICODE notices) |

Local only: `npx supabase start`, `npx supabase db reset --no-seed`. No remote Supabase.

---

## CORE_VERIFIER

`powershell -ExecutionPolicy Bypass -File scripts/verify_netyemen_core_foundation.ps1`

**STATIC VERIFICATION RESULT: PASS (All Rules Satisfied)**

---

## FLUTTER_VALIDATION

| Check | Result |
|---|---|
| JDK | Microsoft OpenJDK **17.0.20+8-LTS** (`C:\Program Files\Microsoft\jdk-17.0.20.8-hotspot`); Flutter-configured |
| `flutter pub get` | **PASS** |
| `flutter analyze` | **PASS** — No issues found |
| `flutter test` | **PASS** — 50/50 |
| `flutter build apk --debug` | **PASS** — `build\app\outputs\flutter-apk\app-debug.apk` (152,109,754 bytes; SHA-256 `1817CC8F6BF776EABC224B181A599B7F54495E90863399AE2F33BAD8247012F6`) |

---

## SECRET_SCAN

- Grep over tracked non-doc sources for live credentials / private keys / JWT literals: only documentation/test role references to `service_role` (no secret values)
- No `supabase/.temp`, `.branches`, or `build/` staged
- Accidental `android/gradle.properties` Flutter migrator edit reverted before report commit

**SECRET_SCAN_RESULT: PASS**

---

## FINDINGS_TABLE

| ID | Severity | Component | Evidence | Impact | Recommendation |
|---|---|---|---|---|---|
| CUR-CL-01 | LOW | `cancel_network_addition_request` | Status is selected then `UPDATE` without `WHERE status = 'submitted'` | Requester-only TOCTOU: cancel could race after support moves to `under_review`; no cross-user / privilege escalation | Optional hygiene: atomic `UPDATE … WHERE status = 'submitted' AND requester_user_id = auth.uid()` |
| CUR-CL-02 | NOTE | Android permissions | `ACCESS_FINE_LOCATION` maxSdk 32 for OS Wi-Fi scan APIs; `NEARBY_WIFI_DEVICES` + `neverForLocation` | Location not collected/transmitted | Keep documenting OS prerequisite |
| CUR-CL-03 | NOTE | Duplicate-of linking | Best-effort SELECT-then-INSERT for open SSID without partial unique index | Rare concurrent inserts may both omit `duplicate_of`; no authz bypass | Optional later advisory lock / partial unique index |
| CUR-CL-04 | NOTE | Demo auth gate | `AuthRequiredGate` bypass in debug demo/unconfigured | Local UI only; release unconfigured blocked | Keep demo bypass out of production builds |

No BLOCKER, HIGH, or MEDIUM findings remain after remediation verification.

---

## COUNTS

| Severity | Count |
|---|---|
| BLOCKER | 0 |
| HIGH | 0 |
| MEDIUM | 0 |
| LOW | 1 |
| NOTE | 3 |

---

## REMAINING_GOVERNANCE_ITEMS

- **OD-AUTH-01** — Production SMS OTP gateway provider selection remains OPEN. Source does not hardcode a production gateway, does not alter remote Supabase configuration, and does not claim production OTP readiness. This is a production-launch governance blocker, not a source-only HOLD for this slice.

---

## FINAL_DECISION

**PASS**

Reason: Independent verification of target SHA `5cbcc875f491b6002ce4bd8757ff31316f9c65bc` found **0 BLOCKER**, **0 HIGH**, and **0 MEDIUM**. Codex HOLD items R-01–R-05 are closed with code inspection plus local SQL 001–006, adversarial probes, core verifier, and Flutter analyze/test/APK evidence. All 18 focus areas PASS. Remaining items are LOW/NOTE hygiene or open governance (OD-AUTH-01), which do not mandate HOLD under the source-only decision rule for this slice.
