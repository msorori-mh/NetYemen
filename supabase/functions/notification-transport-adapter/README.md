# NetYemen V1 — Notification Transport Adapter Edge Function

This Edge Function binds two external-pilot capabilities:

1. **FCM push transport adapter** (`action='dispatch_push'`) — OD-NOTIF-01
2. **Internal card secret AES-256-GCM decryption** (`action='decrypt_card_secret'`) — OD-CARD-01
3. **Authenticated customer card reveal** (`action='reveal_card_secret'`) — validates purchase ownership before server-side decryption

## Endpoints

| Method | Path | Body `action` |
|---|---|---|
| `POST` | `/functions/v1/notification-transport-adapter` | `dispatch_push` |
| `POST` | `/functions/v1/notification-transport-adapter` | `decrypt_card_secret` |
| `POST` | `/functions/v1/notification-transport-adapter` | `reveal_card_secret` |

## Required environment variables

### Production / physical pilot

These variables must be configured as Edge Function secrets (never committed):

| Variable | Purpose |
|---|---|
| `SUPABASE_URL` | Auto-provided by Supabase. |
| `SUPABASE_SERVICE_ROLE_KEY` | Auto-provided by Supabase; used to update `public.notification_deliveries` and `public.device_push_tokens`. |
| `FCM_PROJECT_ID` | Firebase project ID for FCM HTTP v1. |
| `FCM_CLIENT_EMAIL` | FCM service account client email. |
| `FCM_PRIVATE_KEY` | FCM service account PEM private key (RS256). |
| `CARD_MASTER_KEY_v1` | Base64-encoded 32-byte AES-256 key for the legacy `decrypt_card_secret` action. Customer reveal does not use it: cards are decrypted in Postgres (pgcrypto) with the Vault secret `card_master_key`. |

### Local / source-only builds

- `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, and `FCM_PRIVATE_KEY` may be omitted.
  The function returns `accepted: false, status: 'credential_required'` and does
  **not** fake a successful dispatch.
- `CARD_MASTER_KEY_v1` may be omitted only by local crypto tests. The
  deterministic TEST_ONLY key (derived from constants in this repository, so it
  is public) is used only when **all** of these hold, otherwise the function
  fails closed with `CARD_KEY_NOT_CONFIGURED`:
  1. `CARD_CRYPTO_ALLOW_TEST_KEY=true`;
  2. `CARD_CRYPTO_ENVIRONMENT` is exactly `local` or `test`;
  3. `SUPABASE_URL` is not a hosted project URL (`*.supabase.co`,
     `*.supabase.in`).

  **Never set either flag on a hosted project.** Even if both are set there,
  condition 3 refuses the key.

### Optional

| Variable | Purpose |
|---|---|
| `INTERNAL_FUNCTION_SECRET` | Dedicated bearer secret accepted for `dispatch_push` / `decrypt_card_secret` instead of the service-role key. Compared in constant time. |
| `ALLOWED_ORIGINS` | Comma-separated browser origins (for example `https://admin.example.com`). Unset: `Access-Control-Allow-Origin: *` (legacy behaviour). Set: only listed origins are echoed and any other `Origin` receives `403 ORIGIN_NOT_ALLOWED`. Requests without an `Origin` header (mobile app, server-to-server) are unaffected. |

## Response and failure semantics

- Every response carries `Cache-Control: no-store`; the reveal/decrypt
  responses contain a card PIN.
- `dispatch_push` outcomes:

| FCM result | `status` | HTTP | Device token |
|---|---|---|---|
| success | `sent` | 200 | kept |
| `UNREGISTERED` / HTTP 404, or `INVALID_ARGUMENT` about the registration token | `permanent_failure` | 200 | **deactivated** |
| other `INVALID_ARGUMENT` / other 4xx (message rejected) | `permanent_failure`, `token_deactivated: false` | 200 | kept |
| HTTP 401 / 403 (credentials, project or sender misconfigured) | `configuration_error`, `retryable: false` | 503 | kept -- the caller must stop the batch |
| HTTP 429 / 5xx / network | `transient_failure`, `retryable: true` | 502 | kept |

  A credential or quota problem therefore can no longer deactivate every
  user's push token.

## Deploy / configure

```bash
# Deploy the function
supabase functions deploy notification-transport-adapter

# Set secrets (use real values, never commit them)
supabase secrets set FCM_PROJECT_ID=your-project-id
supabase secrets set FCM_CLIENT_EMAIL=your-service-account@your-project-id.iam.gserviceaccount.com
supabase secrets set FCM_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
supabase secrets set CARD_MASTER_KEY_v1=your-base64-encoded-32-byte-key
```

## Local testing

```bash
# Crypto roundtrip / tamper / wrong-key tests (no real credentials needed)
deno run --allow-env supabase/functions/notification-transport-adapter/test_crypto.ts
```

## Security notes

- FCM service-account private keys and card master keys are **server-side only**.
- No provider secrets are embedded in the Flutter app or repository.
- Card plaintext is never logged by this function.
- Customer reveal accepts only a `purchase_id`. The ownership-enforcing RPC
  `reveal_purchase_card_secret` decrypts in Postgres and returns `card_pin`,
  which this function passes to the app as `plaintext`.
