# Reused Labs — Provenance & Adaptation Map

This directory's starting point is a set of labs **copied from the existing
`datacouch-io/Advanced_Kubernetes` repo** (the GKE/EKS/`kind` course) and renamed into this
course's final scheme (see [`kubernetes_final_lab_list.md`](kubernetes_final_lab_list.md)).

**Status of these files: copied source, not finished labs.** Every one was built and verified on its
*original* platform (real GKE, or local `kind`) — never on the **Nutanix Kubernetes platform** this
course targets. Each carries a `♻️ Reused source` banner at the top saying so. They are here to be
**adapted and re-tested**, which is the next phase of work, not to be shipped as-is.

## Mapping: repo file → this course

| New id | This file | From repo | Original platform | Adaptation weight |
|---|---|---|---|---|
| **Lab A** | `lab-A-cluster-architecture.md` | Lab 1 — GKE cluster architecture | real GKE | **HEAVY** — Autopilot/Standard/private/release-channel are GKE concepts; needs an NKE equivalent |
| **Lab B** | `lab-B-multicluster-service-mesh.md` | Lab 4 — Installing the mesh | real GKE ×2 | **MEDIUM** — Istio install/config is portable; fleet + cluster provisioning is GKE |
| **Lab C** | `lab-C-image-scanning-admission-control.md` | Lab 7 — Kyverno admission control | local `kind` | **LIGHT** — Kyverno is platform-agnostic |
| **Lab D** | `lab-D-workload-identity-binary-authorization.md` | Lab 8 — Workload Identity + Binary Auth | real GKE | **HEAVY** — both are GCP-native; needs SPIFFE/SPIRE + cosign/Kyverno or rescope |
| **Lab E** | `lab-E-falco-runtime-security.md` | Lab 9 — Falco runtime security | local `kind` | **LIGHT** — Falco is platform-agnostic |
| **Lab F** | `lab-F-hpa-vpa-autoscaling.md` | Lab 10 — Advanced HPA/VPA | local `kind` | **LIGHT** — HPA/VPA is platform-agnostic |
| **Lab 15B** | `lab-15b-distributed-training.md` | Lab 12 — Kubeflow distributed training | local `kind` | **MEDIUM** — Kubeflow portable; new lab adds Kueue admission/preemption; note the KFP dead-end in its §12.5 |
| **Lab 16** (src 1) | `lab-16-gpu-tpu-inference.md` | Lab 13 — GPU/TPU inference | real GKE | **HEAVY** — GKE GPU/TPU hardware; hit a real `GPUS_ALL_REGIONS=0` quota wall |
| **Lab 16** (src 2) | `lab-16-ml-inference-pipeline.md` | Lab 14 — Simple ML inference pipeline | local `kind` | **LIGHT** — portable; feeds the new Lab 16 autoscaling-signals design |
| **Lab G** | `lab-G-chaos-mesh.md` | Lab 16 — Chaos Mesh | local `kind` | **LIGHT** — Chaos Mesh is platform-agnostic |

**Lab 16 is two source files → one new lab.** The new Lab 16 ("Inference Autoscaling Signals") is to
be authored by adapting both `lab-16-gpu-tpu-inference.md` and `lab-16-ml-inference-pipeline.md`.

**Lab 13 (Fleet Registration & Staged Upgrades)** is marked *Reuse (validation methodology)* in the
lab list — it draws on repo Labs 2–6's fleet-build methodology, **not** a copied file. Those files
were **not** copied (per the agreed scope). If needed during the build, they are in the source repo
at `../Advanced_Kubernetes/lab-0{2,3,5,6}-*.md`.

## What was copied

- The 10 lab files above, **renamed** to the new scheme.
- Their screenshots, under `screenshots/` with dirs **renamed** to match (`lab-A`, `lab-B`, … ,
  `lab-16-gpu-tpu`, `lab-16-pipeline`). All 61 inline image references were rewired and verified to
  resolve.
- Their raw captured output in `evidence/` (10 files, for Labs B, C, D, E, F), **renamed** to match;
  all 15 inline evidence references rewired and verified.
- `00-setup-environment-guide.md` and `LAB-CREATION-METHODOLOGY.md`, **as-is reference** — the setup
  guide is GKE/`gcloud`-oriented and will need a Nutanix rewrite before it is the course's real
  setup guide.

## What was changed during the copy

1. **File and asset names** → the new course scheme.
2. **Screenshot and evidence paths** inside each file → the renamed dirs/files (verified: 0 broken).
3. **Cross-links between copied labs** → rewritten to the new filenames (e.g. Lab C's link to Lab 8
   now points at `lab-D-…`).
4. **Cross-links to labs that were NOT copied** (repo Labs 2, 3, 5, 6, 11, 15) → **converted to plain
   text** (16 occurrences) so nothing is a dangling link. These are places where the new course will
   eventually point at its own Lab 13 (fleet), Lab 7 (Cilium/Hubble), Lab 11 (Loki), etc. Re-link
   them during adaptation. Occurrences by file:
   - `lab-A-…` — repo Lab 2 (fleet), repo Lab 11 (autoscaler/GPU)
   - `lab-B-…` — repo Lab 3 (federation), repo Lab 5 (traffic shaping)
   - `lab-D-…` — repo Lab 11
   - `lab-F-…` — repo Lab 11
   - `lab-15b-…` — repo Lab 3
   - `lab-16-gpu-tpu-…` — repo Lab 11
   - `lab-16-ml-inference-…` — repo Lab 15 (OpenTelemetry → new course uses Loki, Lab 11)
   - `lab-G-…` — repo Lab 5

## What was NOT changed

The lab **bodies** are the GKE/`kind` originals, unedited apart from the path/link rewiring above.
Titles still say "Lab 1", "Lab 4", etc. and reference GKE/`gcloud`. **Adapting the content for
Nutanix — and re-testing it — is the next phase**, per the plan to copy first and build second.

## Adaptation priority (suggested)

- **Drop-in-ready-ish (LIGHT):** C, E, F, G, and the pipeline half of 16 — Kyverno/Falco/HPA-VPA/Chaos
  Mesh all run on any conformant cluster, so the main work is swapping the `kind` bootstrap for an NKE
  cluster and re-capturing screenshots.
- **Real rework (MEDIUM):** B, 15B — portable core, GKE-specific provisioning/fleet to replace.
- **Substantial / decision needed (HEAVY):** A, D, and the GPU half of 16 — these lean on GCP-native
  features (Autopilot, Workload Identity Federation, Binary Authorization, GKE GPU pools). Each needs
  either a genuine Nutanix equivalent or a rescope, and that is a design decision to make before
  building.
