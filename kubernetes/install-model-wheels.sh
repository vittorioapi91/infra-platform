#!/usr/bin/env bash
# Build and copy idp + trading_agent wheels into kubernetes/wheels/
# Usage: bash kubernetes/install-model-wheels.sh [dev|staging|prod]
#
# Platform (default linux-arm64 for model-training Docker on ARM):
#   WHEEL_PLATFORM=linux-arm64|linux-x86_64|macosx-arm64|win-x86_64

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IFP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV="${1:-dev}"
WHEEL_PLATFORM="${WHEEL_PLATFORM:-linux-arm64}"

resolve_platform_flag() {
  case "$1" in
    linux-arm64) echo "--linux-arm64" ;;
    linux-x86_64) echo "--linux-x86_64" ;;
    macosx-arm64) echo "--macosx-arm64" ;;
    win-x86_64) echo "--win-x86_64" ;;
    *)
      echo "Unknown WHEEL_PLATFORM=$1; using --linux-arm64" >&2
      echo "--linux-arm64"
      ;;
  esac
}

resolve_wheel_tag() {
  case "$1" in
    linux-arm64) echo "manylinux2014_aarch64" ;;
    linux-x86_64) echo "linux_x86_64" ;;
    macosx-arm64) echo "macosx" ;;
    win-x86_64) echo "win_amd64" ;;
    *) echo "manylinux2014_aarch64" ;;
  esac
}

find_wheel() {
  local dist_dir="$1"
  local pkg_prefix="$2"
  local platform_tag="$3"
  ls -1 "${dist_dir}/${pkg_prefix}"-*"${platform_tag}"*.whl 2>/dev/null | sort -V | tail -n 1 || true
}

build_idp_wheel() {
  local platform_flag="$1"
  local platform_tag="$2"
  local build_script="${IDP_ROOT}/scripts/build-wheel.sh"
  if [ ! -x "${build_script}" ]; then
    echo "idp build script not found: ${build_script}" >&2
    exit 1
  fi
  echo "Building idp wheel for env=${ENV} platform=${WHEEL_PLATFORM}..." >&2
  (cd "${IDP_ROOT}" && "${build_script}" "${ENV}" "${platform_flag}")
  find_wheel "${IDP_ROOT}/dist/${ENV}" "idp" "${platform_tag}"
}

build_trading_agent_wheel() {
  local platform_flag="$1"
  local platform_tag="$2"
  local build_script="${TPA_ROOT}/scripts/build-wheel.sh"
  if [ ! -x "${build_script}" ]; then
    echo "trading_agent build script not found: ${build_script}" >&2
    exit 1
  fi
  echo "Building trading_agent wheel for env=${ENV} platform=${WHEEL_PLATFORM}..." >&2
  (cd "${TPA_ROOT}" && "${build_script}" "${ENV}" "${platform_flag}")
  find_wheel "${TPA_ROOT}/dist/${ENV}" "trading_agent" "${platform_tag}"
}

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

PLATFORM_FLAG="$(resolve_platform_flag "${WHEEL_PLATFORM}")"
PLATFORM_TAG="$(resolve_wheel_tag "${WHEEL_PLATFORM}")"
WHEELS_DIR="${IFP_ROOT}/kubernetes/wheels"
mkdir -p "${WHEELS_DIR}"

IDP_WHEEL="$(find_wheel "${IDP_ROOT}/dist/${ENV}" "idp" "${PLATFORM_TAG}")"
if [ -z "${IDP_WHEEL}" ]; then
  IDP_WHEEL="$(build_idp_wheel "${PLATFORM_FLAG}" "${PLATFORM_TAG}")"
fi

TPA_WHEEL="$(find_wheel "${TPA_ROOT}/dist/${ENV}" "trading_agent" "${PLATFORM_TAG}")"
if [ -z "${TPA_WHEEL}" ]; then
  TPA_WHEEL="$(build_trading_agent_wheel "${PLATFORM_FLAG}" "${PLATFORM_TAG}")"
fi

if [ -z "${IDP_WHEEL}" ] || [ ! -f "${IDP_WHEEL}" ]; then
  echo "No idp wheel found for platform tag ${PLATFORM_TAG} in ${IDP_ROOT}/dist/${ENV}/" >&2
  exit 1
fi

if [ -z "${TPA_WHEEL}" ] || [ ! -f "${TPA_WHEEL}" ]; then
  echo "No trading_agent wheel found for platform tag ${PLATFORM_TAG} in ${TPA_ROOT}/dist/${ENV}/" >&2
  exit 1
fi

cp "${IDP_WHEEL}" "${WHEELS_DIR}/"
cp "${TPA_WHEEL}" "${WHEELS_DIR}/"
echo "Copied wheels to ${WHEELS_DIR}:"
ls -1 "${WHEELS_DIR}"/*.whl
