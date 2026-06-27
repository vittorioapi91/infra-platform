#!/usr/bin/env bash
# Copy idp + trading_agent wheels from sibling repos into kubernetes/wheels/
# Usage: bash kubernetes/install-model-wheels.sh [dev|staging|prod]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IFP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV="${1:-dev}"

if [ -d "${IFP_ROOT}/../infra-data-pipelines" ]; then
  IDP_ROOT="$(cd "${IFP_ROOT}/../infra-data-pipelines" && pwd)"
elif [ -n "${IDP_ROOT:-}" ] && [ -d "${IDP_ROOT}" ]; then
  IDP_ROOT="${IDP_ROOT}"
else
  echo "infra-data-pipelines not found (expected sibling of infra-platform)" >&2
  exit 1
fi

if [ -d "${IFP_ROOT}/../TradingPythonAgent" ]; then
  TPA_ROOT="$(cd "${IFP_ROOT}/../TradingPythonAgent" && pwd)"
elif [ -n "${TPA_ROOT:-}" ] && [ -d "${TPA_ROOT}" ]; then
  TPA_ROOT="${TPA_ROOT}"
else
  echo "TradingPythonAgent not found (expected sibling of infra-platform)" >&2
  exit 1
fi

WHEELS_DIR="${IFP_ROOT}/kubernetes/wheels"
mkdir -p "${WHEELS_DIR}"

IDP_WHEEL="$(ls -1 "${IDP_ROOT}/dist/${ENV}"/idp-*.whl 2>/dev/null | sort -V | tail -n 1 || true)"
if [ -z "${IDP_WHEEL}" ]; then
  echo "Building idp wheel for env=${ENV}..." >&2
  (cd "${IDP_ROOT}" && ENV="${ENV}" python3 setup.py bdist_wheel --dist-dir "dist/${ENV}")
  IDP_WHEEL="$(ls -1 "${IDP_ROOT}/dist/${ENV}"/idp-*.whl | sort -V | tail -n 1)"
fi

TPA_WHEEL="$(ls -1 "${TPA_ROOT}/dist/${ENV}"/trading_agent-*.whl 2>/dev/null | sort -V | tail -n 1 || true)"
if [ -z "${TPA_WHEEL}" ]; then
  echo "Building trading_agent wheel for env=${ENV}..." >&2
  (cd "${TPA_ROOT}" && ENV="${ENV}" python3 setup.py bdist_wheel --dist-dir "dist/${ENV}")
  TPA_WHEEL="$(ls -1 "${TPA_ROOT}/dist/${ENV}"/trading_agent-*.whl | sort -V | tail -n 1)"
fi

cp "${IDP_WHEEL}" "${WHEELS_DIR}/"
cp "${TPA_WHEEL}" "${WHEELS_DIR}/"
echo "Copied wheels to ${WHEELS_DIR}:"
ls -1 "${WHEELS_DIR}"/*.whl
