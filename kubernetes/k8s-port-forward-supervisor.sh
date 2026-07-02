#!/usr/bin/env bash
# DEPRECATED: use Docker Compose sidecar `k8s-port-forwards` instead.
# Kept for manual recovery only. start-all-services.sh manages the compose service.
#
# Keep Kubernetes UI port-forwards alive (dashboard :8001, kubeflow :8088).
# Restarts forwards when they drop (common during Kubeflow install or API blips).
#
# Usage:
#   bash kubernetes/k8s-port-forward-supervisor.sh          # start background supervisor
#   bash kubernetes/k8s-port-forward-supervisor.sh --daemon # run loop (internal)
#   bash kubernetes/k8s-port-forward-supervisor.sh --stop

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${K8S_PF_SUPERVISOR_LOG:-$HOME/.trading-agent-k8s-pf-supervisor.log}"
PID_FILE="${K8S_PF_SUPERVISOR_PID:-$HOME/.trading-agent-k8s-pf-supervisor.pid}"
INTERVAL_SEC="${K8S_PF_SUPERVISOR_INTERVAL:-15}"

log() { echo "[k8s-pf-supervisor] $(date '+%H:%M:%S') $*" | tee -a "${LOG_FILE}"; }

supervisor_running() {
  [[ -f "${PID_FILE}" ]] || return 1
  local pid
  pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
  [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null
}

stop_supervisor() {
  if supervisor_running; then
    kill "$(cat "${PID_FILE}")" 2>/dev/null || true
    sleep 1
  fi
  rm -f "${PID_FILE}"
  log "Supervisor stopped"
}

run_daemon() {
  log "Daemon started (interval=${INTERVAL_SEC}s)"
  while true; do
    bash "${SCRIPT_DIR}/port-forward-kubernetes-dashboard.sh" >>"${LOG_FILE}" 2>&1 || true
    bash "${SCRIPT_DIR}/port-forward-kubeflow.sh" >>"${LOG_FILE}" 2>&1 || true
    sleep "${INTERVAL_SEC}"
  done
}

LOCK_DIR="${K8S_PF_SUPERVISOR_LOCK:-$HOME/.trading-agent-k8s-pf-supervisor.lockdir}"

acquire_lock() {
  if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
    log "Another supervisor start in progress; exiting"
    exit 0
  fi
  trap 'rmdir "${LOCK_DIR}" 2>/dev/null || true' EXIT
}

case "${1:-}" in
  --daemon)
    run_daemon
    ;;
  --stop)
    stop_supervisor
    ;;
  *)
    acquire_lock
    if supervisor_running; then
      log "Already running (pid $(cat "${PID_FILE}"))"
      exit 0
    fi
    nohup bash "${SCRIPT_DIR}/k8s-port-forward-supervisor.sh" --daemon >>"${LOG_FILE}" 2>&1 &
    echo $! >"${PID_FILE}"
    log "Supervisor started (pid $(cat "${PID_FILE}")); port-forwards will be ready within ~20s"
    ;;
esac
