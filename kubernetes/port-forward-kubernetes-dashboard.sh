#!/usr/bin/env bash
# Start kubectl port-forward for Kubernetes Dashboard (HTTPS on localhost:8001).
# Idempotent: skips if already healthy.
#
# Usage: bash kubernetes/port-forward-kubernetes-dashboard.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECTL_CONTEXT="${KUBECTL_CONTEXT:-kind-trading-cluster}"
LOCAL_PORT="${KUBERNETES_DASHBOARD_PORT:-8001}"
LOG_FILE="${KUBERNETES_DASHBOARD_PF_LOG:-$HOME/.trading-agent-kubernetes-dashboard-pf.log}"
PID_FILE="${KUBERNETES_DASHBOARD_PF_PID:-$HOME/.trading-agent-kubernetes-dashboard-pf.pid}"

log() { echo "[port-forward-dashboard] $*"; }

dashboard_responds() {
  curl -sk --connect-timeout 2 -o /dev/null -w "%{http_code}" "https://127.0.0.1:${LOCAL_PORT}/" 2>/dev/null | grep -qE "200|302|401|403"
}

port_forward_running() {
  pgrep -f "kubectl port-forward.*kubernetes-dashboard.*${LOCAL_PORT}:443" >/dev/null 2>&1
}

stop_stale_port_forward() {
  if [[ -f "${PID_FILE}" ]]; then
    local old_pid
    old_pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
    if [[ -n "${old_pid}" ]] && kill -0 "${old_pid}" 2>/dev/null; then
      kill "${old_pid}" 2>/dev/null || true
      sleep 1
    fi
    rm -f "${PID_FILE}"
  fi
}

start_port_forward() {
  log "Starting port-forward on https://localhost:${LOCAL_PORT} (context=${KUBECTL_CONTEXT})"
  nohup kubectl port-forward \
    -n kubernetes-dashboard \
    service/kubernetes-dashboard \
    "${LOCAL_PORT}:443" \
    --context "${KUBECTL_CONTEXT}" \
    --address=127.0.0.1 \
    >>"${LOG_FILE}" 2>&1 &
  echo $! >"${PID_FILE}"
}

if ! command -v kubectl >/dev/null 2>&1; then
  log "ERROR: kubectl not found"
  exit 1
fi

if ! kubectl config get-contexts -o name 2>/dev/null | grep -qx "${KUBECTL_CONTEXT}"; then
  log "ERROR: context ${KUBECTL_CONTEXT} not found (run kubernetes/start-kubernetes.sh)"
  exit 1
fi

if ! kubectl get svc kubernetes-dashboard -n kubernetes-dashboard --context "${KUBECTL_CONTEXT}" >/dev/null 2>&1; then
  log "ERROR: kubernetes-dashboard service not found (run kubernetes/start-kubernetes.sh)"
  exit 1
fi

if dashboard_responds; then
  log "Already responding on port ${LOCAL_PORT}"
  exit 0
fi

if port_forward_running; then
  log "Port-forward running but not responding; restarting..."
  orphan_pid="$(pgrep -f "kubectl port-forward.*kubernetes-dashboard.*${LOCAL_PORT}:443" | head -1 || true)"
  if [[ -n "${orphan_pid}" ]]; then
    kill "${orphan_pid}" 2>/dev/null || true
    sleep 1
  fi
fi

port_pid="$(lsof -ti "tcp:${LOCAL_PORT}" -sTCP:LISTEN 2>/dev/null | head -1 || true)"
if [[ -n "${port_pid}" ]]; then
  log "Freeing port ${LOCAL_PORT} (pid ${port_pid})"
  kill "${port_pid}" 2>/dev/null || true
  sleep 1
fi

stop_stale_port_forward
start_port_forward

for _ in $(seq 1 20); do
  if dashboard_responds; then
    log "Ready: https://localhost:${LOCAL_PORT} and http://kubernetes-dashboard.local.info"
    exit 0
  fi
  sleep 1
done

log "ERROR: port-forward started but dashboard did not respond on port ${LOCAL_PORT}"
log "See ${LOG_FILE}"
exit 1
