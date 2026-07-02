#!/usr/bin/env bash
# Upgrade openproject-postgres from PG15 → PG18 (logical dump/restore).
#
# Usage (from repo root):
#   ./docker/upgrade-openproject-postgres-to-18.sh
#   ./docker/upgrade-openproject-postgres-to-18.sh from-backup /path/to/data.pg15-backup-<ts>
#
# Staging: docker/.upgrade-pg18-staging/openproject/

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/docker/docker-compose.infra-platform.yml"
STAGING_DIR="$REPO_ROOT/docker/.upgrade-pg18-staging/openproject"
CONTAINER="openproject-postgres"
APP_CONTAINER="openproject"
DB_NAME="openproject"
DB_USER="openproject"
DB_PASSWORD="${OPENPROJECT_DB_PASSWORD:-openproject}"
JOBS="${UPGRADE_JOBS:-4}"
SIDECAR_TRIES="${UPGRADE_SIDECAR_TRIES:-120}"

resolve_storage_path() {
  python3 -c "import os; print(os.path.realpath('${REPO_ROOT}/storage-infra/openproject-postgres/data'))"
}

wait_for_postgres() {
  local container="$1"
  local user="$2"
  local tries="${3:-90}"
  while [ "$tries" -gt 0 ]; do
    if docker exec -e PGPASSWORD="$DB_PASSWORD" "$container" \
      psql -U "$user" -d postgres -tAc 'SELECT 1' >/dev/null 2>&1; then
      return 0
    fi
    tries=$((tries - 1))
    sleep 2
  done
  return 1
}

wait_for_postgres_stable() {
  local container="$1"
  local user="$2"
  wait_for_postgres "$container" "$user" 90 || return 1
  if docker logs "$container" 2>&1 | grep -q 'PostgreSQL init process complete'; then
    sleep 5
    wait_for_postgres "$container" "$user" 90 || return 1
  fi
  sleep 2
  wait_for_postgres "$container" "$user" 90
}

verify_pg15_backup_path() {
  local backup_path="$1"
  [ -d "$backup_path" ] || { echo "ERROR: backup missing: $backup_path" >&2; exit 1; }
  [ -f "$backup_path/PG_VERSION" ] || { echo "ERROR: no PG_VERSION in $backup_path" >&2; exit 1; }
  local pg_ver
  pg_ver="$(tr -d '[:space:]' <"$backup_path/PG_VERSION")"
  [ "$pg_ver" = "15" ] || { echo "ERROR: expected PG15, got $pg_ver" >&2; exit 1; }
  echo "  backup verified: PG15 at $backup_path ($(du -sh "$backup_path" | awk '{print $1}'))"
}

verify_staging_dump() {
  local staging="$1"
  local globals="$staging/globals.sql"
  local dump_dir="$staging/${DB_NAME}"
  local min_kb="${UPGRADE_MIN_DUMP_KB:-512}"

  [ -s "$globals" ] || { echo "ERROR: empty globals.sql" >&2; exit 1; }
  [ -f "$dump_dir/toc.dat" ] || { echo "ERROR: missing dump toc.dat" >&2; exit 1; }
  local dump_kb
  dump_kb="$(du -sk "$dump_dir" | awk '{print $1}')"
  [ "$dump_kb" -ge "$min_kb" ] || {
    echo "ERROR: dump only ${dump_kb}K (min ${min_kb}K)" >&2
    exit 1
  }
  echo "  staging dump verified: ${dump_kb}K"
}

dump_from_pg15_backup() {
  local backup_path="$1"
  local staging="$2"
  local dump_dir="$staging/${DB_NAME}"

  mkdir -p "$staging"
  rm -rf "$dump_dir"
  verify_pg15_backup_path "$backup_path"

  local sidecar="pg15-dump-openproject-$$"
  docker run -d --name "$sidecar" \
    -v "${backup_path}:/var/lib/postgresql/data" \
    -v "${staging}:/staging" \
    -e POSTGRES_PASSWORD="$DB_PASSWORD" \
    -e POSTGRES_USER="$DB_USER" \
    -e POSTGRES_DB="$DB_NAME" \
    postgres:15 >/dev/null

  echo "  waiting for PG15 sidecar..."
  if ! wait_for_postgres "$sidecar" "$DB_USER" "$SIDECAR_TRIES"; then
    docker rm -f "$sidecar" >/dev/null 2>&1 || true
    echo "ERROR: PG15 sidecar failed to start." >&2
    exit 1
  fi

  docker exec -e PGPASSWORD="$DB_PASSWORD" "$sidecar" \
    sh -c "pg_dumpall -U ${DB_USER} --globals-only > /staging/globals.sql && pg_dump -U ${DB_USER} -d ${DB_NAME} -Fd -j ${JOBS} -f /staging/${DB_NAME}"

  local source_bytes
  source_bytes="$(docker exec -e PGPASSWORD="$DB_PASSWORD" "$sidecar" \
    psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT pg_database_size('${DB_NAME}');")"
  echo "$source_bytes" >"$staging/source_bytes.txt"
  echo "  source DB size: $(numfmt --to=iec-i --suffix=B "$source_bytes" 2>/dev/null || echo "${source_bytes}B")"

  docker rm -f "$sidecar" >/dev/null
  verify_staging_dump "$staging"
}

snapshot_and_dump() {
  local staging="$1"
  local storage backup_path

  echo "=== Stopping ${APP_CONTAINER} and ${CONTAINER} ===" >&2
  docker compose -f "$COMPOSE_FILE" stop "$APP_CONTAINER" "$CONTAINER" >/dev/null

  storage="$(resolve_storage_path)"
  backup_path="$(dirname "$storage")/data.pg15-backup-$(date +%Y%m%d%H%M%S)"

  if [ -d "$storage" ] && [ -n "$(ls -A "$storage" 2>/dev/null || true)" ]; then
    mv "$storage" "$backup_path"
    mkdir -p "$storage"
    echo "  PG15 backup: $backup_path" >&2
  else
    echo "ERROR: no PG15 data at $storage" >&2
    exit 1
  fi

  dump_from_pg15_backup "$backup_path" "$staging" >&2
  printf '%s' "$backup_path"
}

wipe_storage() {
  local storage
  storage="$(resolve_storage_path)"
  mkdir -p "$storage"
  rm -rf "${storage:?}"/*
  echo "  cleared $storage"
}

start_pg18() {
  echo "=== Starting ${CONTAINER} on PG18 ==="
  docker compose -f "$COMPOSE_FILE" pull "$CONTAINER" >/dev/null
  docker compose -f "$COMPOSE_FILE" up -d "$CONTAINER"
  wait_for_postgres_stable "$CONTAINER" "$DB_USER"
}

restore_into_pg18() {
  local staging="$1"
  local globals="$staging/globals.sql"
  local dump_dir="$staging/${DB_NAME}"

  echo "=== Restoring globals ==="
  docker exec -i -e PGPASSWORD="$DB_PASSWORD" "$CONTAINER" \
    psql -U "$DB_USER" -d postgres -v ON_ERROR_STOP=0 --quiet <"$globals" 2>/dev/null || true

  wait_for_postgres_stable "$CONTAINER" "$DB_USER"

  echo "=== Recreating database ${DB_NAME} ==="
  docker exec -e PGPASSWORD="$DB_PASSWORD" "$CONTAINER" \
    psql -U "$DB_USER" -d postgres -v ON_ERROR_STOP=1 <<-EOSQL
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '${DB_NAME}' AND pid <> pg_backend_pid();
DROP DATABASE IF EXISTS ${DB_NAME} WITH (FORCE);
CREATE DATABASE ${DB_NAME};
EOSQL

  echo "=== Restoring ${DB_NAME} (jobs=${JOBS}) ==="
  docker cp "$dump_dir/." "${CONTAINER}:/var/lib/postgresql/openproject-restore/"
  docker exec -e PGPASSWORD="$DB_PASSWORD" "$CONTAINER" \
    pg_restore -U "$DB_USER" -d "$DB_NAME" --no-owner --no-acl -j "$JOBS" /var/lib/postgresql/openproject-restore \
    || echo "WARNING: pg_restore reported errors (often harmless); continuing..." >&2
  docker exec "$CONTAINER" rm -rf /var/lib/postgresql/openproject-restore

  docker exec -e PGPASSWORD="$DB_PASSWORD" "$CONTAINER" postgres --version
  docker exec -e PGPASSWORD="$DB_PASSWORD" "$CONTAINER" \
    psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT pg_size_pretty(pg_database_size('${DB_NAME}'));"
}

start_openproject() {
  echo "=== Starting ${APP_CONTAINER} ==="
  docker compose -f "$COMPOSE_FILE" up -d "$APP_CONTAINER"
}

main() {
  local staging="$STAGING_DIR"
  local backup_path=""

  mkdir -p "$(dirname "$staging")"

  if [ "${1:-}" = from-backup ]; then
    [ "$#" -eq 2 ] || { echo "Usage: $0 from-backup /path/to/data.pg15-backup-<ts>" >&2; exit 1; }
    backup_path="$2"
    docker compose -f "$COMPOSE_FILE" stop "$APP_CONTAINER" "$CONTAINER" >/dev/null 2>&1 || true
    dump_from_pg15_backup "$backup_path" "$staging"
    wipe_storage
  else
    backup_path="$(snapshot_and_dump "$staging")"
    wipe_storage
  fi

  start_pg18
  restore_into_pg18 "$staging"
  start_openproject

  echo ""
  echo "=== Done: openproject-postgres is on PostgreSQL 18 ==="
  echo "PG15 backup: $backup_path"
  echo "Verify: ./docker/verify-openproject-postgres-upgrade.sh $backup_path"
}

main "$@"
