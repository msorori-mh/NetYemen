#!/bin/sh
set -eu

for variable in WASEL_CONTROL_URL WASEL_RADIUS_INTERNAL_KEY WASEL_RADIUS_SHARED_SECRET WASEL_NAS_NETWORK; do
  eval "value=\${$variable:-}"
  case "$value" in
    ""|TEST_ONLY_*|*REPLACE*)
      echo "ERROR: $variable is unset or still contains a placeholder." >&2
      exit 78
      ;;
  esac
done

case "$WASEL_CONTROL_URL" in
  https://*|http://host.docker.internal:*) ;;
  http://radius-control-mock:*)
    if [ "${WASEL_ALLOW_INSECURE_LOCAL:-false}" != "true" ]; then
      echo "ERROR: local HTTP mock requires WASEL_ALLOW_INSECURE_LOCAL=true." >&2
      exit 78
    fi
    ;;
  *)
    echo "ERROR: WASEL_CONTROL_URL must use HTTPS outside local Docker development." >&2
    exit 78
    ;;
esac

exec "$@"
