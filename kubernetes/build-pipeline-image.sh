#!/usr/bin/env bash
# Build Docker image for Kubeflow pipeline steps (dbt + Feast + trading_agent wheels)
# Usage: bash kubernetes/build-pipeline-image.sh [dev|staging|prod]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IFP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV="${1:-dev}"
IMAGE_NAME="tpa-pipeline-runner"
IMAGE_TAG="latest"

bash "${SCRIPT_DIR}/install-model-wheels.sh" "${ENV}"

cd "${IFP_ROOT}"
echo "Building Docker image: ${IMAGE_NAME}:${IMAGE_TAG} (env=${ENV})"
docker build \
  -f kubernetes/Dockerfile.pipeline-runner \
  -t "${IMAGE_NAME}:${IMAGE_TAG}" \
  .

echo "Image built: ${IMAGE_NAME}:${IMAGE_TAG}"
echo "Load into kind: bash kubernetes/deploy-pipeline-image-to-kind.sh"
