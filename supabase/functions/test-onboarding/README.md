# Controlled test onboarding

This unauthenticated Edge Function is fail-closed and intended only for the
temporary, named-tester phone/password pilot. It is **pilot-only**: it is not an
SMS replacement for public production signup and must be disabled
(`TEST_ONBOARDING_ENABLED` unset) before any public launch.

Required server secrets (the function refuses to run if any is missing or
invalid):

- `TEST_ONBOARDING_ENABLED=true`
- `TEST_ONBOARDING_EXPIRES_AT=<ISO-8601 UTC timestamp>` -- must be in the
  future and **at most 14 days ahead**. A later value is treated as a
  misconfiguration (`503 SERVICE_UNAVAILABLE`); extend the pilot by setting a
  new value, not a distant one.
- `TEST_ONBOARDING_INVITE_SHA256=<lowercase SHA-256 of the tester invite>`
- `TEST_ONBOARDING_ALLOWED_PHONES=<comma-separated +9677XXXXXXXX numbers>` --
  **mandatory and non-empty**. Every entry must be a valid `+9677XXXXXXXX`
  number. With an empty or malformed list the function answers
  `503 SERVICE_UNAVAILABLE`; it never falls back to "any phone".
- `TEST_ONBOARDING_INVITE_LABEL=<non-secret audit label>` (optional; defaults
  to `controlled-pilot`)

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are supplied by Supabase. Never
place the service-role key or the invite digest in the Flutter application.

## Behaviour

The function creates a phone-confirmed Auth identity so password login works
without telecom delivery, but the database atomically marks it
`pending_verification`. A requested network-owner account remains a pending
application; this function never grants `network_owner`.

Responses are deliberately uninformative:

| Situation | Response |
|---|---|
| Account created | `201 {"accepted": true}` |
| Phone already registered (nothing is created or changed) | `201 {"accepted": true}` -- identical; the caller can only get in with the real password |
| Wrong invite code | `403 INVALID_INVITE` |
| Phone not on the allowlist | `403 INVALID_INVITE` -- identical |
| Gate disabled / expired | `503 TEST_ONBOARDING_DISABLED` / `403 TEST_ONBOARDING_EXPIRED` |
| Missing/invalid secrets, empty allowlist, expiry > 14 days ahead | `503 SERVICE_UNAVAILABLE` |
| Invalid payload | `400 INVALID_REQUEST` |
| Auth or registration failure | `400` / `500 ACCOUNT_CREATION_FAILED` |

There is no `ACCOUNT_EXISTS` or `TESTER_NOT_ALLOWED` response any more; the
distinction is written to the function log only. The invite digest is compared
in constant time.

## Limits that are NOT implemented here

Edge Function isolates are short-lived and not shared, so in-memory per-IP or
per-phone rate limiting would not work and is not attempted. Abuse is bounded
by the mandatory phone allowlist, the invite code and the 14-day window.
Supabase Auth rate limits still apply to the subsequent password sign-in.

Deployment, secrets, production migration application, and enabling the gate
must each pass a separate release authorization.
