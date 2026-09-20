
**Day 4 · GitOps, Multi-Cluster & Advanced Scheduling**

> YES — **Tested end-to-end** on a **real GKE cluster** (`advk8s-lab`, `dcproject-462806`) with **Kueue v0.19**. Every screenshot is a real capture. The payoff: a tenant asks for **more CPU than its own quota**, gets **blocked** with a precise "1 more needed" message — then, the moment a neighbouring tenant frees capacity, Kueue **admits the same job by borrowing** from the shared cohort. No edits, no re-submit.

## What you'll learn

- Why plain `ResourceQuota` is too rigid for multi-tenant batch: it either wastes capacity (hard caps that sit idle) or lets one tenant starve the rest.
- How **Kueue** governs *jobs* with **ClusterQueues** (a tenant's quota), **LocalQueues** (the namespace-facing handle), and **cohorts** (a group of ClusterQueues that can lend each other unused quota).
- How a job that exceeds its tenant's quota is **suspended** until capacity exists — and how **cohort borrowing** admits it automatically when a neighbour is idle.

## What you'll do

You'll install Kueue, define two tenants (`team-a`, `team-b`) with 1 CPU of quota each in a shared cohort. You'll fill `team-b`'s quota, watch `team-a`'s oversized job get blocked, then free `team-b` and watch `team-a` borrow the freed capacity and run.

## Time & cost

- **Time:** ~35 minutes.
- **Cost:** negligible — a few short-lived `busybox` Pods on the shared GKE cluster.

---

## Before you start

- **Where you'll work:** in a **terminal** on your own machine.
- **Tools you need:** `gcloud`, `kubectl`.
- **Cluster:** a GKE cluster (this course's shared `advk8s-lab`).

> **Nutanix note.** Kueue is platform-agnostic and runs identically on **NKE**. It's the natural fit for on-prem AI/ML and batch platforms, where a fixed pool of expensive nodes (GPUs especially) is shared by several teams. Cohorts let you give each team a *guaranteed* floor while allowing idle capacity to flow to whoever needs it — exactly the utilisation problem Nutanix customers face when consolidating GPU workloads onto shared clusters. You'd swap `cpu` here for `nvidia.com/gpu` and the model is the same.

---

## The idea in 60 seconds

A `ResourceQuota` caps a namespace hard: unused quota is wasted, and there's no way to lend it out. Kueue governs at the **job** level instead. Each tenant gets a **ClusterQueue** with a *nominal* quota — its guaranteed floor. Put several ClusterQueues in the same **cohort** and any of them can **borrow** another's *unused* nominal quota. When a tenant later needs its own quota back, Kueue reclaims it (preempting borrowed workloads if configured).

Jobs don't schedule directly. You label a Job with a **LocalQueue**; Kueue **suspends** it, decides whether quota (own + borrowable) is available, and only then **admits** it — unsuspending it so the scheduler runs its Pods.

![Architecture diagram](artifacts/lab-14/diagrams/diagram.png)

---

## Step 1 — Install Kueue

**Goal:** run the Kueue controller.

```bash
kubectl apply --server-side -f https://github.com/kubernetes-sigs/kueue/releases/download/v0.19.5/manifests.yaml
kubectl -n kueue-system rollout status deploy/kueue-controller-manager --timeout=180s
```

**What you should see:** `kueue-controller-manager` `Running` in `kueue-system`.

**What this means:** Kueue's admission webhook and controller are live. From now on, any Job labelled with a queue is gated by Kueue.

---

## Step 2 — Define two tenants sharing a cohort

**Goal:** give `team-a` and `team-b` 1 CPU of quota each, in a shared cohort so they can lend to each other.

```bash
kubectl create namespace team-a
kubectl create namespace team-b

kubectl apply -f - <<'EOF'
apiVersion: kueue.x-k8s.io/v1beta2
kind: ResourceFlavor
metadata: {name: default-flavor}
---
apiVersion: kueue.x-k8s.io/v1beta2
kind: ClusterQueue
metadata: {name: cq-a}
spec:
  cohortName: org                 # <-- same cohort as cq-b
  namespaceSelector: {}
  resourceGroups:
    - coveredResources: ["cpu"]
      flavors:
        - name: default-flavor
          resources: [{name: cpu, nominalQuota: "1"}]
---
apiVersion: kueue.x-k8s.io/v1beta2
kind: ClusterQueue
metadata: {name: cq-b}
spec:
  cohortName: org                 # <-- same cohort as cq-a
  namespaceSelector: {}
  resourceGroups:
    - coveredResources: ["cpu"]
      flavors:
        - name: default-flavor
          resources: [{name: cpu, nominalQuota: "1"}]
---
apiVersion: kueue.x-k8s.io/v1beta2
kind: LocalQueue
metadata: {name: team-queue, namespace: team-a}
spec: {clusterQueue: cq-a}
---
apiVersion: kueue.x-k8s.io/v1beta2
kind: LocalQueue
metadata: {name: team-queue, namespace: team-b}
spec: {clusterQueue: cq-b}
EOF

kubectl get clusterqueue
```

**What you should see:** `cq-a` and `cq-b`, both in cohort `org`.

**What this means:** each tenant has a guaranteed 1 CPU (its nominal quota), and because they share a cohort, either can borrow the other's idle CPU.

> **What's a `LocalQueue` for?** Tenants submit jobs to a `LocalQueue` in their own namespace; it points at a `ClusterQueue`. This keeps the *quota policy* (cluster-scoped, admin-owned) separate from the *submission handle* (namespace-scoped, tenant-facing).

---

## Step 3 — Fill team-b, then watch team-a get blocked

**Goal:** occupy `team-b`'s quota, then submit an oversized `team-a` job and see Kueue refuse to admit it.

**1. `team-b` uses its full 1 CPU:**

```bash
kubectl apply -f - <<'EOF'
apiVersion: batch/v1
kind: Job
metadata: {name: filler, namespace: team-b, labels: {kueue.x-k8s.io/queue-name: team-queue}}
spec:
  parallelism: 1
  completions: 1
  suspend: true
  template:
    spec:
      restartPolicy: Never
      containers:
        - {name: c, image: busybox:1.36, command: ["sh","-c","sleep 1800"], resources: {requests: {cpu: "1"}}}
EOF
```

**2. `team-a` submits a job needing 2 CPU — double its own quota:**

```bash
kubectl apply -f - <<'EOF'
apiVersion: batch/v1
kind: Job
metadata: {name: big-job, namespace: team-a, labels: {kueue.x-k8s.io/queue-name: team-queue}}
spec:
  parallelism: 2
  completions: 2
  suspend: true
  template:
    spec:
      restartPolicy: Never
      containers:
        - {name: c, image: busybox:1.36, command: ["sh","-c","sleep 1800"], resources: {requests: {cpu: "1"}}}
EOF
```

**3. Inspect the quota and why `team-a` is stuck:**

```bash
kubectl get clusterqueue -o custom-columns='NAME:.metadata.name,COHORT:.spec.cohortName,NOMINAL_CPU:.spec.resourceGroups[0].flavors[0].resources[0].nominalQuota,USED_CPU:.status.flavorsReservation[0].resources[0].total,BORROWED:.status.flavorsReservation[0].resources[0].borrowed,ADMITTED:.status.admittedWorkloads,PENDING:.status.pendingWorkloads'
kubectl get workloads -A
kubectl -n team-a get pods
WL=$(kubectl -n team-a get workloads -o jsonpath='{.items[0].metadata.name}')
kubectl -n team-a get workload "$WL" -o jsonpath='{.status.conditions[?(@.type=="QuotaReserved")].message}{"\n"}'
```

**What you should see:** `team-b`'s workload is `Admitted` in `cq-b`; `team-a`'s workload is **not** admitted and has **no Pods** (Kueue keeps the Job suspended). The reason reads: **`insufficient unused quota for cpu in flavor default-flavor, 1 more needed`** — `team-a` has its own 1 CPU but needs 1 more, and the cohort has none to lend because `team-b` is using `cq-b`.

![team-b admitted; team-a blocked with 'insufficient unused quota, 1 more needed', no pods](artifacts/lab-14/screenshots/01-blocked.png)

**What this means:** Kueue admits **whole jobs** only when the total quota (own + borrowable) is available. Instead of letting `team-a` half-start and jam the cluster, it holds the job suspended and tells you *exactly* how much is missing.

---

## Step 4 — Free team-b and watch team-a borrow

**Goal:** free the neighbour's capacity and see Kueue admit the blocked job automatically.

```bash
kubectl -n team-b delete job filler        # cq-b is now idle
# ...wait a few seconds for Kueue to re-evaluate...
kubectl get clusterqueue -o custom-columns='NAME:.metadata.name,COHORT:.spec.cohortName,NOMINAL_CPU:.spec.resourceGroups[0].flavors[0].resources[0].nominalQuota,USED_CPU:.status.flavorsReservation[0].resources[0].total,BORROWED:.status.flavorsReservation[0].resources[0].borrowed,ADMITTED:.status.admittedWorkloads,PENDING:.status.pendingWorkloads'
kubectl get workloads -A
kubectl -n team-a get pods
```

**What you should see:** `cq-a` now shows **`USED_CPU 2`** with **`BORROWED 1`** — it's using its own 1 CPU plus 1 borrowed from the cohort. `team-a`'s workload is `Admitted` in `cq-a`, and its **2 Pods are Running**. You never touched the `team-a` job — Kueue admitted it the moment capacity appeared.

![After freeing team-b: cq-a USED 2 / BORROWED 1, team-a admitted, 2 pods Running](artifacts/lab-14/screenshots/02-borrowed.png)

**What this means:** this is the whole point of cohorts — **guaranteed floors with elastic sharing**. Each tenant is promised its 1 CPU, but idle capacity flows to whoever needs it, so the cluster stays busy instead of sitting half-empty behind rigid quotas.

---

## Step 5 — Clean up

```bash
kubectl delete namespace team-a team-b --ignore-not-found
kubectl delete clusterqueue cq-a cq-b --ignore-not-found
kubectl delete resourceflavor default-flavor --ignore-not-found
# to remove Kueue entirely:
# kubectl delete -f https://github.com/kubernetes-sigs/kueue/releases/download/v0.19.5/manifests.yaml
```

---

## What you learned

| You saw… | in Step | proof |
|---|---|---|
| Kueue gates jobs by ClusterQueue quota, keeping them suspended | 3 | `team-a` job has no Pods while blocked |
| A job over its tenant's quota is blocked with a precise reason | 3 | `insufficient unused quota for cpu … 1 more needed` |
| Cohort members borrow each other's idle quota | 4 | `cq-a` `BORROWED 1`, `USED_CPU 2` |
| Borrowing admits the blocked job automatically | 4 | `team-a` `Admitted`, 2 Pods `Running` |

## Evidence

Real screenshots for this lab are in [`artifacts/lab-14/screenshots/`](artifacts/lab-14/screenshots/) (2 images), and a command transcript is in [`artifacts/lab-14/evidence/lab-14-kueue.txt`](artifacts/lab-14/evidence/lab-14-kueue.txt).

---

**Next:** [Lab 15A — Dynamic Resource Allocation for Accelerators](lab-15a-dra.docx)
