#!/bin/sh
set -eu

repo_dir=${1:-/opt/wasel-radius/src}
compose_file="$repo_dir/infra/radius/docker-compose.yml"
env_file="$repo_dir/infra/radius/.env"

for command in docker git openssl ufw; do
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

echo "PASS: WASEL One staging VPS preflight"
