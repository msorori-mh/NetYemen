# Legacy public legal Edge Function

This function remains as a compatibility endpoint for the already deployed
pilot, but it is not an approved Google Play page on the shared `supabase.co`
domain. Supabase intentionally rewrites renderable HTML returned from shared
Edge Function domains to `text/plain`.

- `/functions/v1/public-legal/privacy`
- `/functions/v1/public-legal/delete-account`

The deletion form never logs or stores a password. It loads **no third-party
script**: the inline, nonce-protected script calls Supabase Auth
(`/auth/v1/token?grant_type=password`), then
`/rest/v1/rpc/request_my_account_deletion`, then `/auth/v1/logout` with plain
`fetch`, exactly like `legal/delete-account.template.js`. The
Content-Security-Policy allows scripts only by nonce and connections only to
this project's own origin, and reports a generic failure message. The database RPC closes access, disables push tokens,
and creates an immutable audit event.

The approved release pages are generated into the administration web artifact:

```text
<ADMIN_PUBLIC_ORIGIN>/legal/privacy.html
<ADMIN_PUBLIC_ORIGIN>/legal/delete-account.html
```

Generate them through `scripts/configure_waselnet_public_legal_pages.mjs` only
inside the protected admin release workflow. The legacy function must not be
used as a substitute unless a Supabase custom domain is enabled and the exact
response is reverified as `text/html`.

`SUPABASE_URL` and `SUPABASE_ANON_KEY` are injected by Supabase. Never place a
service-role key or another server secret in the HTML.
