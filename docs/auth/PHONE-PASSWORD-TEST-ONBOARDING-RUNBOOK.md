# WASEL NET phone/password test onboarding

Status: **PRODUCTION TEST ONBOARDING ENABLED / HOSTED ADMIN REVIEW HOLD**

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
5. Flutter signs in with phone and password, but guarded operations remain
   blocked while the profile is pending.
6. A platform administrator reviews the dedicated tester application. An
   approval activates the profile as `test_admin_approved`; a rejection
   suspends it. This state is explicitly not phone verification.

Selecting `network_owner` creates `owner_review_status=pending`. It never adds
the `network_owner` role during signup. Every new identity receives only the
baseline `customer` role. The role is granted atomically only when a platform
administrator approves that dedicated owner application. The owner must then
create a network draft through the normal flow; approval does not create a
network or membership automatically.

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

1. Apply `20260821090000_netyemen_test_phone_password_onboarding.sql` and then
   `20260821120000_netyemen_admin_test_onboarding_review.sql`.
2. Run SQL contracts `016_test_phone_password_onboarding.sql` and
   `017_admin_test_onboarding_review.sql`, then database lint.
3. Deploy `test-onboarding` with JWT verification disabled only for this
   invite-protected endpoint.
4. Set the server secrets and a short expiry. Prefer a phone allowlist.
5. Smoke-test one customer and one owner-request identity; verify both remain
   pending before review and neither receives an owner role during signup.
6. Review the customer through the dedicated admin action and verify its
   profile becomes active with `test_admin_approved`.
7. Review the owner request and verify the role is granted only with the
   atomic approval audit event; then create a normal network draft.
8. Reject a disposable test identity and verify its profile is suspended and
   a second decision is blocked.

Do not enable the Flutter signup entry point against production until steps
1–8 pass.

## Exact hosted admin-review closure

The production review gate is deliberately separate from onboarding creation.
Run the read-only verifier first:

~~~powershell
Get-Content -Raw .\supabase\verification\017_hosted_admin_review_production_preflight.sql | Set-Clipboard
~~~

Paste only the SQL contents into the WASEL NET SQL Editor. It maps each
normalized stored phone to an immutable application reference without exposing
the private coordinates. The administration card displays the same reference;
do not make a decision unless the references match exactly.

| Normalized phone | Expected account type | Planned decision |
|---|---|---|
| `967770000021` | customer | approve |
| `967770000022` | network_owner | approve |
| `967770000023` | customer | reject |

These are production writes against exact disposable `TEST_ONLY` identities.
They require a separate explicit authorization after preflight PASS. Use the
local administration console as the signed-in `platform_admin`; do not execute
the review RPC from the SQL Editor and do not use a service-role credential.

After the three authorized decisions, run:

~~~powershell
Get-Content -Raw .\supabase\verification\017_hosted_admin_review_production_postverify.sql | Set-Clipboard
~~~

The post-verify must report three terminal identities, exactly four roles
(three customer roles plus one owner role), exactly three successful admin
review audit events, forced RLS, and no automatically created network or
membership. Any mismatch is HOLD.

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
