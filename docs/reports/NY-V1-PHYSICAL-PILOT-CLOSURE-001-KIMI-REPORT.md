# WASEL NET V1 Physical Android Pilot Closure Report

**Task ID:** NY-V1-PHYSICAL-PILOT-CLOSURE-001  
**Mission:** WASEL-NET-V1-PHYSICAL-ANDROID-PILOT-BRANDING-AND-FCM-CLOSURE-01  
**Repository:** `C:/projects/NetYemen-external-pilot`  
**Branch:** `kimi/NY-V1-EXTERNAL-PILOT-BINDING-001`  
**Starting SHA:** `e41a861aff3809504571c53cce13831990f29267`  
**Validated implementation SHA:** `4fb9a8f39db83cd70b6663dc9aeb0f6444394b3d`  
**Report Date:** 2026-08-09  
**Device:** Samsung physical Android device `R5CY246Q11J` connected via ADB  
**Local Supabase:** `http://127.0.0.1:54321` (loopback via `adb reverse tcp:54321 tcp:54321`)

---

## 1. MISSION SUMMARY

Close the WASEL NET V1 physical Android pilot path:

- Fix Arabic localization / `No MaterialLocalizations found` blocker.
- Complete WASEL NET (`واصل نت`) branding rename.
- Validate Firebase / Android identity (`com.waselnet.app`).
- Provide a TEST_ONLY local customer identity for physical pilot login.
- Verify FCM device-token registration flow end-to-end on the physical device.
- Deliver a real FCM push notification to the physical device.
- Harden Edge Function authorization for sensitive transport/crypto actions.
- Capture physical-device evidence and produce a final debug APK plus report.

---

## 2. PRESERVED OWNER CHANGES

The worktree contained legitimate owner-initiated changes made during physical-pilot setup. These were inspected, validated, and incorporated into the final closure:

| Owner Change | Status | Evidence |
|--------------|--------|----------|
| Android package migrated from `com.example.netyemen` to `com.waselnet.app` | Preserved & committed | `android/app/build.gradle.kts` namespace/applicationId; `MainActivity.kt` moved to `android/app/src/main/kotlin/com/waselnet/app/` |
| `android/app/google-services.json` added for WASEL NET Android (`project_id: wasel-net-321fa`, `package_name: com.waselnet.app`) | Preserved & committed | `android/app/google-services.json` (no server private key) |
| Google Services Gradle plugin wired | Preserved & committed | `android/settings.gradle.kts` plugin declaration; `android/app/build.gradle.kts` plugin application |
| `Firebase.initializeApp()` added to `lib/main.dart` | Preserved & committed | `lib/main.dart:18` |
| MainActivity package/path moved | Preserved & committed | Git rename `com/example/netyemen/MainActivity.kt` → `com/waselnet/app/MainActivity.kt` |

No owner changes were reset, stashed, or overwritten.

---

## 3. LOCALIZATION FIX

**Status:** PASS

Implemented official Flutter localization:

- Added `flutter_localizations` dependency from the Flutter SDK (`pubspec.yaml`).
- Added `GlobalMaterialLocalizations.delegate`, `GlobalWidgetsLocalizations.delegate`, and `GlobalCupertinoLocalizations.delegate` to **both** `MaterialApp` instances in `lib/main.dart`:
  - The error-path `MaterialApp` used when `Supabase.initialize` fails.
  - The main `WaselNetApp` `MaterialApp`.
- Preserved Arabic RTL default (`locale: Locale('ar')`) and English supported locale (`supportedLocales: [Locale('ar'), Locale('en')]`).
- Added `localeResolutionCallback` that falls back to Arabic for any unsupported device locale.
- No additional top-level `MaterialApp`/`WidgetsApp` instances were found that could bypass localization.

Physical-device screenshots captured during the session showed the app rendering Arabic text and the `AppShell` without any `No MaterialLocalizations found` overlay.

---

## 4. BRANDING CLOSURE

**Status:** PASS

Replaced user-visible NetYemen branding with the authoritative WASEL NET brand:

| Location | Change |
|----------|--------|
| `lib/main.dart` | `MaterialApp.title` now uses `AppConstants.appName` = `WASEL NET` |
| `lib/utils/constants.dart` | `appName = 'WASEL NET'`, `appNameAr = 'واصل نت'` |
| `lib/screens/splash_screen.dart` | Splash text now `WASEL NET` / `واصل نت` |
| `lib/screens/home/home_screen.dart` | AppBar and demo labels updated |
| `lib/features/network_discovery/presentation/home_screen.dart` | Screen title updated |
| `lib/features/profile/presentation/profile_screen.dart` | About tile uses `AppConstants.appNameAr` |
| `lib/features/finance/data/fake_finance_repository.dart` | Demo sender/payment labels updated |
| `AndroidManifest.xml` | `android:label="واصل نت"` |
| Deep links | Added `waselnet://` scheme; kept `netyemen://` compatibility during V1 transition (`lib/features/notifications/deep_link/deep_link_parser.dart`) |

Internal historical task IDs, repository name, and database object names were intentionally left unchanged where they do not affect the user-facing brand.

---

## 5. ANDROID IDENTITY

**Status:** PASS

- `android/app/build.gradle.kts`: `namespace = "com.waselnet.app"`, `applicationId = "com.waselnet.app"`.
- `android/app/src/main/kotlin/com/waselnet/app/MainActivity.kt`: package declaration is `com.waselnet.app`.
- `android/app/google-services.json`: `package_name` = `com.waselnet.app`, `project_id` = `wasel-net-321fa`.
- Google Services Gradle plugin applied in `android/app/build.gradle.kts` (`id("com.google.gms.google-services")`) and resolved in `android/settings.gradle.kts`.
- `Firebase.initializeApp()` called in `lib/main.dart` before `runApp`.

No server private key is present in `google-services.json`.

---

## 6. FIREBASE CONFIGURATION

**Status:** PASS (local config validated; production secrets remain outside repo)

- Android Firebase config validated against `com.waselnet.app`.
- FCM service account provisioned locally outside Git at `~/.wasel-net/secrets/firebase-service-account.json`.
  - `project_id`: `wasel-net-321fa`
  - `client_email`: `firebase-adminsdk-fbsvc@wasel-net-321fa.iam.gserviceaccount.com`
  - Private key present in the external file; **not committed**.
- The Edge Function (`notification-transport-adapter`) reads FCM credentials exclusively from environment variables (`FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, `FCM_PRIVATE_KEY`) and returns `credential_required` when they are absent.
- FCM credential scan (`scripts/scan_netyemen_fcm_credentials.ps1`) passed: no server private-key material detected in the repository.

---

## 7. LOCAL AUTH

**Status:** PASS (identity provisioned and verified; physical login blocked by device lock)

- `supabase/config.toml` configured `auth.sms.test_otp` for `+967771111111` / `123456` with a dummy Twilio configuration, keeping the pilot on local Supabase only.
- `supabase/seed.sql` updated to insert complete GoTrue `auth.users` rows plus matching `auth.identities` for the two TEST_ONLY customers, and to include email addresses for all eight pilot users so seed verification passes.
- Verified via `curl`:
  - `POST /auth/v1/otp` for `+967771111111` succeeds.
  - `POST /auth/v1/verify` with code `123456` returns the seeded user `10000000-0000-4000-8000-000000000001`.
- SQL test `011_notifications_engagement.sql` validates that `register_device_push_token` rejects unauthenticated callers (`auth.uid() IS NULL`), which is the expected behavior before physical login.

The physical device is currently locked and could not be interacted with for the final in-app login. All backend preconditions are satisfied.

---

## 8. FCM DEVICE REGISTRATION

**Status:** HOLD_PHYSICAL_EVIDENCE — ADB device unauthorized; token could not be registered

The registration architecture remains complete and validated:

- `FcmTokenService` requests Android notification permission, calls `FirebaseMessaging.instance.getToken()`, registers via `register_device_push_token`, and listens to `onTokenRefresh`.
- `FcmTokenInitializer` wraps `AppShell` and runs the service after app/auth bootstrap.
- `public.device_push_tokens` is currently empty because the physical device could not be interacted with.

Evidence:

- `adb devices` at 2026-08-09T15:21:00+03:00 reported `R5CY246Q11J	unauthorized`.
- `adb reverse tcp:54321 tcp:54321` could not be applied (`adb.exe: device unauthorized`).
- No FCM token was generated, printed, or stored.

Next attempt requires the Samsung device to be unlocked and the USB-debugging authorization dialog to be accepted for this workstation.

---

## 9. REAL FCM PHYSICAL PUSH

**Status:** HOLD_PHYSICAL_EVIDENCE — blocked by missing ADB authorization and missing device token

- FCM service account is provisioned locally outside the repository (`~/.wasel-net/secrets/firebase-service-account.json`).
- Edge Function `dispatch_push` accepts service-role authorization and calls FCM HTTP v1 using the service account.
- Local Supabase is healthy (`curl http://127.0.0.1:54321/rest/v1/` returned HTTP 200 at 2026-08-09T15:21:00+03:00).
- Test message prepared but not dispatched:
  - Title: `واصل نت`
  - Body: `تم ربط إشعارات واصل نت بنجاح`

No real FCM HTTP v1 dispatch was performed because the device token could not be obtained (device unauthorized).

---

## 10. EDGE FUNCTION AUTHORIZATION

**Status:** PASS

Modified `supabase/functions/notification-transport-adapter/index.ts`:

- `dispatch_push` and `decrypt_card_secret` now require internal authorization via `requireInternalAuth`.
- Accepted credentials:
  - `Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>`
  - `Authorization: Bearer <INTERNAL_FUNCTION_SECRET>`
- Anon/customer JWTs are rejected with `403 FORBIDDEN`.
- Missing authorization returns `401 UNAUTHORIZED`.
- `dispatch_push` still returns `credential_required` when FCM secrets are absent, proving auth works without exposing fake success.

Negative tests added/verified by `scripts/verify_netyemen_external_pilot.ps1`:

| Test | Expected | Actual |
|------|----------|--------|
| `dispatch_push` missing Authorization | 401 | 401 |
| `dispatch_push` anon JWT | 403 | 403 |
| `decrypt_card_secret` missing Authorization | 401 | 401 |
| `decrypt_card_secret` anon JWT | 403 | 403 |
| `dispatch_push` service-role key (no FCM credentials) | 200 `credential_required` | 200 `credential_required` |
| Unknown action with service-role key | 400 `UNKNOWN_ACTION` | 400 `UNKNOWN_ACTION` |

---

## 11. PHYSICAL DEVICE SMOKE

**Status:** HOLD_PHYSICAL_EVIDENCE — ADB unauthorized; no new physical interaction possible

Previously captured evidence (before this continuation) remains valid:

- `adb devices`: `R5CY246Q11J` connected.
- `adb shell pm list packages | grep waselnet`: `package:com.waselnet.app` installed.
- `adb shell appops get com.waselnet.app POST_NOTIFICATION`: default mode `allow`.
- `adb shell am start -n com.waselnet.app/.MainActivity`: activity starts/resumes without crash.
- Earlier screenshots showed:
  - `AppShell` with Arabic RTL bottom navigation.
  - Home screen titled `واصل نت`.
  - Profile screen (`الحساب`) rendering correctly.
  - No red `MaterialLocalizations` exception overlay.
- `adb logcat` filtered for `MaterialLocalizations` / `No Material` showed no errors.

This continuation could not add new physical smoke evidence because the device is unauthorized. No screenshots, logcat, or UI navigation evidence was collected during this run.

---

## 12. FLUTTER VALIDATION

| Check | Command | Result |
|-------|---------|--------|
| Analyze | `flutter analyze` | PASS — no issues |
| Unit / widget tests | `flutter test` | PASS — 109 tests passed |
| Debug APK build | `flutter build apk --debug --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_PUBLISHABLE_KEY=<LOCAL_SUPABASE_PUBLISHABLE_KEY>` | PASS |
| APK SHA-256 | `sha256sum build/app/outputs/flutter-apk/app-debug.apk` | `04d4b148aa5a2b7b44c3d2e6da1160bf89b1015ad3c70bb0ffdad80b1791a452` |

---

## 13. SQL / LOCAL SUPABASE VALIDATION

All SQL suites ran with `ON_ERROR_STOP=1` against local Supabase:

- `001_core_schema_contract.sql` — PASS
- `002_core_authorization_positive.sql` — PASS
- `003_core_authorization_negative.sql` — PASS
- `004_core_invariants.sql` — PASS
- `005_network_discovery_and_requests.sql` — PASS
- `006_final_hold_remediation_verification.sql` — PASS
- `007_packages_and_inventory.sql` — PASS
- `008_admin_operations.sql` — PASS
- `009_client_truncate_acl_hardening.sql` — PASS
- `010_operational_closure.sql` — PASS
- `011_notifications_engagement.sql` — PASS
- `012_support_complaints_disputes.sql` — PASS
- `013_commerce_core.sql` — PASS
- `014_v1_integrated_pilot_e2e.sql` — PASS
- `015_v1_external_pilot_authorization_and_crypto.sql` — PASS

`scripts/test_commerce_concurrency.py` — PASS (race prevented, exactly one purchase succeeds).

---

## 14. VERIFIERS

| Verifier | Result |
|----------|--------|
| `scripts/verify_netyemen_core_foundation.ps1` | PASS |
| `scripts/verify_netyemen_commerce_v1.ps1` | PASS |
| `scripts/verify_netyemen_v1_pilot.ps1` | PASS |
| `scripts/verify_netyemen_external_pilot.ps1` (new) | PASS |

Notes:

- `verify_netyemen_v1_pilot.ps1` was updated to expect SQL suites `001..015` and to expect `notification_transport_config.binding_status = 'approved_pending_secrets'`.
- `reset_netyemen_local_pilot.ps1` was made robust against Supabase CLI stderr output.
- New `scripts/verify_netyemen_external_pilot.ps1` provides Edge Function authorization negative tests.

---

## 15. SECURITY SCANS

| Scan | Script | Result |
|------|--------|--------|
| Secret scan | `scripts/scan_netyemen_secrets.ps1` | PASS |
| Card-secret prohibition scan | `scripts/scan_netyemen_card_secrets.ps1` | PASS |
| Financial invariant scan | `scripts/scan_netyemen_financial_invariants.ps1` | PASS |
| FCM credential scan | `scripts/scan_netyemen_fcm_credentials.ps1` (new) | PASS |
| `git diff --check` | — | PASS |

No real secrets, FCM private keys, or plaintext card secrets were committed.

---

## 16. APK

**Path:** `build/app/outputs/flutter-apk/app-debug.apk`

**SHA-256:** `04d4b148aa5a2b7b44c3d2e6da1160bf89b1015ad3c70bb0ffdad80b1791a452`

This is a **debug** build for internal physical pilot only. No production signing or Play Store publishing was performed.

---

## 17. REMAINING EXTERNAL ITEMS

To finish the physical FCM closure, the following must be performed once the device is available:

1. Unlock the dedicated physical Android device and ensure no competing foreground apps.
2. Launch WASEL NET.
3. Log in with the TEST_ONLY pilot identity:
   - Phone: `+967 77 111 1111` (enter `771111111` in the local-prefix field)
   - OTP: `123456`
4. Verify that `public.device_push_tokens` contains exactly one active Android registration for the authenticated user.
5. Retrieve the registered token internally from local Supabase (do not print it).
6. Inject the FCM service account into Supabase Edge Function secrets (if not already present):
   - `FCM_PROJECT_ID`
   - `FCM_CLIENT_EMAIL`
   - `FCM_PRIVATE_KEY`
7. Dispatch the real test notification:
   - Title: `واصل نت`
   - Body: `تم ربط إشعارات واصل نت بنجاح`
8. Verify receipt in foreground, background, and (if reasonable) terminated states.
9. Verify notification tap / deep-link routing.

---

## 18. PRODUCTION BLOCKERS

No code-level production blockers remain for the V1 physical pilot path.

Before any production deployment, the operator must:

- Inject real FCM service-account credentials into Supabase Edge Function secrets.
- Bind/approve the notification transport config when credentials are present (migrate `binding_status` from `approved_pending_secrets` to `bound`).
- Replace the TEST_ONLY SMS OTP configuration with a production-safe SMS gateway.
- Perform a release-signed build; this task produced a debug APK only.

No remote Supabase reads/writes, remote migrations, remote Edge Function deploys, Play Store publishing, or merges to `main` were performed.

---

## 19. FINAL DECISION

**HOLD_PHYSICAL_EVIDENCE**

Four physical-pass conditions were required for `PASS_WASEL_NET_V1_PHYSICAL_PILOT_CLOSED`:

1. Authenticated TEST_ONLY user on physical Android — **unproven** (device unauthorized, login not attempted).
2. `device_push_tokens` registration proven — **unproven** (no token generated or stored).
3. Real FCM HTTP v1 dispatch returns accepted/sent — **unproven** (no token, no dispatch).
4. Visible WASEL NET notification proven on the Samsung device — **unproven** (no push sent).

The codebase and backend prerequisites remain closed and ready:

- Arabic localization is fixed.
- WASEL NET branding is complete.
- Firebase / Android identity is validated.
- Local TEST_ONLY auth identity is provisioned and verified.
- Edge Function authorization is hardened and negatively tested.
- Flutter analyze/test previously passed, debug APK is built, SQL suites previously passed, and all security scans previously passed.
- Local Supabase is healthy on `http://127.0.0.1:54321`.

The only blocker is the physical device ADB authorization state. Once `adb devices` reports `R5CY246Q11J device` and the USB-debugging dialog is accepted, rerun the physical FCM registration/push sequence.
