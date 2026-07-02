#!/usr/bin/env bash
# Load Docker image into kind cluster
# Usage: bash kubernetes/deploy-model-image-to-kind.sh [hmm-model-training|tpa-pipeline-runner]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${1:-hmm-model-training}"
IMAGE_TAG="latest"
KIND_CLUSTER="trading-cluster"

# Check if image exists locally
if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${IMAGE_NAME}:${IMAGE_TAG}$"; then
  echo "Error: Docker image ${IMAGE_NAME}:${IMAGE_TAG} not found locally."
  echo "Build first:" >&2
  echo "  bash kubernetes/build-model-image.sh dev" >&2
  echo "  bash kubernetes/build-pipeline-image.sh dev" >&2
  exit 1
fi

# Check if kind cluster exists
if ! kind get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER}$"; then
  echo "Error: kind cluster '${KIND_CLUSTER}' does not exist."
  echo "Create cluster: bash kubernetes/start-kubernetes.sh" >&2
  exit 1
fi

echo "Loading image ${IMAGE_NAME}:${IMAGE_TAG} into kind cluster: ${KIND_CLUSTER}"
kind load docker-image "${IMAGE_NAME}:${IMAGE_TAG}" --name "${KIND_CLUSTER}"

echo "✓ Image loaded into kind cluster successfully"
echo "Image: ${IMAGE_NAME}:${IMAGE_TAG}"
echo "Ready to use in Kubernetes Jobs"

