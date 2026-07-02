#!/usr/bin/env bash
# Compile macro_ml_pipeline.yaml from the trading_agent wheel.
# Usage: bash kubeflow/compile-pipeline.sh [dev|staging|prod]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IFP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV="${1:-dev}"
OUTPUT="${SCRIPT_DIR}/macro_ml_pipeline.yaml"

export ENV
bash "${SCRIPT_DIR}/install-trading-agent.sh"

if ! python -c "import kfp" 2>/dev/null; then
    pip install -q "kfp>=2.0.0"
fi

python <<PY
from kfp import compiler
from trading_agent._kubeflow_.pipeline import macro_ml_pipeline

compiler.Compiler().compile(
    macro_ml_pipeline,
    "${OUTPUT}",
)
print("Compiled macro_ml_pipeline.yaml")
PY

echo "Output: ${OUTPUT}"
