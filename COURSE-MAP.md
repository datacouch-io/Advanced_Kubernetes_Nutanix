# Advanced Kubernetes (Nutanix) — Course Map

**Restructured 2026-09-25 to the client's three-day outline** (`Kubernetes_Advanced_3-Day_Outline.docx`).

Three scheduled days of 13 labs, an optional additional day of 3, and 12 further labs held in reserve.
Every lab is a self-contained student guide — orientation → step-by-step with real screenshots →
"what you learned" → evidence — and ships with a matching `.docx` beside it.

**Platform key:** `GKE` = Google Kubernetes Engine · `kind` = local Docker-based cluster, used where
the lab needs control-plane, CNI, multi-cluster or bare-metal access.

| Folder | Outline coverage | Labs |
|---|---|---|
| [`day-1-internals-and-networking/`](day-1-internals-and-networking/) | Modules 1–4 | 4 |
| [`day-2-stateful-storage-and-exposure/`](day-2-stateful-storage-and-exposure/) | Modules 5–8 | 4 |
| [`day-3-gitops-fleet-and-governance/`](day-3-gitops-fleet-and-governance/) | Modules 9–11 | 5 |
| [`additional/optional-day-control-plane-and-war-room/`](additional/optional-day-control-plane-and-war-room/) | Modules 12–14 (optional day) | 3 |
| [`additional/further-labs/`](additional/further-labs/) | Not in this outline | 13 |

---

## Day 1 — How Kubernetes Really Works: Internals & Networking

| Module | Topic | Lab | What the lab proves | Platform |
|---|---|---|---|---|
| 1 | The Reconciliation Engine | [Reconciliation Tracing](day-1-internals-and-networking/lab-01-reconciliation-tracing.md) | Watch desired vs observed state converge after disruptive actions | kind |
| 2 | The API Server & Request Lifecycle at Scale | [API Priority & Fairness](day-1-internals-and-networking/lab-02-api-priority-fairness.md) | Keep critical traffic succeeding under a LIST storm with a FlowSchema | kind |
| 3 | Scheduling & Controllers | [Pending-Pod Diagnostics](day-1-internals-and-networking/lab-04-pending-pod-diagnostics.md) | Diagnose and clear seeded unschedulable Pods | GKE |
| 4 | Networking & the Data Plane | [Cilium & Hubble Flow Diagnosis](day-1-internals-and-networking/lab-08-cilium-hubble.md) | Trace a dropped flow to a specific network policy, then confirm the fix | kind |

*End-of-day diagnostic scenario — Pending **and** DNS failure — is run from the Module 3 and Module 4
labs back to back. No separate lab file.*

## Day 2 — Stateful Workloads, Persistent Storage & Service Exposure

| Module | Topic | Lab | What the lab proves | Platform |
|---|---|---|---|---|
| 5 | Stateful Workloads & Persistent Storage | [StatefulSets, PVCs & Volume Snapshots](day-2-stateful-storage-and-exposure/lab-11-statefulsets-snapshots.md) | Survive a snapshot/restore cycle with data intact | GKE |
| 6 | Backup, Restore & DR with Velero | [Backup & Restore with Velero](day-2-stateful-storage-and-exposure/lab-12-velero-backup-restore.md) | Delete a whole namespace and bring it back from object storage | GKE |
| 7 | Service Exposure on Bare Metal | [Bare-Metal LoadBalancer (MetalLB)](day-2-stateful-storage-and-exposure/lab-13-metallb.md) | Give a `LoadBalancer` Service a real IP on bare metal; survive node failure | kind |
| 8 | Logging & Observability with Loki | [Log-Based Diagnosis with Loki](day-2-stateful-storage-and-exposure/lab-14-loki.md) | Pinpoint a failure's root cause with a LogQL query | GKE |

## Day 3 — GitOps, Fleet Management & Multi-Cluster Governance

| Module | Topic | Lab | What the lab proves | Platform |
|---|---|---|---|---|
| 9 | GitOps with Flux CD | [GitOps Delivery with Flux](day-3-gitops-fleet-and-governance/lab-15-flux.md) | Deliver from Git; manual drift is reverted automatically | GKE |
| 10 | Fleet Management & Multi-Cluster Ops | [Two Clusters as One Fleet (Flux)](day-3-gitops-fleet-and-governance/lab-29-flux-fleet-two-clusters.md) | One repo, per-cluster overlays, canary→production rings gated by a merge | kind ×2 |
| 10 | *(alternative)* | [Fleet Registration & Staged Rollout](day-3-gitops-fleet-and-governance/lab-16-fleet.md) | The same job with Rancher Fleet | kind ×3 |
| 11 | Multi-Tenancy, Quotas & Limits | [Tenant Quota Governance](day-3-gitops-fleet-and-governance/lab-27-tenant-quota-governance.md) | Quota + LimitRange via Flux; exhaustion diagnosed; per-cluster quota from a fleet budget | kind |
| 11 | *(continued)* | [Multi-Tenant Quota with Kueue](day-3-gitops-fleet-and-governance/lab-17-kueue.md) | A quota-blocked tenant borrows idle capacity via a cohort | GKE |

*End-of-day diagnostic scenario — a Flux-delivered tenant change that fails to reconcile, then hits
quota exhaustion — combines the Module 9 and Module 11 labs.*

## Optional Additional Day — Control-Plane Internals & Production War-Room

| Module | Topic | Lab | What the lab proves | Platform |
|---|---|---|---|---|
| 12 | etcd — the cluster's source of truth | [etcd Quota Alarm & Recovery](additional/optional-day-control-plane-and-war-room/lab-03-etcd-quota-recovery.md) | Trip the etcd NOSPACE alarm, then compact/defrag/disarm back to writable | kind |
| 13 | Extending Kubernetes — CRDs & Operators | [Operators, Finalizers & Stuck Deletions](additional/optional-day-control-plane-and-war-room/lab-06-operators-finalizers.md) | Free a resource stuck `Terminating` by fixing its finalizer | GKE |
| 14 | Capstone — Production War-Room | [Capstone: Production War-Room](additional/optional-day-control-plane-and-war-room/lab-26-capstone.md) | Six fault domains matching the outline — API pressure, etcd, operator, scheduling, CoreDNS/NetworkPolicy, Kueue | kind |

## Further Labs — not in this outline

Twelve tested labs held in reserve. Full table in
[`additional/further-labs/README.md`](additional/further-labs/README.md).

Cluster architecture · scale knee-point · Istio multi-cluster mesh · Kyverno admission control ·
DRA · distributed training · HPA/VPA · inference autoscaling · workload identity & binary
authorization · Falco · agentic guardrails · Chaos Mesh · a GKE capstone variant.

---

## Shared assets

| Path | Contents |
|---|---|
| [`artifacts/`](artifacts/) | Per-lab `screenshots/`, `diagrams/`, `evidence/` — referenced by every lab |
| [`tools/`](tools/) | `lab2docx.sh` and helpers that build the Word copies |
| [`build/`](build/) | Intermediate build files and the Word reference style |

Lab numbering (`lab-01` … `lab-26`) is **unchanged** from the 26-lab course — only the folders moved,
so evidence paths, `.docx` names and the old→new history in
[`RENUMBERING-MAP.md`](RENUMBERING-MAP.md) all still line up.
