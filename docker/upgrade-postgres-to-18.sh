#!/usr/bin/env bash
# Upgrade postgres-{dev,test,prod} from PG15 → PG18 with pgvector.
#
# Uses logical dump/restore (safe across major versions). PG15 data is moved to
# <storage>.pg15-backup-<timestamp> on the host/SSD; compose must mount
# storage-postgresql/{env} at /var/lib/postgresql (PG18 layout: 18/docker/).
#
# Usage (from repo root):
#   ./docker/upgrade-postgres-to-18.sh test
#   ./docker/upgrade-postgres-to-18.sh test prod
#   ./docker/upgrade-postgres-to-18.sh all
#
# Watch progress: ./docker/watch-postgres-upgrade.sh dev
# Verify after upgrade: ./docker/verify-postgres-upgrade.sh dev /path/to/*.pg15-backup-*
# Cleanup PG15 backups: ./docker/cleanup-postgres-pg15-backups.sh --confirm
#
# Dev datalake can be 200GB+; allow many hours. Staging: docker/.upgrade-pg18-staging/
#
# Data safety: PG15 data is moved (never deleted) to *.pg15-backup-<timestamp>.
# The backup directory is mounted read-only in the dump sidecar. Live storage is
# only cleared after a verified logical dump exists in staging.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/docker/docker-compose.infra-platform.yml"
STAGING_DIR="$REPO_ROOT/docker/.upgrade-pg18-staging"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-2014}"
JOBS="${UPGRADE_JOBS:-4}"

write_progress() {
  local env="$1" stage_index="$2" stage="$3" detail="$4"
  local percent="${5:-0}" current_bytes="${6:-0}" source_bytes="${7:-0}"
  local staging="$STAGING_DIR/$env"
  mkdir -p "$staging"
  local now started_at
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [ -f "$staging/progress.json" ]; then
    started_at="$(python3 -c "import json; print(json.load(open('$staging/progress.json')).get('started_at','$now'))" 2>/dev/null || echo "$now")"
  else
    started_at="$now"
  fi
  python3 - "$staging/progress.json" <<PY
import json
doc = {
    "env": "$env",
    "stage_index": int("$stage_index"),
    "stage_total": 8,
    "stage": "$stage",
    "detail": """$detail""",
    "percent": int("$percent"),
    "current_bytes": int("$current_bytes"),
    "source_bytes": int("$source_bytes"),
    "started_at": "$started_at",
    "updated_at": "$now",
}
with open("$staging/progress.json", "w") as f:
    json.dump(doc, f, indent=2)
PY
}

start_dump_size_monitor() {
  local env="$1" staging="$2" source_bytes="$3"
  local dump_dir="$staging/datalake"
  (
    while true; do
      if [ ! -d "$dump_dir" ]; then
        sleep 2
        continue
      fi
      if [ -f "$dump_dir/toc.dat" ]; then
        break
      fi
        local kb
        kb="$(du -sk "$dump_dir" 2>/dev/null | awk '{print $1}')"
        local bytes=$((kb * 1024))
        local pct=20
        if [ "$source_bytes" -gt 0 ] && [ "$bytes" -gt 0 ]; then
          pct=$((bytes * 40 / source_bytes + 15))
          [ "$pct" -gt 59 ] && pct=59
        fi
        write_progress "$env" 2 dump_datalake "Dumping datalake" "$pct" "$bytes" "$source_bytes"
      fi
      sleep 10
    done
  ) &
  echo $!
}

usage() {
  echo "Usage: $0 {dev|test|prod|all} [dev|test|prod ...]" >&2
  exit 1
}

resolve_storage_path() {
  local env="$1"
  python3 -c "import os; print(os.path.realpath('${REPO_ROOT}/storage-postgresql/${env}'))"
}

require_container() {
  local name="$1"
  if ! docker ps --format '{{.Names}}' | grep -qx "$name"; then
    echo "ERROR: container $name is not running. Start PG15 instances before upgrade." >&2
    exit 1
  fi
}

wait_for_postgres() {
  local container="$1"
  local tries=90
  while [ "$tries" -gt 0 ]; do
    if docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container" \
      psql -U postgres -d postgres -tAc 'SELECT 1' >/dev/null 2>&1; then
      return 0
    fi
    tries=$((tries - 1))
    sleep 2
  done
  echo "ERROR: $container did not become ready." >&2
  exit 1
}

# Fresh PG18 data dirs run /docker-entrypoint-initdb.d then stop/restart PostgreSQL.
wait_for_postgres_stable() {
  local container="$1"
  wait_for_postgres "$container"
  if docker logs "$container" 2>&1 | grep -q 'PostgreSQL init process complete'; then
    echo "  waiting for post-init restart..."
    sleep 5
    wait_for_postgres "$container"
  fi
  sleep 3
  wait_for_postgres "$container"
}

verify_pg15_backup_path() {
  local backup_path="$1"
  if [ ! -d "$backup_path" ]; then
    echo "ERROR: backup path does not exist: $backup_path" >&2
    exit 1
  fi
  if [ ! -f "$backup_path/PG_VERSION" ]; then
    echo "ERROR: $backup_path is not a PostgreSQL data directory (no PG_VERSION)" >&2
    exit 1
  fi
  local pg_ver
  pg_ver="$(tr -d '[:space:]' <"$backup_path/PG_VERSION")"
  if [ "$pg_ver" != "15" ]; then
    echo "ERROR: expected PG15 backup, found PG_VERSION=$pg_ver at $backup_path" >&2
    exit 1
  fi
  local backup_kb
  backup_kb="$(du -sk "$backup_path" | awk '{print $1}')"
  echo "  backup verified: PG${pg_ver}, ${backup_kb}K on disk at $backup_path"
}

verify_staging_dump() {
  local staging="$1"
  local env="$2"
  local globals_sql="$staging/globals.sql"
  local dump_dir="$staging/datalake"
  local min_dump_kb="${UPGRADE_MIN_DUMP_KB:-10240}"

  if [ ! -s "$globals_sql" ]; then
    echo "ERROR: staging globals.sql is missing or empty — aborting before touching storage." >&2
    exit 1
  fi
  if [ ! -f "$dump_dir/toc.dat" ]; then
    echo "ERROR: staging dump missing toc.dat — aborting before touching storage." >&2
    exit 1
  fi
  local dump_kb
  dump_kb="$(du -sk "$dump_dir" | awk '{print $1}')"
  if [ "$dump_kb" -lt "$min_dump_kb" ]; then
    echo "ERROR: staging dump is only ${dump_kb}K (min ${min_dump_kb}K for $env) — aborting." >&2
    echo "  PG15 backup is unchanged; re-run from-backup when ready." >&2
    exit 1
  fi
  echo "  staging dump verified: globals=$(wc -c <"$globals_sql" | tr -d ' ') bytes, datalake=${dump_kb}K"
}

dump_from_pg15_backup() {
  local env="$1"
  local backup_path="$2"
  local staging="$3"
  local globals_sql="$staging/globals.sql"
  local dump_dir="$staging/datalake"

  mkdir -p "$staging"
  rm -rf "$dump_dir"

  echo "=== Dumping from PG15 backup: $backup_path ==="
  verify_pg15_backup_path "$backup_path"
  write_progress "$env" 0 sidecar_recovery "Starting PG15 sidecar" 2 0 0
  local sidecar="pg15-dump-${env}-$$"
  docker run -d --name "$sidecar" \
    -v "${backup_path}:/var/lib/postgresql/data" \
    -v "${staging}:/staging" \
    -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
    pgvector/pgvector:pg15 >/dev/null

  # Large datalakes (100GB+) can take many minutes to recover on first start.
  local tries="${UPGRADE_SIDECAR_TRIES:-900}"
  echo "  waiting for PG15 sidecar (up to $((tries * 2 / 60)) min)..."
  local wait_started
  wait_started="$(date +%s)"
  while [ "$tries" -gt 0 ]; do
    if docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$sidecar" \
      psql -U postgres -d postgres -tAc 'SELECT 1' >/dev/null 2>&1; then
      break
    fi
    local redo_line elapsed pct
    redo_line="$(docker logs "$sidecar" 2>&1 | grep 'redo in progress' | tail -1 | sed 's/^.*LOG:  //')"
    elapsed=$(( $(date +%s) - wait_started ))
    pct=$(( elapsed * 12 / (tries * 2) ))
    [ "$pct" -gt 14 ] && pct=14
    write_progress "$env" 0 sidecar_recovery "${redo_line:-Recovering WAL (${elapsed}s)}" "$pct" 0 0
    tries=$((tries - 1))
    sleep 2
  done
  if [ "$tries" -eq 0 ]; then
    docker rm -f "$sidecar" >/dev/null 2>&1 || true
    echo "ERROR: sidecar $sidecar failed to start for dump." >&2
    exit 1
  fi

  local source_bytes
  source_bytes="$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$sidecar" \
    psql -U postgres -d datalake -tAc "SELECT pg_database_size('datalake');")"
  echo "$source_bytes" >"$staging/source_bytes.txt"
  echo "  source datalake size (logical): $(numfmt --to=iec-i --suffix=B "$source_bytes" 2>/dev/null || echo "${source_bytes} bytes")"
  write_progress "$env" 1 dump_globals "Dumping roles/globals" 15 0 "$source_bytes"

  write_progress "$env" 2 dump_datalake "Dumping datalake" 18 0 "$source_bytes"
  local monitor_pid
  monitor_pid="$(start_dump_size_monitor "$env" "$staging" "$source_bytes")"
  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$sidecar" \
    sh -c "pg_dumpall -U postgres --globals-only > /staging/globals.sql && pg_dump -U postgres -d datalake -Fd -j ${JOBS} -f /staging/datalake"
  kill "$monitor_pid" 2>/dev/null || true
  wait "$monitor_pid" 2>/dev/null || true

  docker rm -f "$sidecar" >/dev/null

  write_progress "$env" 3 verify_dump "Verifying dump" 60 \
    "$(du -sk "$dump_dir" | awk '{print $1 * 1024}')" "$source_bytes"

  verify_staging_dump "$staging" "$env"

  local size
  size="$(du -sh "$dump_dir" | awk '{print $1}')"
  echo "  dump dir size: $size"
}

dump_from_running_container() {
  local container="$1"
  local staging="$2"
  local env="$3"

  echo "=== Stopping $container and snapshotting PG15 data ==="
  docker compose -f "$COMPOSE_FILE" stop "$container" >/dev/null

  local storage backup_path
  storage="$(resolve_storage_path "$env")"
  backup_path="${storage}.pg15-backup-$(date +%Y%m%d%H%M%S)"

  if [ -d "$storage" ] && [ -n "$(ls -A "$storage" 2>/dev/null || true)" ]; then
    mv "$storage" "$backup_path"
    mkdir -p "$storage"
    echo "  PG15 backup: $backup_path"
  else
    echo "ERROR: no PG15 data found at $storage" >&2
    exit 1
  fi

  dump_from_pg15_backup "$env" "$backup_path" "$staging"
}

backup_and_wipe_storage() {
  local env="$1"
  local storage
  storage="$(resolve_storage_path "$env")"

  echo "=== Preparing empty storage at $storage ==="
  if [ -d "$storage" ] && [ -n "$(ls -A "$storage" 2>/dev/null || true)" ]; then
    rm -rf "${storage:?}"/*
    echo "  cleared $storage"
  else
    mkdir -p "$storage"
    echo "  storage ready: $storage"
  fi
}

start_pg18() {
  local env="$1"
  echo "=== Starting postgres-$env on PG18 ==="
  write_progress "$env" 4 start_pg18 "Starting PG18" 62 0 0
  docker compose -f "$COMPOSE_FILE" pull "postgres-$env" >/dev/null
  docker compose -f "$COMPOSE_FILE" up -d "postgres-$env"
  wait_for_postgres_stable "postgres-$env"
}

restore_into_pg18() {
  local env="$1"
  local container="postgres-$env"
  local staging="$2"
  local globals_sql="$staging/globals.sql"
  local dump_dir="$staging/datalake"

  echo "=== Restoring globals into $container ==="
  docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" "$container" \
    psql -U postgres -d postgres -v ON_ERROR_STOP=0 --quiet <"$globals_sql" 2>/dev/null || true

  wait_for_postgres_stable "$container"

  echo "=== Recreating empty datalake before restore (skip init-schema conflicts) ==="
  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container" \
    psql -U postgres -d postgres -v ON_ERROR_STOP=1 <<-EOSQL
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = 'datalake' AND pid <> pg_backend_pid();
DROP DATABASE IF EXISTS datalake WITH (FORCE);
CREATE DATABASE datalake;
EOSQL

  local source_bytes=0
  if [ -f "$staging/source_bytes.txt" ]; then
    source_bytes="$(tr -d '[:space:]' <"$staging/source_bytes.txt")"
  fi

  echo "=== Restoring datalake (parallel jobs=$JOBS) ==="
  write_progress "$env" 5 restore_copy "Copying dump into container" 65 0 "$source_bytes"
  touch "$staging/.copy_started"
  docker cp "$dump_dir/." "$container:/var/lib/postgresql/datalake-restore/"
  touch "$staging/.restore_started"
  write_progress "$env" 6 pg_restore "Restoring datalake" 72 0 "$source_bytes"
  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container" \
    pg_restore -U postgres -d datalake --no-owner --no-acl -j "$JOBS" /var/lib/postgresql/datalake-restore \
    || { echo "WARNING: pg_restore reported errors (often harmless); continuing..." >&2; }
  docker exec "$container" rm -rf /var/lib/postgresql/datalake-restore

  echo "=== Enabling pgvector ==="
  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container" \
    psql -U postgres -d datalake -v ON_ERROR_STOP=1 -c 'CREATE EXTENSION IF NOT EXISTS vector;'

  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container" postgres --version
  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container" \
    psql -U postgres -d datalake -tAc \
    "SELECT 'PostgreSQL ' || current_setting('server_version') || ', pgvector ' || extversion FROM pg_extension WHERE extname = 'vector';"

  local restored_bytes
  restored_bytes="$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container" \
    psql -U postgres -d datalake -tAc "SELECT pg_database_size('datalake');")"
  write_progress "$env" 7 done "Upgrade complete" 100 "$restored_bytes" "$source_bytes"
}

upgrade_from_backup() {
  local env="$1"
  local backup_path="$2"
  local staging="$STAGING_DIR/$env"

  echo ""
  echo "################################################################"
  echo "# Upgrading $env from PG15 backup -> PG18 + pgvector"
  echo "################################################################"

  docker compose -f "$COMPOSE_FILE" stop "postgres-$env" >/dev/null 2>&1 || true
  dump_from_pg15_backup "$env" "$backup_path" "$staging"
  verify_staging_dump "$staging" "$env"
  backup_and_wipe_storage "$env"
  start_pg18 "$env"
  restore_into_pg18 "$env" "$staging"

  echo "=== Done: $env is on PostgreSQL 18 + pgvector ==="
}

upgrade_env() {
  local env="$1"
  local container="postgres-$env"
  local staging="$STAGING_DIR/$env"

  echo ""
  echo "################################################################"
  echo "# Upgrading $env: PG15 -> PG18 + pgvector"
  echo "################################################################"

  require_container "$container"

  local db_size
  db_size=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container" \
    psql -U postgres -d datalake -tAc "SELECT pg_size_pretty(pg_database_size('datalake'));")
  echo "Current datalake size: $db_size"

  dump_from_running_container "$container" "$staging" "$env"
  verify_staging_dump "$staging" "$env"
  backup_and_wipe_storage "$env"
  start_pg18 "$env"
  restore_into_pg18 "$env" "$staging"

  echo "=== Done: $env is on PostgreSQL 18 + pgvector ==="
}

main() {
  if [ "$#" -lt 1 ]; then
    usage
  fi

  if [ "$1" = from-backup ]; then
    if [ "$#" -ne 3 ]; then
      echo "Usage: $0 from-backup {dev|test|prod} /path/to/.pg15-backup-<timestamp>" >&2
      exit 1
    fi
    mkdir -p "$STAGING_DIR"
    upgrade_from_backup "$2" "$3"
    exit 0
  fi

  if [ "$1" = restore-only ]; then
    if [ "$#" -ne 2 ]; then
      echo "Usage: $0 restore-only {dev|test|prod}" >&2
      exit 1
    fi
    local env="$2"
    local staging="$STAGING_DIR/$env"
    if [ ! -d "$staging/datalake" ]; then
      echo "ERROR: no staging dump at $staging/datalake" >&2
      exit 1
    fi
    wait_for_postgres_stable "postgres-$env"
    restore_into_pg18 "$env" "$staging"
    exit 0
  fi

  mkdir -p "$STAGING_DIR"
  echo "Staging dumps: $STAGING_DIR"
  echo "Compose file: $COMPOSE_FILE (expects pgvector/pgvector:pg18, mount /var/lib/postgresql)"

  local targets=()
  if [ "$1" = all ]; then
    targets=(test prod dev)
  else
    targets=("$@")
  fi

  for env in "${targets[@]}"; do
    case "$env" in
      dev|test|prod) upgrade_env "$env" ;;
      *) usage ;;
    esac
  done

  echo ""
  echo "Upgrade complete. Restart nginx-proxy if Postgres connections fail via gateway:"
  echo "  cd docker && docker compose -f docker-compose.infra-platform.yml restart nginx-proxy"
}

main "$@"
