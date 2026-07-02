#!/usr/bin/env bash
#
# Install trading_agent for Kubeflow compile/submit hosts (pipeline code in wheel).
#
# Usage:
#   ENV=dev bash kubeflow/install-trading-agent.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IFP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV="${ENV:-dev}"
TPA_ROOT="${TPA_ROOT:-${IFP_ROOT}/../TradingPythonAgent}"
WHEELS_DIR="${TPA_WHEELS_DIR:-${IFP_ROOT}/kubernetes/wheels}"

log() { echo "[kubeflow/install-trading-agent] $*"; }

install_from_source() {
    if [[ ! -f "${TPA_ROOT}/setup.py" ]] || [[ ! -d "${TPA_ROOT}/src/_kubeflow_" ]]; then
        return 1
    fi
    log "Installing editable trading_agent from ${TPA_ROOT} (ENV=${ENV})"
    ENV="${ENV}" TRADING_AGENT_SKIP_IDP_REQUIREMENT=1 pip install -q -e "${TPA_ROOT}"
    return 0
}

install_from_wheel() {
    local wheel=""
    if [[ -d "${WHEELS_DIR}" ]]; then
        wheel="$(ls -1 "${WHEELS_DIR}"/trading_agent-*.whl 2>/dev/null | sort | tail -1 || true)"
    fi
    if [[ -z "${wheel}" ]]; then
        return 1
    fi
    log "Installing trading_agent wheel: ${wheel}"
    pip install -q "${wheel}"
    return 0
}

if [[ -d "${TPA_ROOT}/src/_kubeflow_" ]]; then
    install_from_source || install_from_wheel
else
    install_from_wheel || install_from_source
fi

python -c "
import trading_agent._kubeflow_.pipeline
import trading_agent._kubeflow_.commands
import trading_agent._kubeflow_.runner
print('trading_agent kubeflow modules ready')
"
log "trading_agent wheel installed (_kubeflow_, _kserve_)"
