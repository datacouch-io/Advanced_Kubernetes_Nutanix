# Lab 15 — Let Git Drive the Cluster (GitOps Delivery with Flux)

**Day 4 · GitOps, Multi-Cluster & Advanced Scheduling**

> ✅ **Tested end-to-end** on a **real GKE cluster** (`advk8s-lab`, `dcproject-462806`) with **Flux v2**. Every screenshot is a real capture. The payoff: you deliver an app to the cluster **without ever running `kubectl apply`** — Flux pulls it from Git — and then you *delete the live Deployment* and watch Flux **put it back**, because Git says it should exist.

## What you'll learn

- What **GitOps** actually means: Git is the single source of truth, and an in-cluster agent continuously makes the cluster match it — the same reconciliation idea from Lab 1, now applied to *your whole app*.
- How **Flux** works: a `GitRepository` source (what to watch) plus a `Kustomization` (what to apply and how often).
- Why GitOps gives you **drift detection and self-healing** for free: anything that diverges from Git is reverted.

## What you'll do

You'll install Flux on the cluster, point it at a public Git repo, and let it deploy an app (`podinfo`). Then you'll simulate drift — delete the running Deployment — and watch Flux reconcile the cluster back to what Git declares.

## Time & cost

- **Time:** ~35 minutes.
- **Cost:** negligible — Flux controllers and `podinfo` are small Pods on the shared GKE cluster.

---

## Before you start

- **Where you'll work:** in a **terminal** on your own machine.
- **Tools you need:** `gcloud`, `kubectl`, and the **`flux`** CLI (`brew install fluxcd/tap/flux`).
- **Cluster:** a GKE cluster (this course's shared `advk8s-lab`).
- **No GitHub account needed:** we use `flux install` (controllers only) and point at a **public** repo, so you never need a Git token for this lab.

> **Nutanix note.** Flux is CNCF-graduated and completely platform-agnostic — it runs identically on **NKE**. In fact GitOps is the *recommended* operating model for on-prem fleets: instead of engineers running `kubectl` against production Nutanix clusters (untracked, un-reviewable), every change is a Git commit that Flux pulls and applies. That gives you an audit trail, code review, and instant rollback (`git revert`) on infrastructure you can't always reach interactively.

---

## The idea in 60 seconds

Normally you *push* changes to a cluster: you run `kubectl apply` from your laptop or CI. GitOps inverts this — the cluster **pulls**. An agent inside the cluster (Flux) watches a Git repo and continuously reconciles the cluster to match it. Two Flux objects do this:

- a **`GitRepository`** — *where* to look (repo URL, branch, poll interval),
- a **`Kustomization`** — *what* to apply (a path in that repo), how often, and whether to **prune** (delete things removed from Git).

Because Flux reconciles on a loop, the cluster is *always* converging on Git. Change the cluster by hand and it drifts; Flux notices and reverts it. The only durable way to change anything is to change Git.

```mermaid
flowchart TB
    GIT["Git repo<br/>(desired state: podinfo manifests)"] -->|"GitRepository: poll every 1m"| SRC["source-controller<br/>(fetches the revision)"]
    SRC --> KUST["Kustomization: apply ./kustomize<br/>prune=true, interval=1m"]
    KUST -->|"kustomize-controller applies"| CLUSTER["cluster: Deployment + Service + HPA"]
    CLUSTER -.->|"someone deletes the Deployment (drift)"| DRIFT["cluster ≠ Git"]
    DRIFT -->|"next reconcile"| KUST
    KUST -->|"re-applies from Git"| CLUSTER
```

---

## Step 1 — Install Flux on the cluster

**Goal:** get the Flux controllers running. (No Git bootstrap, no token — just the agents.)

**1. Check prerequisites, then install:**

```bash
flux check --pre
flux install
```

**2. Confirm the controllers are up:**

```bash
kubectl -n flux-system get pods
```

**What you should see:** four Deployments `Running` in `flux-system` — `source-controller` (fetches Git), `kustomize-controller` (applies manifests), plus `helm-controller` and `notification-controller`.

**What this means:** the reconciliation engine is now living in your cluster. It isn't watching anything yet — you'll tell it what to watch next.

---

## Step 2 — Point Flux at a Git repo and let it deploy the app

**Goal:** declare a Git source and a Kustomization, and watch the app appear — without ever applying it yourself.

**1. Create the `GitRepository` source** (a public repo, polled every minute):

```bash
kubectl create namespace podinfo
flux create source git podinfo \
  --url=https://github.com/stefanprodan/podinfo \
  --branch=master \
  --interval=1m
```

**2. Create the `Kustomization`** that applies the manifests in `./kustomize` into the `podinfo` namespace, pruning anything removed from Git:

```bash
flux create kustomization podinfo \
  --source=GitRepository/podinfo \
  --path="./kustomize" \
  --prune=true \
  --interval=1m \
  --target-namespace=podinfo \
  --wait
```

**3. Confirm Flux is reconciling, and that the app is running:**

```bash
flux get sources git
flux get kustomizations
kubectl -n podinfo get deploy,svc,hpa
```

**What you should see:** both the source and the Kustomization report `READY: True` with a revision like `master@sha1:dd507173`, and `podinfo` (Deployment + Service + HPA) is running in the `podinfo` namespace — **you never ran `kubectl apply` for it.**

![Flux source and Kustomization both READY; podinfo delivered from Git](../artifacts/lab-15/screenshots/01-gitops-delivery.png)

**What this means:** the app's desired state lives in Git, and Flux pulled it and applied it. From here on, the way to change this app is to change Git — not the cluster.

---

## Step 3 — Cause drift, and watch Flux self-heal

**Goal:** change the cluster out from under Flux and prove it reverts you.

**1. Delete the live Deployment** — the cluster now disagrees with Git:

```bash
kubectl -n podinfo delete deploy podinfo
kubectl -n podinfo get deploy podinfo
```

**2. Trigger a reconcile** (Flux would do this on its own within the 1-minute interval; we force it so you don't wait):

```bash
flux reconcile kustomization podinfo --with-source
kubectl -n podinfo get deploy podinfo
```

**What you should see:** right after the delete, `kubectl get deploy podinfo` returns **`NotFound`** — but after the reconcile, the Deployment is **back** (`podinfo 1/1`), recreated from Git.

![Deployment deleted (NotFound), then restored by Flux on reconcile](../artifacts/lab-15/screenshots/02-drift-selfheal.png)

**What this means:** this is GitOps self-healing. Flux compared the cluster to Git, saw the Deployment was missing, and re-applied it. The same thing happens to *any* manual change — an edited image tag, a scaled replica count, a deleted Service — because Git, not the cluster, is the source of truth.

> ⚠️ **Gotcha — don't fight the reconciler.** Because Flux reverts drift, a "quick manual `kubectl edit` in production" will silently disappear at the next reconcile, which is baffling if you don't know Flux is running. To make a *real* change, commit it to Git (or `flux suspend kustomization <name>` first if you genuinely need to pause reconciliation for a break-glass fix). Manual edits are for debugging only.

---

## Step 4 — Clean up

```bash
kubectl delete namespace podinfo --ignore-not-found
flux delete source git podinfo --silent
flux delete kustomization podinfo --silent
# to remove Flux itself:
# flux uninstall --silent
```

---

## What you learned

| You saw… | in Step | proof |
|---|---|---|
| Flux runs the reconciliation engine inside the cluster | 1 | four controllers `Running` in `flux-system` |
| A GitRepository + Kustomization delivers an app from Git | 2 | both `READY: True`; `podinfo` running, never `kubectl apply`-ed |
| The cluster converges on the Git revision | 2 | `Applied revision: master@sha1:dd507173` |
| Manual drift is detected and reverted (self-healing) | 3 | Deployment deleted → `NotFound` → restored on reconcile |

## Evidence

Real screenshots for this lab are in [`artifacts/lab-15/screenshots/`](../artifacts/lab-15/screenshots/) (2 images), and a command transcript is in [`artifacts/lab-15/evidence/lab-12-flux.txt`](../artifacts/lab-15/evidence/lab-12-flux.txt).

---

---

**Next:** [Lab 16 — Drive Many Clusters from One Git Repo (Fleet Registration & Staged Rollout)](lab-16-fleet.md)
