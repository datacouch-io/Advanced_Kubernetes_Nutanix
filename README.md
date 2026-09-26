# Advanced Kubernetes (Nutanix)

A hands-on, 26-lab advanced Kubernetes course. Every lab is a **student guide** — it tells you where to go, when to open a terminal, what each command does, what output to expect, and what it means — and every result is backed by a **real command run against a real cluster** with **real screenshots**. Each lab also maps its ideas to the **Nutanix Kubernetes (NKE)** platform.

- **Start here for the full ordered index:** [COURSE-MAP.md](COURSE-MAP.md)
- **Word (.docx) copies:** beside each lab, inside its day folder
- **Renamed from an earlier scheme?** old → new mapping in [RENUMBERING-MAP.md](RENUMBERING-MAP.md)

---

## Who this is for

Engineers who already know Kubernetes basics (Pods, Deployments, Services, `kubectl`) and want to operate it under pressure: diagnosing failures, running stateful and AI/ML workloads, delivering with GitOps across a fleet, and securing and stress-testing the platform. The course builds from *how Kubernetes really works* up to a production war-room capstone.

## How each lab is structured

Every lab follows the same shape so you always know where you are:

1. **What you'll learn / What you'll do / Time & cost** — orientation up front.
2. **Before you start** — where you work, the tools you need, the cluster you use.
3. **The idea in 60 seconds** — a diagram and a plain-English mental model.
4. **Steps** — each step is *Goal → do this → what you should see → screenshot → what it means*.
5. **⚠️ Gotcha** and **Nutanix note** callouts — real pitfalls hit during testing, and how each idea maps to on-prem NKE.
6. **What you learned** — a table tying each takeaway to the proof you saw.
7. **Evidence** — links to the lab's real screenshots and command transcript.

## Course structure

**Restructured 2026-09-25 to the client's three-day outline.** Three scheduled days of 13 labs, an
optional additional day of 3, and 12 further labs held in reserve.

| Folder | Outline coverage | Labs |
|---|---|---|
| [`day-1-internals-and-networking/`](day-1-internals-and-networking/) | Modules 1–4 — internals & networking | 4 |
| [`day-2-stateful-storage-and-exposure/`](day-2-stateful-storage-and-exposure/) | Modules 5–8 — stateful, storage, exposure, logging | 4 |
| [`day-3-gitops-fleet-and-governance/`](day-3-gitops-fleet-and-governance/) | Modules 9–11 — GitOps, fleet, quotas | 5 |
| [`additional/optional-day-control-plane-and-war-room/`](additional/optional-day-control-plane-and-war-room/) | Modules 12–14 — optional fourth day | 3 |
| [`additional/further-labs/`](additional/further-labs/) | Not in this outline | 13 |

Each day folder holds its labs, their `.docx` handouts, and a README mapping **module → lab**.
Scope-per-lab tables for all 26 are in [COURSE-MAP.md](COURSE-MAP.md).

**Lab numbering is unchanged** (`lab-01` … `lab-26`), so the day folders read out of numeric order —
Day 1 is labs 01, 02, 04, 08. That is deliberate: keeping the IDs stable means evidence paths, `.docx`
filenames and [RENUMBERING-MAP.md](RENUMBERING-MAP.md) all still line up. The module mapping, not the
lab number, is the running order.

## Platforms & cost

Labs are **cloud-first on GKE** where a managed control plane matters, and **local `kind`** where a lab needs control-plane, CNI, multi-cluster, or bare-metal access (or where a cloud cluster would add cost without adding learning). Each lab's header states its platform, time, and cost.

- **`kind` labs cost $0** — they run in Docker on your machine.
- **GKE labs cost a few dollars each** if you tear down promptly; every lab ends with a clean-up step.
- The **Nutanix note** in each lab explains what changes (and what doesn't) on NKE — usually only the cluster provisioning and the load-balancer/StorageClass specifics; the Kubernetes mechanics are identical.

## Prerequisites & tooling

You'll need a machine with:

- **`docker`**, **`kind`**, **`kubectl`**, **`helm`** — used across most labs.
- **`gcloud`** authenticated to a GCP project with billing — for the GKE labs.
- Lab-specific CLIs, installed where the lab uses them: `istioctl`, `velero`, `flux`, `trivy`, `cilium`/`hubble`, `logcli`, `git`.

Each lab's **Before you start** section lists exactly what that lab needs, so you can install tools just-in-time.

## Building the Word documents

Every lab has a pre-built `.docx` in the day folders. To rebuild one from its Markdown (renders the Mermaid diagram via Kroki, then pandoc):

```bash
bash tools/lab2docx.sh lab-13-metallb.md "Lab 13 — Bare-Metal LoadBalancer with MetalLB"
```

Requires `pandoc`, `curl`, and `python3`; the styled template lives in `build/reference-styled.docx`.

## Repository layout

```
Advanced_Kubernetes_Nutanix/
├── README.md                     # this file
├── COURSE-MAP.md                 # authoritative index: all 26 labs, scope, platform
├── RENUMBERING-MAP.md            # old (A–G / 1–18) → new (01–26) mapping
├── lab-01-….md … lab-26-….md     # the 26 lab student guides
├── word/                         # a .docx per lab (built from the Markdown)
├── artifacts/
│   └── lab-NN/
│       ├── screenshots/          # real screen captures used in the lab
│       ├── diagrams/             # the rendered Mermaid diagram
│       └── evidence/             # command transcripts
├── tools/                        # lab2docx.sh and doc-build helpers
└── build/                        # reference-styled.docx + build scratch
```

## Notes

- **`LAB-CREATION-METHODOLOGY.md`** documents the house standard these labs are built to (real commands, real screenshots, honest gotchas, Nutanix mapping).
- **`00-setup-environment-guide.md`**, **`REUSED-FROM-REPO.md`**, and **`kubernetes_final_lab_list.md`** are historical/reference documents from earlier drafts and may use the older lab numbering; **COURSE-MAP.md** is the current source of truth.
