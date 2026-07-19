# Valkey Admin Demo

A demo showing Valkey Admin connecting to a live Valkey instance running in Kubernetes.

---

## Option A — Kubernetes Cluster Demo (Valkey Operator)

A 3-shard × 2-node Valkey cluster managed by the Valkey Operator, with Valkey Admin deployed inside the cluster.

### Prerequisites

- A running Kubernetes cluster (v1.31+) with `kubectl` configured
- Helm 3
- [Valkey Operator](https://github.com/valkey-io/valkey-operator) installed in the cluster — install it with:

```bash
helm repo add valkey https://valkey.io/valkey-helm
helm repo update
helm install valkey-operator valkey/valkey-operator -n valkey-operator-system --create-namespace
```

Verify it's running:

```bash
kubectl get pods -n valkey-operator-system
```

> The operator lives in its own namespace (`valkey-operator-system`), separate from the demo's `demo-cluster` namespace. Deleting `demo-cluster` (see Teardown) does **not** remove the operator — you only need to install it once per Kubernetes cluster. If you tear down the whole Kubernetes cluster itself (not just the namespace), you'll need to reinstall the operator before redeploying this demo.

### Step 1 — Deploy the Valkey cluster

```bash
kubectl apply -f k8s-cluster/valkeycluster.yaml
```

Wait for all 6 pods to be `2/2 Running`:

```bash
kubectl get pods -n demo-cluster -w
```

Verify the cluster formed correctly. You can check the CR's own status:

```bash
kubectl get valkeycluster -n demo-cluster -w
# Expected: STATE Ready, REASON ClusterHealthy
```

Or check cluster state directly on a node:

```bash
kubectl exec -n demo-cluster valkey-demo-0-0-0 -c server -- \
  sh -c "unset VALKEYCLI_AUTH && valkey-cli --user valkey-admin -a '' CLUSTER INFO" \
  2>&1 | grep cluster_state
# Expected: cluster_state:ok
```

### Step 2 — Deploy Valkey Admin

```bash
kubectl apply -f k8s-cluster/valkey-admin.yaml
```

Wait for it to be ready:

```bash
kubectl get pods -n demo-cluster | grep valkey-admin
```

### Step 3 — Deploy the load generator

This seeds the cluster with realistic data (sessions, products, leaderboards, orders) and keeps traffic flowing. The seeding/traffic logic lives in plain shell scripts under `k8s-cluster/scripts/` (not inlined in the YAML), so generate a ConfigMap from them first, then apply the Deployment:

```bash
kubectl create configmap load-generator-scripts \
  --from-file=k8s-cluster/scripts/seed.sh \
  --from-file=k8s-cluster/scripts/generate-load.sh \
  -n demo-cluster --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f k8s-cluster/load-generator.yaml
```

> If you edit `seed.sh` or `generate-load.sh`, re-run the `kubectl create configmap ... | kubectl apply -f -` command above and restart the deployment (`kubectl rollout restart deployment/load-generator -n demo-cluster`) to pick up the change — the ConfigMap doesn't auto-reload into a running pod.

> **Watch out:** there are two `load-generator.yaml` files in this repo — `k8s-cluster/load-generator.yaml` (this one, for the Operator-managed cluster demo, connects to `valkey-demo` in cluster mode) and `k8s/load-generator.yaml` (for the standalone Option B Docker demo, connects to a plain `valkey` host). Applying the wrong one into `demo-cluster` will silently hang forever waiting to ping a host (`valkey`) that doesn't exist there, and nothing gets seeded. Always use `k8s-cluster/load-generator.yaml` for this option.

### Step 4 — Port-forward Valkey Admin

```bash
kubectl port-forward svc/valkey-admin 8080:8080 -n demo-cluster
```

Open **http://localhost:8080** in your browser.

### Step 5 — Connect to the cluster

Valkey Admin opens with an **Add Connection** screen.

You need the IP of a running Valkey pod — get it with:

```bash
kubectl get pods -n demo-cluster -o wide | grep valkey-demo
```

Pick any primary pod IP (e.g. `10.42.2.42`) and fill in:

- **Host:** `<pod-ip>` (e.g. `10.42.2.42`)
- **Port:** `6379`
- **Username:** `valkey-admin`
- **Password:** leave empty
- **Endpoint type:** Cluster

Click **Connect**. Valkey Admin will auto-discover all 6 nodes.

> **Note:** The Valkey Operator only exposes a headless service. You must connect via a direct pod IP — the headless DNS name causes connection routing issues with the Glide cluster client.

### What you will see

- **Cluster Topology** — 3 primaries + 3 replicas, memory and key count per node
- **Dashboard** — live commands/sec, memory, connected clients
- **Key Browser** — thousands of pre-seeded keys (sessions, products, leaderboards)
- **Hot Keys** — most-accessed keys from the load generator
- **Command Logs** — real-time command stream

### Known limitations (Valkey Operator, current version)

This is not a production-ready deployment pattern — it's a demo of Valkey Admin against a real Operator-managed cluster. Straight from the operator's own docs:

- **No operator-managed external access (LoadBalancer/Ingress)** — this is why we connect Valkey Admin via a direct pod IP instead of a stable endpoint. Pod IPs change on every restart/reschedule, so you'll need to re-grab the IP each time you redeploy.
- No cert-manager integration (manual TLS Secret only)
- No module support
- No backup/restore
- No default shard-aware anti-affinity (must configure Kubernetes affinity rules yourself)
- API is `v1alpha1` and may change in future releases
- Cluster mode only (no standalone or sentinel)

Separately (not an operator limitation, still unresolved on our side): the metrics sidecar/exporter is not working yet — needs further investigation into the operator's full CRD reference to see if there's a metrics field we're missing.

For a real deployment, Valkey Admin should run outside the database's namespace/infra entirely, reached through a stable endpoint with network policy restricting direct DB access — none of which this demo sets up, by design, to keep it simple.

### Teardown

```bash
kubectl delete namespace demo-cluster
```

This removes the cluster, Valkey Admin, and the load generator, but leaves the Valkey Operator itself untouched (it lives in `valkey-operator-system`, not `demo-cluster`) — you won't need to reinstall it before redeploying this demo again.

---

## Option B — Standalone Docker Demo

A single Valkey instance with Valkey Admin running via Docker Compose.

### Prerequisites

- A running Kubernetes cluster (`kubectl` configured)
- [Docker](https://docs.docker.com/get-docker/) with Docker Compose v2

### Step 1 — Deploy Valkey to Kubernetes

```bash
./setup.sh
```

### Step 2 — Forward the Valkey port

```bash
kubectl port-forward --address 0.0.0.0 svc/valkey -n demo 6379:6379
```

Leave this running.

### Step 3 — Start Valkey Admin

```bash
docker compose up -d
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
docker compose down
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
