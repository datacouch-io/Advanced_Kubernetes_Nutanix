# Lab 7 — Find the Cluster's Breaking Point (Cluster Scale Knee-Point)

**Day 2 · Extending and Operating the Platform Under Pressure**

> ✅ **Tested end-to-end** on a **real GKE cluster** (`advk8s-day2`, `dcproject-462806`), a fixed two-node pool. Every number and the graph come from a real run. What you'll prove: time-to-ready is flat and near-instant while Pods fit — then at one specific replica count it **falls off a cliff**, because the cluster ran out of schedulable CPU. That's the knee, and it's far below the cluster's raw vCPU count.

## What you'll learn

- What a scaling **knee-point** is: the replica count where time-to-ready stops being flat and degrades sharply.
- Why a cluster's *real* capacity is far smaller than its raw vCPU count — system Pods (kube-dns, kube-proxy, …) reserve a big slice of every node before your first Pod lands.
- How to measure the knee yourself: scale in steps, time each step to `Ready`, and read the curve.
- What actually happens past the knee (`Pending` Pods, `Insufficient cpu`) and the three ways to move it out.

## What you'll do

You'll take a fixed two-node cluster, scale a Deployment up in steps (2, 4, 6, … 16 replicas), and time how long each step takes to become fully `Ready`. You'll plot the result and see a flat line that suddenly cliffs — the knee — then look at exactly why the Pods past it can't schedule.

## Time & cost

- **Time:** ~35 minutes.
- **Cost:** negligible beyond the Day-2 cluster — this runs on the fixed two nodes and adds no capacity.

---

## Before you start

- **Where you'll work:** in a **terminal** on your own machine.
- **Tools you need:** `gcloud`, `kubectl`.
- **Cluster:** reuse the Day-2 GKE cluster from [Lab 6](lab-06-operators-finalizers.md), as a **fixed two-node pool** (autoscaling off, so the knee is a clean, fixed boundary rather than a moving target):

```bash
gcloud container clusters update advk8s-day2 --zone us-central1-a \
  --no-enable-autoscaling --node-pool default-pool
gcloud container clusters resize advk8s-day2 --node-pool default-pool --num-nodes 2 --zone us-central1-a --quiet
```

> **Nutanix note.** The measurement technique and the finding — real capacity is far below raw vCPU, and time-to-ready cliffs at the boundary — are identical on any platform. The per-node system reservation differs (GKE's managed DaemonSets vs. NKE's), so the *exact* knee replica count is platform-specific, but the shape is universal. On NKE you'd move the knee out with a bigger node pool or the Kubernetes Cluster Autoscaler, exactly as GKE does (we turned autoscaling off here on purpose so the boundary stays put and is measurable).

---

## The idea in 60 seconds

A node's **allocatable** CPU is already less than its physical vCPU (the kubelet/OS reserve some). Then, before *any* of your workloads land, system Pods — `kube-dns`, `kube-proxy`, `node-local-dns`, CSI drivers, metrics — reserve a big chunk of what's left. So a cluster's *real* capacity for your Pods is a small fraction of its "2 vCPU × 2 nodes = 4 cores" on paper.

While your Pods fit into that real free CPU, the scheduler places them in **seconds** — the flat part of the curve. The instant a step asks for more than the free CPU can hold, the extra Pods go `Pending` with `Insufficient cpu`, and on a fixed cluster they stay there. That's the knee — a hard boundary, which makes scale-up time *bimodal*: near-instant below it, never above it.

![Architecture diagram](artifacts/lab-07/diagrams/diagram.png)

---

## Step 1 — See how little CPU is actually free

**Goal:** confirm a fixed two-node pool and measure the real free capacity, then create the Deployment you'll scale.

**1. Check the nodes and how much CPU is already reserved, then create a Deployment whose Pods each request `50m`:**

```bash
kubectl get nodes --no-headers | grep -c ' Ready '     # 2

# how much CPU is already spoken for, per node:
kubectl describe nodes | grep -A6 'Allocated resources' | grep -E 'cpu'

kubectl create deployment scaletest --image=nginx:1.27 --replicas=0
kubectl set resources deployment scaletest --requests=cpu=50m
```

**What you should see:** two nodes, each with **940m allocatable** but a large fraction already requested by `kube-system` (in our run ~753m on one node, ~561m on the other — two `kube-dns` Pods at ~260m each dominate). Only **~560m** is free cluster-wide — about eleven `50m` Pods.

![Two nodes; most of each node's CPU already reserved by system Pods](artifacts/lab-07/screenshots/01-setup.png)

**What this means:** that ~560m is the real capacity, and it's where the knee will land — around 11–12 of your Pods, not the 4 cores the cluster advertises.

---

## Step 2 — Measure: scale in steps and time each to Ready

**Goal:** scale through a sequence of replica counts, timing each step to fully `Ready` (capped at 20s — past that we call it "did not converge").

**1. Run the measurement loop:**

```bash
for N in 2 4 6 8 10 12 14 16; do
  start=$(date +%s)
  kubectl scale deployment scaletest --replicas=$N
  kubectl rollout status deployment/scaletest --timeout=20s
  end=$(date +%s)
  ready=$(kubectl get pods -l app=scaletest --field-selector=status.phase=Running --no-headers | wc -l | tr -d ' ')
  pending=$(kubectl get pods -l app=scaletest --field-selector=status.phase=Pending --no-headers | wc -l | tr -d ' ')
  echo "replicas=$N  time=$((end-start))s  ready=$ready  pending=$pending"
done
```

**What you should see:** flat and fast up to the boundary, then a wall:

| replicas | time to Ready | ready | pending |
|---:|---:|---:|---:|
| 2 | 2s | 2 | 0 |
| 4 | 2s | 4 | 0 |
| 6 | 2s | 6 | 0 |
| 8 | 3s | 8 | 0 |
| 10 | 3s | 10 | 0 |
| **12** | **22s (timeout)** | **10** | **2** |
| 14 | 22s (timeout) | 10 | 4 |
| 16 | 23s (timeout) | 10 | 6 |

![The measurement: flat and fast, then a cliff](artifacts/lab-07/screenshots/02-measurement.png)

**What this means:** up to **10** replicas everything is `Ready` in 2–3 seconds. At **12**, two Pods can't be placed — `ready` sticks at 10 and the step times out. The cluster's real capacity is exactly 10 of these `50m` Pods (≈500m), matching the ~560m free from Step 1. The knee is at 12.

---

## Step 3 — Graph the knee

**Goal:** plot time-to-ready against replicas so the knee is unmistakable.

The chart below is generated from the measurement above (a small script, `tools/scale_chart.py`, turns the numbers into this SVG/PNG):

![Time-to-ready vs replicas — the knee where Pods stop fitting](artifacts/lab-07/diagrams/knee-chart.png)

**What this means:** the green points (2–10) sit flat along the bottom at 2–3 seconds. Then the line goes almost vertical — the orange point at 12 is the knee, where Pods started going `Pending` and the step stopped converging. There's no gentle ramp: the jump from "instant" to "never" happens between two adjacent steps. That's why the *average* scale-up time is a useless planning number, and the knee is the only one that matters.

---

## Step 4 — Look at what's stuck past the knee

**Goal:** confirm the cliff is unschedulable Pods, not slow ones.

**1. List the Pending Pods and read why:**

```bash
kubectl get pods -l app=scaletest --field-selector=status.phase=Pending
PEND=$(kubectl get pods -l app=scaletest --field-selector=status.phase=Pending -o jsonpath='{.items[0].metadata.name}')
kubectl describe pod "$PEND" | grep -m1 'Insufficient cpu'
```

**What you should see:** several `Pending` Pods, and a `FailedScheduling` event reading **`0/2 nodes are available: 2 Insufficient cpu.`**

![Pending Pods with Insufficient cpu past the knee](artifacts/lab-07/screenshots/03-pending-past-knee.png)

**What this means:** these Pods aren't slow — they're *unschedulable*. On this fixed cluster they'll wait forever. **Moving the knee out** means adding real capacity: bigger nodes (more allocatable each), more nodes, or the cluster autoscaler — which watches for exactly these `Pending` Pods and provisions a node automatically (we turned it off here so the boundary would stay put).

---

## Step 5 — Clean up

```bash
kubectl delete deployment scaletest
```

Leave `advk8s-day2` for Lab 10, or delete it if you're done with Day 2:

```bash
gcloud container clusters delete advk8s-day2 --zone us-central1-a --quiet
```

---

## What you learned

| You saw… | in Step | proof |
|---|---|---|
| Real capacity ≪ raw vCPU (system Pods reserve a lot) | 1 | ~560m free of 1880m allocatable |
| Time-to-ready is flat while Pods fit | 2 / 3 | flat low steps |
| It cliffs at the replica count that exceeds free CPU | 3 | the knee on the graph |
| Past the knee, Pods are `Pending` (Insufficient cpu), not slow | 4 | `FailedScheduling` event |
| Move the knee out with bigger/more nodes or the autoscaler | 4 |

## Evidence

Real screenshots and the generated chart are in [`artifacts/lab-07/`](artifacts/lab-07/), and the captured measurements are in [`artifacts/lab-07/evidence/lab-06-cluster-scale-knee-point.txt`](artifacts/lab-07/evidence/lab-06-cluster-scale-knee-point.txt).

---

---

**Next:** [Lab 8 — Trace a Blocked Network Flow to the Exact Policy (Cilium & Hubble)](lab-08-cilium-hubble.md)
