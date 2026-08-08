# NetYemen V1 — Notification Transport Adapter Edge Function

This Edge Function binds two external-pilot capabilities:

1. **FCM push transport adapter** (`action='dispatch_push'`) — OD-NOTIF-01
2. **Card secret AES-256-GCM decryption** (`action='decrypt_card_secret'`) — OD-CARD-01

## Endpoints

| Method | Path | Body `action` |
|---|---|---|
| `POST` | `/functions/v1/notification-transport-adapter` | `dispatch_push` |
| `POST` | `/functions/v1/notification-transport-adapter` | `decrypt_card_secret` |

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
| `CARD_MASTER_KEY_v1` | Base64-encoded 32-byte AES-256 key for card vault v1. |

### Local / source-only builds

- `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, and `FCM_PRIVATE_KEY` may be omitted.
  The function returns `accepted: false, status: 'credential_required'` and does
  **not** fake a successful dispatch.
- `CARD_MASTER_KEY_v1` may be omitted for local crypto tests. A deterministic
  `TEST_ONLY` key is derived from a fixed seed and a loud warning is logged.
  **Never use this fallback in production or the physical pilot.**

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
