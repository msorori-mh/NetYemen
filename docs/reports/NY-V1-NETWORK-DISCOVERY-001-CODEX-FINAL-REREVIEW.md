# NY-V1 Network Discovery — Codex Final Re-review

- TASK_ID: `NY-V1-NETWORK-DISCOVERY-001-CODEX-FINAL-REREVIEW-01`
- Target SHA: `b1da5c0bc0b55ac782a5a0544836e0d777e267d0`
- Previous failed target: `9ff8e3a4d02b5c0bc0bb47bb1268154438e74854`
- Review date: 2026-08-08 (Asia/Riyadh)
- Role: independent final re-reviewer
- Scope: review only; no runtime/source changes, production actions, remote Supabase access, merge, or push

## Target and review inputs

The worktree was initially clean and `HEAD` exactly matched the required target SHA. The complete original Codex review and complete Kimi remediation report were read before inspecting and executing the target. The comparison from the previous target to this target contains 22 changed files: UUID/idempotency code and tests, auth routing/state code and tests, SSID normalization, request SQL/RLS tests, and remediation documentation.

## Previous findings closure matrix

| ID | Previous severity | Re-review result | Evidence |
|---|---:|---|---|
| F-01 | HIGH | PARTIAL / NOT CLOSED | Generated keys are valid UUID v4 values and the UUID-typed RPC accepts them. Atomic database replay is fixed. However, the single global pending key is not bound to a payload or screen lifecycle; after a failed attempt, editing/navigating to a logically new request reuses the old UUID and can return the old row. See R-02. |
| F-02 | HIGH | NOT CLOSED | Login is reachable and invokes genuine Supabase phone OTP Auth, but successful OTP verification is followed by an upsert to nonexistent `public.users`. The local schema has `public.profiles` only, so the intended success navigation is interrupted and the error is presented as an incorrect OTP. See R-01. |
| F-03 | MEDIUM | CLOSED | `INSERT ... ON CONFLICT (requester_user_id, idempotency_key) DO NOTHING RETURNING id` followed by lookup removes the prior check-then-insert idempotency race. Concurrent conflicts wait on the unique constraint and resolve to the existing row. |
| F-04 | MEDIUM | NOT CLOSED | A transition table was added, but it explicitly permits `matched_existing -> approved/rejected`, all same-status rewrites, and uses an unlocked read followed by an unconditional update. Concurrent resolvers can both validate stale state and overwrite each other. See R-03. |
| F-05 | MEDIUM | NOT CLOSED | Dart now applies NFC and agrees with PostgreSQL for tested Arabic decomposed/composed input and ordinary spaces. Full Unicode whitespace behavior still differs: PostgreSQL left U+00A0 unchanged, while Dart `RegExp(r'\s+')` follows ECMAScript whitespace and collapses U+00A0. See R-04. |
| F-06 | LOW | PARTIAL / NOT CLOSED | Focused UUID, notifier, auth-gate, profile, and Unicode NFC tests were added. Production Supabase auth/profile integration is still untested, allowing R-01 to pass all 39 tests; adverse scanner/provider integration gaps also remain. |
| F-07 | LOW | CLOSED | Cancellation failures are now surfaced through an Arabic `SnackBar`; the prior catch-and-discard behavior was removed. |

## Independent execution evidence

| Command/check | Result |
|---|---|
| `flutter pub get` | PASS |
| `flutter analyze` | PASS — no issues |
| `flutter test` | PASS — 39 tests |
| `flutter build apk --debug` | PASS |
| `flutter doctor -v` / `java -version` | PASS — Flutter uses Microsoft OpenJDK 17.0.20+8-LTS |
| APK | `build/app/outputs/flutter-apk/app-debug.apk`, 152,105,598 bytes, SHA-256 `5E0F571CE30DEA021458B22DF3222A2D4C9202657E3AE9247184F217E8C50312` |
| `npx supabase start` | PASS — local loopback stack only |
| `npx supabase db reset --no-seed` | PASS |
| SQL 001 with `ON_ERROR_STOP=1` | PASS |
| SQL 002 with `ON_ERROR_STOP=1` | PASS |
| SQL 003 with `ON_ERROR_STOP=1` | PASS |
| SQL 004 with `ON_ERROR_STOP=1` | PASS |
| SQL 005 with `ON_ERROR_STOP=1` | PASS |
| `scripts/verify_netyemen_core_foundation.ps1` | PASS |
| `git diff --check` | PASS |
| Secret scan of target delta | PASS — one textual match was the remediation report's phrase “service-role key”; no credential value, private key, password, or new secret was found |

The Flutter build temporarily invoked Flutter's tracked Gradle-property migrator; its generated working-tree edit was removed. Before this report, the worktree was clean again. No remote Supabase command was run.

## UUID and idempotency result

The UUID generator uses `Random.secure()`, sets version 4 and RFC 4122 variant bits, and emits canonical lowercase `8-4-4-4-12` text. Unit tests generated valid and distinct values. The local PostgreSQL RPC accepts UUID input. Database idempotency is correctly scoped by `(requester_user_id, idempotency_key)`, preventing cross-user replay collisions, and the atomic insert fixes F-03.

The client contract is incomplete. `pendingIdempotencyKeyProvider` is application/provider-scope state. It is retained on failure and cleared only after success or an explicit `resetIdempotency()` call, but `AddRequestScreen` neither resets it when a new form is opened nor ties it to the submitted payload. `resetIdempotency()` is not called by the request UI. Consequently:

1. request A fails after its UUID is allocated;
2. the user edits the form or leaves and opens a new request B;
3. B reuses A's UUID;
4. if A actually committed but its response was lost, B receives A's row and displays success for the wrong logical request.

Thus retry preservation works, but the mandatory “new logical requests receive new UUIDs” and safe scoping requirements do not.

## Authentication result

The public catalog remains reachable without authentication. Private “My Requests” and “Add Request” surfaces use `AuthRequiredGate` and route unauthenticated users to a reachable login. Login calls Supabase `auth.signInWithOtp`, verification calls Supabase `auth.verifyOTP(..., OtpType.sms)`, `currentUserProvider` observes `onAuthStateChange` and falls back to the restored current session, and profile sign-out calls Supabase Auth. No fake release identity was introduced.

The end-to-end fresh-user login path is nevertheless broken. After `verifyOTP` returns a user, `OTPScreen` awaits `SupabaseService.createOrUpdateUser()`, which upserts `public.users`. Independent local schema inspection returned `to_regclass('public.users') = NULL` and `to_regclass('public.profiles') = public.profiles`; the core auth trigger already provisions `profiles`. The missing-table exception is caught by the OTP screen's broad catch, “رمز التحقق غير صحيح” is shown, and `pushAndRemoveUntil(... AppShell)` is not reached. Therefore fresh login and authenticated request submission through the intended success flow are not verified functional.

`OD-AUTH-01` remains open/unapproved and blocks production launch. No SMS vendor or production Auth configuration was added or approved by this remediation.

## Database remediation result

SQL reset and all suites pass, RLS remains forced, RPC execution remains authenticated-only, requester identity is derived from `auth.uid()`, active-profile checks remain, customers have no direct write policy, anonymous request reads are denied, and support/admin read policies remain role checked. No new privilege-escalation path was found.

The idempotent submit implementation is atomic for the unique requester/key pair. Duplicate-of detection remains advisory and can still race, but this behavior was already identified as advisory in the original review and was not worsened by remediation.

The resolution state machine is not coherent with its stated terminal model. SQL lines 334–337 permit `matched_existing` to change to `approved` or `rejected` and permit any status to rewrite itself. SQL 005 passes because its NEG-12 setup first exercises the permitted `matched_existing -> approved` transition, then checks only that `approved -> rejected/under_review` fail. It therefore does not prove the remediation report's claim that all terminal statuses cannot be rewritten. In addition, status is selected without `FOR UPDATE`, then later updated by ID without rechecking the source status, so two concurrent resolvers can both validate the same pre-terminal status and the later update can overwrite the earlier terminal result and metadata.

## SSID normalization result

NFC parity is materially improved. Independent PostgreSQL checks showed composed Arabic ALEF WITH HAMZA ABOVE and decomposed ALEF + COMBINING HAMZA ABOVE normalize to identical UTF-8 (`d8a3`), and ordinary Arabic text separated by ASCII spaces normalizes with a hyphen.

The contracts are not fully identical for Unicode whitespace. `public.normalize_ssid(U&'A\00A0B')` returned UTF-8 hex `61c2a062`, retaining the no-break space, while Dart uses ECMAScript `\s`, whose whitespace set includes U+00A0, and therefore produces `a-b`. Canonically equivalent Arabic behavior passes, but the broader mandatory Arabic/Unicode contract does not fully agree.

## Regression result

The target compiles, tests, and builds and preserves the prior catalog/privacy/RLS posture. No secret or privilege-escalation regression was found. However, the remediation introduced or exposed three material functional/state regressions: the missing-table post-auth call, unsafe logical-request UUID reuse after failure, and concurrently overwritable resolution transitions. Test coverage does not catch these release-path issues.

## Findings

| ID | Severity | Finding | Impact/evidence |
|---|---:|---|---|
| R-01 | HIGH | Fresh Supabase OTP login success path writes to nonexistent `public.users` | `otp_screen.dart:32-42` verifies with Supabase, then awaits `createOrUpdateUser`; `supabase_service.dart:42-52` upserts `users`. Local reset contains `profiles` and no `users`, so intended login completion/navigation fails and authenticated request submission is not end-to-end reachable. F-02 remains unresolved. |
| R-02 | HIGH | Idempotency UUID is not scoped to a logical request | `network_request_providers.dart:50,75-95` retains one global pending key after failure; `AddRequestScreen` never resets or payload-binds it. A new form/payload after failure can replay an earlier committed request and falsely report success. This violates mandatory new-logical-request UUID behavior and leaves F-01 incomplete. |
| R-03 | MEDIUM | Resolution state machine permits terminal rewrites and has a stale-read race | Migration lines 320-358 permit `matched_existing -> approved/rejected`, permit same-status rewrites, read without locking, and update without a source-status predicate. Concurrent resolution can overwrite terminal state/metadata. F-04 remains unresolved. |
| R-04 | MEDIUM | Dart/PostgreSQL Unicode whitespace normalization differs | Local PostgreSQL retained U+00A0; Dart `RegExp(r'\s+')` collapses it. F-05 remains unresolved despite correct NFC/Arabic canonical equivalence. |
| R-05 | LOW | Production auth/repository and adverse scanner paths remain untested | All 39 tests pass while R-01 remains present. F-06 is only partially closed. |

Counts: BLOCKER 0, HIGH 2, MEDIUM 2, LOW 1, NOTE 0.

## Final decision

**HOLD**

Exact unresolved release findings: R-01 and R-02 are HIGH. F-04 and F-05 also remain incompletely remediated as R-03 and R-04. The target must not be accepted or merged until the fresh-user auth completion path, logical-request idempotency scope, atomic terminal transition rules, and cross-runtime Unicode normalization contract are corrected and independently retested. `OD-AUTH-01` remains unimplemented/unapproved and no production launch approval is implied.
