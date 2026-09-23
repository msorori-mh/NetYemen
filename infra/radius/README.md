# WASEL One — FreeRADIUS pilot

This directory is the deployable pilot bridge for existing MikroTik Hotspot
routers. It does not require a new appliance at the partner site.

## Local start

1. Copy `.env.example` to `.env` and replace every placeholder.
2. Start local Supabase and serve `radius-control` with its internal key.
3. Run `docker compose up --build` from this directory.
4. Install a trusted TLS certificate for the Hotspot hostname, then substitute
   all placeholders in
   `mikrotik/wasel-one-pilot.rsc.template`, export the router configuration,
   then apply the pilot template to one test router only.
5. Test one access, one interim update, and one stop before widening the pilot.

Generate secrets outside the repository, for example:

```bash
openssl rand -base64 32
```

## Fail-closed controls

- Startup refuses unset and placeholder secrets.
- Only the configured NAS network is accepted.
- Message-Authenticator is required.
- The Hotspot login profile is HTTPS-only; the template refuses to proceed
  without an explicit certificate name.
- Non-local control-plane URLs must use HTTPS.
- The container is read-only, drops Linux capabilities, and does not retain
  credentials or raw RADIUS packets.
- PAP is accepted only for this encrypted pilot path. A public rollout requires
  a private tunnel or RadSec and a separate production gate.

## Rollback

Run `mikrotik/rollback-wasel-one-pilot.rsc` to disable only the tagged RADIUS
entry. Restore the Hotspot profile from the configuration export captured before
the change. The rollback deliberately does not guess or overwrite prior values.
