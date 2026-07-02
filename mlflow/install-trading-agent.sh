#!/usr/bin/env bash
#
# Install trading_agent for MLflow model training (provides macro HMM + _mlflow_).
#
# Usage:
#   bash mlflow/install-trading-agent.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IFP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TPA_ROOT="${TPA_ROOT:-${IFP_ROOT}/../TradingPythonAgent}"
WHEELS_DIR="${TPA_WHEELS_DIR:-${IFP_ROOT}/kubernetes/wheels}"
ENV="${ENV:-dev}"

log() { echo "[mlflow/install-trading-agent] $*"; }

if [[ -f "${TPA_ROOT}/setup.py" ]] && [[ -d "${TPA_ROOT}/src/_mlflow_" ]]; then
    log "Installing editable trading_agent from ${TPA_ROOT}"
    ENV="${ENV}" TRADING_AGENT_SKIP_IDP_REQUIREMENT=1 pip install -q -e "${TPA_ROOT}"
elif wheel="$(ls -1 "${WHEELS_DIR}"/trading_agent-*.whl 2>/dev/null | sort | tail -1)"; then
    log "Installing trading_agent wheel: ${wheel}"
    pip install -q "${wheel}"
else
    echo "trading_agent source or wheel not found" >&2
    exit 1
fi

python -c "from trading_agent._mlflow_.tracking import MLflowTracker, MACRO_HMM_MODEL_NAME; print(MACRO_HMM_MODEL_NAME)"
log "MLflow training modules ready"
