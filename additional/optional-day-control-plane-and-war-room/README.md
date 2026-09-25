# Optional Additional Day — Control-Plane Internals & Production War-Room

**Modules 12–14 of the client outline.**

| Module | Topic | Lab | What the lab proves | Platform |
|---|---|---|---|---|
| Module 12 | etcd — The Cluster's Source of Truth | [etcd Quota Alarm & Recovery](lab-03-etcd-quota-recovery.md) | Trip the etcd NOSPACE alarm, then compact/defrag/disarm back to writable | kind |
| Module 13 | Extending Kubernetes — CRDs & Operators | [Operators, Finalizers & Stuck Deletions](lab-06-operators-finalizers.md) | Free a resource stuck `Terminating` by fixing its finalizer | GKE |
| Module 14 | Capstone — Production War-Room | [Capstone: Production War-Room](lab-26-capstone.md) | Diagnose and heal six simultaneous fault domains; write the postmortem | GKE |

This day is **in the client outline** but priced and scheduled separately. It is self-contained: nothing in Days 1–3 depends on it.

---

Each lab ships with a matching **`.docx`** in this folder for handout use.
Screenshots and command transcripts live in [`../../artifacts/`](../../artifacts/), shared across the whole course.

Full index: [`../../COURSE-MAP.md`](../../COURSE-MAP.md)
