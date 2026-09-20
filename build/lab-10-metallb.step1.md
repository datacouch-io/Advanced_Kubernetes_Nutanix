# Lab 10 — Give On-Prem Services a Real IP (Bare-Metal LoadBalancer with MetalLB)

**Day 3 · Stateful Workloads, Persistent Storage & Service Exposure**

> ✅ **Tested end-to-end** on a real 4-node `kind` cluster with **MetalLB v0.14.9**. Every screenshot is a real capture. You'll watch a `Service type=LoadBalancer` sit at `<pending>` forever, then get a **real, reachable IP** from MetalLB — and keep that IP working after you kill the node that was announcing it.

## What you'll learn

- Why `Service type=LoadBalancer` gives an `EXTERNAL-IP` on a cloud (GKE) but stays `<pending>` on bare metal / on-prem — there's no cloud load-balancer controller.
- How **MetalLB** fills that gap: an `IPAddressPool` plus **Layer-2 advertisement** that assigns an address and announces it from a node.
- How MetalLB **survives a node failure** — the address is re-announced from another node.
- Why this is one of the most **Nutanix-relevant** labs: on-prem NKE clusters need exactly this.

## What you'll do

You'll expose a Deployment as a LoadBalancer and see it stuck `<pending>`. Then you'll install MetalLB, give it an address pool, and watch the Service get a reachable IP. Finally you'll `docker stop` the node announcing that IP and prove the Service stays up.

## Time & cost

- **Time:** ~40 minutes.
- **Cost:** **$0** — runs on a local `kind` cluster.

---

## Before you start

- **Where you'll work:** in a **terminal** on your own machine.
- **Tools you need:** `docker`, `kind`, `kubectl`.
- **Cluster:** a multi-node `kind` cluster (this course's `advk8s-day1`, 1 control-plane + 3 workers — you need multiple nodes for the failover step).

> **Nutanix note — and why this one is `kind`, not GKE.** On GKE a `LoadBalancer` Service is handled for you by a Google Cloud load balancer, so MetalLB would be redundant. MetalLB is for **bare-metal and on-prem** clusters that have no cloud LB — which is exactly the situation on a **Nutanix** on-prem cluster. So this lab runs on `kind` to *simulate* bare metal. On real NKE you'd install MetalLB the same way (or use Nutanix's own load-balancing), point the `IPAddressPool` at a range on your Nutanix network, and everything else here is identical.

---

## The idea in 60 seconds

`Service type=LoadBalancer` asks the cluster for an external IP. On a cloud, a controller calls the cloud API and provisions a real load balancer, filling in `EXTERNAL-IP`. On bare metal there's no such controller, so the field stays `<pending>` — the Service works *inside* the cluster but has no external address.

**MetalLB** is that missing controller for bare metal. You give it a pool of IPs (`IPAddressPool`) from your network, and in **Layer-2 mode** one node answers ARP for each assigned IP and forwards traffic to the Service. If that node dies, MetalLB re-elects another node to announce the IP — so the address survives node failure.

![Architecture diagram](artifacts/lab-10/diagrams/diagram.png)

---

## Step 1 — Watch a LoadBalancer Service hang at `<pending>`

**Goal:** see that, without a cloud LB, an external IP never appears.

**1. Expose a Deployment as a LoadBalancer:**

```bash
kubectl create deployment web --image=nginx:1.27-alpine
kubectl expose deployment web --port=80 --type=LoadBalancer --name=web-lb
kubectl get svc web-lb
```

**What you should see:** `web-lb` of type `LoadBalancer` with `EXTERNAL-IP: <pending>` — and it will stay that way indefinitely.

![LoadBalancer Service stuck at <pending> on kind](artifacts/lab-10/screenshots/01-pending.png)

**What this means:** nothing in a bare-metal cluster is watching for `LoadBalancer` Services to assign them an address. The Service has a `ClusterIP` and works inside the cluster, but there's no external IP. On Nutanix on-prem you'd hit exactly this.

---

## Step 2 — Install MetalLB and give it an address pool

**Goal:** install MetalLB, hand it a range of IPs from the cluster's network, and watch the Service get a reachable address.

**1. Install MetalLB and wait for it:**

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml
kubectl -n metallb-system rollout status deployment/controller --timeout=150s
kubectl -n metallb-system rollout status daemonset/speaker --timeout=120s
```

**2. Give it an `IPAddressPool` from the kind docker subnet** (find yours with `docker network inspect kind`; here it's `172.19.0.0/16`, so we use a high, unused range):

```bash
kubectl apply -f - <<'EOF'
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata: {name: kind-pool, namespace: metallb-system}
spec:
  addresses: ["172.19.255.200-172.19.255.250"]
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata: {name: l2, namespace: metallb-system}
spec:
  ipAddressPools: [kind-pool]
EOF

kubectl get svc web-lb
```

**3. Reach the IP from inside the cluster network** (on Docker-Desktop-for-Mac the docker subnet isn't routable from your Mac, so curl from a node):

```bash
IP=$(kubectl get svc web-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
docker exec advk8s-day1-worker3 curl -s -o /dev/null -w "HTTP %{http_code}\n" http://$IP
```

**What you should see:** `web-lb` now has a real `EXTERNAL-IP` (e.g. `172.19.255.200`), and the curl returns **`HTTP 200`**.

![MetalLB assigned a real IP; curl returns 200](artifacts/lab-10/screenshots/02-metallb-ip.png)

**What this means:** MetalLB is the load-balancer controller the cluster was missing. It picked an address from your pool and is announcing it (Layer-2) from one node, so the Service is now reachable at a stable IP.

---

## Step 3 — Survive a node failure

**Goal:** kill the node that's announcing the IP and prove the Service stays reachable.

**1. Find the announcing node, then stop it:**

```bash
IP=$(kubectl get svc web-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
kubectl describe svc web-lb | grep 'announcing from node'   # e.g. advk8s-day1-worker

# simulate a node failure:
docker stop advk8s-day1-worker
```

**2. Wait for Kubernetes to mark the node `NotReady`, then curl the same IP from a surviving node:**

```bash
kubectl get node advk8s-day1-worker            # NotReady after a few seconds
kubectl describe svc web-lb | grep 'announcing from node'   # now a DIFFERENT node
docker exec advk8s-day1-worker3 curl -s -o /dev/null -w "HTTP %{http_code}\n" http://$IP
```

**What you should see:** after the node goes `NotReady`, MetalLB shows the IP `announcing from node "advk8s-day1-worker2"` (a different node), and curling the **same IP** returns **`HTTP 200`**.

![After the announcing node fails, the IP is re-announced elsewhere and still returns 200](artifacts/lab-10/screenshots/03-failover.png)

> ⚠️ **Gotcha — there's a brief failover window.** For the first few seconds after the node stops, curl may fail (`HTTP 000`): Kubernetes hasn't yet marked the node `NotReady`, so it still routes some traffic to the dead Pod, and the L2 announcement hasn't moved. Once the node is `NotReady` (endpoints pruned) and MetalLB re-announces from a healthy node, it recovers. This is normal L2 failover behaviour — L2 mode fails *over*, it doesn't load-balance across nodes.

**3. Restore the node:**

```bash
docker start advk8s-day1-worker
```

---

## Step 4 — Clean up

```bash
kubectl delete svc web-lb --ignore-not-found
kubectl delete deployment web --ignore-not-found
# to remove MetalLB: kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml
```

---

## What you learned

| You saw… | in Step | proof |
|---|---|---|
| A LoadBalancer Service stays `<pending>` on bare metal | 1 | `EXTERNAL-IP <pending>` on kind |
| MetalLB assigns a real IP from a pool | 2 | `web-lb` gets `172.19.255.200`, curl `200` |
| The IP is reachable via L2 announcement from a node | 2 | curl `200` from another node |
| The IP survives the announcing node failing | 3 | re-announced from a different node, curl `200` |
| L2 mode fails over (brief window), it doesn't balance | 3 gotcha |

## Evidence

Real screenshots for this lab are in [`artifacts/lab-10/screenshots/`](artifacts/lab-10/screenshots/) (3 images), and a command transcript is in [`artifacts/lab-10/evidence/lab-10-metallb.txt`](artifacts/lab-10/evidence/lab-10-metallb.txt).

---

**Next:** [Lab 11 — Log-Based Diagnosis with Loki](lab-11-loki.md)
