#!/usr/bin/env bash
# Compare PG15 backup (or running PG15 container) vs postgres-{env} on PG18.
#
# Checks catalog objects, partition tree, view definitions, and row counts
# for every user table/partition in datalake.
#
# Usage (from repo root):
#   ./docker/verify-postgres-upgrade.sh dev /path/to/dev.pg15-backup-<timestamp>
#   ./docker/verify-postgres-upgrade.sh dev --pg15-container pg15-verify-dev
#
# Requires postgres-{env} (PG18) running. Starts a temporary PG15 sidecar when
# a backup path is given; removes it on exit unless --keep-sidecar.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-2014}"
SIDECAR_TRIES="${VERIFY_SIDECAR_TRIES:-900}"

usage() {
  echo "Usage: $0 {dev|test|prod} <backup-path>|--pg15-container <name> [--keep-sidecar]" >&2
  exit 1
}

resolve_storage_path() {
  local env="$1"
  python3 -c "import os; print(os.path.realpath('${REPO_ROOT}/storage-postgresql/${env}'))"
}

wait_for_postgres() {
  local container="$1"
  local tries="$2"
  while [ "$tries" -gt 0 ]; do
    if docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container" \
      psql -U postgres -d postgres -tAc 'SELECT 1' >/dev/null 2>&1; then
      return 0
    fi
    tries=$((tries - 1))
    sleep 2
  done
  return 1
}

start_pg15_sidecar() {
  local env="$1"
  local backup_path="$2"
  local sidecar="pg15-verify-${env}-$$"

  if [ ! -f "$backup_path/PG_VERSION" ]; then
    echo "ERROR: not a PostgreSQL data directory: $backup_path" >&2
    exit 1
  fi
  local pg_ver
  pg_ver="$(tr -d '[:space:]' <"$backup_path/PG_VERSION")"
  if [ "$pg_ver" != "15" ]; then
    echo "ERROR: expected PG15 backup, found PG_VERSION=$pg_ver" >&2
    exit 1
  fi

  echo "=== Starting PG15 sidecar: $sidecar ==="
  docker run -d --name "$sidecar" \
    -v "${backup_path}:/var/lib/postgresql/data" \
    -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
    pgvector/pgvector:pg15 >/dev/null

  echo "  waiting for sidecar (up to $((SIDECAR_TRIES * 2 / 60)) min)..."
  if ! wait_for_postgres "$sidecar" "$SIDECAR_TRIES"; then
    docker rm -f "$sidecar" >/dev/null 2>&1 || true
    echo "ERROR: sidecar $sidecar did not become ready." >&2
    exit 1
  fi
  echo "$sidecar"
}

export_catalog_objects() {
  local container="$1"
  local outfile="$2"
  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container" psql -U postgres -d datalake -At -F $'\t' -c "
SELECT kind, nspname, name, COALESCE(extra, '')
FROM (
  SELECT 'schema' AS kind, nspname::text AS nspname, ''::text AS name, ''::text AS extra
  FROM pg_namespace
  WHERE nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
    AND nspname NOT LIKE 'pg_%'

  UNION ALL
  SELECT CASE c.relkind
           WHEN 'r' THEN CASE WHEN c.relispartition THEN 'partition' ELSE 'table' END
           WHEN 'p' THEN 'partitioned_table'
           WHEN 'v' THEN 'view'
           WHEN 'm' THEN 'matview'
           WHEN 'S' THEN 'sequence'
           WHEN 'f' THEN 'foreign_table'
           ELSE 'other:' || c.relkind::text
         END,
         n.nspname::text, c.relname::text,
         COALESCE(CASE WHEN c.relkind IN ('r','p') THEN pg_size_pretty(pg_total_relation_size(c.oid)) END, '')
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
    AND n.nspname NOT LIKE 'pg_%'

  UNION ALL
  SELECT 'index', n.nspname::text, c.relname::text, ''
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relkind = 'i'
    AND n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
    AND n.nspname NOT LIKE 'pg_%'
) s
ORDER BY 1, 2, 3;" >"$outfile"
}

export_partition_tree() {
  local container="$1"
  local outfile="$2"
  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container" psql -U postgres -d datalake -At -F $'\t' -c "
SELECT n.nspname, parent.relname, child.relname
FROM pg_inherits i
JOIN pg_class child ON child.oid = i.inhrelid
JOIN pg_class parent ON parent.oid = i.inhparent
JOIN pg_namespace n ON n.oid = child.relnamespace
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY 1, 2, 3;" >"$outfile"
}

export_view_definitions() {
  local container="$1"
  local outfile="$2"
  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container" psql -U postgres -d datalake -At -c "
SELECT n.nspname || '.' || c.relname || '|' || pg_get_viewdef(c.oid, true)
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'v'
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY 1;" >"$outfile"
}

compare_row_counts() {
  local pg15="$1"
  local pg18="$2"
  local mismatches=0
  local total=0

  echo "=== Row counts (all user tables/partitions) ==="
  while IFS='|' read -r schema table; do
    total=$((total + 1))
    local c15 c18
    c15="$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$pg15" \
      psql -U postgres -d datalake -tAc "SELECT count(*) FROM \"${schema}\".\"${table}\"")"
    c18="$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$pg18" \
      psql -U postgres -d datalake -tAc "SELECT count(*) FROM \"${schema}\".\"${table}\"")"
    if [ "$c15" != "$c18" ]; then
      echo "MISMATCH ${schema}.${table}  PG15=$c15  PG18=$c18"
      mismatches=$((mismatches + 1))
    fi
  done < <(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$pg15" psql -U postgres -d datalake -At -c "
    SELECT schemaname, relname
    FROM pg_stat_user_tables
    WHERE schemaname NOT LIKE 'pg_%'
    ORDER BY schemaname, relname;")

  echo "  scanned: $total relations, mismatches: $mismatches"
  [ "$mismatches" -eq 0 ]
}

run_verification() {
  local env="$1"
  local pg15="$2"
  local pg18="postgres-${env}"
  local tmp
  tmp="$(mktemp -d)"
  local failed=0

  if ! docker ps --format '{{.Names}}' | grep -qx "$pg18"; then
    echo "ERROR: $pg18 is not running." >&2
    exit 1
  fi

  echo ""
  echo "################################################################"
  echo "# Verifying $env: PG15 ($pg15) vs PG18 ($pg18)"
  echo "################################################################"

  export_catalog_objects "$pg15" "$tmp/pg15-catalog.tsv"
  export_catalog_objects "$pg18" "$tmp/pg18-catalog.tsv"

  echo "=== Catalog objects (kind / schema / name) ==="
  cut -f1-3 "$tmp/pg15-catalog.tsv" | sort -u >"$tmp/pg15-ids.tsv"
  cut -f1-3 "$tmp/pg18-catalog.tsv" | sort -u >"$tmp/pg18-ids.tsv"
  echo "  PG15: $(wc -l <"$tmp/pg15-ids.tsv" | tr -d ' ') objects"
  echo "  PG18: $(wc -l <"$tmp/pg18-ids.tsv" | tr -d ' ') objects"
  echo "  only in PG15:"
  comm -23 "$tmp/pg15-ids.tsv" "$tmp/pg18-ids.tsv" | sed 's/^/    /' || true
  echo "  only in PG18:"
  comm -13 "$tmp/pg15-ids.tsv" "$tmp/pg18-ids.tsv" | sed 's/^/    /' || true
  if comm -23 "$tmp/pg15-ids.tsv" "$tmp/pg18-ids.tsv" | grep -q .; then
    failed=1
  fi

  echo "=== Object counts by kind ==="
  echo -n "  PG15: "; cut -f1 "$tmp/pg15-catalog.tsv" | sort | uniq -c | sort -k2 | tr '\n' ' '; echo
  echo -n "  PG18: "; cut -f1 "$tmp/pg18-catalog.tsv" | sort | uniq -c | sort -k2 | tr '\n' ' '; echo

  export_partition_tree "$pg15" "$tmp/pg15-partitions.tsv"
  export_partition_tree "$pg18" "$tmp/pg18-partitions.tsv"
  echo "=== Partition inheritance tree ==="
  if diff -q "$tmp/pg15-partitions.tsv" "$tmp/pg18-partitions.tsv" >/dev/null; then
    echo "  identical ($(wc -l <"$tmp/pg15-partitions.tsv" | tr -d ' ') rows)"
  else
    echo "  DIFFER"
    diff "$tmp/pg15-partitions.tsv" "$tmp/pg18-partitions.tsv" | head -20 || true
    failed=1
  fi

  export_view_definitions "$pg15" "$tmp/pg15-views.txt"
  export_view_definitions "$pg18" "$tmp/pg18-views.txt"
  echo "=== View definitions ==="
  if diff -q "$tmp/pg15-views.txt" "$tmp/pg18-views.txt" >/dev/null; then
    echo "  identical ($(wc -l <"$tmp/pg15-views.txt" | tr -d ' ') app views)"
  else
  if diff -q \
    <(sed 's/|.*//' "$tmp/pg15-views.txt" | sort) \
    <(sed 's/|.*//' "$tmp/pg18-views.txt" | sort) >/dev/null; then
    echo "  same view names (definition formatting may differ)"
  else
    echo "  view name DIFFER"
    failed=1
  fi
  fi

  if ! compare_row_counts "$pg15" "$pg18"; then
    failed=1
  fi

  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$pg18" postgres --version
  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$pg18" \
    psql -U postgres -d datalake -tAc "SELECT pg_size_pretty(pg_database_size('datalake'));"

  rm -rf "$tmp"

  echo ""
  if [ "$failed" -eq 0 ]; then
    echo "=== PASS: $env PG15 and PG18 datalake match ==="
    return 0
  fi
  echo "=== FAIL: differences found for $env ===" >&2
  return 1
}

main() {
  local env="" backup_path="" pg15_container="" keep_sidecar=false
  local started_sidecar=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      dev|test|prod) env="$1" ;;
      --pg15-container) pg15_container="$2"; shift ;;
      --keep-sidecar) keep_sidecar=true ;;
      -h|--help) usage ;;
      *)
        if [ -z "$backup_path" ] && [ "${1:0:2}" != "--" ]; then
          backup_path="$1"
        else
          usage
        fi
        ;;
    esac
    shift
  done

  [ -n "$env" ] || usage
  [ -n "$backup_path" ] || [ -n "$pg15_container" ] || usage

  if [ -n "$backup_path" ]; then
    started_sidecar="$(start_pg15_sidecar "$env" "$backup_path")"
    pg15_container="$started_sidecar"
  fi

  if ! docker ps --format '{{.Names}}' | grep -qx "$pg15_container"; then
    echo "ERROR: PG15 container not running: $pg15_container" >&2
    exit 1
  fi

  trap 'if [ -n "${started_sidecar:-}" ] && ! $keep_sidecar; then docker rm -f "$started_sidecar" >/dev/null 2>&1 || true; fi' EXIT

  run_verification "$env" "$pg15_container"
}

main "$@"
