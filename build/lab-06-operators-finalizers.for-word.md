
**Day 2 · Extending and Operating the Platform Under Pressure**

> YES — **Tested end-to-end** on a **real GKE cluster** (`dcproject-462806`, the shared Day-2 cluster). Every screenshot is a real capture. The eye-opener: `kubectl delete` prints `… deleted`, yet the object is **still there** with a `deletionTimestamp` set — because a finalizer is holding it open. Deletion in Kubernetes is a two-phase handshake, not an instant remove.

## What you'll learn

- What a **finalizer** is — a key in `.metadata.finalizers` that turns deletion into a two-phase operation — and why `kubectl delete` succeeding does **not** mean the object is gone.
- How the deletion lifecycle really works: `deletionTimestamp` is set, the object goes `Terminating`, and it's removed only once every finalizer is cleared.
- Why **operators** add finalizers (to guarantee cleanup runs first), and what happens when the operator is down: their resources wedge in `Terminating` forever.
- How to diagnose a stuck object *and* a stuck **namespace**, the manual override to force deletion — and why that override is dangerous.

## What you'll do

You'll wedge three different things into `Terminating` on purpose — a ConfigMap, a custom resource, and a whole namespace — diagnose each, and recover it. Along the way you'll see exactly why "it won't delete" is almost always a finalizer.

## Time & cost

- **Time:** ~35 minutes.
- **Cost:** negligible — everything here is control-plane-only (no extra nodes or storage). Reuses the Day-2 GKE cluster.

---

## Before you start

- **Where you'll work:** in a **terminal** on your own machine.
- **Tools you need:** `gcloud`, `kubectl`.
- **Cluster:** this lab creates a shared Day-2 GKE cluster (reused by Labs 6 and C):

```bash
gcloud container clusters create advk8s-day2 \
  --zone us-central1-a --num-nodes 2 --machine-type e2-medium \
  --disk-size 30 --release-channel regular
gcloud container clusters get-credentials advk8s-day2 --zone us-central1-a
```

> **Nutanix note.** Finalizers, `deletionTimestamp`, the `Terminating` state, and namespace `status.conditions` are pure Kubernetes API machinery — identical on NKE, GKE, and `kind`. Nothing here is cloud-specific; we run it on GKE only because Day 2 is cloud-first. It behaves exactly the same on a Nutanix NKE cluster.

---

## The idea in 60 seconds

Deleting a Kubernetes object is a **two-phase** operation:

1. You call delete. The API server sets `.metadata.deletionTimestamp`; the object enters `Terminating`. It is **not** removed yet.
2. Any controller that registered a **finalizer** (a string in `.metadata.finalizers`) runs its cleanup, then removes *its own* finalizer key.
3. Only when `.metadata.finalizers` is empty does the object actually get deleted.

This is how operators guarantee cleanup — an operator managing a cloud load balancer adds a finalizer so deleting its custom resource first deprovisions the real load balancer, *then* lets the resource vanish. The failure mode is the mirror image: if a finalizer is present but nothing ever removes it (the operator crashed, was uninstalled, or never existed), the object is stuck in `Terminating` forever. That's the most common "why won't this delete?" incident in Kubernetes, and you'll reproduce it three ways.

![Architecture diagram](artifacts/lab-06/diagrams/diagram.png)

---

## Step 1 — Warm-up: watch `delete` lie to you

**Goal:** put a finalizer on a plain ConfigMap and see that "deleted" doesn't mean gone.

**1. Create a ConfigMap, add a finalizer, then delete it:**

```bash
kubectl create configmap protected --from-literal=k=v
kubectl patch configmap protected --type=merge \
  -p '{"metadata":{"finalizers":["demo.example.com/protect"]}}'

kubectl delete configmap protected --wait=false     # prints "deleted" ...
kubectl get configmap protected \
  -o jsonpath='name={.metadata.name}  deletionTimestamp={.metadata.deletionTimestamp}  finalizers={.metadata.finalizers}{"\n"}'
```

**What you should see:** `kubectl delete` prints `configmap "protected" deleted`, but the `get` still returns it — with `deletionTimestamp` set and `finalizers=["demo.example.com/protect"]`.

![ConfigMap "deleted" but still present with a deletionTimestamp](../../artifacts/lab-06/screenshots/01-configmap-finalizer.png)

**What this means:** it's in `Terminating`, waiting for a finalizer that nobody will ever remove. Clear it by hand and it vanishes instantly:

```bash
kubectl patch configmap protected --type=merge -p '{"metadata":{"finalizers":null}}'
kubectl get configmap protected      # Error ... NotFound
```

---

## Step 2 — The operator pattern: a custom resource that won't delete

**Goal:** define a custom resource (as an operator would), create one *with* a finalizer, then delete it while no operator is running to process it.

**1. Create the CRD and one custom resource carrying a finalizer:**

```bash
kubectl apply -f - <<'EOF'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: widgets.example.com
spec:
  group: example.com
  scope: Namespaced
  names: {plural: widgets, singular: widget, kind: Widget}
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties: {size: {type: string}}
EOF
kubectl wait --for=condition=Established crd/widgets.example.com --timeout=30s

kubectl apply -f - <<'EOF'
apiVersion: example.com/v1
kind: Widget
metadata:
  name: gadget
  finalizers: ["widgets.example.com/cleanup"]
spec: {size: large}
EOF
```

**2. Delete it and check:**

```bash
kubectl delete widget gadget --wait=false
kubectl get widget gadget \
  -o jsonpath='name={.metadata.name}  deletionTimestamp={.metadata.deletionTimestamp}  finalizers={.metadata.finalizers}{"\n"}'
```

**What you should see:** the `Widget` is stuck exactly like the ConfigMap — `deletionTimestamp` set, `finalizers=["widgets.example.com/cleanup"]`, still present.

![Widget stuck in Terminating — the operator finalizer is never processed](../../artifacts/lab-06/screenshots/02-operator-finalizer-stuck.png)

**What this means:** in production this is a resource whose operator was going to run some external cleanup before letting it go. With the operator down, deletion can never complete.

**3. Force it out** with the same finalizer patch:

```bash
kubectl patch widget gadget --type=merge -p '{"metadata":{"finalizers":null}}'
kubectl get widget gadget      # NotFound
```

![Finalizer removed — the Widget is finally deleted](../../artifacts/lab-06/screenshots/03-operator-finalizer-fixed.png)

> ⚠️ **Gotcha — force-removing a finalizer skips the cleanup it was protecting.** Patching `finalizers: null` makes the object disappear, but it **bypasses whatever the operator was going to do** — deprovisioning a cloud disk, deregistering a load balancer, deleting a DNS record. You may have **orphaned the real resource** it represented, which will keep costing money and won't be tracked. The correct fix is almost always to get the operator healthy again so it removes its own finalizer *after* real cleanup; the manual patch is a last resort for when the operator is gone for good and you've verified the external cleanup by hand.

---

## Step 3 — The classic incident: a namespace stuck in `Terminating`

**Goal:** wedge a whole namespace by leaving one finalizer-blocked object inside it, then diagnose it from the namespace's own conditions.

**1. Create a namespace with a blocked ConfigMap inside, then delete the namespace:**

```bash
kubectl create namespace stuck-demo
kubectl -n stuck-demo create configmap blocker --from-literal=k=v
kubectl -n stuck-demo patch configmap blocker --type=merge \
  -p '{"metadata":{"finalizers":["demo.example.com/hold"]}}'

kubectl delete namespace stuck-demo --wait=false
kubectl get namespace stuck-demo -o jsonpath='phase={.status.phase}{"\n"}'
kubectl get namespace stuck-demo -o jsonpath='{range .status.conditions[*]}{.type}={.status} ({.reason}){"\n"}{end}'
```

*(The conditions take ~10 seconds to populate after the delete — if the second command prints nothing, wait a moment and re-run it.)*

**What you should see:** `phase=Terminating`, and the conditions name the blockage — `NamespaceContentRemaining=True (SomeResourcesRemain)` and `NamespaceFinalizersRemaining=True (SomeFinalizersRemain)`.

![Namespace Terminating, conditions point at the remaining content](../../artifacts/lab-06/screenshots/04-namespace-stuck.png)

**What this means:** deleting a namespace deletes everything in it — so a single finalizer-blocked object wedges the whole namespace. The namespace's `status.conditions` are the right place to look first: they tell you *what* it's waiting on, so you don't have to guess.

**2. Fix the root cause** — clear the finalizer on the object *inside* the namespace:

```bash
kubectl -n stuck-demo patch configmap blocker --type=merge -p '{"metadata":{"finalizers":null}}'
kubectl get namespace stuck-demo      # after ~25s: NotFound
```

![Blocker cleared — the namespace terminates](../../artifacts/lab-06/screenshots/05-namespace-recovered.png)

**What this means:** within about half a minute (the namespace controller re-checks on an interval) the namespace finishes and disappears. Note that you fixed the *cause* (the blocked object), not the symptom — editing the namespace's own `spec.finalizers` (the other "fix" you'll see online) is a sledgehammer that can strand the very content it was still trying to clean up.

---

## Step 4 — The other operator failure: a reconcile hot loop

**Goal:** meet the failure where every controller reports success and the cluster still thrashes.

A stuck deletion is loud — something sits in `Terminating` and stays there. A **hot loop** is the
opposite: two controllers each doing their job correctly, forever, against each other. Nothing errors.

The textbook version is an operator that requeues itself without backoff. The version you will
actually meet is this one:

> **Git declares `spec.replicas: 2`. A HorizontalPodAutoscaler declares `minReplicas: 5`.**
> Neither is wrong. Neither yields.

Set it up — a Flux Kustomization applying a Deployment pinned at 2 replicas, then:

```bash
kubectl -n shop autoscale deploy/api --min=5 --max=10 --cpu=80%
```

**Sample the replica count every five seconds:**

```
t+5    deploy=2  hpa=5
t+15   deploy=5  hpa=5      <- HPA wins
t+20   deploy=2  hpa=5      <- Flux wins
t+30   deploy=5  hpa=5
t+65   deploy=2  hpa=5
t+85   deploy=2  hpa=5
t+90   deploy=5  hpa=5
```

Pods are being created and destroyed continuously. Now try to find that in the usual places.

![Ninety seconds of sampling: the Deployment oscillates 5, 2, 5, 2, 5, 2 while the HPA minimum never moves off 5](../../artifacts/lab-06/screenshots/06-hot-loop-oscillation.png)


### Why this is hard to see

```bash
kubectl -n flux-system get kustomization app -o jsonpath='{.status.conditions}'
kubectl -n shop get hpa api -o jsonpath='{.status.conditions}'
```

```
ready = True    msg = Applied revision: main@sha1:5e998bf4...
hpa   = AbleToScale True, ScaledToZero False, ScalingActive False
```

> ⚠️ **`ScalingActive False` is not the bug, and it does not stop the loop.** On `kind`, the
> metrics pipeline often serves node metrics but not Pod metrics, so the HPA reports
> `failed to get cpu utilization: no metrics returned from resource metrics API` and `TARGETS`
> shows `cpu: <unknown>`. It still enforces **`minReplicas: 5`** — which is all this fight needs.
> If your cluster has working Pod metrics you will see `ScalingActive True` instead; the
> oscillation is identical either way.

**Both controllers report success.** Flux says it applied the revision — true. The HPA says it is
scaling normally — also true. Neither can see the other, and **nothing in either status will ever
tell you there is a fight.**

### Where it does show: the event `count` field

```bash
kubectl -n shop get events \
  -o custom-columns='COUNT:.count,REASON:.reason,MSG:.message' | grep -i scaling
```

```
COUNT   REASON              MSG
1       ScalingReplicaSet   Scaled up replica set api-97fd78bc6 from 0 to 2
9       ScalingReplicaSet   Scaled up replica set api-97fd78bc6 from 2 to 5
9       ScalingReplicaSet   Scaled down replica set api-97fd78bc6 from 5 to 2
```

![Flux reports Ready True with the revision applied and the HPA reports no error, while the ScalingReplicaSet events show the same scale-up and scale-down repeated four times each](../../artifacts/lab-06/screenshots/07-both-controllers-report-success.png)


**Nine up, nine down.** Kubernetes aggregates repeated events into one record with a `count`, so the
default `kubectl get events` output shows this as two unremarkable lines. Ask for the count column
and the loop is obvious.

> **The diagnostic habit worth taking away:** when something is thrashing and every controller claims
> success, stop reading statuses and start counting events. `.count` is the field that reveals
> repetition, and it is not in the default output.

### The fix — decide which controller owns the field

Remove `spec.replicas` from the Git manifest entirely and let the HPA own it:

```yaml
spec:
  # replicas deliberately ABSENT — the HorizontalPodAutoscaler owns this field.
  selector:
    matchLabels: { app: api }
```

```
deploy=5  hpa=5
deploy=5  hpa=5      ... stable for 75s, counts stopped advancing
```

> ⚠️ **Gotcha — deleting `replicas` is not "leave it alone".** The field **defaults to 1**, so the
> Deployment scaled `2 → 1` before the HPA pulled it back to 5. On a busy service that is a real
> capacity dip in the middle of your fix. Do it in a maintenance window, or keep the field in Git and
> tell the reconciler to **ignore** it rather than removing it.

**The general rule:** for any field, exactly one controller may own it. Two owners is not a
misconfiguration you can tune your way out of — it is a design error, and the only fix is to decide.

---

## Step 5 — Clean up

```bash
kubectl delete crd widgets.example.com --ignore-not-found
```

Leave the `advk8s-day2` cluster running for Labs 6 and C.

---

## What you learned

| You saw… | in Step | proof |
|---|---|---|
| `kubectl delete` returning "deleted" ≠ object gone | 1 | ConfigMap present with `deletionTimestamp` after "deleted" |
| A finalizer holds an object in `Terminating` until removed | 1 / 2 | object persists with `finalizers` set |
| Operator resources wedge when the operator can't clear its finalizer | 2 | `Widget` stuck on `widgets.example.com/cleanup` |
| Force-removing a finalizer skips protected cleanup | 2 gotcha |
| A finalizer-blocked object wedges its whole namespace | 3 | `stuck-demo` in `Terminating` |
| Namespace `status.conditions` name the blockage | 3 | `NamespaceContentRemaining` / `NamespaceFinalizersRemaining` |
| A hot loop is two controllers each succeeding, forever | 4 | replicas oscillating `2↔5` while both report Ready |
| Controller status never reveals a fight | 4 | Flux `Applied revision` while the replica count oscillates |
| Event `.count` is where repetition shows | 4 | one line, `count=9` — invisible in default output |
| One field, one owner — two owners is a design error | 4 | removing `replicas` from Git settled it at 5/5 |
| Deleting `replicas` momentarily scales to 1 | 4 gotcha | `Scaled down from 2 to 1` before the HPA recovered it |


## Evidence

The hot-loop run is captured in
[`artifacts/lab-06/evidence/lab-06-reconcile-hot-loop.txt`](../../artifacts/lab-06/evidence/lab-06-reconcile-hot-loop.txt)
— 58 lines from 2026-09-25 (Kubernetes 1.37.0, Flux 2.9.5), including the oscillation samples, the
aggregated event counts, both controllers reporting success, and the momentary drop to 1 during the fix.

### Original evidence

Real screenshots for this lab are in [`artifacts/lab-06/screenshots/`](../../artifacts/lab-06/screenshots/) (5 images), and a full command transcript is in [`artifacts/lab-06/evidence/lab-05-operators-finalizers.txt`](../../artifacts/lab-06/evidence/lab-05-operators-finalizers.txt).

---

---

**Next:** [Lab 7 — Find the Cluster's Breaking Point (Cluster Scale Knee-Point)](../further-labs/lab-07-cluster-scale-knee-point.docx)
