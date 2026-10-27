# Valkey Admin Demo

A demo showing Valkey Admin connecting to a live Valkey instance running in Kubernetes.

---

## Option A:  Kubernetes Cluster Demo (Valkey Operator)

A 3-shard × 2-node Valkey cluster managed by the Valkey Operator, with Valkey Admin deployed inside the cluster.

### Prerequisites

- A running Kubernetes cluster (v1.31+) with `kubectl` configured
- Helm 3
- [Valkey Operator](https://github.com/valkey-io/valkey-operator) installed in the cluster, install it with:

```bash
helm repo add valkey https://valkey.io/valkey-helm
helm repo update
helm search repo valkey
helm install valkey-operator valkey/valkey-operator -n valkey-operator-system --create-namespace
```

Verify it's running:

```bash
kubectl get pods -n valkey-operator-system
# Output
NAME                               READY   STATUS    RESTARTS   AGE
valkey-operator-78f45b6f49-2dljp   1/1     Running   0          67s
```

> The operator lives in its own namespace (`valkey-operator-system`).

### Step 1: Deploy the Valkey cluster

```bash

# This yaml created the `demo-cluster` namespace and Valkey cluster
kubectl apply -f k8s-cluster/valkeycluster.yaml

# Wait for all 6 pods to be `2/2 Running`:
kubectl get pods -n demo-cluster -w

# Output
NAME                READY   STATUS    RESTARTS   AGE
valkey-demo-0-0-0   2/2     Running   0          36s
valkey-demo-0-1-0   2/2     Running   0          36s
valkey-demo-1-0-0   2/2     Running   0          36s
valkey-demo-1-1-0   2/2     Running   0          36s
valkey-demo-2-0-0   2/2     Running   0          35s
valkey-demo-2-1-0   2/2     Running   0          35s

# Verify the cluster formed correctly. You can check the CR's own status:
kubectl get valkeycluster -n demo-cluster

# Output
NAME   STATE   REASON           AGE
demo   Ready   ClusterHealthy   88s

# Or check cluster state directly on a node:
kubectl exec -n demo-cluster valkey-demo-0-0-0 -c server -- \
  sh -c "unset VALKEYCLI_AUTH && valkey-cli --user valkey-admin -a '' CLUSTER INFO" \
  2>&1 | grep cluster_state

# Output
cluster_state:ok
```

### Step 2: Deploy Valkey Admin

```bash
# This yaml will install valkey-admin in `demo-cluster` namespace 
kubectl apply -f k8s-cluster/valkey-admin.yaml

# Wait for it to be ready:
kubectl get pods -n demo-cluster | grep valkey-admin

# Output
valkey-admin-6777cf4bcf-9wpxx   1/1     Running   0          29s
```

### Step 3: Deploy the load generator

This seeds the cluster with realistic data (sessions, products, leaderboards, orders) and keeps traffic flowing. The seeding/traffic logic lives in plain shell scripts under `k8s-cluster/scripts/` (not inlined in the YAML), so generate a ConfigMap from them first, then apply the Deployment:

```bash
kubectl create configmap load-generator-scripts \
  --from-file=k8s-cluster/scripts/seed.sh \
  --from-file=k8s-cluster/scripts/generate-load.sh \
  -n demo-cluster --dry-run=client -o yaml | kubectl apply -f -

```
To watch the seed progress
```bash
kubectl apply -f k8s-cluster/load-generator.yaml
```

> If you edit `seed.sh` or `generate-load.sh`, re-run the `kubectl create configmap ... | kubectl apply -f -` command above and restart the deployment (`kubectl rollout restart deployment/load-generator -n demo-cluster`) to pick up the change, the ConfigMap doesn't auto-reload into a running pod.

> **Watch out:** there are two `load-generator.yaml` files in this repo, `k8s-cluster/load-generator.yaml` (this one, for the Operator-managed cluster demo, connects to `valkey-demo` in cluster mode) and `k8s/load-generator.yaml` (for the standalone Option B Docker demo, connects to a plain `valkey` host). Applying the wrong one into `demo-cluster` will silently hang forever waiting to ping a host (`valkey`) that doesn't exist there, and nothing gets seeded. Always use `k8s-cluster/load-generator.yaml` for this option.

### Step 4: Port-forward Valkey Admin

```bash
# The Valkey Admin pod runs inside the cluster and its port is not accessible from outside. kubectl port-forward creates a temporary tunnel so your local browser can reach it at http://localhost:8080.
kubectl port-forward svc/valkey-admin 8080:8080 -n demo-cluster
```

Open **http://localhost:8080** in your browser.

[Insert Image Here]

### Step 5: Connect to the cluster

Valkey Admin opens with an **Add Connection** screen.

You need the IP of a running Valkey pod, get it with:

```bash
kubectl get pods -n demo-cluster -o wide | grep valkey-demo
```

Pick any primary pod IP and fill in:

- **Host:** `<pod-ip>` (e.g. `10.42.2.42`)
- **Port:** `6379`
- **Username:** `valkey-admin`
- **Password:** leave empty
- **Endpoint type:** Cluster

Click **Connect**. Valkey Admin will auto-discover all 6 nodes.

> **Note:** The Valkey Operator only exposes a headless service. You must connect via a direct pod IP — the headless DNS name causes connection routing issues with the Glide cluster client.
> **Note:** The pod naming convention tells you: valkey-demo-{shard}-{role}-{index} — the middle number is the role, where 0 = primary and 1 = replica. So from your output, the primaries are: 
  - valkey-demo-0-**0**-0 → 10.42.2.3
  - valkey-demo-1-**0**-0 → 10.42.2.4
  - valkey-demo-2-**0**-0 → 10.42.1.4

### What you will see

- **Cluster Topology**: 3 primaries + 3 replicas, memory and key count per node
- **Dashboard**: live commands/sec, memory, connected clients
- **Key Browser**: thousands of pre-seeded keys (sessions, products, leaderboards)
- **Hot Keys**: most-accessed keys from the load generator
- **Command Logs** : real-time command stream

### Optional: Generate historical metrics data (Last 30 Days)

Valkey Admin 1.3 supports viewing up to 30 days of CPU and memory metrics. Since real data takes weeks to accumulate, you can backfill synthetic historical data to demo this feature immediately.

See [metrics-backfill/README.md](metrics-backfill/README.md) for full instructions. Quick start:

```bash
# After connecting to the cluster in the UI (Step 5):
./metrics-backfill/backfill.sh 45
```

This generates 45 days of data — 30 days visible in the chart plus 15 days outside the retention window — and restarts Valkey Admin automatically.

### Teardown

```bash
kubectl delete namespace demo-cluster
```

This removes the cluster, Valkey Admin, and the load generator, but leaves the Valkey Operator itself untouched (it lives in `valkey-operator-system`, not `demo-cluster`), you won't need to reinstall it before redeploying this demo again.

---

## Option B:  Standalone Docker Demo

A single Valkey instance with Valkey Admin running via Docker Compose.

### Prerequisites

- A running Kubernetes cluster (`kubectl` configured)
- [Docker](https://docs.docker.com/get-docker/) with Docker Compose v2

### Step 1 — Deploy Valkey to Kubernetes

```bash
./k8s-valkey-standalone/setup.sh
```

### Step 2 — Forward the Valkey port

```bash
kubectl port-forward --address 0.0.0.0 svc/valkey -n demo 6379:6379
```

Leave this running.

### Step 3 — Start Valkey Admin

```bash
docker compose -f k8s-valkey-standalone/docker-compose.yml up -d
```

Open **http://localhost:8080**.

### Step 4 — Connect to Valkey

- **Host:** `host.docker.internal`
- **Port:** `6379`
- Uncheck **Use TLS**

Click **Connect**.

### Teardown

```bash
kubectl delete namespace demo
docker compose -f k8s-valkey-standalone/docker-compose.yml down
```

---

## Architecture (Cluster mode)

```
  Kubernetes cluster (demo-cluster namespace)
  ┌──────────────────────────────────────────────────────┐
  │                                                      │
  │  load-generator pod                                  │
  │  (seeds data + continuous traffic)                   │
  │            │                                         │
  │            ▼                                         │
  │  ┌─────────────────────────────────────┐             │
  │  │  Valkey Cluster (Operator-managed)  │             │
  │  │  3 shards × 2 nodes = 6 pods        │             │
  │  │  svc: valkey-demo (headless :6379)  │             │
  │  └─────────────────────────────────────┘             │
  │            │                                         │
  │            ▼                                         │
  │  ┌──────────────────────┐                            │
  │  │  valkey-admin pod    │                            │
  │  │  DEPLOYMENT_MODE=Web │                            │
  │  │  svc: valkey-admin   │                            │
  │  │  :8080               │                            │
  │  └──────────────────────┘                            │
  └──────────────────────────────────────────────────────┘
            │ kubectl port-forward 8080
            ▼
     http://localhost:8080
```
