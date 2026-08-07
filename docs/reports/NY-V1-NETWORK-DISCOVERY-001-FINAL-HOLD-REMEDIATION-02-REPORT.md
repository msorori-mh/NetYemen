> # NY-V1-NETWORK-DISCOVERY-001-FINAL-HOLD-REMEDIATION-02
>
> | Field | Value |
> |---|---|
> | MISSION | NY-V1-NETWORK-DISCOVERY-001-FINAL-HOLD-REMEDIATION-02 |
> | STARTING_SHA | b1da5c0bc0b55ac782a5a0544836e0d777e267d0 |
> | ENDING_SHA | 71fab3c32ec8c3061385cc1da13c5e8e0d800e3d |
> | BRANCH | kimi/NY-V1-NETWORK-DISCOVERY-001-CONTINUE |
> | WORKTREE_STATUS | Clean (no unstaged modifications; `android/gradle.properties` migrator edit reverted) |
>
> ## CODEX_FINDING_CLOSURE_MATRIX
>
> ### R-01 — HIGH — Fresh User OTP Completion
>
> | Item | Detail |
> |---|---|
> | Previous evidence | `OTPScreen` awaited `SupabaseService.createOrUpdateUser()`, which upserted the nonexistent `public.users` table. Local schema inspection returned `to_regclass('public.users') = NULL`; the core V1 trigger `public.handle_new_user` already provisions `public.profiles` and `public.user_roles`. The missing-table exception was caught as "رمز التحقق غير صحيح" and success navigation did not run. |
> | Root cause | Client success path assumed a legacy `public.users` identity table that is not part of the V1 core identity architecture. |
> | Remediation | Removed the `createOrUpdateUser()` method and its invocation from `OTPScreen`. After `verifyOTP` returns a user, the screen relies on the existing `auth.users` -> `public.profiles`/`public.user_roles` trigger provisioning and navigates to `AppShell`. `SupabaseService.getUserProfile()` now reads from `public.profiles` and constructs `AppUser` using V1 fields only. |
> | Files changed | `lib/services/supabase_service.dart`, `lib/screens/auth/otp_screen.dart` |
> | Tests / evidence | `test/features/auth/otp_screen_test.dart` (widget test proving OTP success navigates to `AppShell` without any `public.users` reference); `supabase/tests/006_final_hold_remediation_verification.sql` CHECK 1 (`AUTH_FRESH_USER_PASS`). |
> | Closure status | **CLOSED** |
>
> ### R-02 — HIGH — Idempotency Key Reuse Across Logical Requests
>
> | Item | Detail |
> |---|---|
> | Previous evidence | `pendingIdempotencyKeyProvider` stored a single global UUID. After a failed request, the UUID was retained; editing the form or opening a new request reused it and could return the wrong committed row. |
> | Root cause | Idempotency UUID was not bound to the immutable logical request payload. |
> | Remediation | Replaced the global key provider with `pendingIdempotencySessionProvider`, an `IdempotencySession` that stores both the UUID and a deterministic payload fingerprint. `SubmitRequestNotifier` reuses the UUID only while the fingerprint matches; otherwise it mints a new UUID. `AddRequestScreen` calls `resetIdempotency()` in `initState` so a fresh screen starts a new logical request. Server-side, `submit_network_addition_request` now raises `IDEMPOTENCY_PAYLOAD_MISMATCH` if the same `(requester_user_id, idempotency_key)` is replayed with different payload fields. |
> | Files changed | `lib/features/network_requests/presentation/network_request_providers.dart`, `lib/features/network_requests/presentation/add_request_screen.dart`, `supabase/migrations/20260727130000_netyemen_network_addition_requests.sql` |
> | Tests / evidence | `test/features/network_requests/submit_request_notifier_test.dart` (retry-after-failure same payload, changed payload after failure mints new key, independent submissions distinct keys); `supabase/tests/005_network_discovery_and_requests.sql` NEG-14; `supabase/tests/006_final_hold_remediation_verification.sql` CHECK 2 & 3. |
> | Closure status | **CLOSED** |
>
> ### R-03 — MEDIUM — Terminal State Rewrites / Stale Read Race
>
> | Item | Detail |
> |---|---|
> | Previous evidence | `resolve_network_addition_request` read status without locking, allowed `matched_existing -> approved/rejected`, permitted same-status rewrites, and updated by ID without a source-status predicate. Two concurrent resolvers could overwrite each other. |
> | Root cause | State-machine logic was not enforced atomically at the database level. |
> | Remediation | Redesigned `resolve_network_addition_request` to use a single guarded atomic `UPDATE ... WHERE status IN ('submitted', 'under_review')`. Only non-terminal statuses may transition; `approved`, `rejected`, `matched_existing`, and `cancelled` are protected. Added metadata coherence checks: `matched_network_id` is required for `matched_existing` and forbidden for other statuses. Concurrent resolvers now serialize through row locking and the predicate guarantees only one terminal resolution succeeds. |
> | Files changed | `supabase/migrations/20260727130000_netyemen_network_addition_requests.sql` |
> | Tests / evidence | `supabase/tests/005_network_discovery_and_requests.sql` NEG-12, NEG-13, NEG-15; `supabase/tests/006_final_hold_remediation_verification.sql` CHECK 4 & 5. |
> | Closure status | **CLOSED** |
>
> ### R-04 — MEDIUM — Unicode Whitespace Normalization Parity
>
> | Item | Detail |
> |---|---|
> | Previous evidence | PostgreSQL `\s` left U+00A0 unchanged while Dart `RegExp(r'\s+')` collapsed it, producing different normalized SSIDs for the same logical input. |
> | Root cause | The two runtimes used different implicit whitespace definitions. |
> | Remediation | Defined one explicit whitespace contract covering ASCII whitespace, U+0085, U+00A0, U+1680, U+2000-U+200A, U+2028, U+2029, U+202F, U+205F, and U+3000. Implemented identical trim/collapse logic in both `public.normalize_ssid` (PostgreSQL `U&` string + `regexp_replace`) and `ScanMatcher.normalizeForMatching` (Dart `RegExp` built from `String.fromCharCode` codepoints). NFC normalization and lowercase behavior are unchanged. |
> | Files changed | `supabase/migrations/20260727091000_netyemen_core_rls_and_audit.sql`, `lib/features/network_discovery/data/scan_matcher.dart` |
> | Tests / evidence | `test/features/network_discovery/scan_matcher_test.dart` (NBSP, narrow NBSP, ideographic space, U+2000-U+200A, Arabic NFC); `supabase/tests/005_network_discovery_and_requests.sql` POS-09; `supabase/tests/006_final_hold_remediation_verification.sql` CHECK 6. |
> | Closure status | **CLOSED** |
>
> ### R-05 — LOW — Auth / Repository Integration Coverage
>
> | Item | Detail |
> |---|---|
> | Previous evidence | All 39 tests passed while R-01 remained present; production auth/profile integration paths were not exercised. |
> | Root cause | Tests did not assert the actual OTP success path, payload-bound idempotency behavior, or the new database-level state machine / normalization contracts. |
> | Remediation | Added `test/features/auth/otp_screen_test.dart`, `test/fakes/fake_supabase_service.dart`, expanded `submit_request_notifier_test.dart` and `scan_matcher_test.dart`, and extended `supabase/tests/005_network_discovery_and_requests.sql` with NEG-12/13/14/15 and POS-09. Added `supabase/tests/006_final_hold_remediation_verification.sql` as a source-controlled realistic local check. |
> | Files changed | `test/features/auth/otp_screen_test.dart`, `test/fakes/fake_supabase_service.dart`, `test/features/network_requests/submit_request_notifier_test.dart`, `test/features/network_discovery/scan_matcher_test.dart`, `supabase/tests/005_network_discovery_and_requests.sql`, `supabase/tests/006_final_hold_remediation_verification.sql` |
> | Tests / evidence | Flutter tests increased from 39 to 50, all pass; SQL suites 001-005 pass; realistic local verification script passes. |
> | Closure status | **CLOSED** |
>
> ## AUTH_FRESH_USER_RESULT
>
> **PASS**
>
> - `public.users` does not exist in the local schema.
> - Simulated fresh `auth.users` insert auto-provisions `public.profiles` and `public.user_roles` via `public.handle_new_user`.
> - `OTPScreen` no longer calls any legacy `public.users` upsert and navigates to `AppShell` on successful OTP verification.
>
> ## IDEMPOTENCY_RESULT
>
> **PASS**
>
> - Same immutable logical payload + same UUID returns the same request row.
> - Retry after failure reuses the UUID when the payload is unchanged.
> - A materially changed payload mints a new UUID on the client and is rejected by the server if the old UUID is reused.
> - Cross-user UUID collision remains impossible because of the `(requester_user_id, idempotency_key)` unique index.
>
> ## STATE_MACHINE_CONCURRENCY_RESULT
>
> **PASS**
>
> - Terminal statuses (`approved`, `rejected`, `matched_existing`) cannot be rewritten.
> - `cancelled` requests cannot be resolved.
> - Resolution is a single atomic `UPDATE ... WHERE status IN ('submitted', 'under_review')`; stale or concurrent updates fail closed.
> - `matched_network_id` coherence is enforced (required for `matched_existing`, forbidden otherwise).
>
> ## UNICODE_NORMALIZATION_RESULT
>
> **PASS**
>
> - Dart and PostgreSQL now share the same explicit Unicode whitespace contract.
> - Verified vectors include U+00A0, U+0085, U+2000-U+200A, U+202F, U+205F, U+3000, Arabic SSIDs, and NFC-equivalent strings.
> - The database remains authoritative: `submit_network_addition_request` ignores any client-normalized value and re-derives it server-side.
>
> ## FLUTTER
>
> | Check | Result |
> |---|---|
> | JDK | Microsoft OpenJDK 17.0.20+8-LTS |
> | `flutter pub get` | PASS |
> | `flutter analyze` | 0 issues |
> | `flutter test` | 50/50 PASS |
> | `flutter build apk --debug` | PASS (`build\app\outputs\flutter-apk\app-debug.apk`) |
>
> ## SUPABASE
>
> | Check | Result |
> |---|---|
> | `npx supabase start` | PASS (local loopback stack only) |
> | `npx supabase db reset --no-seed` | PASS |
> | SQL 001 `ON_ERROR_STOP=1` | PASS |
> | SQL 002 `ON_ERROR_STOP=1` | PASS |
> | SQL 003 `ON_ERROR_STOP=1` | PASS |
> | SQL 004 `ON_ERROR_STOP=1` | PASS |
> | SQL 005 `ON_ERROR_STOP=1` | PASS |
> | SQL 006 realistic local verification `ON_ERROR_STOP=1` | PASS |
>
> ## CORE_VERIFIER
>
> `powershell -ExecutionPolicy Bypass -File scripts/verify_netyemen_core_foundation.ps1`
>
> **STATIC VERIFICATION RESULT: PASS (All Rules Satisfied)**
>
> ## SECURITY_REGRESSION_RESULT
>
> **PASS**
>
> - No `public.users` shadow identity architecture introduced.
> - No broad authenticated DML grants added.
> - `network_addition_requests` remains `FORCE RLS`; no INSERT/UPDATE/DELETE policies; mutations only via SECURITY DEFINER RPCs.
> - `submit_network_addition_request`, `cancel_network_addition_request`, `resolve_network_addition_request` retain `SET search_path = public, pg_temp` and derive requester identity from `auth.uid()`.
> - No new RLS bypass, generic admin bypass, or unsafe `EXECUTE` grants introduced.
> - Cursor PASS verdict on RLS, authorization, SECURITY DEFINER, Wi-Fi privacy, secrets, and core foundation is preserved.
>
> ## SECRET_SCAN
>
> **PASS**
>
> - No committed service-role keys, JWT literals, private keys, or production API keys.
> - `supabase/.temp`, `supabase/.branches`, and `build/` are not staged.
> - `git diff --check` reports no whitespace errors (only LF/CRLF warnings for files created on Windows).
>
> ## COMMITS
>
> | SHA | Message |
> |---|---|
> | 345b4b5 | fix(auth): repair fresh-user Supabase identity completion |
> | 8cec225 | fix(db): bind idempotency keys to immutable logical requests and enforce atomic terminal transitions |
> | a8f3bc8 | fix(app): unify Unicode SSID whitespace normalization |
> | b3799e3 | test(app): cover final network discovery hold remediation |
> | 71fab3c | fix(app): bind idempotency session to immutable logical request payload |
>
> ## PUSH_RESULT
>
> Branch `kimi/NY-V1-NETWORK-DISCOVERY-001-CONTINUE` will be pushed to update existing Draft PR #5. No duplicate PR will be created.
>
> ## PR_5_STATUS
>
> - Open
> - Draft
> - Unmerged
>
> ## REMAINING_GOVERNANCE
>
> - **OD-AUTH-01** — Production SMS OTP gateway provider selection remains OPEN. The source code does not choose or hardcode a production gateway, does not alter remote Supabase configuration, and does not claim production OTP readiness. This is a production-launch governance blocker, not a source-only HOLD for this slice.
>
> ## REMAINING_BLOCKERS
>
> None.
>
> ## FINAL_DECISION
>
> **PASS**
>
> R-01, R-02, R-03, and R-04 are demonstrably closed with focused client and server changes, paired Dart/PostgreSQL tests, and realistic local verification. R-05 coverage has been strengthened. No security regression was introduced. OD-AUTH-01 remains the only open governance item and is explicitly out of scope for a source-only HOLD.
