#!/usr/bin/env bash
# Verify openproject PG15 backup vs openproject-postgres on PG18.
#
# Usage:
#   ./docker/verify-openproject-postgres-upgrade.sh /path/to/data.pg15-backup-<ts>
#   ./docker/verify-openproject-postgres-upgrade.sh --pg15-container pg15-verify-openproject

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_NAME="openproject"
DB_USER="openproject"
DB_PASSWORD="${OPENPROJECT_DB_PASSWORD:-openproject}"
PG18="openproject-postgres"
SIDECAR_TRIES="${VERIFY_SIDECAR_TRIES:-120}"

usage() {
  echo "Usage: $0 <backup-path>|--pg15-container <name> [--keep-sidecar]" >&2
  exit 1
}

wait_for_postgres() {
  local container="$1" tries="$2"
  while [ "$tries" -gt 0 ]; do
    if docker exec -e PGPASSWORD="$DB_PASSWORD" "$container" \
      psql -U "$DB_USER" -d postgres -tAc 'SELECT 1' >/dev/null 2>&1; then
      return 0
    fi
    tries=$((tries - 1))
    sleep 2
  done
  return 1
}

start_sidecar() {
  local backup_path="$1"
  local sidecar="pg15-verify-openproject-$$"
  docker run -d --name "$sidecar" \
    -v "${backup_path}:/var/lib/postgresql/data" \
    -e POSTGRES_PASSWORD="$DB_PASSWORD" \
    -e POSTGRES_USER="$DB_USER" \
    -e POSTGRES_DB="$DB_NAME" \
    postgres:15 >/dev/null
  wait_for_postgres "$sidecar" "$SIDECAR_TRIES" || {
    docker rm -f "$sidecar" >/dev/null 2>&1 || true
    echo "ERROR: sidecar failed" >&2
    exit 1
  }
  echo "$sidecar"
}

export_object_ids() {
  local container="$1" outfile="$2"
  docker exec -e PGPASSWORD="$DB_PASSWORD" "$container" psql -U "$DB_USER" -d "$DB_NAME" -At -F $'\t' -c "
SELECT kind, nspname, name
FROM (
  SELECT 'schema' AS kind, nspname::text, ''::text AS name
  FROM pg_namespace WHERE nspname NOT IN ('pg_catalog','information_schema','pg_toast') AND nspname NOT LIKE 'pg_%'
  UNION ALL
  SELECT CASE c.relkind WHEN 'r' THEN CASE WHEN c.relispartition THEN 'partition' ELSE 'table' END
                      WHEN 'p' THEN 'partitioned_table' WHEN 'v' THEN 'view' WHEN 'm' THEN 'matview'
                      WHEN 'S' THEN 'sequence' ELSE 'other:'||c.relkind::text END,
         n.nspname::text, c.relname::text
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname NOT IN ('pg_catalog','information_schema','pg_toast') AND n.nspname NOT LIKE 'pg_%'
  UNION ALL
  SELECT 'index', n.nspname::text, c.relname::text
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE c.relkind='i' AND n.nspname NOT LIKE 'pg_%'
) s ORDER BY 1,2,3;" >"$outfile"
}

compare_row_counts() {
  local pg15="$1" pg18="$2"
  local mismatches=0 total=0
  while IFS='|' read -r schema table; do
    total=$((total + 1))
    local c15 c18
    c15="$(docker exec -e PGPASSWORD="$DB_PASSWORD" "$pg15" psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT count(*) FROM \"${schema}\".\"${table}\"")"
    c18="$(docker exec -e PGPASSWORD="$DB_PASSWORD" "$pg18" psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT count(*) FROM \"${schema}\".\"${table}\"")"
    if [ "$c15" != "$c18" ]; then
      echo "MISMATCH ${schema}.${table}  PG15=$c15  PG18=$c18"
      mismatches=$((mismatches + 1))
    fi
  done < <(docker exec -e PGPASSWORD="$DB_PASSWORD" "$pg15" psql -U "$DB_USER" -d "$DB_NAME" -At -c "
    SELECT schemaname, relname FROM pg_stat_user_tables WHERE schemaname NOT LIKE 'pg_%' ORDER BY 1,2;")
  echo "  row counts: $total tables, $mismatches mismatches"
  [ "$mismatches" -eq 0 ]
}

spot_check_openproject() {
  local pg18="$1"
  echo "=== OpenProject spot checks (PG18) ==="
  docker exec -e PGPASSWORD="$DB_PASSWORD" "$pg18" psql -U "$DB_USER" -d "$DB_NAME" -c "
SELECT 'users' AS entity, count(*)::text AS n FROM users
UNION ALL SELECT 'projects', count(*)::text FROM projects
UNION ALL SELECT 'work_packages', count(*)::text FROM work_packages
UNION ALL SELECT 'journals', count(*)::text FROM journals
ORDER BY 1;"
}

main() {
  local backup_path="" pg15="" keep_sidecar=false started=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --pg15-container) pg15="$2"; shift ;;
      --keep-sidecar) keep_sidecar=true ;;
      -h|--help) usage ;;
      *) backup_path="$1" ;;
    esac
    shift
  done

  [ -n "$backup_path" ] || [ -n "$pg15" ] || usage
  docker ps --format '{{.Names}}' | grep -qx "$PG18" || { echo "ERROR: $PG18 not running" >&2; exit 1; }

  if [ -n "$backup_path" ]; then
    started="$(start_sidecar "$backup_path")"
    pg15="$started"
  fi

  trap 'if [ -n "${started:-}" ] && ! $keep_sidecar; then docker rm -f "$started" >/dev/null 2>&1 || true; fi' EXIT

  local tmp failed=0
  tmp="$(mktemp -d)"
  export_object_ids "$pg15" "$tmp/pg15.tsv"
  export_object_ids "$PG18" "$tmp/pg18.tsv"

  echo "=== Catalog objects ==="
  echo "  PG15: $(sort -u "$tmp/pg15.tsv" | wc -l | tr -d ' ')"
  echo "  PG18: $(sort -u "$tmp/pg18.tsv" | wc -l | tr -d ' ')"
  if ! diff -q <(sort -u "$tmp/pg15.tsv") <(sort -u "$tmp/pg18.tsv") >/dev/null; then
    echo "  DIFFERENCES:"
    comm -3 <(sort -u "$tmp/pg15.tsv") <(sort -u "$tmp/pg18.tsv") | head -20
    failed=1
  else
    echo "  identical"
  fi

  if ! compare_row_counts "$pg15" "$PG18"; then failed=1; fi
  spot_check_openproject "$PG18"
  docker exec -e PGPASSWORD="$DB_PASSWORD" "$PG18" postgres --version

  rm -rf "$tmp"
  if [ "$failed" -eq 0 ]; then
    echo "=== PASS: openproject PG15 and PG18 match ==="
  else
    echo "=== FAIL: differences found ===" >&2
    exit 1
  fi
}

main "$@"
