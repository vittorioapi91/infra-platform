#!/usr/bin/env bash
# Create PV/PVC for pipeline Feast/dbt runtime data (kind hostPath → storage-infra).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECTL_CONTEXT="${KUBECTL_CONTEXT:-kind-trading-cluster}"

if ! kubectl get namespace kubeflow --context "${KUBECTL_CONTEXT}" >/dev/null 2>&1; then
  echo "ERROR: kubeflow namespace not found. Install Kubeflow Pipelines first." >&2
  exit 1
fi

bash "${SCRIPT_DIR}/provision-pipeline-runtime-data.sh"
kubectl apply -f "${SCRIPT_DIR}/pipeline-data-volumes.yaml" --context "${KUBECTL_CONTEXT}"
echo "Pipeline runtime data volumes ready (namespace kubeflow)."
