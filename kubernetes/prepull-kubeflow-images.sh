#!/usr/bin/env bash
# Pre-pull Kubeflow Pipelines images into the kind trading-cluster node.
#
# On Apple Silicon, several KFP images are amd64-only; kubelet then fails with
# "no match for platform in manifest". This script pulls the right platform and
# loads images into kind before install, avoiding long ContainerCreating stalls.
#
# Usage:
#   bash kubernetes/prepull-kubeflow-images.sh
#   bash kubernetes/prepull-kubeflow-images.sh --restart-stuck   # also recycle stuck pods

set -euo pipefail

CLUSTER_NAME="${KIND_CLUSTER:-trading-cluster}"
NODE_CONTAINER="${CLUSTER_NAME}-control-plane"
RESTART_STUCK=false

if [[ "${1:-}" == "--restart-stuck" ]]; then
  RESTART_STUCK=true
fi

log() { echo "[prepull-kubeflow] $*"; }

KFP_IMAGES=(
  "docker.io/library/alpine:3.23"
  "mysql:8.4"
  "ghcr.io/chrislusf/seaweedfs:4.34"
  "quay.io/argoproj/workflow-controller:v4.0.5"
  "gcr.io/ml-pipeline/application-crd-controller:20231101"
  "gcr.io/tfx-oss-public/ml_metadata_store_server:1.14.0"
  "ghcr.io/kubeflow/kfp-api-server:master"
  "ghcr.io/kubeflow/kfp-cache-deployer:master"
  "ghcr.io/kubeflow/kfp-cache-server:master"
  "ghcr.io/kubeflow/kfp-frontend:master"
  "ghcr.io/kubeflow/kfp-metadata-envoy:master"
  "ghcr.io/kubeflow/kfp-metadata-writer:master"
  "ghcr.io/kubeflow/kfp-persistence-agent:master"
  "ghcr.io/kubeflow/kfp-scheduled-workflow-controller:master"
  "ghcr.io/kubeflow/kfp-viewer-crd-controller:master"
  "ghcr.io/kubeflow/kfp-visualization-server:master"
)

if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  log "ERROR: kind cluster '${CLUSTER_NAME}' not found"
  exit 1
fi

if ! docker inspect "${NODE_CONTAINER}" >/dev/null 2>&1; then
  log "ERROR: kind node container '${NODE_CONTAINER}' not running"
  exit 1
fi

host_arch="$(uname -m)"
node_arch="$(docker exec "${NODE_CONTAINER}" uname -m)"
pull_platform="linux/${node_arch}"

# KFP master tags are often amd64-only; on arm64 Macs pull amd64 and load into kind.
if [[ "${host_arch}" == "arm64" || "${node_arch}" == "aarch64" ]]; then
  pull_platform="linux/amd64"
  log "Detected arm64 host/node — pulling linux/amd64 images and loading into kind"
else
  log "Detected ${node_arch} — pulling native images via crictl"
fi

pull_via_ctr() {
  local image="$1"
  log "Pulling ${image} via ctr (${pull_platform})..."
  if docker exec "${NODE_CONTAINER}" ctr -n k8s.io images pull --platform "${pull_platform}" "${image}"; then
    return 0
  fi
  log "ERROR: ctr pull failed for ${image}"
  return 1
}

for image in "${KFP_IMAGES[@]}"; do
  pull_via_ctr "${image}"
done

log "All images pre-pulled"

if [[ "${RESTART_STUCK}" == true ]] && command -v kubectl >/dev/null 2>&1; then
  KUBECTL_CONTEXT="${KUBECTL_CONTEXT:-kind-${CLUSTER_NAME}}"
  if kubectl config get-contexts -o name 2>/dev/null | grep -qx "${KUBECTL_CONTEXT}"; then
    log "Recycling kubeflow pods stuck in ContainerCreating / ImagePullBackOff / Init:Error..."
    stuck_pods="$(kubectl get pods -n kubeflow --context "${KUBECTL_CONTEXT}" --no-headers 2>/dev/null \
      | awk '$3 ~ /ContainerCreating|ImagePullBackOff|ErrImagePull|Init:Error/ {print $1}')"
    if [[ -n "${stuck_pods}" ]]; then
      echo "${stuck_pods}" | xargs kubectl delete pod -n kubeflow --context "${KUBECTL_CONTEXT}"
    fi
  fi
fi

log "Done"
