#!/bin/bash
set -euo pipefail

DAYS=${1:-45}
NAMESPACE=${2:-demo-cluster}

echo "==> Finding valkey-admin pod in namespace '$NAMESPACE'..."
POD=$(kubectl get pod -n "$NAMESPACE" -l app=valkey-admin -o jsonpath='{.items[0].metadata.name}')
if [ -z "$POD" ]; then
  echo "ERROR: No valkey-admin pod found in namespace '$NAMESPACE'"
  exit 1
fi
echo "    Pod: $POD"

echo ""
echo "==> Locating data directory inside pod..."
DATA_ROOT=$(kubectl exec -n "$NAMESPACE" "$POD" -- find /app /home /usr/src /opt -type d -name "data" -path "*/server/data" 2>/dev/null | head -1)
if [ -z "$DATA_ROOT" ]; then
  echo "ERROR: Could not find server/data directory inside the pod."
  echo "       Make sure you have connected to the Valkey cluster in the UI first."
  exit 1
fi
echo "    Data root: $DATA_ROOT"

# Find directories that contain .ndjson files — these are the actual node data dirs
DATA_DIRS=$(kubectl exec -n "$NAMESPACE" "$POD" -- sh -c \
  "find '$DATA_ROOT' -name '*.ndjson' -not -name '*_synthetic*' -not -name '*_0*' | xargs -I{} dirname {} 2>/dev/null | sort -u" || true)

if [ -z "$DATA_DIRS" ]; then
  echo "ERROR: No node data directories found (no .ndjson files yet)."
  echo "       Make sure you have connected to the Valkey cluster in the UI first"
  echo "       and waited a few seconds for Valkey Admin to write initial metric files."
  exit 1
fi

echo "    Node data dirs found:"
echo "$DATA_DIRS" | sed 's/^/      /'

echo ""
echo "==> Copying gen-metrics.mjs into pod..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kubectl cp "$SCRIPT_DIR/gen-metrics.mjs" "$NAMESPACE/$POD:/tmp/gen-metrics.mjs"

echo ""
echo "==> Generating $DAYS days of synthetic metrics for each node..."
while IFS= read -r DATA_DIR; do
  [ -z "$DATA_DIR" ] && continue
  NODE=$(basename "$DATA_DIR")
  echo "    -> $NODE"
  kubectl exec -n "$NAMESPACE" "$POD" -- node /tmp/gen-metrics.mjs "$DATA_DIR" "$DAYS"
done <<< "$DATA_DIRS"

echo ""
echo "==> Renaming synthetic files to match Valkey Admin naming pattern..."
kubectl exec -n "$NAMESPACE" "$POD" -- sh -c "
  find '$DATA_ROOT' -name '*_synthetic.ndjson' | while read f; do
    mv \"\$f\" \"\$(echo \"\$f\" | sed 's/_synthetic\\.ndjson\$/_0.ndjson/')\"
  done
"
echo "    Files renamed."

echo ""
echo "==> Restarting Valkey Admin to pick up historical data..."
kubectl exec -n "$NAMESPACE" "$POD" -- sh -c "kill 1"
echo "    Restarting — wait ~15 seconds, then open the Dashboard"
echo "    and select 'Last 30 Days'."

echo ""
echo "======================================================"
echo "  Done!"
echo "======================================================"
