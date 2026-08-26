# Controlled test onboarding

This unauthenticated Edge Function is fail-closed and intended only for the
temporary, named-tester phone/password pilot. It is not an SMS replacement for
public production signup.

Required server secrets:

- `TEST_ONBOARDING_ENABLED=true`
- `TEST_ONBOARDING_EXPIRES_AT=<ISO-8601 UTC timestamp>`
- `TEST_ONBOARDING_INVITE_SHA256=<lowercase SHA-256 of the tester invite>`
- `TEST_ONBOARDING_INVITE_LABEL=<non-secret audit label>`
- `TEST_ONBOARDING_ALLOWED_PHONES=<optional comma-separated +967 numbers>`

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are supplied by Supabase. Never
place the service-role key or the invite digest in the Flutter application.

The function creates a phone-confirmed Auth identity so password login works
without telecom delivery, but the database atomically marks it
`pending_verification`. A requested network-owner account remains a pending
application; this function never grants `network_owner`.

Deployment, secrets, production migration application, and enabling the gate
must each pass a separate release authorization.
