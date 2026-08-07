# NY-V1-NETWORK-DISCOVERY-001 — Cursor Closure Security Review

## MISSION

`NY-V1-NETWORK-DISCOVERY-001-CURSOR-CLOSURE-SECURITY-REVIEW-01`

Final independent security and concurrency closure review of NetYemen V1 Network Discovery after FINAL-HOLD-REMEDIATION-02.

Review-only. No runtime/source fixes. No Production. No remote Supabase. No merge.

## REVIEW_TARGET_SHA

`5cbcc875f491b6002ce4bd8757ff31316f9c65bc`

## REVIEW_BRANCH

`cursor/NY-V1-NETWORK-DISCOVERY-001-CLOSURE`

## WORKTREE_STATUS

- Review executed with worktree checked out at exact target SHA `5cbcc875f491b6002ce4bd8757ff31316f9c65bc` (detached HEAD) and clean before validation.
- Remediation range inspected: `b1da5c0bc0b55ac782a5a0544836e0d777e267d0..5cbcc875f491b6002ce4bd8757ff31316f9c65bc` (14 files; auth, idempotency, state machine, Unicode, tests, docs).
- Flutter `android/gradle.properties` migrator edit from `flutter build apk --debug` was reverted and is not part of this report commit.
- Prior reports read completely and not trusted blindly:
  - Cursor security review (PASS on `b1da5c0…`)
  - Codex final re-review (HOLD on `b1da5c0…`; R-01–R-05)
  - FINAL-HOLD-REMEDIATION-02 report (claimed PASS)

## CODEX_HOLD_CLOSURE_MATRIX

| ID | Prior | Independent result | Evidence |
|---|---|---|---|
| R-01 | HIGH | **CLOSED** | `OTPScreen` no longer calls `createOrUpdateUser`; no client `from('users')`; `handle_new_user` provisions `profiles` + `customer`; SQL 006 AUTH_FRESH_USER_PASS; ADV-12 PASS |
| R-02 | HIGH | **CLOSED** | Client `IdempotencySession` binds UUID v4 to payload fingerprint; `AddRequestScreen.initState` resets session; server `IDEMPOTENCY_PAYLOAD_MISMATCH`; unique `(requester_user_id, idempotency_key)`; SQL 006 CHECK 2–3; ADV-1/2/3 PASS |
| R-03 | MEDIUM | **CLOSED** | Atomic `UPDATE … WHERE status IN ('submitted','under_review')`; terminals (`approved`,`rejected`,`matched_existing`) and `cancelled` cannot rewrite; ADV-4/5/6/7 + matched_existing terminal PASS |
| R-04 | MEDIUM | **CLOSED** | Shared explicit Unicode whitespace set in Dart + PostgreSQL; ADV-13 + SQL 006 UNICODE_NORMALIZATION_PASS; Flutter scan_matcher tests |
| R-05 | LOW | **CLOSED** | OTP widget test, expanded notifier/scan tests, SQL 005/006 extensions; Flutter 50/50 PASS |

---

## IDENTITY_PROVISIONING_RESULT

**PASS**

- Successful OTP completion navigates to `AppShell` without any write to `public.users`.
- Local schema: `to_regclass('public.users') IS NULL`.
- Fresh `auth.users` insert provisions `public.profiles` + `public.user_roles (customer)` via `public.handle_new_user`.
- `SupabaseService.getUserProfile` reads `public.profiles` only.
- Existing-user login path uses real Supabase OTP (`signInWithOtp` / `verifyOTP` SMS).
- Session restoration via `onAuthStateChange` + `currentUser` fallback.
- Sign-out via Profile → `Supabase.auth.signOut`; private providers empty when signed out.
- Unauthenticated public catalog browse remains available; My Requests / Add Request gated by `AuthRequiredGate`.
- No fake release identity; release unconfigured remains blocked.
- No privilege escalation introduced on the fresh-user path.
- **OD-AUTH-01** remains OPEN governance only (no production SMS provider chosen/hardcoded; no remote Auth config mutation; no production OTP readiness claim).

## IDEMPOTENCY_RESULT

**PASS**

- Client UUID is standards-compliant v4 (`Random.secure`, version/variant bits).
- One logical request owns one UUID; same payload retry reuses the same UUID; changed payload mints a new UUID.
- Screen open resets pending session (`resetIdempotency()` in `AddRequestScreen.initState`).
- Server rejects same UUID + different payload with `IDEMPOTENCY_PAYLOAD_MISMATCH`.
- Cross-user same UUID creates distinct rows under `(requester_user_id, idempotency_key)`.
- Concurrent same-key races resolved by `INSERT … ON CONFLICT DO NOTHING` then validate/re-select.
- Requester identity is always `auth.uid()`; client cannot supply requester id for ownership.
- Failures retain session only while fingerprint matches; success clears session.

## STATE_MACHINE_CONCURRENCY_RESULT

**PASS**

- Guarded atomic update: `UPDATE … WHERE id = … AND status IN ('submitted','under_review')`.
- Verified fail-closed: `approved→rejected`, `approved→under_review`, `matched_existing→approved`, conflicting second resolve.
- `matched_network_id` required for `matched_existing` and forbidden otherwise.
- `resolved_by` / `resolved_at` / `resolution_note` set in the same atomic update for terminal statuses.
- Stale concurrent reviewer actions cannot both succeed (second gets `INVALID_TRANSITION`).

## RLS_ASSESSMENT

**PASS** (no remediation regression)

- `ENABLE` + `FORCE ROW LEVEL SECURITY` on `network_addition_requests`.
- SELECT policies only (owner / support_agent / platform_admin / system_auditor).
- No INSERT/UPDATE/DELETE policies — mutations only via SECURITY DEFINER RPCs.
- Cross-user SELECT denied (ADV-11); anon SELECT privilege absent (ADV-10).
- Suites 001–004 PASS (core foundation RLS intact).

## RPC_ASSESSMENT

**PASS**

| RPC | Auth | Identity | Notes |
|---|---|---|---|
| `submit_network_addition_request` | active profile | `auth.uid()` | Server normalizes SSID; payload-bound idempotency |
| `cancel_network_addition_request` | active profile + owner | `auth.uid()` | Only `submitted` intended; see CUR-CL-01 TOCTOU |
| `resolve_network_addition_request` | admin/support | `auth.uid()` as `resolved_by` | Atomic terminal guard |

## ACL_GRANTS_REVOKES

**PASS with MEDIUM hygiene finding (pre-existing; not introduced by remediation-02)**

Intended migration posture:

- `REVOKE ALL … FROM PUBLIC`
- `GRANT SELECT … TO authenticated`
- No INSERT/UPDATE/DELETE to clients
- RPC EXECUTE: PUBLIC revoked; authenticated granted

Independent local ACL probe after `db reset --no-seed`:

- Confirmed: authenticated has SELECT; no INSERT/UPDATE/DELETE for authenticated/anon.
- Residual Supabase default privileges left `TRUNCATE` (also TRIGGER/REFERENCES) on `network_addition_requests` for `anon`, `authenticated`, and `service_role`.
- Direct local SQL as `anon` and `authenticated` successfully executed `TRUNCATE public.network_addition_requests` (transaction rolled back).
- Same residual `anon TRUNCATE` pattern exists on foundation `profiles`; `networks` correctly used explicit `REVOKE ALL FROM anon`.
- Not reachable via PostgREST/Flutter API verbs (no TRUNCATE endpoint). Requires direct SQL role assumption.
- Not introduced in `b1da5c0..5cbcc87` (grant lines unchanged by remediation).

## SECURITY_DEFINER_REVIEW

**PASS**

| Function | search_path | auth.uid() | Dynamic SQL | Escalation |
|---|---|---|---|---|
| submit / cancel / resolve request RPCs | `public, pg_temp` | Yes | None | No |
| `has_platform_role` / `normalize_ssid` | `public, pg_temp` | Helper / N/A | None | No |
| `handle_new_user` | `public, pg_temp` | Trigger | None | Defaults customer only |

No client-supplied identity trust. Schema-qualified table access in RPCs. No unsafe `EXECUTE format(...)`.

## AUTHENTICATION_BOUNDARY

**PASS**

- Public approved networks browsable without auth.
- Private request screens gated.
- Submit requires auth + active profile server-side.
- Real Supabase phone OTP; no fake release identity.
- OD-AUTH-01 open governance only (not a source-only HOLD).

## UNICODE_NORMALIZATION_RESULT

**PASS**

Dart `ScanMatcher.normalizeForMatching` and PostgreSQL `public.normalize_ssid` share the same explicit whitespace contract covering U+0020, tab, newline, U+0085, U+00A0, U+1680, U+2000–U+200A, U+2028, U+2029, U+202F, U+205F, U+3000.

Local PostgreSQL ADV-13 vectors all normalize `A<ws>B` → `a-b`. Arabic `يمن نت` → `يمن-نت`. NFC behavior covered by Flutter tests. Database remains authoritative on submit (`normalize_ssid(p_observed_ssid_display)`); client cannot forge normalized values through RPC parameters.

## WIFI_PRIVACY_RESULT

**PASS**

- Scan is explicit user action only (`performScan` from UI buttons).
- No background scanning paths in feature code.
- Results memory-only (Riverpod); SSID-only extraction in `AndroidWifiScanService`.
- Must-not-persist/transmit controls hold: no BSSID/MAC/location/signal/frequency/password in repository RPC params or request schema.
- AndroidManifest: `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`, `ACCESS_FINE_LOCATION` maxSdk 32, `NEARBY_WIFI_DEVICES` + `neverForLocation` (OS prerequisite NOTE).

## ADVERSARIAL_TESTS

Local-only SQL transaction (rolled back). All PASS:

| # | Case | Result |
|---|---|---|
| 1 | same UUID + different payload | PASS (`IDEMPOTENCY_PAYLOAD_MISMATCH`) |
| 2 | cross-user same UUID replay | PASS (2 distinct rows; counted as postgres) |
| 3 | same payload retry | PASS |
| 4 | terminal → terminal rewrite | PASS |
| 5 | terminal → under_review | PASS |
| 6/7 | stale / conflicting reviewer resolution | PASS |
| 8 | unauthorized direct resolution metadata update | PASS (no UPDATE privilege; row unchanged) |
| 9 | wrong-role resolve RPC | PASS (`FORBIDDEN_ROLE`) |
| 10 | anon / private request access | PASS |
| 11 | cross-user request read | PASS |
| 12 | fresh-user provisioning path | PASS |
| 13 | Unicode whitespace normalization | PASS |
| + | matched_existing terminal rewrite | PASS |

## SQL_TEST_RESULTS

Executed after `npx supabase db reset --no-seed` via `docker exec … psql -v ON_ERROR_STOP=1` against local `supabase_db_netyemen-local`.

| Suite | Result |
|---|---|
| 001_core_schema_contract.sql | **PASS** |
| 002_core_authorization_positive.sql | **PASS** |
| 003_core_authorization_negative.sql | **PASS** |
| 004_core_invariants.sql | **PASS** |
| 005_network_discovery_and_requests.sql | **PASS** |
| 006_final_hold_remediation_verification.sql | **PASS** |

## FLUTTER_VALIDATION

| Check | Result |
|---|---|
| JDK | OpenJDK 17.0.20 (Microsoft; Flutter-configured) |
| `flutter pub get` | PASS |
| `flutter analyze` | PASS — No issues found |
| `flutter test` | PASS — 50/50 |
| `flutter build apk --debug` | PASS — `build\app\outputs\flutter-apk\app-debug.apk` |

## CORE_VERIFIER

`powershell -ExecutionPolicy Bypass -File scripts/verify_netyemen_core_foundation.ps1`

**STATIC VERIFICATION RESULT: PASS (All Rules Satisfied)**

## SECRET_SCAN

**PASS**

- No committed service_role JWT literals, OpenRouter/Kimi API keys, private keys, or production credentials in tracked non-doc sources.
- Matches for `service_role` are documentation/test role switches and GRANT targets only.
- `supabase/.temp`, `supabase/.branches`, and `build/` are not tracked/staged.
- `git diff --check` on remediation range: clean.
- Local Supabase demo JWTs from `supabase status` are runtime-local only (not committed).

## REGRESSION_ASSESSMENT

- Core suites 001–004 PASS after remediation migrations.
- Request RLS/RPC posture preserved; no new INSERT/UPDATE/DELETE client policies.
- SECURITY DEFINER `search_path` and `auth.uid()` identity model preserved.
- Wi-Fi privacy not weakened.
- Prior Codex HOLD items R-01–R-05 independently re-verified closed.
- Residual incomplete `REVOKE` vs Supabase default privileges (TRUNCATE) is pre-existing ACL hygiene and also present on foundation `profiles`; not a remediation-02 regression.

---

## FINDINGS_TABLE

| ID | Severity | Component | Evidence | Impact | Recommendation |
|---|---|---|---|---|---|
| CUR-CL-01 | LOW | `cancel_network_addition_request` | Status checked in PL/pgSQL then `UPDATE … WHERE id AND requester_user_id` without `AND status = 'submitted'` | Requester can cancel after support moved request to `under_review` if cancel races the status change; requester-scoped only | Optional: atomic `UPDATE … WHERE status = 'submitted' AND requester_user_id = auth.uid()` |
| CUR-CL-02 | MEDIUM | ACL on `network_addition_requests` | After local reset, `anon`/`authenticated` retain `TRUNCATE`; direct `SET ROLE anon/authenticated; TRUNCATE …` succeeded (rolled back). Same residue on `profiles`. Not introduced in remediation diff. | Destructive wipe if an attacker obtains a direct SQL session as anon/authenticated; not reachable via PostgREST/Flutter API | Follow core `networks` pattern: `REVOKE ALL FROM anon, authenticated` then `GRANT SELECT TO authenticated` only |
| CUR-CL-03 | NOTE | AndroidManifest | `ACCESS_FINE_LOCATION` maxSdk 32 | OS Wi-Fi scan prerequisite; app does not collect/transmit location | Keep documenting; do not expand to background/coarse location |
| CUR-CL-04 | NOTE | duplicate_of linking | SELECT-then-INSERT without lock/partial unique on open SSID | Rare concurrent same-SSID submits may both omit `duplicate_of` | Optional advisory lock / partial unique later |
| CUR-CL-05 | NOTE | AuthRequiredGate demo bypass | Bypass when `isDemoMode \|\| !isConfigured` | Debug/local UI only; release unconfigured blocked | Keep demo bypass out of customer release builds |

## COUNTS

| Severity | Count |
|---|---|
| BLOCKER | 0 |
| HIGH | 0 |
| MEDIUM | 1 |
| LOW | 1 |
| NOTE | 3 |

## REMAINING_GOVERNANCE_ITEMS

- **OD-AUTH-01** — Production SMS OTP gateway provider selection remains OPEN. Source does not choose/hardcode a production gateway, does not alter remote Supabase Auth configuration, and does not claim production OTP readiness. Production-launch governance blocker only; not a source-only HOLD for this slice.

## FINAL_DECISION

**PASS**

Reason: Target SHA `5cbcc875f491b6002ce4bd8757ff31316f9c65bc` independently verified with **0 BLOCKER** and **0 HIGH**. Codex HOLD items R-01–R-05 are closed in source and locally retested (SQL 001–006 PASS, adversarial suite PASS, Flutter analyze/tests/APK PASS, core verifier PASS). The single MEDIUM (CUR-CL-02 residual TRUNCATE privileges) is pre-existing Supabase default-privilege residue also present on foundation `profiles`, unchanged by this remediation range, and not reachable through the Flutter/PostgREST attack surface for this vertical slice; it does not violate the mandatory remediation acceptance contracts under the stated decision rule. OD-AUTH-01 remains open governance only.
