# Day 2 — Stateful Workloads, Persistent Storage & Service Exposure

**Modules 5–8 of the client outline.**

| Module | Topic | Lab | What the lab proves | Platform |
|---|---|---|---|---|
| Module 5 | Stateful Workloads & Persistent Storage | [StatefulSets, PVCs & Volume Snapshots](lab-11-statefulsets-snapshots.md) | Survive a snapshot/restore cycle with data intact | GKE |
| Module 6 | Backup, Restore & Disaster Recovery with Velero | [Backup & Restore with Velero](lab-12-velero-backup-restore.md) | Delete a whole namespace and bring it back from object storage | GKE |
| Module 7 | Service Exposure on Bare Metal — MetalLB with Cilium | [Bare-Metal LoadBalancer (MetalLB)](lab-13-metallb.md) | Give a `LoadBalancer` Service a real IP on bare metal; survive node failure | kind |
| Module 8 | Logging & Observability with Loki | [Log-Based Diagnosis with Loki](lab-14-loki.md) | Pinpoint a failure's root cause with a LogQL query | GKE |

**War-room scenario (Module 6):** the backup reports `Completed` but the restored database will not start. Lab 12 ends with the restore verification that sets this up.

---

Each lab ships with a matching **`.docx`** in this folder for handout use.
Screenshots and command transcripts live in [`../artifacts/`](../artifacts/), shared across the whole course.

Full index: [`../COURSE-MAP.md`](../COURSE-MAP.md)
