#!/usr/bin/env bash

set -euo pipefail

resolve_compose() {
  if command -v docker-compose >/dev/null 2>&1; then
    echo "docker-compose"
    return 0
  fi

  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    echo "docker compose"
    return 0
  fi

  echo "Error: Neither docker compose nor docker-compose is available in PATH." >&2
  echo "Please install Docker and Docker Compose v2." >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage: ./debug.sh [service ...]

Follow container logs for the entire TRP stack or the specified services.
Examples:
  ./debug.sh                 # follow logs for all services
  ./debug.sh api web         # follow logs only for the API and web containers
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

COMPOSE_BIN=$(resolve_compose)

echo "==> Displaying container status"
$COMPOSE_BIN ps

echo
echo "==> Following logs (Ctrl+C to stop)"
if [[ $# -gt 0 ]]; then
  $COMPOSE_BIN logs -f --tail=100 "$@"
else
  $COMPOSE_BIN logs -f --tail=100
fi
