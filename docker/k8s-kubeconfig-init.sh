#!/bin/bash
# Shared kubeconfig setup for k8s port-forward sidecars (kind API via host gateway).

prepare_kubeconfig() {
  export KUBECONFIG=/tmp/kubeconfig
  if [ ! -f /kube/config ]; then
    echo "No kubeconfig at /kube/config"
    return 1
  fi
  cp /kube/config /tmp/kubeconfig
  sed -i 's|https://127.0.0.1:|https://host.docker.internal:|g' /tmp/kubeconfig
  sed -i 's|https://localhost:|https://host.docker.internal:|g' /tmp/kubeconfig
  kubectl config set-cluster kind-trading-cluster --insecure-skip-tls-verify=true 2>/dev/null || true
}
