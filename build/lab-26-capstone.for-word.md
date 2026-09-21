
**Day 5 · Kubernetes as the AI-Native Platform**

> YES — **Tested end-to-end** on a **real GKE cluster** (`advk8s-lab`). Every screenshot is a real capture. The payoff: you inherit a namespace broken across **six independent fault domains** at once, triage it with `kubectl`, fix each root cause, and end with **every workload healthy** — then write the postmortem.

## What you'll do

This is the capstone. You'll seed one incident that breaks an application six different ways — scheduling, images, config, networking, lifecycle, and storage — then work as the on-call engineer: **triage → diagnose → fix → verify**, and produce a postmortem. It exercises the diagnostic muscles from across the whole course.

## Time & cost

- **Time:** ~60 minutes.
- **Cost:** negligible — one namespace of small workloads on the shared GKE cluster.

---

## Before you start

- **Where you'll work:** in a **terminal** with `kubectl` pointed at a GKE cluster.
- **Tools you need:** `gcloud`, `kubectl`.
- **Mindset:** don't fix blindly. For each broken workload, find the **symptom** (`get`), the **root cause** (`describe`/`get -o yaml`), *then* the fix. That triage loop is the real skill.

> **Nutanix note.** Nothing here is cloud-specific — every fault and fix is standard Kubernetes and behaves identically on **NKE**. This is the exact shape of a real on-prem incident: several unrelated things break at once and you have only `kubectl` and your head. The one storage detail that changes on Nutanix is the StorageClass name (you'd use your Nutanix CSI class instead of GKE's `standard-rwo`); the *diagnosis* — a PVC stuck `Pending` on a non-existent class — is the same.

---

## The scenario

You're paged: the `warroom` app is down. Six things are wrong simultaneously, each in a different domain you studied this week:

![Architecture diagram](artifacts/lab-26/diagrams/diagram.png)

---

## Step 1 — Seed the incident

**Goal:** create the broken state. (In a real incident this is what you'd *find*; here you seed it so you can practise the recovery.)

Apply the six-fault bundle:

```bash
kubectl create namespace warroom
kubectl -n warroom apply -f - <<'EOF'
# 1 scheduling: impossible nodeSelector
apiVersion: apps/v1
kind: Deployment
metadata: {name: orders, labels: {app: orders}}
spec: {replicas: 1, selector: {matchLabels: {app: orders}}, template: {metadata: {labels: {app: orders}}, spec: {nodeSelector: {disktype: nvme}, containers: [{name: c, image: nginx:1.27-alpine}]}}}
---
# 2 image: typo'd tag
apiVersion: apps/v1
kind: Deployment
metadata: {name: payments, labels: {app: payments}}
spec: {replicas: 1, selector: {matchLabels: {app: payments}}, template: {metadata: {labels: {app: payments}}, spec: {containers: [{name: c, image: nginx:1.27-alpnie}]}}}
---
# 3 config: envFrom a missing ConfigMap
apiVersion: apps/v1
kind: Deployment
metadata: {name: checkout, labels: {app: checkout}}
spec: {replicas: 1, selector: {matchLabels: {app: checkout}}, template: {metadata: {labels: {app: checkout}}, spec: {containers: [{name: c, image: nginx:1.27-alpine, envFrom: [{configMapRef: {name: checkout-config}}]}]}}}
---
# 4 networking: Service selector typo (pods are healthy)
apiVersion: apps/v1
kind: Deployment
metadata: {name: frontend, labels: {app: frontend}}
spec: {replicas: 2, selector: {matchLabels: {app: frontend}}, template: {metadata: {labels: {app: frontend}}, spec: {containers: [{name: c, image: nginx:1.27-alpine, ports: [{containerPort: 80}]}]}}}
---
apiVersion: v1
kind: Service
metadata: {name: frontend}
spec: {selector: {app: frontendd}, ports: [{port: 80, targetPort: 80}]}
---
# 6 storage: PVC with a non-existent StorageClass, mounted by analytics
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: data}
spec: {accessModes: ["ReadWriteOnce"], storageClassName: fast-nvme, resources: {requests: {storage: 1Gi}}}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: analytics, labels: {app: analytics}}
spec: {replicas: 1, selector: {matchLabels: {app: analytics}}, template: {metadata: {labels: {app: analytics}}, spec: {containers: [{name: c, image: nginx:1.27-alpine, volumeMounts: [{name: d, mountPath: /data}]}], volumes: [{name: d, persistentVolumeClaim: {claimName: data}}]}}}
EOF

# 5 lifecycle: a resource stuck Terminating on a finalizer
kubectl -n warroom apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata: {name: legacy-record, finalizers: ["warroom.example.com/blocker"]}
data: {note: "old data"}
EOF
kubectl -n warroom delete configmap legacy-record --wait=false
```

---

## Step 2 — Triage: see everything that's wrong

**Goal:** get the full picture before touching anything.

```bash
kubectl -n warroom get pods
kubectl -n warroom get endpoints frontend
kubectl -n warroom get pvc data
kubectl -n warroom get configmap legacy-record -o jsonpath='{.metadata.name}  deletionTimestamp={.metadata.deletionTimestamp}  finalizers={.metadata.finalizers}{"\n"}'
```

**What you should see:** six distinct symptoms — `orders`/`analytics` `Pending`, `payments` `ImagePullBackOff`, `checkout` `CreateContainerConfigError`, `frontend` pods `Running` but its Service has **no endpoints**, the `data` PVC `Pending`, and `legacy-record` with a `deletionTimestamp` set but not gone.

![Triage: six distinct faults across scheduling, image, config, networking, storage, lifecycle](artifacts/lab-26/screenshots/01-triage.png)

**What this means:** these are six *independent* failures, each with a different signature. Recognising the signature is half the diagnosis — `Pending` vs `ImagePullBackOff` vs `CreateContainerConfigError` each point at a different domain.

---

## Step 3 — Diagnose and fix each domain

For each, the diagnostic that reveals the root cause is shown first, then the fix.

**1. Scheduling — `orders` Pending.** `kubectl -n warroom describe pod -l app=orders` shows `node(s) didn't match node selector: disktype=nvme`. No node has that label.

```bash
kubectl -n warroom patch deploy orders --type=json -p '[{"op":"remove","path":"/spec/template/spec/nodeSelector"}]'
```

**2. Image — `payments` ImagePullBackOff.** `describe pod` shows `Failed to pull image "nginx:1.27-alpnie"` — a typo in the tag.

```bash
kubectl -n warroom set image deploy/payments c=nginx:1.27-alpine
```

**3. Config — `checkout` CreateContainerConfigError.** `describe pod` shows `configmap "checkout-config" not found` — the container's `envFrom` references a ConfigMap that doesn't exist.

```bash
kubectl -n warroom create configmap checkout-config --from-literal=MODE=prod --from-literal=TIMEOUT=30
```

**4. Networking — `frontend` Service has 0 endpoints.** The pods are healthy, so compare labels: `kubectl -n warroom get svc frontend -o jsonpath='{.spec.selector}'` shows `app=frontendd` but the pods are `app=frontend` — a selector typo.

```bash
kubectl -n warroom patch svc frontend --type=merge -p '{"spec":{"selector":{"app":"frontend"}}}'
```

**5. Lifecycle — `legacy-record` stuck Terminating.** It has a `deletionTimestamp` but a finalizer (`warroom.example.com/blocker`) whose controller doesn't exist, so nothing clears it.

```bash
kubectl -n warroom patch configmap legacy-record --type=merge -p '{"metadata":{"finalizers":[]}}'
```

**6. Storage — `data` PVC Pending, `analytics` Pending.** `describe pvc data` shows it references StorageClass `fast-nvme`, which doesn't exist. `storageClassName` is immutable, so recreate the PVC (and the pod that mounts it) with a real class:

```bash
kubectl -n warroom delete deploy analytics
kubectl -n warroom delete pvc data
kubectl -n warroom apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: data}
spec: {accessModes: ["ReadWriteOnce"], resources: {requests: {storage: 1Gi}}}   # default StorageClass
EOF
kubectl -n warroom apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: analytics, labels: {app: analytics}}
spec: {replicas: 1, selector: {matchLabels: {app: analytics}}, template: {metadata: {labels: {app: analytics}}, spec: {containers: [{name: c, image: nginx:1.27-alpine, volumeMounts: [{name: d, mountPath: /data}]}], volumes: [{name: d, persistentVolumeClaim: {claimName: data}}]}}}
EOF
```

---

## Step 4 — Verify the cluster is fully healthy

**Goal:** confirm every domain is green.

```bash
kubectl -n warroom get pods
kubectl -n warroom get endpoints frontend
kubectl -n warroom get pvc data
kubectl -n warroom get configmap legacy-record   # expect NotFound
```

**What you should see:** all six pods `Running`, `frontend` now has real endpoint IPs, the `data` PVC is `Bound` (StorageClass `standard-rwo`), and `legacy-record` is gone (`NotFound`).

![Resolved: all pods Running, Service has endpoints, PVC Bound, stuck resource gone](artifacts/lab-26/screenshots/02-resolved.png)

**What this means:** you took a cluster failing six different ways to fully healthy — each fix targeted at a root cause you diagnosed, not guessed.

---

## Step 5 — The postmortem

| # | Domain | Symptom | How you found it | Root cause | Fix | Course link |
|---|---|---|---|---|---|---|
| 1 | Scheduling | `orders` Pending | `describe pod` → node-selector event | `nodeSelector: disktype=nvme` matches no node | remove the nodeSelector | Lab 4 |
| 2 | Image | `payments` ImagePullBackOff | `describe pod` → pull error | typo `nginx:1.27-alpnie` | correct the tag | Lab C/D |
| 3 | Config | `checkout` CreateContainerConfigError | `describe pod` → `configmap … not found` | missing `checkout-config` ConfigMap | create the ConfigMap | Lab 11/1 |
| 4 | Networking | `frontend` Service, 0 endpoints | compare Service selector to pod labels | selector typo `app=frontendd` | fix the selector | Lab B/10 |
| 5 | Lifecycle | `legacy-record` stuck Terminating | `get -o jsonpath` → finalizer + deletionTimestamp | orphaned finalizer, no controller | clear the finalizer | Lab 5 |
| 6 | Storage | `data` PVC Pending | `describe pvc` → no such StorageClass | `storageClassName: fast-nvme` | recreate with a real class | Lab 8 |

**Prevention (the real postmortem output):** admission policy to reject images by tag and unknown StorageClasses (Labs C/D/17), CI validation of Service selectors against pod labels, alerting on `Pending`/`ImagePullBackOff`/non-Ready endpoints, and a guardrail against orphaned finalizers.

---

## Step 6 — Clean up

```bash
kubectl delete namespace warroom --ignore-not-found
```

---

## What you learned

| You saw… | in Step | proof |
|---|---|---|
| Six independent faults each have a distinct signature | 2 | Pending vs ImagePullBackOff vs CreateContainerConfigError vs 0-endpoints vs Terminating vs PVC-Pending |
| Diagnosis comes before the fix | 3 | each fix targeted a root cause from `describe`/`get -o yaml` |
| A multi-domain incident can be driven to fully healthy | 4 | all pods Running, endpoints present, PVC Bound, stuck resource gone |
| Every fault maps back to a course topic | 5 | postmortem links each to its lab |

## Evidence

Real screenshots for this lab are in [`artifacts/lab-26/screenshots/`](artifacts/lab-26/screenshots/) (2 images), and a command transcript is in [`artifacts/lab-26/evidence/lab-18-capstone.txt`](artifacts/lab-26/evidence/lab-18-capstone.txt).

---

**This is the end of the course.** Across all 26 labs you traced Kubernetes' reconciliation and control plane, operated it under pressure, ran stateful workloads and exposed them, delivered with GitOps across a fleet, scheduled AI/accelerator workloads, and secured and stress-tested the platform — each claim backed by a real command against real infrastructure. Now you can walk into a war-room and drive it back to green.
