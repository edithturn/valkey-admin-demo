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
DIR="$(dirname "$0")"
kubectl apply -f "$DIR/valkey.yaml" -f "$DIR/valkey-replica.yaml" -n "$NAMESPACE"

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
echo "Next — add a new connection in Valkey Admin:"
echo ""
echo "  Host: valkey.$NAMESPACE.svc.cluster.local"
echo "  Port: 6379"
echo "  Endpoint type: Node"
