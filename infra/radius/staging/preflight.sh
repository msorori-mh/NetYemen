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

# "UFW active" proves nothing about the RADIUS ports: Docker publishes them via
# DNAT + FORWARD, which bypasses the ufw INPUT chain. The effective restriction
# is the DOCKER-USER rule installed by wasel-radius-firewall.service.
firewall_helper=/usr/local/sbin/wasel-radius-firewall
test -x "$firewall_helper" || {
  echo "HOLD: $firewall_helper is missing; published RADIUS ports are not restricted." >&2
  exit 1
}
systemctl is-enabled --quiet wasel-radius-firewall.service || {
  echo "HOLD: wasel-radius-firewall.service is not enabled; the restriction would not survive a reboot." >&2
  exit 1
}
"$firewall_helper" check >/dev/null 2>&1 || {
  echo "HOLD: DOCKER-USER does not drop UDP 1812/1813 from outside the NAS network (run as root)." >&2
  exit 1
}
firewall_cidr=$("$firewall_helper" print-cidr)
nas_network=$(sed -n 's/^WASEL_NAS_NETWORK=//p' "$env_file" | tail -n 1 | tr -d '"'"'"'[:space:]')
test -n "$nas_network" && test "$firewall_cidr" = "$nas_network" || {
  echo "HOLD: firewall NAS network ($firewall_cidr) differs from WASEL_NAS_NETWORK ($nas_network) in $env_file." >&2
  exit 1
}
# No other rule may accept the RADIUS ports ahead of the restriction.
first_rule=$(iptables -w -S DOCKER-USER | grep -- '^-A DOCKER-USER' | head -n 1)
case "$first_rule" in
  *1812*DROP*) ;;
  *)
    echo "HOLD: the RADIUS restriction is not the first DOCKER-USER rule: $first_rule" >&2
    exit 1
    ;;
esac

echo "PASS: WASEL One staging VPS preflight"
