# Lab 9 — Make Two Clusters Behave Like One (Multi-Cluster Service Mesh with Istio)

**Day 2 · Extending and Operating the Platform Under Pressure**

> ✅ **Tested end-to-end** on a **real two-cluster GKE platform** (`platform-a`, `platform-b`). Every screenshot is a real capture. The payoff: a backend on `platform-a` calls `http://database:5432` **by plain Service name** and the request is routed *across the mesh* to the real database Pod on `platform-b` — proven by inspecting the Envoy sidecar's own endpoint list and seeing a remote-cluster Pod IP.

## What you'll learn

- Istio's **multi-primary, multi-network** model: one control plane per cluster, a shared root of trust, connected by **east-west gateways** rather than assuming direct pod-to-pod routing.
- Why a **shared root CA** is what makes cross-cluster mTLS trustworthy — two independent cluster CAs would never trust each other's workload certs.
- How the *same Service name* in both clusters becomes **one logical service**, so a caller uses a Service name instead of a hand-copied load-balancer IP.
- How to *prove* cross-cluster routing by inspecting the Envoy sidecar's endpoints.

## What you'll do

You'll generate a shared CA, install Istio on both clusters, stand up east-west gateways, exchange remote secrets so each control plane discovers the other's endpoints, then route a call from `platform-a` to a database that only exists on `platform-b` — by name.

## Time & cost

- **Time:** ~75 minutes — the most involved lab of the day.
- **Cost:** two small GKE clusters plus two extra load balancers (the east-west gateways).

---

## Before you start

- **Where you'll work:** in a **terminal** with `kubectl` contexts named `platform-a` and `platform-b` for two GKE clusters, and **`istioctl`** installed.
- **Assumed setup:** both clusters run the course storefront app (a `backend` Deployment on `platform-a`; the real `database` Pod on `platform-b`). This lab wires the two clusters into one mesh so `backend` can reach `database` by name.

> **Nutanix note.** Istio is platform-agnostic; this multi-primary/multi-network topology installs identically across **NKE** clusters — including *across sites*, which is a common Nutanix pattern (a mesh spanning two data centres or a DC and an edge). The only GKE-specific parts are the two clusters' provisioning and the LoadBalancer Services fronting the east-west gateways; on-prem those gateways get their external IPs from **MetalLB** (Lab 13) or Nutanix load balancing instead. The certs, Istio install, remote-secret exchange, and cross-cluster discovery are unchanged.

---

## The idea in 60 seconds

In **multi-primary, multi-network**, each cluster runs its own `istiod` and they're peers. "Multi-network" means Istio does *not* assume `platform-a`'s pods can reach `platform-b`'s pod IPs directly — cross-cluster traffic flows through a per-cluster **east-west gateway** (an Istio-managed Envoy exposed by a load balancer).

For this to be *trustworthy*, both clusters' workload certs must chain to the **same root CA** — so you generate one root and a per-cluster intermediate *before* installing Istio. Then you exchange **remote secrets** so each `istiod` can watch the other's services. Once both clusters have a `database` Service of the same name, Istio treats them as **one logical service**, and a call to `database` from `platform-a` is routed to the real endpoint on `platform-b`.

![Architecture diagram](artifacts/lab-09/diagrams/diagram.png)

---

## Step 1 — Generate a shared root CA and per-cluster intermediates

**Goal:** create one root CA and an intermediate per cluster, and install them as each cluster's `cacerts`.

```bash
mkdir -p /tmp/istio-certs && cd /tmp/istio-certs
ISTIO_VERSION=1.31.0            # match your installed istioctl version
curl -L https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istio-${ISTIO_VERSION}-osx-arm64.tar.gz -o istio.tar.gz
tar xzf istio.tar.gz
cd istio-${ISTIO_VERSION}/tools/certs
make -f Makefile.selfsigned.mk root-ca
make -f Makefile.selfsigned.mk platform-a-cacerts
make -f Makefile.selfsigned.mk platform-b-cacerts
```

![Root CA generated, then platform-a and platform-b intermediates, chained correctly](artifacts/lab-09/screenshots/01-certs-generated.png)

Install each intermediate as the cluster's `cacerts` secret:

```bash
for ctx in platform-a platform-b; do
  kubectl --context $ctx create namespace istio-system
  kubectl --context $ctx create secret generic cacerts -n istio-system \
    --from-file=${ctx}/ca-cert.pem --from-file=${ctx}/ca-key.pem \
    --from-file=${ctx}/root-cert.pem --from-file=${ctx}/cert-chain.pem
done
```

![istio-system namespace + cacerts secret created on both clusters](artifacts/lab-09/screenshots/02-cacerts-secrets.png)

**What you should see:** the root CA and both intermediates generated, and `cacerts` created in `istio-system` on both clusters.

**What this means:** both clusters now share one root of trust, so workload certs issued by each `istiod` will validate across the cluster boundary — the prerequisite for cross-cluster mTLS.

> ⚠️ **Gotcha — pin `ISTIO_VERSION` to your installed `istioctl`.** This download is used only for its `tools/certs` Makefiles and `samples/multicluster/` scripts. Mixing an older samples release with a newer installed `istioctl` risks `IstioOperator` API drift. Run `istioctl version --remote=false` and match it (swap `osx-arm64` for `linux-amd64` on Linux).

---

## Step 2 — Install Istio on both clusters

**Goal:** install a control plane per cluster — same `meshID`, different `network`.

```bash
istioctl install -y --context=platform-a -f - <<EOF
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  values:
    global:
      meshID: mesh1
      network: network1
      multiCluster: {clusterName: platform-a}
EOF

istioctl install -y --context=platform-b -f - <<EOF
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  values:
    global:
      meshID: mesh1
      network: network2
      multiCluster: {clusterName: platform-b}
EOF

kubectl --context platform-a label namespace default istio-injection=enabled --overwrite
kubectl --context platform-b label namespace default istio-injection=enabled --overwrite
```

**What you should see:** clean Istio installs on both clusters (core, CNI, istiod, ingress), and `default` labelled for sidecar injection.

![Istio installed on both clusters; default namespace labeled](artifacts/lab-09/screenshots/04-istio-install-b.png)

**What this means:** the **same `meshID`** makes them one mesh; the **different `network`** per cluster tells Istio *not* to assume direct pod routing between them, and to use the east-west gateway instead. (`platform-a` alone: [`03-istio-install-a.png`](artifacts/lab-09/screenshots/03-istio-install-a.png).)

---

## Step 3 — Expose an east-west gateway on each cluster

**Goal:** give each cluster the Envoy gateway through which cross-cluster traffic flows.

```bash
cd /tmp/istio-certs/istio-${ISTIO_VERSION}

samples/multicluster/gen-eastwest-gateway.sh --mesh mesh1 --network network1 --cluster platform-a \
  | istioctl --context platform-a install -y -f -
kubectl --context platform-a apply -n istio-system -f samples/multicluster/expose-services.yaml

samples/multicluster/gen-eastwest-gateway.sh --mesh mesh1 --network network2 --cluster platform-b \
  | istioctl --context platform-b install -y -f -
kubectl --context platform-b apply -n istio-system -f samples/multicluster/expose-services.yaml

kubectl --context platform-a get svc istio-eastwestgateway -n istio-system
kubectl --context platform-b get svc istio-eastwestgateway -n istio-system
```

![platform-a east-west gateway created](artifacts/lab-09/screenshots/05-eastwest-a.png)

![Both east-west gateways; platform-a already has an EXTERNAL-IP, platform-b still pending](artifacts/lab-09/screenshots/06-eastwest-b.png)

**What you should see:** both `istio-eastwestgateway` Services get real external IPs (`platform-b`'s may take a minute longer to leave `<pending>`).

**What this means:** `expose-services.yaml` is what makes mesh Services reachable *through* the gateway — without it the gateway exists but forwards nothing.

---

## Step 4 — Exchange remote secrets (link the two control planes)

**Goal:** give each `istiod` read access to the other cluster so it can discover its endpoints.

```bash
# wait for platform-b's gateway IP first
until kubectl --context platform-b get svc istio-eastwestgateway -n istio-system \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null | grep -q .; do sleep 5; done

istioctl create-remote-secret --context=platform-a --name=platform-a | kubectl --context=platform-b apply -f -
istioctl create-remote-secret --context=platform-b --name=platform-b | kubectl --context=platform-a apply -f -
```

![Remote secrets created on both clusters](artifacts/lab-09/screenshots/07-remote-secrets.png)

**What you should see:** `istio-remote-secret-platform-a` and `-platform-b` created.

**What this means:** each cluster's `istiod` now holds a client credential for the *other* cluster, so it can watch the other's Endpoints/Services and fold them into its own service registry. Without this step, both clusters have a healthy standalone mesh that simply doesn't know the other exists.

---

## Step 5 — Route to a Service that lives only on the other cluster

**Goal:** replace a hand-copied IP with a plain Service name resolved across the mesh.

```bash
# a 'database' Service on platform-a with NO local pods — deliberately
kubectl --context platform-a apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata: {name: database}
spec:
  ports: [{port: 5432, targetPort: 5432}]
  selector: {app: database}
EOF

kubectl --context platform-a set env deployment/backend DB_HOST=database
kubectl --context platform-a rollout restart deployment/backend
kubectl --context platform-a rollout status deployment/backend --timeout=120s
kubectl --context platform-a exec deployment/backend -- \
  python3 -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8080/catalog').read().decode())"
```

**What you should see:** the real product list — `[{"name":"Keyboard","price":49.99},{"name":"Mouse","price":19.99},{"name":"Monitor","price":199.99}]` — even though `DB_HOST` is now the plain name `database`, whose only real endpoint is on `platform-b`.

![database Service created, backend rerouted, real product list returned](artifacts/lab-09/screenshots/08-mesh-native-routing.png)

**Prove it's genuinely cross-cluster** by inspecting the backend sidecar's endpoints:

```bash
istioctl proxy-config endpoints deployment/backend.default --context platform-a | grep -i database
```

**What you should see:** an endpoint like `10.72.1.10:5432 HEALTHY` — an IP inside `platform-b`'s Pod CIDR (`10.72.0.0/14`), nowhere near `platform-a`'s (`10.84.0.0/14`).

![Envoy endpoint for 'database' resolves to a platform-b Pod IP](artifacts/lab-09/screenshots/09-proxy-config-endpoint.png)

**What this means:** direct proof — `platform-a`'s backend sidecar is routing this call across the mesh to the real Pod on `platform-b`, not to anything local. The same Service name, in both clusters, is one logical service.

---

## What you learned

| You saw… | in Step | proof |
|---|---|---|
| A shared root CA with per-cluster intermediates | 1 | `cacerts` on both clusters, one root |
| Multi-primary control planes, one mesh, two networks | 2 | same `meshID`, different `network` |
| East-west gateways expose services cross-cluster | 3 | real external IPs on both gateways |
| Remote secrets let each control plane see the other | 4 | `istio-remote-secret-*` on both |
| A call routes cross-cluster by Service name | 5 | Envoy endpoint = a `platform-b` Pod IP |

## Evidence

Real screenshots for this lab are in [`artifacts/lab-09/screenshots/`](artifacts/lab-09/screenshots/) (9 images).

---

---

**Next:** [Lab 10 — Block Bad Images Before They Run (Image Scanning & Admission Control with Kyverno)](lab-10-image-scanning-admission-control.md)
