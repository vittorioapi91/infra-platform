#!/usr/bin/env bash
# Emit kind cluster YAML with absolute host paths for pipeline runtime data mounts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IFP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE="${SCRIPT_DIR}/kind-trading-cluster.yaml"

sed "s|__IFP_ROOT__|${IFP_ROOT}|g" "${TEMPLATE}"
