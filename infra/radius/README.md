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

## Packet-level test

The disposable harness drives a real FreeRADIUS process against a local
control-plane mock. It never contacts Supabase or a live router:

```bash
sh infra/radius/test/run-radius-e2e.sh
```

It sends one accepted login, one rejected login, then a realistic accounting
sequence: a **Start with no counters** (exactly what RFC 2866 and MikroTik
send), an Interim-Update and a Stop with counters and gigawords, and an
Accounting-On. The mock `JSON.parse`s every body strictly and the run fails if
FreeRADIUS ever emitted invalid JSON, if the Start did not arrive as numeric
zeros, if Accounting-On reached the control plane, or if the daemon (PID 1) is
still running as root.

## Accounting contract

- **Start without counters.** An Accounting-Start carries no
  `Acct-Input-Octets`, `Acct-Output-Octets`, `Acct-Session-Time` or gigawords.
  The previous template used `%{integer:Attr}`, which expands to an empty string
  for a missing attribute and produced `"input_bytes":,` (invalid JSON, HTTP
  500, no Accounting-Response, and then every Interim/Stop rejected because no
  Start had been recorded). Now:
  - `sites-available/wasel` sets the three counters to `0` for `Start` only;
  - `mods-available/wasel_rest` uses the FreeRADIUS 3.x alternation
    `%{%{Attr}:-default}` for every numeric field, so the body is valid JSON
    whatever the NAS omits. Gigawords default to `0` in every packet; a missing
    octet/time counter on an Interim-Update or Stop is sent as `null`;
  - `radius-control` treats a missing/`null` counter as `0` for `start` only,
    rejects it with HTTP 400 for `interim_update`/`stop` (recording zero usage
    would silently under-bill), and answers malformed JSON with `400
    INVALID_JSON` instead of `500`.
- **Accounting-On / Accounting-Off.** These NAS reboot signals have no `Class`
  and no session. FreeRADIUS answers them with an Accounting-Response locally
  and does not call the control plane, so the router stops retransmitting.
  Sessions orphaned by a router reboot are closed server-side by the
  stale-session reaper in PostgreSQL; nothing in this directory closes them.
- Any other accounting packet without `Class`, `NAS-Identifier`,
  `Acct-Session-Id` or `Acct-Status-Type` is dropped (no response).

## Network exposure (read before starting the stack on a public host)

Docker publishes container ports with DNAT and FORWARD rules. Those packets
never traverse the `ufw` INPUT chain, so **`ufw allow from <router> to any port
1812` does not restrict a published port, and "UFW: active" proves nothing**:
without further rules UDP 1812/1813 are reachable from the whole internet.

`staging/cloud-init.yaml.template` therefore installs
`/usr/local/sbin/wasel-radius-firewall` and `wasel-radius-firewall.service`,
which insert this rule at the top of the `DOCKER-USER` chain before Docker
starts, on every boot (Docker is `RequiredBy` it, so Docker does not start if
the rule cannot be installed):

```text
iptables -I DOCKER-USER -p udp -m conntrack ! --ctorigsrc <ROUTER_CIDR> --ctorigdstport 1812:1813 -j DROP
```

`staging/preflight.sh` (run as root) verifies that the rule is present, is the
first `DOCKER-USER` rule, is enabled for reboot, and uses the same network as
`WASEL_NAS_NETWORK` in `.env`. `render-cloud-init.sh` refuses to emit a file
with any unreplaced `__PLACEHOLDER__`. On a host that was not built from the
template, install the same script and unit by hand before `docker compose up`.
`WASEL_RADIUS_BIND_IP` can additionally bind the published ports to one host
address (for example a WireGuard interface). IPv6 is not forwarded to the
container; IPv6 packets to the host ports hit the ufw default-deny INPUT policy.

## One shared secret for all routers (limitation)

`freeradius/clients.conf` defines a single `client` block: every source address
inside `WASEL_NAS_NETWORK` is accepted with the one
`WASEL_RADIUS_SHARED_SECRET`. That is acceptable for a one-router pilot
(`/32`). With several routers it means a secret extracted from one router lets
its holder impersonate any other router in the network (forge
`NAS-Identifier`, submit accounting for foreign sessions) and decrypt PAP
passwords captured from them, and one compromised router forces a secret
rotation on all of them.

To give each router its own secret:

1. Generate one secret per router (`openssl rand -base64 32`) and add one
   variable per router to `.env` and to `environment:` in `docker-compose.yml`,
   for example `WASEL_NAS_ROUTER01_IP` / `WASEL_NAS_ROUTER01_SECRET`.
2. Replace the single block in `freeradius/clients.conf` with one block per
   router, each limited to that router's `/32`:

   ```text
   client wasel_router01 {
       ipaddr = $ENV{WASEL_NAS_ROUTER01_IP}
       secret = $ENV{WASEL_NAS_ROUTER01_SECRET}
       require_message_authenticator = yes
       nas_type = other
       shortname = wasel-router01
   }
   ```

3. Add each new variable name to the fail-closed loop at the top of
   `docker-entrypoint-wasel.sh` so an unset or placeholder secret still stops
   startup.
4. Keep the firewall in step: `WASEL_ROUTER_CIDR` in
   `/etc/wasel-radius/firewall.env` accepts one CIDR. For routers that do not
   share a prefix, extend `wasel-radius-firewall` to one ACCEPT rule per router
   followed by the DROP rule, and extend `preflight.sh` accordingly.
5. Apply the matching per-router secret in each router's rendered
   `wasel-one-pilot.rsc`, rebuild, and re-run the packet E2E and `-XC` check.
6. Optionally reject a mismatching `NAS-Identifier` per client in
   `sites-available/wasel` (compare `%{client:shortname}` with
   `&NAS-Identifier`); the control plane currently trusts the identifier the
   packet carries.

The same split is required before any router is on a dynamic or shared (CGNAT)
address; in that case use a tunnel (WireGuard) or RadSec rather than widening
`WASEL_NAS_NETWORK`.

## Container image

- The base image is a build argument: `FREERADIUS_IMAGE` (compose:
  `WASEL_FREERADIUS_IMAGE`). The default is the mutable tag
  `freeradius/freeradius-server:3.2.7`. Outside local development resolve and
  verify a digest yourself and build with
  `freeradius/freeradius-server@sha256:<digest>`. No digest is committed.
- The entrypoint starts as root, then `radiusd` switches to the unprivileged
  `freerad` user through `security { user, group }` in the base image's
  `radiusd.conf`. The image build fails if that directive is not `freerad`, and
  the packet E2E fails if PID 1 is uid 0.

## MikroTik template

- `timeout=3s` on the RADIUS client (was `1s`). One login crosses FreeRADIUS,
  an HTTPS Edge Function, a PostgreSQL RPC and a bcrypt verification; on an Edge
  Function cold start that exceeds 1s and RouterOS rejects a valid login.
- Every placeholder is read into a variable once and a generic guard refuses to
  run while any value is empty or still contains `{{` / `}}`. The template also
  refuses to run if the profile or certificate does not exist, if a
  `WASEL_ONE_PILOT` entry already exists, or if the Hotspot profile already has
  `use-radius=yes` (it must not take over an existing RADIUS deployment).
- Use secrets without `"`, `$` or `\` (base64 output is safe): the values are
  placed inside RouterOS double-quoted strings.

## Fail-closed controls

- Startup refuses unset and placeholder secrets.
- Only the configured NAS network is accepted by FreeRADIUS (`clients.conf`)
  and, on the staging host, by the `DOCKER-USER` firewall rule.
- Message-Authenticator is required.
- The Hotspot login profile is HTTPS-only; the template refuses to proceed
  without an explicit certificate name.
- Non-local control-plane URLs must use HTTPS.
- The container is read-only and drops all Linux capabilities except the three
  needed to initialize directories and switch to the unprivileged `freerad`
  user (`CHOWN`, `SETGID`, `SETUID`). It does not retain credentials or raw
  RADIUS packets.
- PAP is accepted only for this encrypted pilot path. A public rollout requires
  a private tunnel or RadSec and a separate production gate.

## Rollback

Run `mikrotik/rollback-wasel-one-pilot.rsc`. It disables only the tagged RADIUS
entry and sets `use-radius=no` on the exact Hotspot profile the template
changed (the profile name is stored in the comment of the inert
`wasel-one-pilot-state` script entry created at apply time). Because the
template refuses to run on a profile that already used RADIUS, `no` is the
pre-change value; leaving `use-radius=yes` with no RADIUS server would make
every Hotspot login fail. `login-by` and `ssl-certificate` are not reverted --
the script does not guess prior values -- so restore those from the
configuration export captured before the change.

The complete gate order and database verification commands are documented in
`docs/WASEL-ONE-PILOT-RUNBOOK.md`.
