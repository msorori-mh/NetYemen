# Public legal pages

This public Edge Function serves the Google Play privacy policy and an external
self-service account-deletion form:

- `/functions/v1/public-legal/privacy`
- `/functions/v1/public-legal/delete-account`

The deletion form never logs or stores a password. It signs in directly through
Supabase Auth, invokes `request_my_account_deletion`, signs out, and reports a
generic failure message. The database RPC closes access, disables push tokens,
and creates an immutable audit event.

Deploy with JWT verification disabled because the two HTML pages are public:

```bash
supabase functions deploy public-legal --no-verify-jwt
```

`SUPABASE_URL` and `SUPABASE_ANON_KEY` are injected by Supabase. Never place a
service-role key or another server secret in the HTML.
