# NY-V1-NETWORK-DISCOVERY-001 — Cursor Final Security Review

## MISSION

`NY-V1-NETWORK-DISCOVERY-001-CURSOR-FINAL-SECURITY-REVIEW-01`

Independent security, authorization, privacy, Supabase RLS/RPC, PostgreSQL ACL, and abuse-case review of the NetYemen V1 Network Discovery vertical slice after Kimi remediation of the prior Codex HOLD.

Review-only. No runtime fixes. No redesign. No merge.

## REVIEW_TARGET_SHA

`b1da5c0bc0b55ac782a5a0544836e0d777e267d0`

## REVIEW_BRANCH

`cursor/NY-V1-NETWORK-DISCOVERY-001-SECURITY-REVIEW`

## WORKTREE_STATUS

- `git branch --show-current` = `cursor/NY-V1-NETWORK-DISCOVERY-001-SECURITY-REVIEW`
- `git rev-parse HEAD` = `b1da5c0bc0b55ac782a5a0544836e0d777e267d0` (exact match)
- `git status --short` = clean before review and before report commit
- Foundation range reviewed: `1fe96d6867210da3e603f8ab08c01ddc36401158..b1da5c0bc0b55ac782a5a0544836e0d777e267d0`
- Remediation range reviewed: `9ff8e3a4d02b5c0bc0bb47bb1268154438e74854..b1da5c0bc0b55ac782a5a0544836e0d777e267d0`
- Accidental `android/gradle.properties` mutation from `flutter build apk --debug` was reverted; not included in this report commit

## REVIEWED_OBJECTS

### Database

- `supabase/migrations/20260727090000_netyemen_core_identity_and_networks.sql`
- `supabase/migrations/20260727091000_netyemen_core_rls_and_audit.sql`
- `supabase/migrations/20260727130000_netyemen_network_addition_requests.sql`
- Table `public.network_addition_requests`
- RPCs: `submit_network_addition_request`, `cancel_network_addition_request`, `resolve_network_addition_request`
- Helpers relied upon: `has_platform_role`, `normalize_ssid`, `set_updated_at`, `handle_new_user`
- RLS policies on `network_addition_requests` (customer / support / admin / auditor SELECT)
- Unique index `(requester_user_id, idempotency_key)`
- Grants/revokes on table and RPC EXECUTE

### Flutter / Android

- Auth: `lib/screens/auth/login_screen.dart`, `lib/screens/auth/otp_screen.dart`, `lib/features/auth/presentation/auth_required_gate.dart`, `lib/providers/app_providers.dart`, `lib/features/profile/presentation/profile_screen.dart`
- Requests: `lib/features/network_requests/**`
- Discovery / Wi-Fi: `lib/features/network_discovery/**`, `android/app/src/main/AndroidManifest.xml`
- Idempotency: `lib/core/utils/uuid_generator.dart`
- SSID: `lib/features/network_discovery/data/scan_matcher.dart` vs `public.normalize_ssid`
- Shell wiring: `lib/app/app_shell.dart`, `lib/main.dart`

### Tests / verifiers

- `supabase/tests/001`–`005`
- `scripts/verify_netyemen_core_foundation.ps1`
- Local adversarial SQL transaction (rolled back)
- Flutter analyze / test / debug APK

---

## AUTHORIZATION_MATRIX

| Actor | Public approved networks | Own addition requests | Other users' requests | Submit RPC | Cancel own submitted | Resolve RPC | Direct INSERT/UPDATE request rows | Privilege fields (`status`, `matched_network_id`, `duplicate_of`, `resolved_by`, `resolution_note`) |
|---|---|---|---|---|---|---|---|---|
| `anon` | SELECT (RLS: active+verified) | No table privilege | No | Denied (`auth.uid()` null) | N/A | Denied | Denied | Denied |
| `authenticated` customer | SELECT | SELECT own only | Denied by RLS | Allowed if active profile | Allowed if owner + `submitted` | Denied (`FORBIDDEN_ROLE`) | No INSERT/UPDATE grants | Denied |
| suspended profile | Public catalog only | N/A | Denied | Denied (`INACTIVE_PROFILE`) | Denied | Denied | Denied | Denied |
| `support_agent` | Yes | SELECT all (triage) | SELECT | Yes (as self) | Own only | Allowed (role-gated) | No direct DML | Via resolve RPC only |
| `platform_admin` | Yes | SELECT all | SELECT | Yes | Own only | Allowed | No direct DML | Via resolve RPC only |
| `system_auditor` | Yes | SELECT all | SELECT | Not privileged for resolve | Own only if also customer requester | Denied | No direct DML | Read-only |
| `service_role` | Bypass (platform) | Bypass | Bypass | N/A for customer path | N/A | N/A | Trusted backend only | Trusted backend only |

Requester identity is always `auth.uid()` inside SECURITY DEFINER RPCs. There is no client-supplied `requester_user_id` parameter.

---

## SECURITY_DEFINER_REVIEW

| Function | search_path | auth.uid() authoritative | Dynamic SQL | EXECUTE grants | Privilege boundary |
|---|---|---|---|---|---|
| `submit_network_addition_request` | `public, pg_temp` | Yes; null → UNAUTHENTICATED | None | REVOKE PUBLIC; GRANT authenticated | Inserts only as authenticated caller; normalizes SSID server-side; active profile required |
| `cancel_network_addition_request` | `public, pg_temp` | Yes | None | REVOKE PUBLIC; GRANT authenticated | Ownership + `submitted` only |
| `resolve_network_addition_request` | `public, pg_temp` | Yes; `resolved_by` set from `auth.uid()` | None | REVOKE PUBLIC; GRANT authenticated | `platform_admin` OR `support_agent` only; state machine enforced |
| `has_platform_role` (foundation) | `public, pg_temp` | Yes | None | anon+authenticated (RLS helper) | Boolean helper; no writes |
| `normalize_ssid` (foundation) | `public, pg_temp` | N/A | None | anon+authenticated | Immutable transform only |
| `set_updated_at` / `handle_new_user` (foundation) | `public, pg_temp` | Trigger context | None | PUBLIC revoked | Unchanged foundation |

No caller-controlled schema resolution observed. No unsafe `EXECUTE format(...)` in the new RPCs.

---

## RLS_ASSESSMENT

- `ENABLE` + `FORCE ROW LEVEL SECURITY` on `network_addition_requests`
- SELECT policies only: requester self, support_agent, platform_admin, system_auditor
- No INSERT/UPDATE/DELETE policies — intentional; mutations only via SECURITY DEFINER RPCs
- Combined with ACL (SELECT-only for authenticated; no anon grants), direct DML is denied
- Core foundation tables remain FORCE RLS; 001–004 suites still PASS (no regression)

---

## RPC_ASSESSMENT

### `submit_network_addition_request`

- Auth + active profile checks
- Server-derived `observed_ssid_normalized` via `public.normalize_ssid` (client cannot override)
- Atomic idempotency: `INSERT ... ON CONFLICT (requester_user_id, idempotency_key) DO NOTHING` then re-select
- Best-effort `duplicate_of` link for other open requests with same normalized SSID
- Returns only `{id, status}`

### `cancel_network_addition_request`

- Owner-only; status must be `submitted`
- Sets `cancelled`; does not touch privileged resolution columns

### `resolve_network_addition_request`

- Role-gated to admin/support
- Allowed transitions:
  - `submitted` → `under_review` | `matched_existing` | `approved` | `rejected`
  - `under_review` → `under_review` | `matched_existing` | `approved` | `rejected`
  - `matched_existing` → `matched_existing` | `approved` | `rejected`
  - same-status no-op otherwise
- Terminal rewrite blocked (`approved`→`rejected`, reopen to `under_review`, resolve of `cancelled`) — verified adversarially and in suite 005 NEG-12
- `resolved_by` / `resolved_at` set only for terminal-ish resolution statuses from server identity

---

## ACL_GRANTS_REVOKES

Observed for `network_addition_requests`:

- `REVOKE ALL ... FROM PUBLIC`
- `GRANT SELECT ... TO authenticated`
- No INSERT/UPDATE/DELETE to `authenticated`
- No grants to `anon` (adversarial ADV-ACL PASS)
- RPC EXECUTE: PUBLIC revoked; authenticated granted for submit/cancel/resolve
- Mutations rely on definer privileges + internal authz checks, not broad table DML grants

---

## IDEMPOTENCY_AND_CONCURRENCY

| Check | Result |
|---|---|
| Client key is UUID v4 (`UuidGenerator`) | PASS — RFC version/variant bits; tests cover format/uniqueness |
| New logical submit generates new key | PASS — key cleared only after success; next submit minting new UUID |
| Retry preserves same key on failure | PASS — pending key retained in `pendingIdempotencyKeyProvider` on error |
| Scoped to requester | PASS — unique `(requester_user_id, idempotency_key)`; cross-user same key creates distinct rows |
| Concurrent same-key races | PASS — `ON CONFLICT DO NOTHING` + re-select; no duplicate business row |
| Replay with different payload | Returns original row (standard idempotency; does not mutate SSID) — NOTE only |
| Open-SSID duplicate linking under true parallel insert | Best-effort only; no partial unique index on open normalized SSID — LOW |

---

## AUTHENTICATION_BOUNDARY

| Requirement | Result |
|---|---|
| Unauthenticated browse of public approved networks | PASS (catalog RLS + anon column grants on networks/aliases) |
| Private request screens gated | PASS (`AuthRequiredGate` on My Requests / Add Request) |
| Submit requires auth | PASS (client gate + server `auth.uid()` / active profile) |
| Login is real Supabase Auth OTP | PASS (`signInWithOtp` / `verifyOTP` type SMS) |
| No fake release identity | PASS (`AppBootstrapState.unconfiguredRelease` blocks runnable unconfigured release) |
| Sign-out reachable | PASS (ProfileScreen → `Supabase.auth.signOut`) |
| Session identity drives private data | PASS (`currentUserProvider` from auth state; my-requests empty when signed out) |
| OD-AUTH-01 production SMS gateway | OPEN governance — code does not hardcode a production SMS provider or claim OTP readiness |

Legacy note: `OTPScreen` still calls `SupabaseService.createOrUpdateUser` against a pre-V1 `users` table that is not part of the core migrations. V1 profile provisioning is via `handle_new_user`. This is a leftover client path, not a server privilege bypass (LOW).

Demo/debug unconfigured mode intentionally bypasses the auth gate for local UI testing only; release unconfigured remains blocked.

---

## SSID_NORMALIZATION

Contract (Dart `ScanMatcher.normalizeForMatching` and PostgreSQL `public.normalize_ssid`):

1. trim  
2. Unicode NFC  
3. lowercase  
4. whitespace → `-`  
5. collapse hyphens  
6. trim surrounding hyphens  

Local PostgreSQL probes:

- Arabic + Latin SSIDs normalize non-empty and preserve Arabic letters
- Whitespace variants collapse equivalently
- Case folding aligns for Latin
- Distinct Arabic forms with/without diacritics are not incorrectly forced equal (`يمَن` vs `يمن` → distinct)

Database remains authoritative on submit (RPC ignores any client-normalized value; none is accepted as a parameter). Client normalization is for local matching UX only.

---

## WIFI_PRIVACY

| Control | Evidence | Result |
|---|---|---|
| Scan only after explicit user action | Home `_ScanSection` button → `performScan()` | PASS |
| No background scanning | No periodic/worker scan paths in feature code | PASS |
| Memory-only results | `scanResultProvider` in-memory Riverpod state; `clearScan` available | PASS |
| Only SSID used | `AndroidWifiScanService` extracts `accessPoint.ssid` only | PASS |
| No BSSID/MAC/RSSI/frequency/password/coords transmitted | Repository RPC params are SSID + optional text fields only | PASS |
| Android permissions | `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`; `ACCESS_FINE_LOCATION` maxSdk 32; `NEARBY_WIFI_DEVICES` + `neverForLocation` | PASS with NOTE (OS Wi-Fi scan prerequisite on older APIs; location not collected/sent) |

---

## ADVERSARIAL_TESTS

Local-only interactive SQL (transaction rolled back). All PASS:

| # | Case | Result |
|---|---|---|
| 1 | anon submit | Denied |
| 2 | anon private read | Denied (`insufficient_privilege`) |
| 3 | cross-user read | Denied (0 rows) |
| 4 | cross-user cancel | Denied |
| 5 | requester spoofing | Impossible; ownership = `auth.uid()` |
| 6 | direct privileged status mutation | Denied |
| 7 | forged `duplicate_of` | Denied |
| 8 | forged `matched_network_id` | Denied |
| 9 | forged `resolved_by` | Denied |
| 10 | unauthorized `resolution_note` | Denied |
| 11 | customer resolve RPC | Denied |
| 12 | idempotency replay / cross-user key | Scoped correctly |
| 13 | sequential duplicate linking | `duplicate_of` set |
| 14 | invalid transitions | Denied |
| 15 | core foundation role escalation | Denied |
| ACL | no INSERT/UPDATE/anon grants | Confirmed |

---

## SQL_TEST_RESULTS

Executed via `docker exec ... psql -v ON_ERROR_STOP=1` against local `supabase_db_netyemen-local` after `npx supabase db reset --no-seed`.

| Suite | Result |
|---|---|
| 001_core_schema_contract.sql | PASS |
| 002_core_authorization_positive.sql | PASS (`ROLE_CONTEXT_*` notices; 14 positive) |
| 003_core_authorization_negative.sql | PASS (30 negative) |
| 004_core_invariants.sql | PASS (12 invariants) |
| 005_network_discovery_and_requests.sql | PASS (POS/NEG including terminal transition NEG-12) |

---

## FLUTTER_VALIDATION

| Check | Result |
|---|---|
| JDK | OpenJDK 17.0.20 (Flutter-configured Microsoft JDK 17) |
| `flutter pub get` | PASS |
| `flutter analyze` | PASS — No issues found |
| `flutter test` | PASS — 39 tests |
| `flutter build apk --debug` | PASS — `build\app\outputs\flutter-apk\app-debug.apk` |

---

## CORE_VERIFIER

`powershell -ExecutionPolicy Bypass -File scripts/verify_netyemen_core_foundation.ps1`

**STATIC VERIFICATION RESULT: PASS (All Rules Satisfied)**

Note: static verifier still scopes to NY-GOV-BE-001 core artifacts; network-addition coverage was reviewed directly via migration + suite 005 + adversarial probes.

---

## SECRET_SCAN

- Diff scan over foundation→target for `service_role` secrets, JWT-looking literals, OpenRouter/Kimi keys, private keys: no committed production secrets (only documentation mentions / local demo JWT material from `supabase status`, not in git)
- `git diff --check` on review range: clean
- No `supabase/.temp`, `.branches`, or build artifacts staged
- Placeholders such as `YOUR_ALAWAEL_API_KEY` remain placeholders, not live credentials

**SECRET_SCAN_RESULT: PASS**

---

## REGRESSION_ASSESSMENT

- Core authorization suites 001–004 PASS after network-discovery migration
- Adversarial ADV-15 confirms customers still cannot self-assign `platform_admin`
- Profile cross-read still denied (suite 005 NEG-10)
- No weakening of FORCE RLS, audit append-only, or network admin-field protections observed in the remediation diff
- Prior Codex HOLD items (UUID idempotency, atomic submit, state machine, reachable auth, SSID alignment) independently re-verified

---

## FINDINGS_TABLE

| ID | Severity | Component | Evidence | Impact | Recommendation |
|---|---|---|---|---|---|
| CUR-ND-01 | LOW | Auth client leftover | `OTPScreen` → `createOrUpdateUser` upserts legacy `users` (not in V1 migrations); V1 profiles come from `handle_new_user` | Post-OTP UX may error despite valid Supabase session; not a privilege escalation | Align OTP success path to V1 `profiles` (or remove legacy upsert) in a follow-up hygiene task |
| CUR-ND-02 | LOW | Duplicate linking | Open-request `duplicate_of` is best-effort SELECT-then-INSERT without a partial unique index on open normalized SSID | Rare concurrent inserts of the same SSID may both omit `duplicate_of`; no authz bypass | Optional later: advisory lock or partial unique index for open statuses |
| CUR-ND-03 | NOTE | Android permissions | `ACCESS_FINE_LOCATION` maxSdkVersion 32 required by OS for Wi-Fi scan APIs | Not transmitted; `NEARBY_WIFI_DEVICES` uses `neverForLocation` | Keep documenting OS prerequisite; do not expand to coarse/background location |
| CUR-ND-04 | NOTE | Idempotency semantics | Replay with different SSID/payload returns original row | Expected; no second business action | Keep client key bound to a single logical draft |
| CUR-ND-05 | NOTE | Demo auth gate | `AuthRequiredGate` bypass when `isDemoMode` / unconfigured debug | Local UI only; release unconfigured blocked | Keep demo bypass out of production builds (already gated) |

No BLOCKER or HIGH findings remain after remediation verification.

---

## COUNTS

| Severity | Count |
|---|---|
| BLOCKER | 0 |
| HIGH | 0 |
| MEDIUM | 0 |
| LOW | 2 |
| NOTE | 3 |

---

## REMAINING_GOVERNANCE_ITEMS

- **OD-AUTH-01** — Production SMS OTP gateway provider selection remains OPEN. Source does not silently choose/hardcode a production gateway, does not alter remote Supabase configuration, and does not claim production OTP readiness. This remains a production-launch governance blocker, not a source-only HOLD for this slice.

---

## FINAL_DECISION

**PASS**

Reason: Independent verification of target SHA `b1da5c0bc0b55ac782a5a0544836e0d777e267d0` found **0 BLOCKER** and **0 HIGH**. Prior Codex HOLD remediation items are present and effective (UUID idempotency, atomic submit, coherent resolution state machine, reachable Supabase auth, Dart/PostgreSQL SSID alignment). Local SQL suites 001–005 PASS, core foundation verifier PASS, Flutter analyze/tests/APK PASS, and adversarial authorization/idempotency probes PASS. Remaining items are LOW/NOTE hygiene or open governance (OD-AUTH-01), which do not mandate HOLD under the stated decision rule.
