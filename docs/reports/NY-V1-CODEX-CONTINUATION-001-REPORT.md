# WASEL NET — Continuation Execution Report

**Work item:** NY-V1-CODEX-CONTINUATION-001  
**Repository:** msorori-mh/NetYemen  
**Pull request:** #15  
**Execution branch:** `kimi/NY-V1-EXTERNAL-PILOT-BINDING-001`  
**Evidence commit:** `c6098f33b30072786077367e702f4ca659a2a90b`  
**Date:** 2026-08-19

## Executive result

The repository baseline was reconciled against `main`, the pull request was retargeted to the authoritative base, and the source/CI closure gates are now **PASS**.

The only remaining release hold is the physical external-pilot evidence that requires an authorized Android device and an actual FCM delivery.

## Implemented in this continuation

1. Corrected the FCM token lifecycle:
   - do not register a token before an authenticated user exists;
   - initialize registration after sign-in;
   - prevent duplicate token-refresh subscriptions;
   - deactivate/unlink the token before sign-out;
   - cover the sign-in/sign-out lifecycle with an automated test.
2. Prevented a potential `setState` call after OTP navigation/disposal.
3. Hardened Flutter CI:
   - concurrency cancellation;
   - bounded timeout;
   - formatting, analysis, tests, debug APK build, and artifact upload.
4. Hardened Supabase CI:
   - enabled project delivery branches;
   - bounded timeout;
   - expanded SQL verification from 001–005 to 001–015;
   - retained core, commerce, pilot, secret, card, financial, and FCM scans.
5. Applied canonical Dart formatting and fixed the resulting strict analyzer finding.
6. Replaced brittle widget runtime-type assertions with semantic visible-label assertions.

## Evidence

| Gate | Evidence | Result |
|---|---|---|
| Dart formatting | Flutter CI run #34, step “Verify Formatting” | PASS |
| Static analysis | Flutter CI run #34, step “Analyze Static Code” | PASS |
| Flutter tests | Flutter CI run #34, step “Run Tests” | PASS |
| Android debug APK | Flutter CI run #34, build + artifact upload | PASS |
| Supabase migrations | Supabase Core CI run #38 | PASS |
| SQL tests 001–015 | Supabase Core CI run #38 | PASS |
| Repository verifiers/scans | Supabase Core CI run #38 | PASS |

## Gate decision

### Source and CI closure: PASS

No known source-level or automated-verification blocker remains at the evidence commit.

### Physical external pilot: HOLD

Release evidence is not complete until all of the following are captured on a real authorized Android device:

1. `adb devices` shows the target device as `device`, not `unauthorized`.
2. The debug APK is installed and the user completes OTP authentication.
3. The device token is linked to the authenticated user.
4. A real FCM notification is delivered, opened, and routed correctly.
5. Sign-out deactivates/unlinks the token.
6. Logs/screenshots are attached to the physical pilot report without exposing credentials or tokens.

## Required operator action

On the pilot workstation:

```powershell
adb kill-server
adb start-server
adb devices
```

Unlock the Samsung device, accept **Allow USB debugging**, and select **Always allow from this computer**. Do not paste Firebase service-account contents, OTP values, access tokens, or device tokens into GitHub or chat.

## Next execution stages

1. Close physical Android/FCM pilot evidence.
2. Validate administrator acceptance flows against pilot data.
3. Run release-candidate build and production fail-closed checks.
4. Promote the pull request from draft only after the physical gate is PASS.
