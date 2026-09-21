
**Day 5 · Kubernetes as the AI-Native Platform**

> YES — **Tested end-to-end** on a **real GKE cluster** (`advk8s-lab`) with the **Kubeflow Training Operator** and **Kueue v0.19**. Every screenshot is a real capture. The payoff: you submit two real distributed-training jobs; Kueue **admits one and holds the other** because the quota is full — then, when the first finishes, it **automatically admits the waiting job**, which runs a genuine `torch.distributed` collective across three Pods (`all_reduce result: 3.0`).

## What you'll learn

- How the **Training Operator** turns a `PyTorchJob` into master + worker Pods and wires `torch.distributed` for you (no manual `MASTER_ADDR`/`RANK`).
- How **Kueue** (Lab 14) governs those jobs: a training job that exceeds available quota is **suspended** until capacity frees, then admitted automatically.
- Why this pairing is how shared GPU/accelerator clusters stay both **fair** and **busy**.

## What you'll do

You'll enable Kueue to manage `PyTorchJob`s, define a quota big enough for one job, then submit two — watching one run and one wait, and the waiter start the moment the first finishes.

## Time & cost

- **Time:** ~40 minutes.
- **Cost:** negligible — small CPU-only `python:3.11-slim` Pods on the shared GKE cluster (no GPU needed to exercise the mechanics).

---

## Before you start

- **Where you'll work:** in a **terminal** with `kubectl` pointed at a GKE cluster.
- **Tools you need:** `gcloud`, `kubectl`.
- **Assumes Lab 14's Kueue is installed** on the cluster (`kueue-system`). You'll add the Training Operator and turn on Kueue's PyTorchJob integration here.

> **Nutanix note.** This is the on-prem AI-platform pattern in miniature. A Nutanix cluster with a *fixed* pool of GPUs is shared by several teams' training jobs; Kueue gives each team a quota floor and queues everything else, so the expensive hardware is neither monopolised nor left idle. Swap the pods' `cpu` request for `nvidia.com/gpu` and this lab *is* the GPU-scheduling story — the Training Operator and Kueue both run unchanged on **NKE**. We use CPU-only PyTorch here so you can exercise the real `torch.distributed` mechanics without a GPU.

---

## The idea in 60 seconds

A `PyTorchJob` describes a **Master** replica and **Worker** replicas. The **Training Operator** creates one Pod per replica and injects the env vars `torch.distributed` needs (`MASTER_ADDR`, `MASTER_PORT`, `WORLD_SIZE`, `RANK`) so the processes form one **process group** — you never hand-wire networking.

**Kueue** sits in front: label the `PyTorchJob` with a **LocalQueue**, and Kueue suspends it until its **ClusterQueue** has enough quota. Submit more jobs than fit, and the extras wait — then get admitted, in order, as running jobs finish.

![Architecture diagram](artifacts/lab-19/diagrams/diagram.png)

---

## Step 1 — Install the Training Operator and let Kueue manage PyTorchJobs

**Goal:** get the operator running and add `kubeflow.org/pytorchjob` to Kueue's managed frameworks.

**1. Install the Training Operator:**

```bash
kubectl apply --server-side -k "github.com/kubeflow/training-operator/manifests/overlays/standalone?ref=v1.9.0"
kubectl wait --for=condition=Available --timeout=150s -n kubeflow deployment/training-operator
```

**2. Enable the PyTorchJob integration in Kueue and restart its controller** (Kueue's default framework list doesn't include it):

```bash
# add kubeflow.org/pytorchjob to integrations.frameworks in the Kueue config, then:
kubectl -n kueue-system edit cm kueue-manager-config   # uncomment: - "kubeflow.org/pytorchjob"
kubectl -n kueue-system rollout restart deploy/kueue-controller-manager
kubectl -n kueue-system rollout status deploy/kueue-controller-manager --timeout=120s
```

**What you should see:** `training-operator` `Running`, and the Kueue controller back up after the restart.

**What this means:** the Training Operator can now reconcile `PyTorchJob`s, and Kueue will *gate* them — suspending any PyTorchJob carrying a queue label until quota is available.

> ⚠️ **Gotcha — Kueue only manages the frameworks in its config.** If `kubeflow.org/pytorchjob` isn't in `integrations.frameworks`, Kueue ignores your PyTorchJobs entirely — they run immediately with no admission control, and you'll wonder why nothing queues. The config change **requires a controller restart** to take effect.

---

## Step 2 — Define a quota and the training code

**Goal:** create a ClusterQueue sized for exactly one job, a LocalQueue for the team, and the distributed-training script.

```bash
kubectl create namespace ml-team

# the real torch.distributed all_reduce test
cat > /tmp/dist_test.py <<'EOF'
import torch, torch.distributed as dist
dist.init_process_group(backend="gloo")
rank, world = dist.get_rank(), dist.get_world_size()
t = torch.tensor([float(rank)])
dist.all_reduce(t, op=dist.ReduceOp.SUM)
print(f"[rank {rank}/{world}] all_reduce result: {t.item()} (expected {sum(range(world))})")
EOF
kubectl -n ml-team create configmap dist-test-code --from-file=dist_test.py=/tmp/dist_test.py

kubectl apply -f - <<'EOF'
apiVersion: kueue.x-k8s.io/v1beta2
kind: ResourceFlavor
metadata: {name: default-flavor}
---
apiVersion: kueue.x-k8s.io/v1beta2
kind: ClusterQueue
metadata: {name: cq-train}
spec:
  namespaceSelector: {}
  resourceGroups:
    - coveredResources: ["cpu"]
      flavors:
        - name: default-flavor
          resources: [{name: cpu, nominalQuota: "3"}]   # one job = 1 master + 2 workers x 1 CPU
---
apiVersion: kueue.x-k8s.io/v1beta2
kind: LocalQueue
metadata: {name: train-queue, namespace: ml-team}
spec: {clusterQueue: cq-train}
EOF
```

**What you should see:** `cq-train` created with a nominal quota of 3 CPU.

**What this means:** 3 CPU is exactly one training job's worth (master + 2 workers × 1 CPU). A second job can't fit until the first releases its quota.

---

## Step 3 — Submit two jobs, and watch Kueue admit one and hold the other

**Goal:** submit two identical `PyTorchJob`s and see Kueue gate them.

Submit a job (repeat for `train-job-b`, changing the name):

```bash
kubectl -n ml-team apply -f - <<'EOF'
apiVersion: kubeflow.org/v1
kind: PyTorchJob
metadata:
  name: train-job-a
  labels: {kueue.x-k8s.io/queue-name: train-queue}   # <-- gates it through Kueue
spec:
  runPolicy: {cleanPodPolicy: None}
  pytorchReplicaSpecs:
    Master:
      replicas: 1
      restartPolicy: OnFailure
      template:
        spec:
          containers:
          - name: pytorch
            image: python:3.11-slim
            command: ["sh","-c","pip install --quiet torch --index-url https://download.pytorch.org/whl/cpu && python /code/dist_test.py && sleep 300"]
            resources: {requests: {cpu: "1"}}
            volumeMounts: [{name: code, mountPath: /code}]
          volumes: [{name: code, configMap: {name: dist-test-code}}]
    Worker:
      replicas: 2
      restartPolicy: OnFailure
      template:
        spec:
          containers:
          - name: pytorch
            image: python:3.11-slim
            command: ["sh","-c","pip install --quiet torch --index-url https://download.pytorch.org/whl/cpu && python /code/dist_test.py && sleep 300"]
            resources: {requests: {cpu: "1"}}
            volumeMounts: [{name: code, mountPath: /code}]
          volumes: [{name: code, configMap: {name: dist-test-code}}]
EOF
```

Then check the state:

```bash
kubectl get clusterqueue cq-train -o custom-columns='NAME:.metadata.name,NOMINAL_CPU:.spec.resourceGroups[0].flavors[0].resources[0].nominalQuota,USED_CPU:.status.flavorsReservation[0].resources[0].total,ADMITTED:.status.admittedWorkloads,PENDING:.status.pendingWorkloads'
kubectl -n ml-team get pytorchjob
kubectl -n ml-team get workloads
kubectl -n ml-team get pods
```

**What you should see:** `cq-train` is fully used (`USED_CPU 3`, `ADMITTED 1`, `PENDING 1`); `train-job-a` is `Running` with 3 Pods; `train-job-b` is **`Suspended`** with **no Pods** — Kueue is holding it because there's no quota left.

![Kueue admits job-a (Running, 3 pods); job-b Suspended with no pods](artifacts/lab-19/screenshots/01-kueue-admission.png)

**What this means:** Kueue admits *whole jobs* only when quota exists. The waiting job consumes nothing — no half-started Pods jamming the scheduler.

---

## Step 4 — Free the quota, and watch the waiter run real distributed training

**Goal:** finish/remove the first job and see Kueue admit the second, which runs a genuine `torch.distributed` collective.

```bash
kubectl -n ml-team delete pytorchjob train-job-a       # releases its 3 CPU
# Kueue admits train-job-b automatically within seconds; it pip-installs torch, then runs:
kubectl -n ml-team get workloads
kubectl -n ml-team get pytorchjob train-job-b
kubectl -n ml-team logs train-job-b-master-0 | grep all_reduce
```

**What you should see:** `train-job-b`'s workload flips to `ADMITTED: True`, its Pods start, and the master log prints **`[rank 0/3] all_reduce result: 3.0 (expected 3)`** — three ranks (master + 2 workers), each contributing its rank number (0+1+2 = 3), summed by a real `torch.distributed` `all_reduce` across three separate Pods.

![Queue drained: job-b admitted after job-a freed quota; real all_reduce result: 3.0](artifacts/lab-19/screenshots/02-result.png)

**What this means:** two things at once. The **training** is real — a distributed collective formed across Pods with zero manual networking, thanks to the Training Operator. And the **governance** is real — Kueue queued job-b behind job-a and admitted it the instant capacity appeared. That's exactly how a shared accelerator pool serves many teams without starving or idling.

---

## Step 5 — Clean up

```bash
kubectl delete namespace ml-team --ignore-not-found
kubectl delete clusterqueue cq-train --ignore-not-found
kubectl delete resourceflavor default-flavor --ignore-not-found
# optionally remove the Training Operator:
# kubectl delete -k "github.com/kubeflow/training-operator/manifests/overlays/standalone?ref=v1.9.0"
```

---

## What you learned

| You saw… | in Step | proof |
|---|---|---|
| The Training Operator turns a PyTorchJob into master+worker Pods | 3 | `train-job-a` → 3 Pods, no manual networking |
| Kueue gates training jobs by quota | 3 | job-a admitted, job-b `Suspended`, no pods |
| A waiting job is admitted automatically when quota frees | 4 | delete job-a → job-b `Admitted: True` |
| Real distributed training runs across the Pods | 4 | `all_reduce result: 3.0 (expected 3)` |

## Evidence

Real screenshots for this lab are in [`artifacts/lab-19/screenshots/`](artifacts/lab-19/screenshots/) (2 images), and a command transcript is in [`artifacts/lab-19/evidence/lab-15b-distributed-training.txt`](artifacts/lab-19/evidence/lab-15b-distributed-training.txt).

---

---

**Next:** [Lab 20 — Scale Out *and* Right-Size a Workload (Advanced HPA & VPA Patterns)](lab-20-hpa-vpa-autoscaling.docx)
