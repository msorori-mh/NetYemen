#!/bin/sh
set -eu

repo_dir=${1:-/opt/wasel-radius/src}
compose_file="$repo_dir/infra/radius/docker-compose.yml"
env_file="$repo_dir/infra/radius/.env"

for command in docker git iptables openssl ufw; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "HOLD: missing command: $command" >&2
    exit 1
  }
done

test -f /opt/wasel-radius/CLOUD_INIT_COMPLETE || {
  echo "HOLD: cloud-init completion marker is missing." >&2
  exit 1
}
test -f "$compose_file" || {
  echo "HOLD: compose file is missing: $compose_file" >&2
  exit 1
}
test -f "$env_file" || {
  echo "HOLD: staging .env is missing: $env_file" >&2
  exit 1
}

permissions=$(stat -c '%a' "$env_file")
test "$permissions" = "600" || {
  echo "HOLD: $env_file must have mode 600; found $permissions." >&2
  exit 1
}

if grep -Eq 'REPLACE|YOUR_PROJECT|TEST_ONLY' "$env_file"; then
  echo "HOLD: staging .env still contains a placeholder." >&2
  exit 1
fi

docker compose --env-file "$env_file" -f "$compose_file" config --quiet
systemctl is-active --quiet docker || {
  echo "HOLD: Docker is not active." >&2
  exit 1
}
ufw status | grep -q 'Status: active' || {
  echo "HOLD: UFW is not active." >&2
  exit 1
}

# Docker-published ports bypass UFW; require the explicit bind address and the
# DOCKER-USER source filter installed by cloud-init.
bind_ip=$(sed -n 's/^WASEL_RADIUS_BIND_IP=//p' "$env_file" | tail -n 1)
case "$bind_ip" in
  ''|0.0.0.0|::|'[::]')
    echo "HOLD: WASEL_RADIUS_BIND_IP must be the server's specific IPv4 address." >&2
    exit 1
    ;;
esac
grep -q 'BEGIN WASEL DOCKER-USER' /etc/ufw/after.rules || {
  echo "HOLD: WASEL DOCKER-USER block is missing from /etc/ufw/after.rules." >&2
  exit 1
}
docker_user_rules=$(iptables -S DOCKER-USER 2>/dev/null) || {
  echo "HOLD: cannot read the DOCKER-USER chain (run preflight with sudo)." >&2
  exit 1
}
printf '%s\n' "$docker_user_rules" | grep -q -- '--dports 1812,1813 -j DROP' || {
  echo "HOLD: DOCKER-USER does not drop non-router RADIUS traffic." >&2
  exit 1
}

echo "PASS: WASEL One staging VPS preflight"
