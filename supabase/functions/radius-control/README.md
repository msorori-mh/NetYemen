# WASEL One radius-control

Private machine-to-machine adapter between FreeRADIUS and the service-only
PostgreSQL authorization/accounting RPCs.

Required Edge Function secrets:

- `WASEL_RADIUS_INTERNAL_KEY`: random, dedicated key shared only with FreeRADIUS.
- `SUPABASE_URL`: provided by Supabase.
- `SUPABASE_SERVICE_ROLE_KEY`: provided by Supabase and never shared with RADIUS.

The endpoint accepts only `POST`, limits bodies to 8 KiB, authenticates the
`x-wasel-radius-key` header, validates every field, never logs credentials, and
maps database policy failures to a generic `ACCESS_REJECT` response.

Accounting rules:

- Malformed JSON is answered with `400 INVALID_JSON` (never `500`).
- An RFC 2866 Accounting-Start carries no counters. For `event_type: "start"`
  only, a missing, `null` or empty `input_bytes` / `output_bytes` /
  `session_seconds` is recorded as numeric `0`.
- For `interim_update` and `stop` every counter is mandatory; a missing or
  `null` counter is `400 INVALID_<FIELD>` so usage is never silently zeroed.
- `input_gigawords` / `output_gigawords` are optional for every event type.
- Accounting-On / Accounting-Off are answered by FreeRADIUS itself and never
  reach this function (`INVALID_EVENT_TYPE` if they do).

Local protocol tests:

```bash
deno test supabase/functions/radius-control/protocol_test.ts
```
