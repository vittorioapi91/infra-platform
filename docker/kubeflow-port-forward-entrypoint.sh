#!/bin/bash
set -euo pipefail
source /kubeconfig-init.sh
CONTEXT="${KUBECTL_CONTEXT:-kind-trading-cluster}"

if ! prepare_kubeconfig; then
  sleep infinity
fi

while true; do
  if kubectl get svc ml-pipeline-ui -n kubeflow --context "${CONTEXT}" >/dev/null 2>&1; then
    echo "Starting kubeflow port-forward on :8088"
    kubectl port-forward -n kubeflow svc/ml-pipeline-ui 8088:80 \
      --context "${CONTEXT}" --address=0.0.0.0 || true
  else
    echo "ml-pipeline-ui service not found; retry in 30s"
    sleep 30
    continue
  fi
  echo "kubeflow port-forward exited; restarting in 3s..."
  sleep 3
done
