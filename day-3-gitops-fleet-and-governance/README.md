# Day 3 — GitOps, Fleet Management & Multi-Cluster Governance

**Modules 9–11 of the client outline.**

| Module | Topic | Lab | What the lab proves | Platform |
|---|---|---|---|---|
| Module 9 | GitOps with Flux CD | [GitOps Delivery with Flux](lab-15-flux.md) | Deliver from Git; manual drift is reverted automatically | GKE |
| Module 10 | Fleet Management & Multi-Cluster Operations | [Fleet Registration & Staged Rollout](lab-16-fleet.md) | One commit rolls out across a fleet; drift on one cluster is corrected | kind ×3 |
| Module 11 | Multi-Tenancy, Resource Quotas & Limits Across Clusters | [Multi-Tenant Quota with Kueue](lab-17-kueue.md) | A quota-blocked tenant borrows idle capacity via a cohort | GKE |

**End-of-day diagnostic scenario:** a Flux-delivered tenant change that fails to reconcile and then hits quota exhaustion across the two-cluster fleet. Combine Lab 15's drift/failure diagnosis with Lab 17's quota exhaustion.

---

Each lab ships with a matching **`.docx`** in this folder for handout use.
Screenshots and command transcripts live in [`../artifacts/`](../artifacts/), shared across the whole course.

Full index: [`../COURSE-MAP.md`](../COURSE-MAP.md)
