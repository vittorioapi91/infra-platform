#!/bin/bash
set -euo pipefail
source /kubeconfig-init.sh
CONTEXT="${KUBECTL_CONTEXT:-kind-trading-cluster}"

if ! prepare_kubeconfig; then
  sleep infinity
fi

while true; do
  if kubectl get svc kubernetes-dashboard -n kubernetes-dashboard --context "${CONTEXT}" >/dev/null 2>&1; then
    echo "Starting kubernetes-dashboard port-forward on :8001"
    kubectl port-forward -n kubernetes-dashboard service/kubernetes-dashboard 8001:443 \
      --context "${CONTEXT}" --address=0.0.0.0 || true
  else
    echo "kubernetes-dashboard service not found; retry in 30s"
    sleep 30
    continue
  fi
  echo "dashboard port-forward exited; restarting in 3s..."
  sleep 3
done
