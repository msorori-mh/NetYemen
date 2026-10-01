# WASEL One staging VPS runbook

## Fixed pilot target

- Provider: Hetzner Cloud.
- Plan: CX23 shared vCPU (2 vCPU, 4 GB RAM, 40 GB disk).
- Region: Nuremberg, Germany.
- Image: Ubuntu 24.04 LTS.
- Exposure: SSH from one administrator CIDR; UDP 1812/1813 from one pilot
  router CIDR only.
- Docker-published ports bypass UFW (Docker's DNAT rules run in the
  `FORWARD` path before UFW). The rendered cloud-init therefore also appends a
  `DOCKER-USER` block to `/etc/ufw/after.rules` that drops UDP 1812/1813 from
  any source other than the router CIDR, and the compose file publishes the
  ports only on `WASEL_RADIUS_BIND_IP`, never `0.0.0.0`.
- Scope: one disposable staging server and one MikroTik pilot router.

The provider order and billing remain an explicit human action. No API token or
payment credential belongs in this repository.

## Before ordering

Collect three exact inputs:

1. Administrator public IPv4 CIDR (normally `/32`).
2. Pilot router public IPv4 CIDR (normally `/32`).
3. Administrator SSH public key.

Render the cloud-init file locally:

```bash
export WASEL_ADMIN_CIDR='203.0.113.10/32'
export WASEL_ROUTER_CIDR='198.51.100.20/32'
export WASEL_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)"
sh infra/radius/staging/render-cloud-init.sh /tmp/wasel-cloud-init.yaml
```

Paste `/tmp/wasel-cloud-init.yaml` into the provider cloud-init field when
creating the server. Never commit the rendered file.

## Bootstrap repository and secrets

After cloud-init completes:

```bash
ssh wasel@SERVER_IP
test -f /opt/wasel-radius/CLOUD_INIT_COMPLETE
git clone --branch codex/WASEL-ONE-APK-PILOT-001 --single-branch \
  https://github.com/msorori-mh/NetYemen.git /opt/wasel-radius/src
cd /opt/wasel-radius/src/infra/radius
cp .env.example .env
chmod 0600 .env
```

Replace every placeholder in `.env`. Set `WASEL_RADIUS_BIND_IP` to the
server's own public IPv4 address (the address the router targets). Generate independent values for the
internal key and RADIUS shared secret:

```bash
openssl rand -base64 32
openssl rand -base64 32
```

The internal key must also be configured as the
`WASEL_RADIUS_INTERNAL_KEY` secret for the staging `radius-control` Edge
Function. The RADIUS shared secret must be installed only on the VPS and the
single pilot router.

## Read-only gate, apply, and verification

```bash
sudo sh infra/radius/staging/preflight.sh /opt/wasel-radius/src
docker compose --env-file infra/radius/.env \
  -f infra/radius/docker-compose.yml up --detach --build
docker compose --env-file infra/radius/.env \
  -f infra/radius/docker-compose.yml ps
```

The preflight runs as root because it reads UFW status and the `DOCKER-USER`
chain. Verify externally (from a host outside the router CIDR) that UDP
1812/1813 do not answer before continuing.

Do not apply the MikroTik template until the server preflight, database
preflight, Edge Function health, and router configuration export are all PASS.

## Rollback

```bash
docker compose --env-file infra/radius/.env \
  -f infra/radius/docker-compose.yml down
```

At the router, run `infra/radius/mikrotik/rollback-wasel-one-pilot.rsc`, then
restore the exported Hotspot profile. Delete the staging VPS only after logs and
post-verification evidence have been retained.
