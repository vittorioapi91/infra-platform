#!/bin/bash
# Drop all Postgres datalake data and re-initialize from scratch.
# Use when you can't connect or want a clean state; init scripts run on empty PGDATA.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.infra-platform.yml"
DATA_ROOT="$SCRIPT_DIR/../storage-postgresql"

echo "Stopping postgres-dev, postgres-test, postgres-prod..."
docker compose -f "$COMPOSE_FILE" stop postgres-dev postgres-test postgres-prod

echo "Wiping PGDATA (contents only) for dev, test, prod..."
for env in dev test prod; do
  dir="$DATA_ROOT/$env"
  if [ -e "$dir" ]; then
    target="$dir"
    [ -L "$dir" ] && target="$(cd "$dir" && pwd -P)"
    rm -rf "${target:?}"/* 2>/dev/null || true
    echo "  wiped $target"
  else
    echo "  skip $dir (missing)"
  fi
done

echo "Starting postgres instances (init scripts will run on empty data)..."
docker compose -f "$COMPOSE_FILE" up -d postgres-dev postgres-test postgres-prod

echo "Done. Wait ~10s then connect as dev.user / test.user / prod.user to database 'datalake' (e.g. via nginx ports 54324/54325/54326)."
echo "To create/repair datalake + schemas without wiping data, run: ./docker/provision-datalakes.sh"
