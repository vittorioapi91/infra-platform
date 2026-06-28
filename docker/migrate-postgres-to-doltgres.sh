#!/usr/bin/env bash
# Logical copy: Postgres datalake -> Doltgres datalake (per env).
# Reads from postgres-{env} only; writes only to storage-doltgres/{env}.
# Does NOT modify storage-postgresql/ or postgres-* containers/data.
#
# Usage (from repo root):
#   ./docker/migrate-postgres-to-doltgres.sh test
#   ./docker/migrate-postgres-to-doltgres.sh all
#   POSTGRES_PASSWORD=postgres ./docker/migrate-postgres-to-doltgres.sh dev
#
# Dev (~100GB+) can take many hours; dump staging uses repo/docker/.migration-staging/.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/docker/docker-compose.infra-platform.yml"
STAGING_DIR="$REPO_ROOT/docker/.migration-staging"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-2014}"
JOBS="${MIGRATION_JOBS:-4}"

SCHEMAS=(
  bis bls census edgar eurostat fred imf nasdaqtrader polymarket
  postgres public ishares yfinance
)

usage() {
  echo "Usage: $0 {dev|test|prod|all}" >&2
  exit 1
}

require_container() {
  local name="$1"
  if ! docker ps --format '{{.Names}}' | grep -qx "$name"; then
    echo "ERROR: container $name is not running." >&2
    exit 1
  fi
}

wait_for_doltgres() {
  local container="$1"
  local tries=60
  while [ "$tries" -gt 0 ]; do
    if docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container" \
      psql -h 127.0.0.1 -U postgres -d datalake -tAc 'SELECT 1' >/dev/null 2>&1; then
      return 0
    fi
    tries=$((tries - 1))
    sleep 2
  done
  echo "ERROR: $container did not become ready." >&2
  exit 1
}

reset_doltgres_storage() {
  local env="$1"
  local container="doltgres-$env"
  local storage="$REPO_ROOT/storage-doltgres/$env"

  echo "=== Reset Doltgres storage for $env (postgres data untouched) ==="
  docker compose -f "$COMPOSE_FILE" stop "$container" >/dev/null
  find "$storage" -mindepth 1 ! -name '.gitkeep' -delete 2>/dev/null || true
  docker compose -f "$COMPOSE_FILE" up -d "$container" >/dev/null
  wait_for_doltgres "$container"
  echo "Doltgres $env restarted with empty Dolt storage."
}

filter_pg_dump_sql() {
  grep -v '^ALTER DEFAULT PRIVILEGES' \
    | grep -v '^ALTER USER .* SET search_path' \
    | sed -E 's/^CREATE SCHEMA ([^;]+);/CREATE SCHEMA IF NOT EXISTS \1;/'
}

schema_dump_flags() {
  local flags=()
  local schema
  for schema in "${SCHEMAS[@]}"; do
    flags+=(-n "$schema")
  done
  printf '%s\n' "${flags[@]}"
}

dump_schema_sql() {
  local pg_container="$1"
  local out="$2"
  local -a schema_flags
  mapfile -t schema_flags < <(schema_dump_flags)

  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$pg_container" \
    pg_dump -U postgres -d datalake \
    --schema-only --no-owner --no-acl \
    "${schema_flags[@]}" \
    | filter_pg_dump_sql >"$out"
}

dump_data_custom() {
  local pg_container="$1"
  local dump_dir="$2"
  local -a schema_flags
  mapfile -t schema_flags < <(schema_dump_flags)

  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$pg_container" \
    pg_dump -U postgres -d datalake \
    --data-only --no-owner --no-acl -Fd -j "$JOBS" \
    "${schema_flags[@]}" \
    -f "/tmp/doltgres-migrate-data"

  rm -rf "$dump_dir"
  mkdir -p "$dump_dir"
  docker cp "$pg_container:/tmp/doltgres-migrate-data/." "$dump_dir/"
  docker exec "$pg_container" rm -rf /tmp/doltgres-migrate-data
}

restore_schema_sql() {
  local dolt_container="$1"
  local sql_file="$2"
  docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" "$dolt_container" \
    psql -h 127.0.0.1 -U postgres -d datalake -v ON_ERROR_STOP=1 <"$sql_file"
}

restore_data_custom() {
  local dolt_container="$1"
  local dump_dir="$2"
  docker cp "$dump_dir/." "$dolt_container:/tmp/doltgres-migrate-data/"
  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$dolt_container" \
    pg_restore -h 127.0.0.1 -U postgres -d datalake \
    --no-owner --no-acl --disable-triggers -j "$JOBS" \
    /tmp/doltgres-migrate-data
  docker exec "$dolt_container" rm -rf /tmp/doltgres-migrate-data
}

ensure_app_user() {
  local env="$1"
  local dolt_container="doltgres-$env"
  local app_user
  case "$env" in
    dev) app_user='dev.user' ;;
    test) app_user='test.user' ;;
    prod) app_user='prod.user' ;;
    *) echo "unknown env $env" >&2; exit 1 ;;
  esac

  set +e
  create_out=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$dolt_container" \
    psql -h 127.0.0.1 -U postgres -d datalake -v ON_ERROR_STOP=1 \
    -c "CREATE USER \"$app_user\" WITH PASSWORD '$POSTGRES_PASSWORD' LOGIN CREATEDB;" 2>&1)
  create_status=$?
  set -e
  if [ "$create_status" -ne 0 ]; then
    echo "$create_out" | grep -qi 'already exists' || {
      echo "$create_out" >&2
      exit 1
    }
  fi

  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$dolt_container" \
    psql -h 127.0.0.1 -U postgres -d datalake -v ON_ERROR_STOP=1 <<-EOSQL
GRANT USAGE ON SCHEMA postgres, polymarket, edgar, nasdaqtrader, ishares, fred, bls, bis, eurostat, imf, yfinance, public, census TO "$app_user";
GRANT CREATE ON SCHEMA postgres, polymarket, edgar, nasdaqtrader, ishares, fred, bls, bis, eurostat, imf, yfinance, public, census TO "$app_user";
GRANT ALL ON ALL TABLES IN SCHEMA postgres, polymarket, edgar, nasdaqtrader, ishares, fred, bls, bis, eurostat, imf, yfinance, public, census TO "$app_user";
GRANT ALL ON ALL SEQUENCES IN SCHEMA postgres, polymarket, edgar, nasdaqtrader, ishares, fred, bls, bis, eurostat, imf, yfinance, public, census TO "$app_user";
EOSQL
}

compare_table_counts() {
  local pg_container="$1"
  local dolt_container="$2"
  echo "=== Row-count spot check (postgres vs doltgres) ==="
  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$pg_container" \
    psql -U postgres -d datalake -tAc "
      SELECT schemaname||'.'||relname
      FROM pg_stat_user_tables
      WHERE schemaname NOT IN ('pg_catalog','information_schema','dolt')
      ORDER BY n_live_tup DESC
      LIMIT 5;
    " | while read -r qualified; do
    [ -z "$qualified" ] && continue
    local schema="${qualified%%.*}"
    local table="${qualified#*.}"
    local pg_count dolt_count
    pg_count=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$pg_container" \
      psql -U postgres -d datalake -tAc "SELECT COUNT(*) FROM \"$schema\".\"$table\";" 2>/dev/null || echo ERR)
    dolt_count=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$dolt_container" \
      psql -h 127.0.0.1 -U postgres -d datalake -tAc "SELECT COUNT(*) FROM \"$schema\".\"$table\";" 2>/dev/null || echo ERR)
    echo "  $qualified: postgres=$pg_count doltgres=$dolt_count"
  done
}

migrate_env() {
  local env="$1"
  local pg_container="postgres-$env"
  local dolt_container="doltgres-$env"
  local work="$STAGING_DIR/$env"
  local schema_sql="$work/schema.sql"
  local data_dir="$work/data"

  echo ""
  echo "################################################################"
  echo "# Migrating $env: $pg_container -> $dolt_container"
  echo "################################################################"

  require_container "$pg_container"
  require_container "$dolt_container"

  local db_size
  db_size=$(docker exec "$pg_container" psql -U postgres -d datalake -tAc \
    "SELECT pg_size_pretty(pg_database_size('datalake'));")
  echo "Postgres datalake size: $db_size"

  reset_doltgres_storage "$env"
  mkdir -p "$work"

  echo "=== Schema dump + restore ==="
  dump_schema_sql "$pg_container" "$schema_sql"
  restore_schema_sql "$dolt_container" "$schema_sql"

  echo "=== Data dump + restore (parallel jobs=$JOBS) ==="
  dump_data_custom "$pg_container" "$data_dir"
  restore_data_custom "$dolt_container" "$data_dir"

  ensure_app_user "$env"
  compare_table_counts "$pg_container" "$dolt_container"

  echo "=== Done: $env migrated to storage-doltgres/$env ==="
}

main() {
  local target="${1:-}"
  [ -n "$target" ] || usage

  mkdir -p "$STAGING_DIR"
  echo "Postgres folders are read-only for this script; only storage-doltgres/ is written."
  echo "postgres-* containers stay running."

  case "$target" in
    dev|test|prod) migrate_env "$target" ;;
    all)
      migrate_env test
      migrate_env prod
      migrate_env dev
      ;;
    *) usage ;;
  esac
}

main "$@"
