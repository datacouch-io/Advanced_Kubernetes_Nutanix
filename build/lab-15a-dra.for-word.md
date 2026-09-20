
**Day 5 · Kubernetes as the AI-Native Platform**

> YES — **Tested end-to-end** on a **real Kubernetes 1.34 `kind` cluster** with the upstream **DRA example driver** publishing *simulated* GPUs. Every screenshot is a real capture. The payoff: instead of asking for "1 GPU" and hoping, a Pod asks for a device that matches a **CEL expression on the device's attributes** — and the scheduler places it **only** on a node that actually has a matching device, injecting that exact GPU. A Pod whose selector matches nothing stays `Pending`.

## What you'll learn

- Why the old **device-plugin** model (`nvidia.com/gpu: 1`) is too coarse: you can't say *which kind* of GPU, how much memory, which model, or share one device across Pods.
- What **Dynamic Resource Allocation (DRA)** adds: drivers publish **devices with rich attributes** (model, memory, UUID, driver version…) in `ResourceSlice`s, and workloads select them with **CEL expressions**.
- How the scheduler uses those claims to place a Pod **only where a matching device exists** — and how an unsatisfiable claim leaves a Pod `Pending`.

## What you'll do

You'll stand up a DRA driver that advertises simulated GPUs on two nodes, then submit two Pods: one selecting a specific GPU **by an attribute that exists only on one node**, and one selecting a model that **doesn't exist**. You'll watch the first land on the matching node with the GPU injected, and the second stay `Pending`.

## Time & cost

- **Time:** ~40 minutes.
- **Cost:** **$0** — a local `kind` cluster with *simulated* GPUs (no real accelerator needed).

---

## Before you start

- **Where you'll work:** in a **terminal** on your own machine.
- **Tools you need:** `docker`, `kind`, `kubectl`, `helm`, `git`.
- **Cluster:** you'll create a fresh **Kubernetes 1.34** `kind` cluster in Step 1 — DRA is **GA in 1.34** and enabled by default, so no feature-gate wrangling.

> **Nutanix note.** DRA is how modern Kubernetes exposes accelerators — GPUs, and increasingly NICs and other specialised hardware. On a **Nutanix** cluster with GPUs (passthrough or vGPU), you'd run a real DRA driver (e.g. NVIDIA's) that publishes the actual cards as devices with their true attributes; workloads then request "a GPU with ≥ 40Gi memory of this model" and land only on nodes that have one. We use the upstream **example driver with simulated GPUs** so the mechanics are identical but you need no real hardware.

---

## The idea in 60 seconds

With the classic device plugin, a Pod asks for `nvidia.com/gpu: 1` — an opaque count. You can't express "a GPU with at least 40Gi", "an A100, not a T4", or "share this GPU across two Pods".

**DRA** changes the model. A **driver** publishes each device it manages into a **`ResourceSlice`**, with **attributes** (model, uuid, driverVersion) and **capacity** (memory, compute). A workload creates a **`ResourceClaim`** (usually via a `ResourceClaimTemplate`) that names a **`DeviceClass`** and adds **CEL selectors** over those attributes. The scheduler finds a node whose slice has a device satisfying the claim, **allocates** that device, and the driver **injects** it into the container. No matching device anywhere → the Pod can't be scheduled.

![Architecture diagram](artifacts/lab-15a/diagrams/diagram.png)

---

## Step 1 — Create a 1.34 cluster and install the DRA driver

**Goal:** get a cluster with DRA on, and a driver advertising simulated GPUs on the two worker nodes.

**1. Create the cluster** (2 workers so a device can exist on one node and not the other):

```bash
cat > /tmp/dra-kind.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
  - role: worker
EOF
kind create cluster --name dra-lab --image kindest/node:v1.34.0 --config /tmp/dra-kind.yaml
kubectl api-resources --api-group=resource.k8s.io
```

You should see `deviceclasses`, `resourceclaims`, `resourceclaimtemplates`, and `resourceslices` under `resource.k8s.io/v1` — DRA is live.

**2. Install the example driver** (its image is published to `registry.k8s.io`, so no local build needed):

```bash
git clone --depth 1 --branch v0.5.0 https://github.com/kubernetes-sigs/dra-example-driver /tmp/dra-example-driver
helm install dra-example-driver /tmp/dra-example-driver/deployments/helm/dra-example-driver \
  --namespace dra-example-driver --create-namespace
kubectl -n dra-example-driver rollout status ds/dra-example-driver-kubeletplugin --timeout=150s
```

**3. See the devices it advertises:**

```bash
kubectl get deviceclasses
kubectl get resourceslices -o custom-columns='NODE:.spec.nodeName,DRIVER:.spec.driver,DEVICE:.spec.devices[0].name,MODEL:.spec.devices[0].attributes.model.string,MEMORY:.spec.devices[0].capacity.memory.value'
```

**What you should see:** a `DeviceClass` named `gpu.example.com`, and a `ResourceSlice` on **each** worker advertising a `gpu-0` of model `LATEST-GPU-MODEL` with `80Gi` — each with its own attributes (`model`, `uuid`, `index`, `driverVersion`).

![The driver advertises simulated GPUs with selectable attributes](artifacts/lab-15a/screenshots/01-devices.png)

**What this means:** the cluster now knows about specific, richly-described devices — not just a count. That's what you'll select against.

---

## Step 2 — Request a device by attribute, and watch placement follow

**Goal:** submit one Pod that selects a device present only on `worker2`, and one that selects a device that doesn't exist.

**1. Capture the UUID of a GPU that lives on `worker2`** (so we can target that node by device attribute):

```bash
W2_SLICE=$(kubectl get resourceslice -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.nodeName}{"\n"}{end}' | awk '$2=="dra-lab-worker2"{print $1; exit}')
W2_UUID=$(kubectl get resourceslice "$W2_SLICE" -o jsonpath='{.spec.devices[0].attributes.uuid.string}')
echo "$W2_UUID"
```

**2. Create the matching Pod** — its claim uses a CEL selector on that UUID:

```bash
kubectl create namespace dra-demo
kubectl apply -f - <<EOF
apiVersion: resource.k8s.io/v1
kind: ResourceClaimTemplate
metadata: {namespace: dra-demo, name: gpu-on-worker2}
spec:
  spec:
    devices:
      requests:
        - name: gpu
          exactly:
            deviceClassName: gpu.example.com
            selectors:
              - cel: {expression: "device.attributes['gpu.example.com'].uuid == '${W2_UUID}'"}
---
apiVersion: v1
kind: Pod
metadata: {namespace: dra-demo, name: pod-match}
spec:
  containers:
    - name: ctr
      image: ubuntu:22.04
      command: ["bash","-c","env | grep GPU_DEVICE; trap 'exit 0' TERM; sleep 9999 & wait"]
      resources: {claims: [{name: gpu}]}
  resourceClaims:
    - {name: gpu, resourceClaimTemplateName: gpu-on-worker2}
EOF
```

**3. Create the non-matching Pod** — its claim selects a model that doesn't exist:

```bash
kubectl apply -f - <<'EOF'
apiVersion: resource.k8s.io/v1
kind: ResourceClaimTemplate
metadata: {namespace: dra-demo, name: gpu-nonexistent}
spec:
  spec:
    devices:
      requests:
        - name: gpu
          exactly:
            deviceClassName: gpu.example.com
            selectors:
              - cel: {expression: "device.attributes['gpu.example.com'].model == 'NO-SUCH-GPU-MODEL'"}
---
apiVersion: v1
kind: Pod
metadata: {namespace: dra-demo, name: pod-nomatch}
spec:
  containers:
    - name: ctr
      image: ubuntu:22.04
      command: ["bash","-c","trap 'exit 0' TERM; sleep 9999 & wait"]
      resources: {claims: [{name: gpu}]}
  resourceClaims:
    - {name: gpu, resourceClaimTemplateName: gpu-nonexistent}
EOF
```

**4. Watch where they land, and what got allocated:**

```bash
kubectl -n dra-demo get pods -o wide
kubectl -n dra-demo get resourceclaims -o custom-columns='CLAIM:.metadata.name,ALLOCATED_DEVICE:.status.allocation.devices.results[0].device,ON_NODE:.status.allocation.devices.results[0].pool'
kubectl -n dra-demo logs pod-match | grep GPU_DEVICE
```

**What you should see:** `pod-match` is **`Running` on `dra-lab-worker2`** — the only node with the requested UUID — its claim allocated `gpu-0` on `worker2`, and its container has `GPU_DEVICE_0=gpu-0` injected. `pod-nomatch` is **`Pending`** with an unallocated claim, because no device anywhere matches its selector.

![pod-match placed on worker2 with the GPU injected; pod-nomatch stays Pending](artifacts/lab-15a/screenshots/02-placement.png)

**What this means:** the Pod's *attribute request* drove *placement*. The scheduler didn't just find "a GPU" — it found the specific device satisfying the CEL selector, on the one node that had it, and refused to place the Pod that asked for something no device could provide.

> ⚠️ **Gotcha — a `Pending` DRA Pod looks like a normal scheduling failure.** `pod-nomatch` sits `Pending` with `FailedScheduling: … cannot allocate all claims`. If you forget it's a DRA claim, you'll hunt for taints or node capacity. Always check the `ResourceClaim` (`kubectl get resourceclaim`) — an `<none>` allocation means *no device satisfied the selector*, which is a claim problem, not a node-resources problem.

---

## Step 3 — Clean up

```bash
kind delete cluster --name dra-lab
```

---

## What you learned

| You saw… | in Step | proof |
|---|---|---|
| A DRA driver advertises devices with rich attributes | 1 | `ResourceSlice` per node: model, uuid, 80Gi |
| A workload selects a device with a CEL attribute expression | 2 | claim selector on `uuid` / `model` |
| Placement follows the claim — only a matching node works | 2 | `pod-match` on `worker2`, device `gpu-0` allocated there |
| The device is injected into the container | 2 | `GPU_DEVICE_0=gpu-0` in the logs |
| An unsatisfiable claim leaves the Pod `Pending` | 2 | `pod-nomatch` `Pending`, claim unallocated |

## Evidence

Real screenshots for this lab are in [`artifacts/lab-15a/screenshots/`](artifacts/lab-15a/screenshots/) (2 images), and a command transcript is in [`artifacts/lab-15a/evidence/lab-15a-dra.txt`](artifacts/lab-15a/evidence/lab-15a-dra.txt).

---

**Next:** [Lab 15B — Kueue-Managed Distributed Training](lab-15b-distributed-training.docx)
