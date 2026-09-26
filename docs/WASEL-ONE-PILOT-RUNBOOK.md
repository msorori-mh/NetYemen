# WASEL One — controlled MikroTik pilot runbook

This runbook separates readiness, application, verification, and rollback. It
does not authorize a production database write or a live router change.

## Gate 0 — fixed pilot scope

- One verified partner network.
- One MikroTik Hotspot router and one exported pre-change configuration.
- One `TEST_ONLY` customer entitlement with a small quota and short validity.
- One FreeRADIUS instance reachable only through the approved private path.
- One trusted Hotspot TLS certificate and hostname.
- No payout execution; the pilot creates an accrual record only.

Exit: named operator, maintenance window, router identity, network ID, NAS
identifier, test user ID, rollback owner, and maximum test duration are recorded.

## Gate 1 — read-only preflight

1. Run migrations in staging, not production.
2. Run `021_wasel_one_radius_pilot_preflight.sql` against staging.
3. Deploy `radius-control` with `WASEL_RADIUS_INTERNAL_KEY` in the runtime secret
   store. Never put this key in Flutter, RouterOS scripts, tickets, or Git.
4. Build FreeRADIUS and run `freeradius -XC`.
5. Run `sh infra/radius/test/run-radius-e2e.sh`.
6. Confirm the router clock, DNS, certificate validity, private path, and current
   Hotspot profile export.

Exit: all checks PASS, packet test is green, and the rollback operator is online.

## Gate 2 — apply to one test router

This gate requires explicit authorization for the named staging environment and
router. Replace the placeholders in `wasel-one-pilot.rsc.template` offline. Apply
the resulting file to that router only, then confirm `/radius monitor` has no
timeouts or bad replies.

Stop immediately on certificate mismatch, RADIUS timeout, bad reply, unexpected
local-user impact, or traffic from an unregistered NAS identifier.

## Gate 3 — one end-to-end session

1. Issue a credential for the `TEST_ONLY` entitlement.
2. Join the pilot SSID and submit it through the HTTPS Hotspot page.
3. Verify Access-Accept includes Class, Session-Timeout, Idle-Timeout,
   Acct-Interim-Interval, and Mikrotik-Rate-Limit.
4. Transfer a small known amount of data, wait for one interim update, and log
   out normally.
5. Run `021_wasel_one_radius_pilot_postverify.sql` with the exact session UUID.

Exit: one closed session, monotonic counters, Start/Stop events, entitlement
consumption, and exactly one partner accrual.

## Rollback

1. Run `rollback-wasel-one-pilot.rsc` to disable the tagged RADIUS entry.
2. Restore the saved Hotspot profile from the pre-change export.
3. Revoke the pilot credential and entitlement; do not delete accounting or
   ledger evidence.
4. Disable the pilot NAS node if the router is leaving the pilot.
5. Rotate both dedicated RADIUS secrets if exposure is suspected.
6. Run the post-verification read only and record the exact remaining session,
   event, and accrual identifiers.

Rollback does not remove immutable accounting or financial evidence.
