#!/bin/bash
set -euo pipefail

PROJECT_DIR=/workspace/dbt/feast_features
DOCS_PORT="${DBT_DOCS_PORT:-8880}"

echo "Bootstrapping dbt sidecar..."
apt-get update -qq && apt-get install -y -qq git >/dev/null
pip install -r /workspace/dbt/requirements.txt
bash /workspace/dbt/install-trading-agent.sh &
dbt debug --project-dir "${PROJECT_DIR}" || true

echo "dbt docs for ${DBT_TARGET:-unknown} on :${DOCS_PORT}"
while true; do
  if dbt docs generate --project-dir "${PROJECT_DIR}"; then
    dbt docs serve --project-dir "${PROJECT_DIR}" --host 0.0.0.0 --port "${DOCS_PORT}" || true
  else
    echo "dbt docs generate failed; retrying in 30s..."
    sleep 30
    continue
  fi
  echo "dbt docs serve exited; restarting in 5s..."
  sleep 5
done
