#!/bin/bash
set -euo pipefail

REPO="${FEAST_REPO_PATH:?FEAST_REPO_PATH required}"
UI_PORT="${FEAST_UI_PORT:-8888}"

pip install -q 'feast[grpcio]>=0.36.0'

echo "Feast UI for ${REPO} on :${UI_PORT}"
while true; do
  cd "${REPO}"
  feast ui --host 0.0.0.0 --port "${UI_PORT}" || true
  echo "feast ui exited; restarting in 3s..."
  sleep 3
done
