#!/usr/bin/env bash
# Live progress for postgres-{dev,test,prod} PG18 upgrade.
#
# Usage (from repo root):
#   ./docker/watch-postgres-upgrade.sh dev
#   ./docker/watch-postgres-upgrade.sh dev --once

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGING_DIR="$REPO_ROOT/docker/.upgrade-pg18-staging"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-2014}"
INTERVAL="${WATCH_INTERVAL:-5}"

STAGE_NAMES=(
  "PG15 sidecar WAL recovery"
  "Dumping roles/globals"
  "Dumping datalake"
  "Verifying dump"
  "Starting PG18"
  "Copying dump into container"
  "Restoring datalake"
  "Complete"
)
STAGE_TOTAL=${#STAGE_NAMES[@]}

usage() {
  echo "Usage: $0 {dev|test|prod} [--once]" >&2
  exit 1
}

format_bytes() {
  local bytes="$1"
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec-i --suffix=B "$bytes" 2>/dev/null || echo "${bytes}B"
  else
    python3 -c "b=float('$bytes');
for u in 'B','KiB','MiB','GiB','TiB':
  if b<1024 or u=='TiB': print(f'{b:.1f}{u}'); break
  b/=1024" 2>/dev/null || echo "${bytes}B"
  fi
}

format_duration() {
  local secs="$1"
  printf '%dh %02dm %02ds' $((secs / 3600)) $(((secs % 3600) / 60)) $((secs % 60))
}

render_bar() {
  local pct="$1"
  local width=40
  local filled=$((pct * width / 100))
  local empty=$((width - filled))
  printf '%*s' "$filled" '' | tr ' ' '█'
  printf '%*s' "$empty" '' | tr ' ' '░'
}

read_progress_file() {
  local env="$1"
  local file="$STAGING_DIR/$env/progress.json"
  [ -f "$file" ] || return 1
  python3 - "$file" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
for k in ("stage_index", "stage_total", "stage", "detail", "percent",
          "current_bytes", "source_bytes", "started_at", "updated_at"):
    print(f"{k}={d.get(k, '')}")
PY
}

infer_state() {
  local env="$1"
  local staging="$STAGING_DIR/$env"
  local dump_dir="$staging/datalake"
  local sidecar
  sidecar="$(docker ps --format '{{.Names}}' | grep -E "^pg15-dump-${env}(-[0-9]+)?$" | head -1 || true)"

  local stage_index=0 percent=0 detail="" current_bytes=0 source_bytes=0
  local started_at=""
  if [ -f "$staging/progress.json" ]; then
  while IFS='=' read -r k v; do
    case "$k" in
      stage_index) stage_index="${v:-0}" ;;
      percent) percent="${v:-0}" ;;
      detail) detail="$v" ;;
      current_bytes) current_bytes="${v:-0}" ;;
      source_bytes) source_bytes="${v:-0}" ;;
      started_at) started_at="$v" ;;
    esac
  done < <(read_progress_file "$env" 2>/dev/null || true)
  fi

  if [ -f "$staging/source_bytes.txt" ]; then
    source_bytes="$(tr -d '[:space:]' <"$staging/source_bytes.txt")"
  fi

  if [ "$stage_index" -ge 7 ]; then
  :
  elif [ -n "$sidecar" ]; then
    if docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$sidecar" \
      psql -U postgres -d postgres -tAc 'SELECT 1' >/dev/null 2>&1; then
      if [ -f "$dump_dir/toc.dat" ]; then
        stage_index=2
        current_bytes="$(du -sk "$dump_dir" 2>/dev/null | awk '{print $1 * 1024}')"
        detail="Dump finishing..."
        percent=55
      elif [ -s "$staging/globals.sql" ]; then
        stage_index=2
        current_bytes="$(du -sk "$dump_dir" 2>/dev/null | awk '{print $1 * 1024}')"
        detail="Dumping datalake ($(format_bytes "$current_bytes") so far)"
        if [ "${source_bytes:-0}" -gt 0 ] && [ "$current_bytes" -gt 0 ]; then
          percent=$((current_bytes * 45 / source_bytes + 15))
          [ "$percent" -gt 59 ] && percent=59
        else
          percent=20
        fi
      else
        stage_index=1
        detail="Dumping roles/globals"
        percent=12
      fi
      if [ "${source_bytes:-0}" -eq 0 ]; then
        source_bytes="$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$sidecar" \
          psql -U postgres -d datalake -tAc "SELECT pg_database_size('datalake');" 2>/dev/null || echo 0)"
      fi
    else
      stage_index=0
      detail="$(docker logs "$sidecar" 2>&1 | grep 'redo in progress' | tail -1 | sed 's/^.*LOG:  //')"
      [ -z "$detail" ] && detail="Recovering WAL (sidecar not ready yet)"
      local elapsed
      elapsed="$(docker inspect -f '{{.State.StartedAt}}' "$sidecar" 2>/dev/null || echo "")"
      percent=5
    fi
  elif [ -f "$dump_dir/toc.dat" ]; then
    current_bytes="$(du -sk "$dump_dir" 2>/dev/null | awk '{print $1 * 1024}')"
    if docker ps --format '{{.Names}}' | grep -qx "postgres-${env}"; then
      local pg18
      pg18="$(docker exec "postgres-${env}" postgres --version 2>/dev/null | grep -c '18' || true)"
      if [ "$pg18" -ge 1 ]; then
        local db_bytes
        db_bytes="$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "postgres-${env}" \
          psql -U postgres -d datalake -tAc "SELECT pg_database_size('datalake');" 2>/dev/null || echo 0)"
        current_bytes="$db_bytes"
        if [ -f "$staging/.restore_started" ]; then
          stage_index=6
          detail="Restoring datalake ($(format_bytes "$current_bytes") loaded)"
          if [ "${source_bytes:-0}" -gt 0 ] && [ "$db_bytes" -gt 0 ]; then
            percent=$((db_bytes * 25 / source_bytes + 70))
            [ "$percent" -gt 99 ] && percent=99
          else
            percent=75
          fi
        elif [ -d "$staging/.copy_started" ] || docker exec "postgres-${env}" \
          test -d /var/lib/postgresql/datalake-restore 2>/dev/null; then
          stage_index=5
          detail="Copying dump into container"
          percent=65
        else
          stage_index=4
          detail="Starting PG18 / preparing restore"
          percent=62
        fi
      fi
    else
      stage_index=3
      detail="Dump verified ($(format_bytes "$current_bytes")); preparing PG18"
      percent=60
    fi
  elif [ -n "$sidecar" ]; then
    :
  else
    detail="No active upgrade detected for $env"
    percent=0
    stage_index=0
  fi

  if [ -f "$staging/progress.json" ]; then
    local file_pct
    file_pct="$(python3 -c "import json; print(json.load(open('$staging/progress.json')).get('percent',0))" 2>/dev/null || echo 0)"
    [ "${file_pct:-0}" -gt "${percent:-0}" ] && percent="$file_pct"
  fi

  STAGE_INDEX="$stage_index"
  PERCENT="$percent"
  DETAIL="$detail"
  CURRENT_BYTES="$current_bytes"
  SOURCE_BYTES="$source_bytes"
  STARTED_AT="$started_at"
}

print_status() {
  local env="$1"
  infer_state "$env"

  local stage_label="${STAGE_NAMES[$STAGE_INDEX]:-Unknown}"
  local stage_human="$((STAGE_INDEX + 1))/${STAGE_TOTAL}"
  local now elapsed_str="?"
  now="$(date +%s)"
  if [ -n "$STARTED_AT" ]; then
    local started
    started="$(python3 -c "from datetime import datetime; print(int(datetime.fromisoformat('${STARTED_AT}'.replace('Z','+00:00')).timestamp()))" 2>/dev/null || echo 0)"
    if [ "$started" -gt 0 ]; then
      elapsed_str="$(format_duration $((now - started)))"
    fi
  fi

  clear 2>/dev/null || true
  echo "postgres-${env} → PG18 upgrade"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  printf '[%s] %3d%%\n' "$(render_bar "$PERCENT")" "$PERCENT"
  echo "Stage ${stage_human}: ${stage_label}"
  echo "Detail: ${DETAIL:-—}"
  if [ "${SOURCE_BYTES:-0}" -gt 0 ] && [ "${CURRENT_BYTES:-0}" -gt 0 ]; then
    echo "Progress: $(format_bytes "$CURRENT_BYTES") / $(format_bytes "$SOURCE_BYTES") (logical)"
  elif [ "${CURRENT_BYTES:-0}" -gt 0 ]; then
    echo "Size so far: $(format_bytes "$CURRENT_BYTES")"
  fi
  [ "$elapsed_str" != "?" ] && echo "Elapsed: ${elapsed_str}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Log: tail -f /tmp/upgrade-postgres-${env}.log"
  echo "Refresh: every ${INTERVAL}s (Ctrl+C to exit)"
}

main() {
  local env="${1:-}"
  local once=false
  [ "${2:-}" = --once ] && once=true
  case "$env" in
    dev|test|prod) ;;
    *) usage ;;
  esac

  if $once; then
    print_status "$env"
    exit 0
  fi

  while true; do
    print_status "$env"
    sleep "$INTERVAL"
  done
}

main "$@"
