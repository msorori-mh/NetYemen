# WASEL NET phone/password test onboarding

Status: **SOURCE ONLY / HOLD FOR PRODUCTION ENABLEMENT**

This stage provides a temporary, controlled path for named testers in مأرب
while SMS and WhatsApp delivery is unavailable. It does not replace the final
phone-verification design.

## User flow

1. A tester enters full name, Yemeni mobile number, password, account type,
   governorate/city, an approximate offline location, and the tester invite.
2. The `test-onboarding` Edge Function validates the expiring invite and the
   optional server-side phone allowlist.
3. The function creates a phone/password Auth user using the service role on
   the server. No service credential is present in Flutter.
4. The auth trigger creates the profile atomically as
   `pending_verification`, and the service-only RPC stores the private location
   and requested account type.
5. Flutter signs in with phone and password.

Selecting `network_owner` creates `owner_review_status=pending`. It never adds
the `network_owner` role. Every new identity receives only the baseline
`customer` role.

## Fail-closed controls

- `TEST_ONBOARDING_ENABLED` must equal `true`.
- `TEST_ONBOARDING_EXPIRES_AT` must be a future UTC timestamp.
- `TEST_ONBOARDING_INVITE_SHA256` must be a 64-character SHA-256 digest.
- The underlying invite must be randomly generated with at least 128 bits of
  entropy; do not use a memorable word or shared account password.
- `TEST_ONBOARDING_ALLOWED_PHONES` can restrict creation to named numbers.
- Request bodies are limited to 16 KiB.
- Password and invite values are never logged or stored in the application
  table.
- Exact location is readable only by its user, platform administrators, and
  system auditors.
- A failed database finalization removes the exact newly created auth/profile/
  wallet rows to avoid a partial account.
- Existing financial and privileged RPCs require an active profile, so the
  `pending_verification` test account remains blocked from those operations.

## Production enablement order

Each item requires a separate release authorization and evidence:

1. Apply `20260821090000_netyemen_test_phone_password_onboarding.sql`.
2. Run SQL contract `016_test_phone_password_onboarding.sql` and database lint.
3. Deploy `test-onboarding` with JWT verification disabled only for this
   invite-protected endpoint.
4. Set the server secrets and a short expiry. Prefer a phone allowlist.
5. Smoke-test one customer and one owner-request identity.
6. Verify both profiles remain pending, no owner role was granted, and the
   audit event exists.

Do not enable the Flutter signup entry point against production until steps
1–6 pass.

## Password recovery during the outage

The app does not pretend that SMS recovery works. Test-password resets are
administrator-assisted and must use the Supabase administrative user action;
passwords must never be sent through chat or stored in tickets. The normal
phone OTP recovery flow can be restored after telecom delivery is verified.

## Shutdown / rollback

1. Set `TEST_ONBOARDING_ENABLED=false` immediately; this is the primary kill
   switch.
2. Let the expiry remain in the past and remove the allowed-phone list and
   invite digest.
3. Keep existing test identities pending or suspend them through the audited
   administration path.
4. Do not delete audit evidence.
5. Remove the Flutter tester-signup entry in a later normal release after SMS
   or WhatsApp verification is restored.
