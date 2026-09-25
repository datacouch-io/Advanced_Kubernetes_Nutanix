# Day 1 — How Kubernetes Really Works: Internals & Networking

**Modules 1–4 of the client outline.**

| Module | Topic | Lab | What the lab proves | Platform |
|---|---|---|---|---|
| Module 1 | The Reconciliation Engine — Kubernetes Internals | [Reconciliation Tracing](lab-01-reconciliation-tracing.md) | Watch desired vs observed state converge after disruptive actions | kind |
| Module 2 | The API Server & the Request Lifecycle at Scale | [API Priority & Fairness](lab-02-api-priority-fairness.md) | Keep critical traffic succeeding under a LIST storm with a FlowSchema | kind |
| Module 3 | Scheduling & Controllers — How Intent Becomes Reality | [Pending-Pod Diagnostics](lab-04-pending-pod-diagnostics.md) | Diagnose and clear seeded unschedulable Pods | GKE |
| Module 4 | Networking & the Data Plane — iptables, nftables, eBPF & Cilium | [Cilium & Hubble Flow Diagnosis](lab-08-cilium-hubble.md) | Trace a dropped flow to a specific network policy, then confirm the fix | kind |

**End-of-day diagnostic scenario:** a workload that is both stuck Pending *and* failing DNS resolution, diagnosed using scheduler events and Hubble flow evidence. Draw the fault from Module 3's and Module 4's labs run back to back — there is no separate lab file for it.

---

Each lab ships with a matching **`.docx`** in this folder for handout use.
Screenshots and command transcripts live in [`../artifacts/`](../artifacts/), shared across the whole course.

Full index: [`../COURSE-MAP.md`](../COURSE-MAP.md)
