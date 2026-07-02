#!/usr/bin/env bash
# Load tpa-pipeline-runner image into kind cluster
# Usage: bash kubernetes/deploy-pipeline-image-to-kind.sh

set -euo pipefail

IMAGE_NAME="tpa-pipeline-runner"
IMAGE_TAG="latest"
KIND_CLUSTER="trading-cluster"

if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${IMAGE_NAME}:${IMAGE_TAG}$"; then
  echo "Error: Docker image ${IMAGE_NAME}:${IMAGE_TAG} not found locally." >&2
  echo "Build first: bash kubernetes/build-pipeline-image.sh dev" >&2
  exit 1
fi

if ! kind get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER}$"; then
  echo "Error: kind cluster '${KIND_CLUSTER}' does not exist." >&2
  exit 1
fi

echo "Loading ${IMAGE_NAME}:${IMAGE_TAG} into kind cluster ${KIND_CLUSTER}"
kind load docker-image "${IMAGE_NAME}:${IMAGE_TAG}" --name "${KIND_CLUSTER}"
echo "Ready for Kubeflow pipeline runs"
