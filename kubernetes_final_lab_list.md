# Kubernetes Advanced — FINAL Lab List (26 Labs)

Combines the 19 labs from the original outline with the 7 additional labs sourced from the existing `datacouch-io/Advanced_Kubernetes` repo. Organized by day. Status legend:

- 🆕 **NEW BUILD** — authored from scratch for this course
- ♻️ **REUSE / ADAPT** — adapted from an existing, already-verified repo lab
- ➕ **ADDED FROM REPO** — a previously-unused repo lab, added to fill a gap the outline didn't cover

---

## Day 1 — How Kubernetes Really Works

| # | Lab | Status | Visible End Result |
|---|---|---|---|
| 1 | Reconciliation Tracing (Module 1) | 🆕 New Build | Live trace of desired-vs-observed state converging after disruptive actions |
| 2 | API Request Lifecycle & Priority and Fairness (Module 2) | 🆕 New Build | Critical traffic keeps succeeding under a LIST storm once a FlowSchema is applied |
| 3 | etcd Quota Alarm & Recovery (Module 3 — Add'l Day A) | 🆕 New Build | Cluster goes read-only, then recovers to accepting writes |
| 4 | Pending-Pod Diagnostics (Module 4) | 🆕 New Build | Seeded Pending Pods transition to Running once diagnosed |
| A | Cluster Architecture Choices: Autopilot vs. Standard | ➕ Added from Repo (Lab 1) | Lose and regain control-plane access; Autopilot rejects a privileged container Standard allows |

---

## Day 2 — Extending and Operating the Platform Under Pressure

| # | Lab | Status | Visible End Result |
|---|---|---|---|
| 5 | Operators, Finalizers & Stuck Deletions (Module 5 — Add'l Day A) | 🆕 New Build | A resource stuck in `Terminating` is successfully deleted once the finalizer is fixed |
| 6 | Cluster Scale Knee-Point (Module 6 — Add'l Day A) | 🆕 New Build | Live latency/throughput graph showing the degradation point |
| 7 | Cilium & Hubble Flow Diagnosis (Module 7) | 🆕 New Build | Live flow drop traced to a specific policy rule, then confirmed fixed |
| B | Multi-Cluster Service Mesh with Istio | ➕ Added from Repo (Lab 4) | Envoy sidecar inspection confirms cross-cluster routing to the correct real Pod IP |
| C | Image Scanning & Admission Control with Kyverno | ➕ Added from Repo (Lab 7) | A policy-compliant Pod is still caught crashing at runtime — spec-compliant ≠ image-safe |

---

## Day 3 — Stateful Workloads, Persistent Storage & Service Exposure

| # | Lab | Status | Visible End Result |
|---|---|---|---|
| 8 | StatefulSets, PVCs & Volume Snapshots (Module 8) | 🆕 New Build | Data survives a snapshot/restore cycle; seeded PVC failures resolved |
| 9 | Backup & Restore with Velero (Module 9) | 🆕 New Build | A fully deleted namespace comes back with intact data |
| 10 | Bare-Metal LoadBalancer with MetalLB (Module 10) | 🆕 New Build | A Service with no external IP gets a real, reachable one; survives forced failover |
| 11 | Log-Based Diagnosis with Loki (Module 11) | 🆕 New Build | A LogQL query pinpoints the root cause of a prior module's failure |

---

## Day 4 — GitOps, Fleet Management & Multi-Cluster Governance

| # | Lab | Status | Visible End Result |
|---|---|---|---|
| 12 | Flux CD, Drift Detection & Recovery (Module 12) | 🆕 New Build | A manual `kubectl edit` is silently reverted by Flux within seconds |
| 13 | Fleet Registration & Staged Upgrades (Module 13) | ♻️ Reuse (validation methodology from Labs 2–6) | One commit rolls out across the fleet in sequence; drift on one cluster is caught and corrected |
| 14 | Multi-Tenant Quota Governance with Kueue (Module 14) | 🆕 New Build | A quota-blocked tenant successfully borrows capacity via Kueue cohorts |

---

## Day 5 — Kubernetes as the AI-Native Platform (Additional Day B)

| # | Lab | Status | Visible End Result |
|---|---|---|---|
| 15A | Dynamic Resource Allocation for Accelerators (Module 15, Part A) | 🆕 New Build | A Pod requesting a device by attribute is placed only on a matching simulated node |
| 15B | Kueue-Managed Distributed Training (Module 15, Focused Lesson) | ♻️ Reuse / Adapt (Repo Lab 12) | Real verified `torch.distributed` job (`all_reduce result: 3.0`), now with Kueue admission/preemption added |
| F | Advanced HPA/VPA Autoscaling Patterns | ➕ Added from Repo (Lab 10) | VPA resizes a live Pod's resources with zero restarts |
| 16 | Inference Autoscaling Signals (Module 16) | ♻️ Reuse / Adapt (Repo Labs 13 & 14) | Queue depth/time-to-first-token spikes under load, then recovers after manual scaling |
| D | Workload Identity & Binary Authorization | ➕ Added from Repo (Lab 8) | An unsigned image is denied; the same image, signed, is allowed |
| E | Runtime Security with Falco | ➕ Added from Repo (Lab 9) | Falco fires a live alert on anomalous runtime container behavior |
| 17 | Guardrailed Agentic Kubernetes (Module 17) | 🆕 New Build | An attempted agent mutation is denied and logged; reads succeed normally |
| G | Chaos Engineering with Chaos Mesh | ➕ Added from Repo (Lab 16) | A NetworkChaos experiment plus a default readiness-probe timeout takes a Service to zero ready endpoints, live |
| 18 | Capstone: Production War-Room (Module 18) | 🆕 New Build | A cluster failing across six fault domains simultaneously ends the exercise fully healthy, plus a postmortem |

---

## Final Tally

| Status | Count |
|---|---|
| 🆕 New Build | 15 |
| ♻️ Reuse / Adapt | 3 |
| ➕ Added from Repo | 7 |
| **Total** | **26 labs** (up from the original 19) |

## Cost Profile of the Full 26

| Environment | Labs |
|---|---|
| Free / local (`kind`) | 20 labs — everything except A, B, D (real GKE, "a few $" each) and 15B, 16 (adapt real-cloud repo content, cost depends on final scope decision) |
| Real cloud, low cost (~a few $) | Labs A, B, D |
| Real cloud, cost/scope still to be decided | 15B, 16 — pending the strategic call on whether to adapt the repo's real-GPU versions or keep the simulated `kind` versions as originally scoped |

## Open Items Before Building
1. **Real-cloud vs. simulated decision** for Labs 13, 15B, and 16 — determines whether they use the repo's real GKE/EKS content or the outline's original free/local design.
2. **Lab 15B (instructor-guided vs. participant hands-on)** — the outline marks this as instructor-driven; confirm whether adapting Repo Lab 12 changes that.
3. **Fetch the actual repo lab files** (not just the README summaries) for Labs A–G before finalizing exact steps, screenshots, and duration estimates.
4. **Day 5 is now the heaviest day** (9 labs across 15A/15B/F/16/D/E/17/G/18) — worth reviewing whether Additional Labs D, E, and F should be redistributed earlier in the week rather than all stacked on the final day.
