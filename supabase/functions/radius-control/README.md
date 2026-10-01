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

Every request must carry `client_shortname` (FreeRADIUS `%{client:shortname}`,
derived from the RADIUS client matched by source address and shared secret).
It must equal `nas_identifier` exactly, otherwise the request is rejected with
400 `INVALID_NAS_BINDING`, so a router cannot claim another NAS's identity.

Local protocol tests:

```bash
deno test supabase/functions/radius-control/protocol_test.ts
```
