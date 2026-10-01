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

Local protocol tests:

```bash
deno test supabase/functions/radius-control/protocol_test.ts
```
