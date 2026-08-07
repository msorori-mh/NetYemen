# NY-V1 Network Discovery — Codex Closure Review

- TASK_ID: `NY-V1-NETWORK-DISCOVERY-001-CODEX-CLOSURE-REVIEW-01`
- Target SHA: `5cbcc875f491b6002ce4bd8757ff31316f9c65bc`
- Review date: 2026-08-08 (Asia/Riyadh)
- Scope: review only; local Supabase only; no runtime/source modification, production or remote access, merge, or push

## Review basis

The worktree was clean and `HEAD` exactly matched the required target SHA at review start. The complete prior Codex final re-review and complete final HOLD remediation report were read. The target source, migrations, focused tests, and authentication, request, state-machine, and normalization paths were then independently inspected and executed.

## Closure results

| Finding | Result | Independent evidence |
|---|---|---|
| R-01 | **CLOSED / PASS** | No runtime reference or client write to `public.users` remains. Local insertion of a fresh `auth.users` identity provisioned the matching `public.profiles` row and default `public.user_roles.customer` row through `public.handle_new_user`; SQL 006 confirmed `public.users` is absent. OTP completion calls Supabase `verifyOTP(..., OtpType.sms)` and navigates after a returned user without a legacy-table operation. Existing login is represented by `auth.onAuthStateChange`; session restoration falls back to `client.auth.currentUser` while the stream loads or errors; sign-out calls Supabase Auth and the provider stream drives the unauthenticated UI. Focused OTP/auth-gate/profile widget tests pass. |
| R-02 | **CLOSED / PASS** | The client binds a UUID v4 to a deterministic payload/requester fingerprint, retains it for an unchanged retry, mints a new key for changed payload or a fresh screen, and clears it after success. The RPC uniqueness scope is `(requester_user_id, idempotency_key)`, compares all payload fields on replay, and raises `IDEMPOTENCY_PAYLOAD_MISMATCH` for a changed payload. Independent simultaneous replay returned the same row ID in both sessions and left one row. Reusing the same UUID as another requester produced a separate row, confirming requester isolation. |
| R-03 | **CLOSED / PASS** | Resolution is a single guarded database `UPDATE ... WHERE status IN ('submitted', 'under_review')`. `approved`, `rejected`, `matched_existing`, and `cancelled` cannot be resolved again; match metadata coherence is enforced. Independent concurrent `approved`/`rejected` resolution produced one committed terminal result and one `INVALID_TRANSITION`, so conflicting stale resolutions cannot both succeed. |
| R-04 | **CLOSED / PASS** | Dart and PostgreSQL explicitly enumerate the same whitespace set. Local PostgreSQL vectors normalized every mandated point—U+00A0, U+1680, U+2000 through U+200A, U+2028, U+2029, U+202F, U+205F, and U+3000—to `a-b`. Dart focused tests pass for representative values and the full U+2000..U+200A range; source inspection confirms the remaining mandated points are in the identical explicit set. Correct Arabic composed U+0623 and decomposed U+0627 U+0654 normalized to identical UTF-8, and mixed Arabic/Latin and Latin SSIDs normalized correctly. |
| R-05 | **CLOSED / PASS** | Coverage is meaningful across layers: 50 passing Dart unit/widget tests exercise OTP success/error, auth gating, profile states, UUID generation, retry/change/reset semantics, and normalization; SQL 001–006 exercise schema, authorization, invariants, request RPCs, fresh-user trigger provisioning, payload mismatch, terminal immutability, and Unicode behavior against a reset local database. Independent two-session concurrency checks supplement the source-controlled suites. |

## Flutter and toolchain results

| Check | Result |
|---|---|
| `flutter doctor -v` | Android prerequisites PASS; Flutter 3.44.8 / Dart 3.12.2. Doctor reports only missing Visual Studio for Windows desktop, which is outside the Android target. |
| JDK requirement | PASS — Microsoft OpenJDK 17.0.20+8-LTS selected by Flutter and confirmed by `java -version`. |
| `flutter pub get` | PASS |
| `flutter analyze` | PASS — no issues found |
| `flutter test` | PASS — 50 tests |
| `flutter build apk --debug` | PASS |
| APK | `build/app/outputs/flutter-apk/app-debug.apk`, 152,109,742 bytes, SHA-256 `C601AAD044EFFA7357676F6A51A7CB9D9D0DF64B58EBDBF7A21D61F544FECA61` |

The Flutter build invoked its tracked Gradle-property migrator. Its generated lines were removed and the target file was restored exactly; no runtime/source delta remains.

## Local Supabase and SQL results

| Check | Result |
|---|---|
| `npx supabase start` | PASS — loopback local stack only |
| `npx supabase db reset --no-seed` | PASS |
| SQL 001 with `ON_ERROR_STOP=1` | PASS |
| SQL 002 with `ON_ERROR_STOP=1` | PASS — 14 positive authorization tests |
| SQL 003 with `ON_ERROR_STOP=1` | PASS — 30 negative authorization tests |
| SQL 004 with `ON_ERROR_STOP=1` | PASS — 12 core invariants |
| SQL 005 with `ON_ERROR_STOP=1` | PASS — network discovery/request suite |
| SQL 006 with `ON_ERROR_STOP=1` | PASS — all final-HOLD closure checks |
| Concurrent identical replay | PASS — both calls returned `ba4a5477-4f18-404a-a791-14b0ee087b64`; stored count `1`, distinct-ID count `1` |
| Concurrent conflicting resolution | PASS — one `approved`; the other rejected with `INVALID_TRANSITION` |

No Production or remote Supabase command was used.

## Additional verification

| Check | Result |
|---|---|
| `scripts/verify_netyemen_core_foundation.ps1` | PASS — all rules satisfied |
| `git diff --check` | PASS |
| Secret scan | PASS — no tracked secret-role key, private key, production API-secret, or JWT literal found |
| Artifact scan | PASS — no tracked build, Supabase temp/branch, APK/AAB, keystore, or environment artifact found |

## Findings

No unresolved findings were identified.

Counts: BLOCKER 0, HIGH 0, MEDIUM 0, LOW 0, NOTE 0.

## FINAL_DECISION

**PASS**

R-01 through R-05 are independently verified closed at the exact target SHA. The mandatory authentication provisioning, UUID idempotency, atomic terminal transition, Unicode normalization parity, and meaningful integration-coverage contracts are satisfied. This review does not grant production OTP-provider governance approval and does not perform or authorize a merge.
