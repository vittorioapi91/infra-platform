#!/usr/bin/env bash
# Start kubectl port-forward for Kubeflow Pipelines UI (localhost:8088).
# Idempotent: skips if already healthy.
#
# Usage: bash kubernetes/port-forward-kubeflow.sh

set -euo pipefail

KUBECTL_CONTEXT="${KUBECTL_CONTEXT:-kind-trading-cluster}"
LOCAL_PORT="${KUBEFLOW_UI_PORT:-8088}"
LOG_FILE="${KUBEFLOW_PF_LOG:-$HOME/.trading-agent-kubeflow-pf.log}"
PID_FILE="${KUBEFLOW_PF_PID:-$HOME/.trading-agent-kubeflow-pf.pid}"

log() { echo "[port-forward-kubeflow] $*"; }

kubeflow_responds() {
  curl -s --connect-timeout 2 -o /dev/null -w "%{http_code}" "http://127.0.0.1:${LOCAL_PORT}/" 2>/dev/null | grep -qE "200|302|401|403"
}

nginx_can_reach_kubeflow() {
  docker exec nginx-proxy curl -s --connect-timeout 2 -o /dev/null -w "%{http_code}" \
    "http://host.docker.internal:${LOCAL_PORT}/" 2>/dev/null | grep -qE "200|302|401|403"
}

port_forward_running() {
  pgrep -f "kubectl port-forward.*ml-pipeline-ui.*${LOCAL_PORT}:80" >/dev/null 2>&1
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
  log "Starting port-forward on http://localhost:${LOCAL_PORT} (context=${KUBECTL_CONTEXT}, bind=0.0.0.0 for nginx host.docker.internal)"
  nohup kubectl port-forward \
    -n kubeflow \
    svc/ml-pipeline-ui \
    "${LOCAL_PORT}:80" \
    --context "${KUBECTL_CONTEXT}" \
    --address=0.0.0.0 \
    >>"${LOG_FILE}" 2>&1 &
  echo $! >"${PID_FILE}"
}

if ! command -v kubectl >/dev/null 2>&1; then
  log "ERROR: kubectl not found"
  exit 1
fi

if ! kubectl config get-contexts -o name 2>/dev/null | grep -qx "${KUBECTL_CONTEXT}"; then
  log "ERROR: context ${KUBECTL_CONTEXT} not found"
  exit 1
fi

if ! kubectl get svc ml-pipeline-ui -n kubeflow --context "${KUBECTL_CONTEXT}" >/dev/null 2>&1; then
  log "ml-pipeline-ui not installed yet (skip)"
  exit 0
fi

if ! kubectl get deployment ml-pipeline-ui -n kubeflow --context "${KUBECTL_CONTEXT}" -o jsonpath='{.status.availableReplicas}' 2>/dev/null | grep -qE '^[1-9]'; then
  log "ml-pipeline-ui not ready yet (Kubeflow still installing; skip)"
  exit 0
fi

if kubeflow_responds && nginx_can_reach_kubeflow; then
  log "Already responding on port ${LOCAL_PORT} (host + nginx)"
  exit 0
fi

if kubeflow_responds && ! nginx_can_reach_kubeflow; then
  log "Host responds but nginx cannot reach host.docker.internal:${LOCAL_PORT}; restarting port-forward (bind 0.0.0.0)"
fi

if port_forward_running; then
  log "Port-forward running but not responding; restarting..."
  orphan_pid="$(pgrep -f "kubectl port-forward.*ml-pipeline-ui.*${LOCAL_PORT}:80" | head -1 || true)"
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
  if kubeflow_responds && nginx_can_reach_kubeflow; then
    log "Ready: http://localhost:${LOCAL_PORT} and http://kubeflow.local.info"
    exit 0
  fi
  sleep 1
done

log "ERROR: port-forward started but Kubeflow UI not reachable from host and nginx"
log "See ${LOG_FILE}"
exit 1
