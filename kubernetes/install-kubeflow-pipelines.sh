#!/usr/bin/env bash
# Install Kubeflow Pipelines (standalone) into the kind trading-cluster.
# Usage: bash kubernetes/install-kubeflow-pipelines.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECTL_CONTEXT="${KUBECTL_CONTEXT:-kind-trading-cluster}"
KFP_REF="${KFP_REF:-master}"

log() { echo "[install-kubeflow] $*"; }

if ! command -v kubectl >/dev/null 2>&1; then
  log "ERROR: kubectl not found"
  exit 1
fi

if ! kubectl config get-contexts -o name 2>/dev/null | grep -qx "${KUBECTL_CONTEXT}"; then
  log "ERROR: context ${KUBECTL_CONTEXT} not found. Run kubernetes/start-kubernetes.sh first."
  exit 1
fi

kubectl config use-context "${KUBECTL_CONTEXT}" >/dev/null

log "Pre-pulling pipeline images into kind (avoids slow/stuck kubelet pulls on arm64)..."
bash "${SCRIPT_DIR}/prepull-kubeflow-images.sh"

if kubectl get namespace kubeflow >/dev/null 2>&1; then
  log "Namespace kubeflow already exists"
else
  log "Applying Kubeflow Pipelines cluster-scoped resources (ref=${KFP_REF})..."
  kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=${KFP_REF}"
fi

if kubectl get deployment ml-pipeline-ui -n kubeflow >/dev/null 2>&1; then
  log "ml-pipeline-ui deployment already present"
else
  log "Applying Kubeflow Pipelines dev environment (ref=${KFP_REF})..."
  kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/env/dev?ref=${KFP_REF}"
fi

log "Waiting for ml-pipeline-ui deployment (up to 10 minutes)..."
kubectl wait --for=condition=available deployment/ml-pipeline-ui \
  -n kubeflow --timeout=600s

host_arch="$(uname -m)"
if [[ "${host_arch}" == "arm64" ]]; then
  log "arm64: kfp-metadata-writer is amd64-only — scaling metadata-writer to 0 (pipelines still run)"
  kubectl scale deployment metadata-writer -n kubeflow --replicas=0 2>/dev/null || true
fi

log "Kubeflow Pipelines is ready. UI: http://kubeflow.local.info (compose sidecar kubeflow-port-forward)"
