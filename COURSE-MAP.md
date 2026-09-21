# Advanced Kubernetes (Nutanix) — Course Map

26 labs, taught in order. Each lab is a self-contained student guide (orientation → step-by-step with real screenshots → "what you learned" → evidence) and ships with a matching `.docx` in [`word/`](word/).

**Platform key:** `GKE` = Google Kubernetes Engine · `kind` = local Docker-based cluster (used where the lab needs control-plane, CNI, multi-cluster, or bare-metal access).

## Day 1 — How Kubernetes Really Works
| # | Lab | Scope | Platform |
|---|-----|-------|----------|
| 1 | [Reconciliation Tracing](lab-01-reconciliation-tracing.md) | Watch desired vs observed state converge after disruptive actions | kind |
| 2 | [API Priority & Fairness](lab-02-api-priority-fairness.md) | Keep critical traffic succeeding under a LIST storm with a FlowSchema | kind |
| 3 | [etcd Quota Alarm & Recovery](lab-03-etcd-quota-recovery.md) | Trip the etcd NOSPACE alarm, then compact/defrag/disarm back to writable | kind |
| 4 | [Pending-Pod Diagnostics](lab-04-pending-pod-diagnostics.md) | Diagnose and clear seeded unschedulable Pods | GKE |
| 5 | [Cluster Architecture: Autopilot vs Standard](lab-05-cluster-architecture.md) | Private clusters, master-authorized-networks lockout/recovery, release channels | GKE |

## Day 2 — Operating the Platform Under Pressure
| # | Lab | Scope | Platform |
|---|-----|-------|----------|
| 6 | [Operators, Finalizers & Stuck Deletions](lab-06-operators-finalizers.md) | Free a resource stuck `Terminating` by fixing its finalizer | GKE |
| 7 | [Cluster Scale Knee-Point](lab-07-cluster-scale-knee-point.md) | Find the load level where scheduling latency degrades | GKE |
| 8 | [Cilium & Hubble Flow Diagnosis](lab-08-cilium-hubble.md) | Trace a dropped flow to a specific network policy, then confirm the fix | kind |
| 9 | [Multi-Cluster Service Mesh with Istio](lab-09-multicluster-service-mesh.md) | One logical Service across two clusters; verify cross-cluster routing in Envoy | GKE ×2 |
| 10 | [Image Scanning & Admission Control (Kyverno)](lab-10-image-scanning-admission-control.md) | Block non-compliant images at admission; spec-compliant ≠ safe | GKE |

## Day 3 — Stateful Workloads, Storage & Exposure
| # | Lab | Scope | Platform |
|---|-----|-------|----------|
| 11 | [StatefulSets, PVCs & Volume Snapshots](lab-11-statefulsets-snapshots.md) | Survive a snapshot/restore cycle with data intact | GKE |
| 12 | [Backup & Restore with Velero](lab-12-velero-backup-restore.md) | Delete a whole namespace and bring it back from object storage | GKE |
| 13 | [Bare-Metal LoadBalancer (MetalLB)](lab-13-metallb.md) | Give a `LoadBalancer` Service a real IP on bare metal; survive node failure | kind |
| 14 | [Log-Based Diagnosis with Loki](lab-14-loki.md) | Pinpoint a failure's root cause with a LogQL query | GKE |

## Day 4 — GitOps, Fleet & Governance
| # | Lab | Scope | Platform |
|---|-----|-------|----------|
| 15 | [GitOps Delivery with Flux](lab-15-flux.md) | Deliver from Git; manual drift is reverted automatically | GKE |
| 16 | [Fleet Registration & Staged Rollout](lab-16-fleet.md) | One commit rolls out across a fleet; drift on one cluster is corrected | kind ×3 |
| 17 | [Multi-Tenant Quota with Kueue](lab-17-kueue.md) | A quota-blocked tenant borrows idle capacity via a cohort | GKE |

## Day 5 — Kubernetes as the AI-Native Platform
| # | Lab | Scope | Platform |
|---|-----|-------|----------|
| 18 | [Dynamic Resource Allocation (DRA)](lab-18-dra.md) | Request a device by attribute; placed only on a matching node | kind |
| 19 | [Kueue-Managed Distributed Training](lab-19-distributed-training.md) | A real `torch.distributed` PyTorchJob queued and admitted by Kueue | GKE |
| 20 | [Advanced HPA/VPA Autoscaling](lab-20-hpa-vpa-autoscaling.md) | Asymmetric HPA behavior; VPA in-place resize with zero restarts | kind |
| 21 | [Inference Autoscaling Signals](lab-21-inference-autoscaling.md) | TTFT/queue-depth spike under load, then recover after scaling out | GKE |
| 22 | [Workload Identity & Binary Authorization](lab-22-workload-identity-binary-authorization.md) | Per-pod cloud identity; only signed images admitted | GKE |
| 23 | [Runtime Security with Falco](lab-23-falco-runtime-security.md) | Kernel-level alerts on live container misbehavior; a custom rule | kind |
| 24 | [Guardrailed Agentic Kubernetes](lab-24-agentic-guardrails.md) | An agent's mutations denied + audited by policy; reads succeed | GKE |
| 25 | [Chaos Engineering with Chaos Mesh](lab-25-chaos-mesh.md) | Kill a Pod (self-heal) and inject latency (surface a hidden outage) | kind |
| 26 | [Capstone: Production War-Room](lab-26-capstone.md) | Diagnose and heal six simultaneous fault domains; write the postmortem | GKE |
