# NY-V1 Network Discovery — Independent Codex Review

- TASK_ID: `NY-V1-NETWORK-DISCOVERY-001-CODEX-INDEPENDENT-REVIEW-01`
- REVIEW_TARGET_SHA: `9ff8e3a4d02b5c0bc0bb47bb1268154438e74854`
- REVIEW_BRANCH: `codex/NY-V1-NETWORK-DISCOVERY-001-REVIEW`
- BASE_SHA: `1fe96d6867210da3e603f8ab08c01ddc36401158`
- Review date: 2026-08-07 (Asia/Riyadh)
- Scope: functional, architecture, Flutter, Wi-Fi/privacy, database/RPC/RLS, tests, CI, and line-level integration review.

## Target integrity

The initial worktree was clean, the current branch exactly matched the expected branch, and `HEAD` exactly matched the review target. The base is the merge-base of base and target, so no unexpected ancestry divergence was found.

Implementation commits, oldest first:

1. `27a74f5` — `wip(transfer): preserve NetYemen network discovery local state`
2. `499ab54` — `feat(app): complete NetYemen V1 network discovery`
3. `408d433` — `feat(db): complete network addition request workflow`
4. `89b1d70` — `test(app): verify network discovery vertical slice`
5. `9ff8e3a` — `chore(deps): remove unused permission_handler dependency`

## Architecture and Flutter review

The new code generally uses coherent feature directories, domain entities, repository interfaces, concrete demo/Supabase implementations, and Riverpod providers. Catalog and request persistence are kept behind repository abstractions. Arabic locale and an application-level RTL `Directionality` are present. Catalog, scan, and request screens provide loading, empty, and error states, although cancellation errors are silently discarded.

`String.fromEnvironment` avoids committed deployment credentials. A release build with missing configuration is stopped on an unconfigured screen; missing configuration in debug selects explicit in-memory demo repositories and a fake scanner. A configured environment selects Supabase and the Android scanner. No new hardcoded secret was found. URL validation accepts HTTP as well as HTTPS, which is useful for local development but should be governed by release configuration.

The shell has a material integration defect: it no longer routes to the repository's existing login/OTP screens. It can display and sign out an already-restored Supabase user, but a fresh configured installation has no reachable sign-in action. Consequently, the authenticated network-request vertical slice cannot be used by a new customer.

## Wi-Fi discovery and privacy review

Scanning is initiated only from explicit button presses (initial scan and retry). No timer, background task, lifecycle listener, or automatic scan was found. The Android service immediately projects plugin results to trimmed SSID strings, deduplicates them, and retains results only in Riverpod memory. Matching consumes SSID/alias data only. BSSID, MAC, signal strength, frequency, coordinates, Wi-Fi passwords, and plugin access-point objects are neither persisted nor transmitted by this implementation.

Unsupported platform/device, permission denial, disabled location/Wi-Fi service, and Android scan throttling have typed exceptions and distinct Arabic UI messages. The service treats a failed `startScan()` as throttling; this is conservative but may classify other plugin failures as throttling.

Manifest permissions are scoped to Wi-Fi scanning: `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`, location through Android 12 (`maxSdkVersion=32`), and `NEARBY_WIFI_DEVICES` with `neverForLocation`. No unnecessary permission was identified for the selected scanning plugin/API behavior.

SSID normalization is deterministic within Dart, and duplicate scanned SSIDs are case-insensitively suppressed. However, Dart normalization does not perform the Unicode NFC normalization used by `public.normalize_ssid`; canonically equivalent Unicode SSIDs can therefore be stored/matched differently between catalog data and a scan.

## Database, RPC, and RLS review

Submission and cancellation derive requester identity from `auth.uid()` and require an active profile. There is no requester parameter to spoof. The table has forced RLS, authenticated users receive SELECT only, customers can select only their own rows, anonymous callers have neither table nor RPC access, and all writes are through security-definer RPCs. Customers cannot directly set status, resolution note, match, resolver, or resolution timestamps. Admin/support access is role checked and no direct UPDATE policy is granted. Existing core SQL authorization suites continue to pass.

The request client and RPC are not integrated correctly: the Dart notifier generates a base-36 timestamp token such as `mf...-...`, while `p_idempotency_key` is declared `UUID`. PostgREST/PostgreSQL will reject normal production submissions before the function body executes.

The server-side idempotency implementation is also check-then-insert. Two concurrent calls with the same key can both miss the preliminary SELECT; one then fails the unique index rather than receiving the existing result. Duplicate-of detection has the same unlocked check-then-insert race, although it is advisory rather than a uniqueness guarantee.

Lifecycle transitions are not explicitly constrained. Admin/support may rewrite any request to any allowed review/terminal status. Terminal-to-terminal rewrites succeed and replace resolution metadata; terminal-to-`under_review` attempts retain `resolved_at`/`resolved_by` and fail indirectly through the coherence constraint. This is not a coherent state machine.

## Test and CI review

Dart matcher tests cover trimming, case-insensitive deduplication, empty/unknown values, normalized matching, display matching, unmatched values, and preventing duplicate network output. They do not cover Unicode normalization equivalence, multiple catalog networks sharing one alias, the real Android scanner, scan exception mapping, Riverpod production wiring, Supabase repository serialization, or the generated idempotency key's UUID contract.

The fake request repository tests exercise creation, ordering, cancellation, and missing IDs, but the fake ignores idempotency keys and therefore cannot prove production idempotency. SQL 005 genuinely executes under anon/authenticated/admin/support identities and proves active-user enforcement, own-row visibility, cross-user isolation/cancellation denial, direct mutation denial, requester derivation, basic replay, duplicate linking, and representative resolution/cancellation behavior. It does not test concurrent idempotency, concurrent duplicate detection, resolution transition legality, anonymous SELECT on requests, or attempted direct mutation of each privileged resolution field.

CI was extended to run SQL 005. The existing artifact-presence loop was not extended to require SQL 005 to be non-empty, and Flutter CI does not add production-wiring tests for this vertical slice.

## Independently executed commands and results

| Command | Result |
|---|---|
| `flutter pub get` | PASS |
| `flutter analyze` | PASS — zero issues |
| `flutter test` | PASS — 23 tests |
| `flutter build apk --debug` | NOT VERIFIED / environment failure — Gradle rejected Flutter's configured Android Studio JDK version `25.0.2` before compilation. Retrying with shell Java 17 did not override Flutter's configured JDK. Flutter's attempted `gradle.properties` migration was reverted. |
| `npx supabase start` | PASS — local loopback stack only |
| `npx supabase db reset --no-seed` | PASS |
| SQL 001, `ON_ERROR_STOP=1` | PASS |
| SQL 002, `ON_ERROR_STOP=1` | PASS |
| SQL 003, `ON_ERROR_STOP=1` | PASS |
| SQL 004, `ON_ERROR_STOP=1` | PASS |
| SQL 005, `ON_ERROR_STOP=1` | PASS |
| `scripts/verify_netyemen_core_foundation.ps1` | PASS |
| `git diff --check` before report | PASS |
| Secret scan | PASS for reviewed delivery: no new private credential, service-role key, password, or private key found. Existing `lib/utils/constants.dart` contains a previously documented publishable key and placeholder third-party key, unchanged by this target. |

No remote Supabase command, deployment, push, PR mutation, merge, or runtime-code modification was performed.

## Findings

| ID | Severity | Finding | Evidence / impact |
|---|---|---|---|
| F-01 | HIGH | Client idempotency keys are not UUIDs | `network_request_providers.dart:66-72` creates a base-36 token, while the migration declares `p_idempotency_key UUID` at line 83. Normal production request submission fails at RPC argument conversion. |
| F-02 | HIGH | Fresh users cannot authenticate in the new app shell | `AppShell` exposes only the four new feature screens. `ProfileScreen` supports sign-out but no sign-in; `AddRequestScreen` only reports that authentication is required. The authenticated request workflow is unreachable on a fresh configured install. |
| F-03 | MEDIUM | Idempotent replay is not atomic | Migration lines 144-202 perform SELECT then INSERT. Concurrent identical calls can race and one receives a unique-constraint error rather than the prior result. |
| F-04 | MEDIUM | Resolution lifecycle is not a defined state machine | `resolve_network_addition_request` validates only the destination status, not the source/destination pair, and retains terminal metadata when moving to `under_review`. Terminal rewrites are permitted and reopening fails only via a table check. |
| F-05 | MEDIUM | Dart and database SSID normalization contracts differ | Dart trims/lowercases/replaces whitespace; PostgreSQL additionally applies NFC. Canonically equivalent Unicode scan/catalog values may not match. |
| F-06 | LOW | Production integration and adverse scan paths lack Dart tests | Current tests use demo/fake repositories and never validate RPC parameter types, Supabase parsing, Android plugin mappings, provider production selection, or scan error UI. This allowed F-01 and F-02 to pass all 23 tests. |
| F-07 | LOW | Request cancellation failures are silently swallowed | `my_requests_screen.dart:63-68` catches and discards every cancellation error, leaving the user without feedback or a coherent error state. |

## Counts and recommendation

- BLOCKER: 0
- HIGH: 2
- MEDIUM: 3
- LOW: 2

Final recommendation: **HOLD**.

The local database authorization foundation and privacy posture are materially sound, but the production request path is not functional because of the invalid UUID contract and lack of a reachable authentication flow. These HIGH findings must be corrected and independently retested before acceptance.
