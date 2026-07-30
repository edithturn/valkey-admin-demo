#!/bin/bash
set -euo pipefail

NAMESPACE="demo"

echo "==> Checking prerequisites..."
for cmd in kubectl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: $cmd is not installed or not in PATH"
    exit 1
  fi
done
echo "    kubectl found."

echo ""
echo "==> Creating namespace '$NAMESPACE' if it does not exist..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "==> Deploying Valkey and load generator..."
kubectl apply -f k8s/ -n "$NAMESPACE"

echo ""
echo "==> Waiting for Valkey to be ready..."
kubectl rollout status deployment/valkey -n "$NAMESPACE" --timeout=120s

echo ""
echo "==> Verifying Valkey is responding..."
kubectl exec -n "$NAMESPACE" deploy/valkey -- valkey-cli ping

echo ""
echo "======================================================"
echo "  Valkey is up in namespace: $NAMESPACE"
echo "======================================================"
echo ""
echo "Next — forward Valkey to your machine (keep this running):"
echo ""
echo "  kubectl port-forward --address 0.0.0.0 svc/valkey -n $NAMESPACE 6379:6379"
echo ""
echo "Then start Valkey Admin (in a new terminal):"
echo ""
echo "  docker compose up -d"
echo ""
echo "Open http://localhost:8080 and connect to host.docker.internal:6379"
