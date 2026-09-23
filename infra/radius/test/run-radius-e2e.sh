#!/bin/sh
set -eu

radius_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
compose_file="$radius_dir/docker-compose.test.yml"
project_name="wasel_radius_e2e"
radius_secret="E2E_ONLY_RADIUS_SECRET_32_BYTES_SAFE"

cleanup() {
  docker compose -p "$project_name" -f "$compose_file" down --volumes --remove-orphans >/dev/null 2>&1 || true
}

finish() {
  status=$?
  trap - EXIT INT TERM
  if [ "$status" -ne 0 ]; then
    echo "RADIUS E2E failed; disposable container logs follow:" >&2
    docker compose -p "$project_name" -f "$compose_file" logs --no-color >&2 || true
  fi
  cleanup
  exit "$status"
}
trap finish EXIT INT TERM

cleanup
docker compose -p "$project_name" -f "$compose_file" up --build --detach --wait
sleep 2

radius_container=$(docker compose -p "$project_name" -f "$compose_file" ps -q freeradius)
if [ -z "$radius_container" ]; then
  echo "FAIL: FreeRADIUS container was not created." >&2
  exit 1
fi

auth_accept=$(docker exec -i "$radius_container" sh -c \
  "radclient -x -r 1 -t 3 127.0.0.1:1812 auth '$radius_secret'" <<'EOF'
User-Name = "w1-0123456789abcdef01234567"
User-Password = "TEST_ONLY_E2E_PASSWORD"
NAS-Identifier = "wasel-e2e-nas-01"
Acct-Session-Id = "hs-e2e-000001"
Calling-Station-Id = "02:00:00:00:00:01"
Message-Authenticator = 0x00
EOF
)
printf '%s\n' "$auth_accept" | grep -q "Access-Accept"
printf '%s\n' "$auth_accept" | grep -q 'Class = 0x39393030303030302d303030302d343030302d383030302d303030303030303030303031\|Class = "99000000-0000-4000-8000-000000000001"'
printf '%s\n' "$auth_accept" | grep -q "Session-Timeout = 3600"
printf '%s\n' "$auth_accept" | grep -q 'Mikrotik-Rate-Limit = "4096k/4096k"'

auth_reject=$(docker exec -i "$radius_container" sh -c \
  "radclient -x -r 1 -t 3 127.0.0.1:1812 auth '$radius_secret'" <<'EOF'
User-Name = "w1-0123456789abcdef01234567"
User-Password = "TEST_ONLY_WRONG_PASSWORD"
NAS-Identifier = "wasel-e2e-nas-01"
Acct-Session-Id = "hs-e2e-000001"
Message-Authenticator = 0x00
EOF
)
printf '%s\n' "$auth_reject" | grep -q "Access-Reject"

accounting=$(docker exec -i "$radius_container" sh -c \
  "radclient -x -r 1 -t 3 127.0.0.1:1813 acct '$radius_secret'" <<'EOF'
User-Name = "w1-0123456789abcdef01234567"
NAS-Identifier = "wasel-e2e-nas-01"
Acct-Session-Id = "hs-e2e-000001"
Acct-Status-Type = Start
Class = "99000000-0000-4000-8000-000000000001"
Acct-Input-Octets = 0
Acct-Output-Octets = 0
Acct-Input-Gigawords = 0
Acct-Output-Gigawords = 0
Acct-Session-Time = 0
Message-Authenticator = 0x00
EOF
)
printf '%s\n' "$accounting" | grep -q "Accounting-Response"

stats=$(curl --fail --silent --show-error http://127.0.0.1:18787/stats)
node -e '
const stats = JSON.parse(process.argv[1]);
if (stats.authorizeAccepted !== 1 || stats.authorizeDenied !== 1 || stats.accounting !== 1) {
  throw new Error(`unexpected mock stats: ${JSON.stringify(stats)}`);
}
' "$stats"

echo "PASS: RADIUS packet E2E accepted=1 rejected=1 accounting=1"
