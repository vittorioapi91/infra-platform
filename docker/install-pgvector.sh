#!/usr/bin/env bash
# Enable pgvector on postgres-{dev,test,prod} datalake databases.
# Requires pgvector/pgvector:pg18 image (see docker-compose.infra-platform.yml).
#
# Usage: ./docker/install-pgvector.sh

set -euo pipefail

POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-2014}"

install_pgvector() {
  local container="$1"

  if ! docker ps --format '{{.Names}}' | grep -qx "$container"; then
    echo "ERROR: container $container is not running." >&2
    return 1
  fi

  echo "=== $container ==="
  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container" \
    psql -U postgres -d datalake -v ON_ERROR_STOP=1 -c "CREATE EXTENSION IF NOT EXISTS vector;"

  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container" \
    psql -U postgres -d datalake -tAc "SELECT extname || ' ' || extversion FROM pg_extension WHERE extname = 'vector';"
}

for container in postgres-dev postgres-test postgres-prod; do
  install_pgvector "$container"
done

echo ""
echo "Done. pgvector is enabled on datalake for dev, test, and prod."
