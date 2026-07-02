#!/usr/bin/env bash
#
# Install trading_agent into dbt sidecars (provides _dbt_, _feast_, features, _mlflow_).
#
# Same pattern as Airflow: prefer mounted TradingPythonAgent source for dev iteration,
# fall back to the trading_agent wheel in kubernetes/wheels/.
#
# Usage (inside dbt container):
#   DBT_TARGET=dev bash /workspace/dbt/install-trading-agent.sh
#

set -euo pipefail

ENV="${DBT_TARGET:-dev}"
TPA_ROOT="${TPA_ROOT:-/workspace/TradingPythonAgent}"
WHEELS_DIR="${TPA_WHEELS_DIR:-/workspace/infra-platform/kubernetes/wheels}"

log() { echo "[install-trading-agent] $*"; }

install_from_source() {
    if [[ ! -f "${TPA_ROOT}/setup.py" ]] || [[ ! -d "${TPA_ROOT}/src/_feast_" ]]; then
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

if [[ -d "${TPA_ROOT}/src/_feast_" ]]; then
    install_from_source || install_from_wheel
else
    install_from_wheel || install_from_source
fi

python -c "
import trading_agent._dbt_.config
import trading_agent._feast_.materialize
import trading_agent.features.macro.hodrick_prescott
import trading_agent._mlflow_.tracking
print('trading_agent pipeline modules ready')
"
log "trading_agent wheel installed (_dbt_, _feast_, features, _mlflow_)"
