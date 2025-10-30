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

COMPOSE_BIN=$(resolve_compose)

echo "==> Building and starting the TRP stack"
$COMPOSE_BIN up --build -d

echo
echo "==> Current container status"
$COMPOSE_BIN ps

cat <<'INFO'

TRP stack is up and running.

Available service endpoints:
  • API health check:      http://localhost:3000/healthz
  • Web client:            http://localhost:4173
  • PHP module host:       http://localhost:8080
  • pgAdmin interface:     http://localhost:5050

Use the default configuration admin credentials (admin@example.com / ChangeMeNow!)
to access the Config page and update environment-specific settings such as Google
OAuth mailbox parameters.

INFO
