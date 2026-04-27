#!/usr/bin/env bash
#
# Restore Docker Desktop build artifacts after the DockerDesktop data directory
# gets wiped/corrupted (e.g. due to external SSD disconnects).
#
# What this does:
# - Rebuild local custom images:
#     - jenkins-custom:base
#     - jenkins-custom:lts
# - Optionally rebuild the trading-agent base image.
# - Optionally `docker compose pull` to repopulate official images.
# - Optionally run `./start-all-services.sh` to start the stack.
#
# Notes:
# - This script does not manipulate Docker Desktop's data directory directly.
#   Docker Desktop automatically stores/recreates images inside whatever data
#   folder it is configured to use.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.infra-platform.yml"
START_ALL_SCRIPT="${INFRA_ROOT}/start-all-services.sh"

# The directory you mentioned where Docker Desktop stores its data.
# The script itself does not write to this path directly; it’s just a sanity check.
DOCKER_DESKTOP_DATA_DIR="${DOCKER_DESKTOP_DATA_DIR:-/Volumes/storage-volume/storage-vms/DockerDesktop}"

DO_BUILD_JENKINS=true
DO_BUILD_TRADING_AGENT=false
DO_COMPOSE_PULL=true
DO_START=true

usage() {
  cat <<'EOF'
Usage: ./docker/restore-docker-desktop-build.sh [options]

Options:
  --jenkins                 Rebuild jenkins images only (default)
  --trading-agent           Rebuild trading-agent base image only
  --all                     Rebuild both jenkins + trading-agent base images
  --no-pull                 Skip `docker compose pull`
  --no-start                Skip `./start-all-services.sh`
  -h, --help                Show help
EOF
}

if [ $# -gt 0 ]; then
  for arg in "$@"; do
    case "${arg}" in
      --jenkins)
        DO_BUILD_JENKINS=true
        DO_BUILD_TRADING_AGENT=false
        ;;
      --trading-agent)
        DO_BUILD_JENKINS=false
        DO_BUILD_TRADING_AGENT=true
        ;;
      --all)
        DO_BUILD_JENKINS=true
        DO_BUILD_TRADING_AGENT=true
        ;;
      --no-pull)
        DO_COMPOSE_PULL=false
        ;;
      --no-start)
        DO_START=false
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown option: ${arg}" >&2
        usage >&2
        exit 1
        ;;
    esac
  done
fi

wait_for_docker() {
  echo "Waiting for Docker Desktop to be ready..."
  for i in $(seq 1 60); do
    if docker info >/dev/null 2>&1; then
      echo "✓ Docker is ready"
      return 0
    fi
    sleep 2
  done
  echo "ERROR: Docker Desktop did not become ready in time" >&2
  return 1
}

build_jenkins_images() {
  echo ""
  echo "Building Jenkins custom images..."
  echo ""

  # Base installs tools + Python deps (slow).
  "${SCRIPT_DIR}/build-base-images.sh" jenkins

  echo "Building incremental Jenkins image: jenkins-custom:lts..."
  docker build \
    --platform linux/arm64 \
    -f "${SCRIPT_DIR}/Dockerfile.jenkins" \
    -t jenkins-custom:lts \
    "${SCRIPT_DIR}"

  echo "✓ Built: jenkins-custom:base and jenkins-custom:lts"
}

build_trading_agent_images() {
  echo ""
  echo "Building trading-agent base image..."
  echo ""
  "${SCRIPT_DIR}/build-base-images.sh" trading-agent
}

compose_pull() {
  echo ""
  echo "Pulling images referenced by compose..."
  echo ""
  (cd "${SCRIPT_DIR}" && docker compose -f "${COMPOSE_FILE}" pull)
  echo "✓ Compose pull complete"
}

start_stack() {
  echo ""
  echo "Starting full stack..."
  echo ""
  (cd "${INFRA_ROOT}" && "${START_ALL_SCRIPT}")
}

main() {
  wait_for_docker

  if [ -d "${DOCKER_DESKTOP_DATA_DIR}" ]; then
    local entries
    entries="$(ls -A "${DOCKER_DESKTOP_DATA_DIR}" 2>/dev/null | wc -l | tr -d ' ')"
    if [ "${entries}" = "0" ]; then
      echo "Docker Desktop data dir is empty: ${DOCKER_DESKTOP_DATA_DIR}"
      echo "Assuming Docker Desktop is configured to use this directory, rebuilds will repopulate it."
    else
      echo "Docker Desktop data dir exists: ${DOCKER_DESKTOP_DATA_DIR} (entries: ${entries})"
    fi
  else
    echo "Warning: Docker Desktop data dir not found: ${DOCKER_DESKTOP_DATA_DIR}"
    echo "If Docker Desktop uses a different data dir, rebuilds will go there instead."
  fi

  if [ "${DO_BUILD_JENKINS}" = "true" ]; then
    build_jenkins_images
  fi

  if [ "${DO_BUILD_TRADING_AGENT}" = "true" ]; then
    build_trading_agent_images
  fi

  if [ "${DO_COMPOSE_PULL}" = "true" ]; then
    compose_pull
  fi

  if [ "${DO_START}" = "true" ]; then
    start_stack
  else
    echo "Done (skipped start)."
  fi
}

main "$@"

