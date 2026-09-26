#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
template="$script_dir/cloud-init.yaml.template"
output="${1:-$script_dir/cloud-init.rendered.yaml}"

: "${WASEL_ADMIN_CIDR:?set WASEL_ADMIN_CIDR, for example 203.0.113.10/32}"
: "${WASEL_ROUTER_CIDR:?set WASEL_ROUTER_CIDR, for example 198.51.100.20/32}"
: "${WASEL_SSH_PUBLIC_KEY:?set WASEL_SSH_PUBLIC_KEY}"

cidr_pattern='^[0-9]{1,3}(\.[0-9]{1,3}){3}/(3[0-2]|[12]?[0-9])$'
printf '%s\n' "$WASEL_ADMIN_CIDR" | grep -Eq "$cidr_pattern" || {
  echo "ERROR: WASEL_ADMIN_CIDR must be a single IPv4 CIDR." >&2
  exit 64
}
printf '%s\n' "$WASEL_ROUTER_CIDR" | grep -Eq "$cidr_pattern" || {
  echo "ERROR: WASEL_ROUTER_CIDR must be a single IPv4 CIDR." >&2
  exit 64
}

ssh_key=$(printf '%s\n' "$WASEL_SSH_PUBLIC_KEY" | awk 'NF >= 2 {print $1 " " $2}')
case "$ssh_key" in
  ssh-ed25519\ *|ssh-rsa\ *) ;;
  *)
    echo "ERROR: WASEL_SSH_PUBLIC_KEY must be an ssh-ed25519 or ssh-rsa public key." >&2
    exit 64
    ;;
esac

if [ -e "$output" ]; then
  echo "ERROR: refusing to overwrite $output" >&2
  exit 73
fi

sed \
  -e "s|__ADMIN_CIDR__|$WASEL_ADMIN_CIDR|g" \
  -e "s|__ROUTER_CIDR__|$WASEL_ROUTER_CIDR|g" \
  -e "s|__SSH_PUBLIC_KEY__|$ssh_key|g" \
  "$template" > "$output"

chmod 0600 "$output"
echo "PASS: rendered $output"
