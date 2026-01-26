#!/usr/bin/env bash
# Trigger "Scan Multibranch Pipeline Now" for infra-platform, TradingPythonAgent, PredictionMarketsAgent.
#
# Option A - Via API (requires credentials):
#   export JENKINS_URL="${JENKINS_URL:-http://localhost:8081}"
#   export JENKINS_USER="your-username"
#   export JENKINS_API_TOKEN="your-api-token"
#   ./jenkins/trigger-multibranch-scans.sh
#
# Option B - On restart:
#   An init.groovy.d script in storage-infra/jenkins/data/ triggers these scans
#   automatically when Jenkins starts. Restart: docker compose -f docker/docker-compose.infra-platform.yml restart jenkins
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JENKINS_URL="${JENKINS_URL:-http://localhost:8081}"
JOBS=(infra-platform TradingPythonAgent PredictionMarketsAgent)

if [[ -z "${JENKINS_USER:-}" || -z "${JENKINS_API_TOKEN:-}" ]]; then
  echo "Usage: export JENKINS_USER=... JENKINS_API_TOKEN=... then run $0"
  echo "Or: Restart Jenkins (scans run automatically via init.groovy.d)."
  echo "    docker compose -f docker/docker-compose.infra-platform.yml restart jenkins"
  exit 1
fi

crumb_json="$(curl -s -u "${JENKINS_USER}:${JENKINS_API_TOKEN}" "${JENKINS_URL}/crumbIssuer/api/json")" || true
crumb=""
crumb_field="Jenkins-Crumb"
if [[ -n "$crumb_json" ]]; then
  crumb="$(printf '%s' "$crumb_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('crumb',''))")"
  crumb_field="$(printf '%s' "$crumb_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('crumbRequestField','Jenkins-Crumb'))")"
fi

for j in "${JOBS[@]}"; do
  url="${JENKINS_URL}/job/${j}/build"
  curl_args=(-s -o /dev/null -w "%{http_code}" -u "${JENKINS_USER}:${JENKINS_API_TOKEN}" -X POST "$url")
  [[ -n "$crumb" ]] && curl_args+=(-H "${crumb_field}: ${crumb}")
  code="$(curl "${curl_args[@]}")"
  if [[ "$code" == "201" || "$code" == "200" ]]; then
    echo "Triggered scan: $j"
  else
    echo "Failed to trigger $j (HTTP $code)"
  fi
done
