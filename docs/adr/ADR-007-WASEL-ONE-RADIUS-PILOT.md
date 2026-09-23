# ADR-007: WASEL One RADIUS pilot boundary

- Status: Accepted for local pilot implementation
- Date: 2026-09-22
- Initiative: `WASEL-ONE-RADIUS-001`

## Decision

The pilot uses a standard FreeRADIUS gateway in front of a private Supabase
Edge Function. Existing MikroTik Hotspot routers remain the network access
servers. No partner-side appliance is required.

FreeRADIUS handles RADIUS UDP. The `radius-control` Edge Function validates a
dedicated internal key, normalizes the request, and calls service-only database
RPCs. PostgreSQL is authoritative for credentials, entitlements, partner
participation, sessions, accounting, and accruals.

```mermaid
flowchart LR
    A["MikroTik Hotspot"] <--> B["FreeRADIUS"]
    B --> C["radius-control HTTPS"]
    C --> D["Service-only RPCs"]
    D --> E["Entitlements and ledgers"]
```

## Secret boundary

- The MikroTik shared secret exists only on the router and FreeRADIUS host.
- `WASEL_RADIUS_INTERNAL_KEY` exists only on FreeRADIUS and the Edge Function.
- The Supabase service-role key exists only in the Edge Function runtime.
- Customer RADIUS passwords are returned once, stored only as bcrypt hashes,
  and never written to logs, audit metadata, accounting events, or Git.
- FreeRADIUS-to-control-plane traffic uses HTTPS outside local development.
- Customer-to-Hotspot credential submission uses a trusted HTTPS Hotspot
  certificate; `http-pap` is not allowed by the pilot template.

## Authentication flow

1. An authenticated customer requests credentials for an active entitlement.
2. PostgreSQL returns a generated username/password once and stores a bcrypt
   hash with an expiry no later than the entitlement expiry.
3. MikroTik sends an access request to FreeRADIUS.
4. FreeRADIUS forwards normalized fields to `radius-control` over HTTPS.
5. The database fails closed unless the node, network, plan participation,
   entitlement, credential, quota, and concurrency limit are all valid.
6. An accepted response includes a WASEL session UUID in the RADIUS `Class`
   attribute. MikroTik returns it with accounting packets.

## Accounting flow

`Start`, `Interim-Update`, and `Stop` events contain typed cumulative counters.
The control plane rejects counter regression and cross-node session claims.
Each event has an idempotency key. A stop event closes the session and creates
exactly one partner accrual using the active plan/network compensation model.

## Pilot defaults

- Accounting interim interval: 60 seconds.
- Authorization grant window: 5 minutes.
- Credential lifetime: at most 24 hours and never beyond entitlement expiry.
- Default idle timeout: 5 minutes.
- PAP is accepted only across the HTTPS Hotspot login plus private
  router-to-FreeRADIUS path included in this slice. Production transport must
  use a private tunnel or RadSec before a public rollout.

## Out of scope

- Production deployment or hosted database mutation.
- Live partner router changes.
- CHAP/MS-CHAP, RadSec, high availability, and offline authorization cache.
- Flutter UI for automatic association and credential delivery.
- Automated payout execution.
