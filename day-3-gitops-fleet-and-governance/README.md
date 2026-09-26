# Day 3 — GitOps, Fleet Management & Multi-Cluster Governance

**Modules 9–11 of the client outline.**

Modules 10 and 11 are each delivered by **two** labs. For Module 10 run Lab 29 (Flux — what the outline specifies); Lab 16 is the Rancher Fleet alternative. Module 11 is delivered by **two** labs — run Lab 27 first (it builds the quota contract), then Lab 17 (the tenant borrows against it).

| Module | Topic | Lab | What the lab proves | Platform |
|---|---|---|---|---|
| Module 9 | GitOps with Flux CD | [GitOps Delivery with Flux](lab-15-flux.md) | Deliver from Git; manual drift is reverted automatically | GKE |
| Module 10 | Fleet Management & Multi-Cluster Operations | [Two Clusters as One Fleet (Flux)](lab-29-flux-fleet-two-clusters.md) | One repo, per-cluster overlays, canary→production rings gated by a merge, per-cluster drift correction | kind ×2 |
| Module 10 | *(alternative)* | [Fleet Registration & Staged Rollout](lab-16-fleet.md) | The same job with **Rancher Fleet** — run it for the tooling comparison | kind ×3 |
| Module 11 | Multi-Tenancy, Resource Quotas & Limits Across Clusters | [Tenant Quota Governance](lab-27-tenant-quota-governance.md) | Quota + LimitRange delivered by Flux; exhaustion diagnosed; per-cluster quota from a fleet budget | kind |
| Module 11 | *(continued)* | [Multi-Tenant Quota with Kueue](lab-17-kueue.md) | A quota-blocked tenant borrows idle capacity via a cohort | GKE |

**End-of-day diagnostic scenario:** a Flux-delivered tenant change that fails to reconcile and then hits quota exhaustion across the two-cluster fleet. Combine Lab 15's drift/failure diagnosis with Lab 17's quota exhaustion.

---

Each lab ships with a matching **`.docx`** in this folder for handout use.
Screenshots and command transcripts live in [`../artifacts/`](../artifacts/), shared across the whole course.

Full index: [`../COURSE-MAP.md`](../COURSE-MAP.md)
