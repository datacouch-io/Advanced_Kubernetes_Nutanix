# Lab 27 — Make a Tenant Budget Real (ResourceQuota, LimitRange & a Fleet Budget, delivered by Flux)

**Day 3 · GitOps, Fleet Management & Multi-Cluster Governance — Module 11**

> ✅ **Tested end-to-end** on a real `kind` cluster (Kubernetes 1.37.0) with **Flux 2.9.5** reconciling from a **Gitea 1.22 server running inside the cluster** — no public repository involved. Every number below is from that run. The finding that surprises everyone: the tenant's Deployment stopped at **8 replicas**, not the 20 its CPU request budget implied — because a *default* chosen in the LimitRange, not the request, is what actually consumed the quota.

## What you'll learn

- How a tenant contract — namespace, ResourceQuota, LimitRange — is **delivered by Flux** rather than applied by hand, so the quota is as auditable as the code.
- Why a ResourceQuota **without** a LimitRange silently breaks every ordinary workload, and why the error is nowhere near where you'll look for it.
- How LimitRange defaults quietly set the **overcommit ratio**, and therefore how many Pods a tenant can actually run.
- How to diagnose quota exhaustion when `kubectl get pods` shows **nothing at all**.
- How to derive **per-cluster quota from a single fleet budget** without forking the repository per cluster.

## What you'll do

You'll stand up a Git server inside the cluster, point Flux at it, and deliver a tenant namespace with a quota. You'll watch an ordinary Deployment disappear without trace, find the real error two objects away, and fix it with a LimitRange — delivered the same way. Then you'll drive the tenant into exhaustion, work out why it stopped where it did, and finish by rendering the same Git commit into two different per-cluster quotas from a fleet budget.

## Time & cost

- **Time:** ~60 minutes.
- **Cost:** **$0** — runs on a local `kind` cluster.

---

## Before you start

- **Where you'll work:** a terminal on your own machine.
- **Tools you need:** `docker`, `kind`, `kubectl`, and the **`flux`** CLI (`brew install fluxcd/tap/flux`).
- **Prior labs:** none strictly required, but [Lab 15 — GitOps Delivery with Flux](lab-15-flux.md) makes Step 2 feel familiar, and [Lab 17 — Multi-Tenant Quota with Kueue](lab-17-kueue.md) is the other half of Module 11. Run this one **first**: it establishes the quota contract that Kueue then borrows against.

> **Nutanix note.** Nothing here is cloud-specific — ResourceQuota, LimitRange and Flux are upstream Kubernetes and behave identically on NKE. What changes on-prem is who owns the numbers: with a fixed pool of physical capacity there is no autoscaler to paper over a bad budget, so the fleet-budget arithmetic in Step 6 stops being bookkeeping and becomes the actual constraint.

---

## The idea in 60 seconds

A **ResourceQuota** caps what a namespace may consume. A **LimitRange** supplies the per-container defaults that make the cap enforceable. They only work as a pair, and the failure when you ship one without the other is genuinely hard to read.

Delivering both through **Flux** turns the tenant budget into something reviewed in a pull request and reconciled continuously, rather than a `kubectl apply` somebody ran once. And because Flux can substitute variables at apply time, **one manifest in Git can render a different quota on every cluster** — which is how a fleet-level budget gets divided without forking the repository.

---

## Step 1 — Put a Git server inside the cluster

**Goal:** have a Git source that works with no internet access and no credentials to leak.

Every Flux demo reaches for GitHub. A training room behind a proxy, or a client with an air-gapped environment, cannot. Run the Git server in the cluster instead:

```bash
kubectl create ns git-server
kubectl -n git-server create deployment gitea --image=gitea/gitea:1.22
kubectl -n git-server set env deploy/gitea \
  GITEA__database__DB_TYPE=sqlite3 \
  GITEA__security__INSTALL_LOCK=true
kubectl -n git-server expose deploy/gitea --port=3000
kubectl -n git-server rollout status deploy/gitea
```

Create an account and an empty repository:

```bash
POD=$(kubectl -n git-server get pod -l app=gitea -o name | head -1)
kubectl -n git-server exec $POD -- su git -c \
  "gitea admin user create --username labadmin --password labpass123 \
   --email lab@example.com --admin --must-change-password=false"

kubectl -n git-server exec $POD -- curl -s -u labadmin:labpass123 \
  -X POST http://localhost:3000/api/v1/user/repos \
  -H 'Content-Type: application/json' \
  -d '{"name":"tenants","auto_init":true,"default_branch":"main"}'
```

**What you should see:** `New user 'labadmin' has been successfully created!` and an HTTP `201` from the repository call.

**What this means.** You now have a real Git remote at `http://gitea.git-server.svc.cluster.local:3000/labadmin/tenants.git`, reachable from inside the cluster and from nowhere else.

---

## Step 2 — Point Flux at it and deliver the tenant

**Goal:** make the tenant contract a thing Git owns.

```bash
flux install --components=source-controller,kustomize-controller

kubectl -n flux-system create secret generic gitea-auth \
  --from-literal=username=labadmin --from-literal=password=labpass123
```

Commit a namespace and a quota to `tenants/team-a/`:

```yaml
# tenants/team-a/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: team-a
  labels: { tenant: team-a }
---
# tenants/team-a/quota.yaml
apiVersion: v1
kind: ResourceQuota
metadata: { name: team-a-quota, namespace: team-a }
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 2Gi
    limits.cpu: "4"
    limits.memory: 4Gi
    count/deployments.apps: "5"
```

Then wire up the source:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata: { name: tenants, namespace: flux-system }
spec:
  interval: 30s
  url: http://gitea.git-server.svc.cluster.local:3000/labadmin/tenants.git
  ref: { branch: main }
  secretRef: { name: gitea-auth }
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata: { name: tenants, namespace: flux-system }
spec:
  interval: 30s
  path: ./tenants
  prune: true
  sourceRef: { kind: GitRepository, name: tenants }
EOF

flux get kustomizations
```

**What you should see:**

```
NAME     REVISION            READY   MESSAGE
tenants  main@sha1:6371c28a  True    Applied revision: main@sha1:6371c28a
```

**What this means.** The namespace and its quota now exist because Git says they should. Delete the quota by hand and Flux puts it back within 30 seconds — which is the property that makes a tenant budget a *contract* rather than a suggestion.

---

## Step 3 — Watch an ordinary Deployment vanish

**Goal:** meet the failure the outline calls *"a missing default silently breaks quota enforcement."*

Deploy something completely unremarkable:

```bash
kubectl -n team-a create deployment web --image=nginx:1.27
kubectl -n team-a get pods
kubectl -n team-a get deploy web
```

**What you should see:**

```
$ kubectl -n team-a get pods
No resources found in team-a namespace.

$ kubectl -n team-a get deploy web
NAME   READY   UP-TO-DATE   AVAILABLE   AGE
web    0/1     0            0           8s
```

**What this means — and why it is nasty.** There is no Pending Pod. There is no failing Pod. There is **no Pod at all**, so there is nothing to `describe`. The Deployment just sits at `0/1` looking slow.

The error is two objects away, on the ReplicaSet:

```bash
kubectl -n team-a get events --field-selector reason=FailedCreate \
  -o jsonpath='{.items[-1:].message}'
```

```
Error creating: pods "web-69c6f74b8b-s8jvf" is forbidden: failed quota: team-a-quota:
must specify limits.cpu for: nginx; limits.memory for: nginx;
requests.cpu for: nginx; requests.memory for: nginx
```

Once a ResourceQuota covers `cpu` or `memory`, **every Pod in that namespace must state requests and limits** — and a stock Deployment states none. The tenant is not over budget. It cannot spend at all.

> ⚠️ **Gotcha — the events are on the ReplicaSet, and they expire.** `kubectl describe deploy` will not show you this; the Deployment controller is not the one being refused. Go to the ReplicaSet, or query events by `reason=FailedCreate`. And because events default to a one-hour TTL, a tenant who reports this the next morning will have nothing left to show you.

---

## Step 4 — Ship the LimitRange, the same way

**Goal:** fix it through Git, not through `kubectl`.

Commit alongside the quota:

```yaml
# tenants/team-a/limits.yaml
apiVersion: v1
kind: LimitRange
metadata: { name: team-a-defaults, namespace: team-a }
spec:
  limits:
    - type: Container
      # what a container gets when it asks for nothing
      defaultRequest: { cpu: 100m, memory: 128Mi }
      default:        { cpu: 500m, memory: 512Mi }
      # and the ceiling it may not exceed
      max:            { cpu: "1",  memory: 1Gi }
```

```bash
flux reconcile kustomization tenants --with-source
kubectl -n team-a rollout restart deploy/web
kubectl -n team-a get pods
kubectl -n team-a get pod -l app=web -o jsonpath='{.items[0].spec.containers[0].resources}'
```

**What you should see:**

```
NAME                  READY   STATUS    RESTARTS   AGE
web-bd64fdf85-6dq2f   1/1     Running   0          15s

{"limits":{"cpu":"500m","memory":"512Mi"},"requests":{"cpu":"100m","memory":"128Mi"}}
```

**What this means.** Nothing about the Deployment changed — no one edited the manifest to add resources. The LimitRange filled in exactly what the quota insisted on. **Quota is the ceiling; LimitRange is what lets ordinary workloads reach it.** Ship them together or the tenant is simply locked out.

---

## Step 5 — Exhaust the quota, and work out why it stopped where it did

**Goal:** diagnose exhaustion, and meet the arithmetic that decides a tenant's real capacity.

```bash
kubectl -n team-a scale deploy/web --replicas=25
kubectl -n team-a get deploy web
kubectl -n team-a describe resourcequota team-a-quota
```

**What you should see:**

```
NAME   READY   UP-TO-DATE   AVAILABLE   AGE
web    8/25    8            8           2m4s

Resource                Used  Hard
--------                ----  ----
count/deployments.apps  1     5
limits.cpu              4     4
limits.memory           4Gi   4Gi
requests.cpu            800m  2
requests.memory         1Gi   2Gi
```

```
Error creating: pods ... is forbidden: exceeded quota: team-a-quota,
requested: limits.cpu=500m,limits.memory=512Mi,
used: limits.cpu=4,limits.memory=4Gi, limited: limits.cpu=4,limits.memory=4Gi
```

**Stop and read the numbers before moving on.** It stopped at **8** replicas. The obvious prediction was 20: `requests.cpu` is capped at 2 CPU and each Pod requests `100m`.

But `requests.cpu` is only at **800m of 2** — nowhere near full. The constraint that actually bound is **`limits.cpu`: 4 of 4**, consumed by the LimitRange's *default limit* of `500m` per container:

```
4000m  ÷  500m  =  8 Pods
```

**The overcommit ratio you chose in the LimitRange — not the request — decided how many Pods this tenant can run.** A default limit of `200m` instead of `500m` would have let the same quota carry 20. This is the single most useful thing in the lab: the tenant's real capacity is set by a field most people copy from an example without reading.

> ⚠️ **Gotcha — a quota can block your own incident response.** `limits.cpu` being full means the tenant cannot scale *anything* up, including a controller reacting to an outage. When a quota is exhausted, check whether the thing you're about to rely on to recover is also inside it.

---

## Step 6 — One commit, two clusters, different budgets

**Goal:** split a fleet-level budget across clusters without forking the repository.

Kubernetes has **no cross-cluster quota**. What you can do is derive each cluster's share from a fleet budget and let Flux render it. Replace the hard-coded numbers in Git with variables:

```yaml
# tenants/team-a/quota.yaml
spec:
  hard:
    # rendered per cluster from that cluster's share of the fleet budget
    requests.cpu:    "${TEAM_A_CPU}"
    requests.memory: "${TEAM_A_MEM}"
    limits.cpu:      "${TEAM_A_CPU_LIMIT}"
    limits.memory:   "${TEAM_A_MEM_LIMIT}"
    count/deployments.apps: "5"
```

Each cluster holds **its own share** as a ConfigMap. Fleet budget for `team-a` is 20 CPU; this cluster carries 60%:

```bash
kubectl -n flux-system create configmap cluster-budget \
  --from-literal=TEAM_A_CPU=12       --from-literal=TEAM_A_MEM=12Gi \
  --from-literal=TEAM_A_CPU_LIMIT=24 --from-literal=TEAM_A_MEM_LIMIT=24Gi

kubectl -n flux-system patch kustomization tenants --type merge -p \
  '{"spec":{"postBuild":{"substituteFrom":[{"kind":"ConfigMap","name":"cluster-budget"}]}}}'

flux reconcile kustomization tenants --with-source
kubectl -n team-a get resourcequota team-a-quota -o jsonpath='{.spec.hard}'
```

**Rendered on cluster-01 (60% share):**

```
{"count/deployments.apps":"5","limits.cpu":"24","limits.memory":"24Gi",
 "requests.cpu":"12","requests.memory":"12Gi"}
```

Now swap in the other cluster's share and reconcile again — **without touching Git**:

```bash
kubectl -n flux-system create configmap cluster-budget \
  --from-literal=TEAM_A_CPU=8        --from-literal=TEAM_A_MEM=8Gi \
  --from-literal=TEAM_A_CPU_LIMIT=16 --from-literal=TEAM_A_MEM_LIMIT=16Gi \
  --dry-run=client -o yaml | kubectl apply -f -

flux reconcile kustomization tenants
kubectl -n team-a get resourcequota team-a-quota -o jsonpath='{.spec.hard}'
flux get kustomizations
```

**Rendered with cluster-02's share (40%):**

```
{"count/deployments.apps":"5","limits.cpu":"16","limits.memory":"16Gi",
 "requests.cpu":"8","requests.memory":"8Gi"}

tenants  main@sha1:cca67164  True  Applied revision: main@sha1:cca67164
```

**What this means.** The Git revision is **identical** — `cca67164` both times. The same reviewed, audited manifest produced a 12-CPU quota on one cluster and an 8-CPU quota on the other, because the budget lives in the cluster and the policy lives in Git. No per-cluster branch, no per-cluster directory, no copy-paste drift.

That is the practical answer to *"Kubernetes has no cross-cluster quota"*: you keep the **allocation** in one place and let each cluster carry its share.

---

## Step 7 — Do it again yourself, on a real two-cluster fleet

**Why:** Step 6 proved the mechanism by swapping one ConfigMap. A fleet proves it by having two clusters disagree at the same moment.

**Your task.** Stand up a second `kind` cluster, install Flux on it, point it at the *same* Gitea repository, and give it the 40% ConfigMap. Then change the fleet budget from 20 CPU to 30 and roll the new shares out to both.

**You get the acceptance criteria and nothing else:**

- Both clusters reconcile the **same Git revision**
- `kubectl get resourcequota` returns **different numbers** on each, at the same time
- Raising the fleet budget updates both, and you can say which file you changed to do it
- A tenant hitting quota on cluster-01 is **unaffected** on cluster-02 — and you can explain why that is the intended behaviour, not a bug

**Done when** you can answer: *"team-a wants 4 more CPU. What do you change, who approves it, and how would an auditor know it happened?"*

No commands are given here. Steps 1–6 have the pattern.

---

## Step 8 — Clean up

```bash
kind delete cluster --name cilium-lab
```

---

## What you learned

| You saw… | in Step | proof |
|---|---|---|
| A tenant contract can be delivered and continuously reconciled by Flux | 2 | `Applied revision: main@sha1:6371c28a` from an in-cluster Gitea |
| Flux works fine with no public Git and no internet | 1–2 | source URL is a `.svc.cluster.local` address |
| Quota without LimitRange blocks every ordinary workload | 3 | `get pods` → *No resources found*; Deployment stuck `0/1` |
| The refusal is on the ReplicaSet, not the Pod or Deployment | 3 | `FailedCreate: must specify limits.cpu for: nginx…` |
| LimitRange defaults make the same Deployment admissible, unchanged | 4 | `1/1 Running`, resources `100m/500m` injected |
| The default *limit* sets the overcommit ratio and the real Pod ceiling | 5 | stopped at **8/25**; `limits.cpu 4/4` while `requests.cpu` only `800m/2` |
| Quota exhaustion reports the dimension that actually bound | 5 | `exceeded quota … limited: limits.cpu=4` |
| One commit can render a different quota per cluster | 6 | 12 CPU then 8 CPU, both at revision `cca67164` |

## Evidence

A full command transcript is in [`artifacts/lab-27/evidence/lab-27-tenant-quota-governance.txt`](../artifacts/lab-27/evidence/lab-27-tenant-quota-governance.txt) — 111 lines captured on 2026-09-25 against Kubernetes 1.37.0 with Flux 2.9.5 and Gitea 1.22, covering every output quoted above.

> 📷 **Screenshots outstanding.** The terminal captures for this lab have not been taken yet. The
> transcript above is the authoritative record until they are; every command and output in this lab
> comes from it.

---

**Next:** [Lab 17 — Multi-Tenant Quota with Kueue](lab-17-kueue.md) — the other half of Module 11, where a tenant that has hit the quota you just built borrows idle capacity from a cohort.
