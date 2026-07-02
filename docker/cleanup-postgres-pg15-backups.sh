#!/usr/bin/env bash
# Remove PG15 datalake leftovers after a successful PG18 upgrade.
#
# - Stops/removes pg15-dump-* and pg15-verify-* sidecar containers
# - Deletes storage *.pg15-backup-<timestamp> directories (never live PG18 data)
# - Restarts nginx-proxy so gateway ports point at postgres-{dev,test,prod}
#
# Usage (from repo root):
#   ./docker/cleanup-postgres-pg15-backups.sh --confirm
#   ./docker/cleanup-postgres-pg15-backups.sh dev test --confirm
#   ./docker/cleanup-postgres-pg15-backups.sh --confirm --skip-nginx
#
# Does NOT touch openproject-postgres or running postgres-{dev,test,prod} data.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/docker/docker-compose.infra-platform.yml"

usage() {
  echo "Usage: $0 [{dev|test|prod} ...] --confirm [--skip-nginx]" >&2
  echo "  --confirm     required; deletes PG15 backup dirs and sidecars" >&2
  echo "  --skip-nginx  do not restart nginx-proxy" >&2
  exit 1
}

resolve_storage_path() {
  local env="$1"
  python3 -c "import os; print(os.path.realpath('${REPO_ROOT}/storage-postgresql/${env}'))"
}

remove_pg15_sidecars() {
  local names removed=0
  names="$(docker ps -a --format '{{.Names}}' | grep -E '^pg15-(dump|verify)-' || true)"
  if [ -z "$names" ]; then
    echo "=== PG15 sidecars: none found ==="
    return 0
  fi
  echo "=== Removing PG15 sidecars ==="
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    docker rm -f "$name" >/dev/null
    echo "  removed $name"
    removed=$((removed + 1))
  done <<<"$names"
  echo "  total removed: $removed"
}

remove_pg15_backups_for_env() {
  local env="$1"
  local storage parent
  storage="$(resolve_storage_path "$env")"
  parent="$(dirname "$storage")"
  local found=0

  echo "=== PG15 backups for $env (parent: $parent) ==="
  shopt -s nullglob
  local backup
  for backup in "$parent/${env}.pg15-backup-"*; do
    if [ ! -d "$backup" ]; then
      continue
    fi
  if [ -f "$backup/PG_VERSION" ] && [ "$(tr -d '[:space:]' <"$backup/PG_VERSION")" != "15" ]; then
      echo "  skip (not PG15): $backup" >&2
      continue
    fi
    local size
    size="$(du -sh "$backup" | awk '{print $1}')"
    echo "  deleting $backup ($size)"
    rm -rf "$backup"
    found=$((found + 1))
  done
  shopt -u nullglob
  if [ "$found" -eq 0 ]; then
    echo "  none found"
  fi
}

restart_nginx_proxy() {
  echo "=== Restarting nginx-proxy (postgres gateway 54324-54326 → PG18) ==="
  docker compose -f "$COMPOSE_FILE" restart nginx-proxy
  sleep 2
  if docker exec nginx-proxy nginx -t >/dev/null 2>&1; then
    echo "  nginx config OK"
  else
    echo "ERROR: nginx config test failed after restart." >&2
    exit 1
  fi
}

main() {
  local confirm=false skip_nginx=false
  local targets=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      dev|test|prod) targets+=("$1") ;;
      --confirm) confirm=true ;;
      --skip-nginx) skip_nginx=true ;;
      -h|--help) usage ;;
      *) usage ;;
    esac
    shift
  done

  if [ "${#targets[@]}" -eq 0 ]; then
    targets=(dev test prod)
  fi

  if ! $confirm; then
    echo "Refusing to delete PG15 backups without --confirm." >&2
    echo "This removes *.pg15-backup-* under storage-postgresql parents and pg15 sidecars." >&2
    usage
  fi

  remove_pg15_sidecars
  for env in "${targets[@]}"; do
    remove_pg15_backups_for_env "$env"
  done

  if ! $skip_nginx; then
    restart_nginx_proxy
  fi

  echo ""
  echo "=== Done: PG15 datalake backups/sidecars cleaned for ${targets[*]} ==="
  echo "Live PG18 data: storage-postgresql/{dev,test,prod} (unchanged)"
}

main "$@"
