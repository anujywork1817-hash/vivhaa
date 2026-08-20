#!/usr/bin/env bash
# Runs golang-migrate against the local Postgres instance via Docker,
# so no local `migrate` CLI install is required.
#
# Usage:
#   scripts/migrate.sh up
#   scripts/migrate.sh down 1
#   scripts/migrate.sh version
#   scripts/migrate.sh create add_profiles_table
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-postgres}"
DB_NAME="${DB_NAME:-myapp}"
DB_SSLMODE="${DB_SSLMODE:-disable}"

CMD="${1:-}"
shift || true

if [ "$CMD" = "create" ]; then
  NAME="${1:?usage: scripts/migrate.sh create <name>}"
  docker run --rm -v "$(pwd)/migrations:/migrations" migrate/migrate \
    create -ext sql -dir /migrations -seq "$NAME"
  exit 0
fi

# When running against a DB on the host machine (localhost), the migrate
# container needs host.docker.internal instead of localhost.
CONTAINER_DB_HOST="$DB_HOST"
if [ "$DB_HOST" = "localhost" ] || [ "$DB_HOST" = "127.0.0.1" ]; then
  CONTAINER_DB_HOST="host.docker.internal"
fi

DSN="postgres://${DB_USER}:${DB_PASSWORD}@${CONTAINER_DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=${DB_SSLMODE}"

docker run --rm --add-host=host.docker.internal:host-gateway \
  -v "$(pwd)/migrations:/migrations" migrate/migrate \
  -path=/migrations -database "$DSN" "$CMD" "$@"
