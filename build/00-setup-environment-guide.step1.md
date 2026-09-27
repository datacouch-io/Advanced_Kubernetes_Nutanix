# Environment Setup Guide — Advanced Kubernetes (Nutanix)

**Day 1: How Kubernetes Really Works · Day 2: Stateful Workloads & Service Exposure · Day 3: GitOps, Fleet & Governance**

Work through this **before** the session. Several labs provision real cloud infrastructure, and losing the first hour of Day 1 to tool installation costs hands-on time you don't get back.

The authoritative index of what runs when is [`COURSE-MAP.md`](COURSE-MAP.md). Each lab also states its own prerequisites in its **Before you start** section; where this guide and a lab disagree, the lab wins.

---

## 1. What you are setting up for

The scheduled course is **three days, 13 core labs**:

| Day | Folder | Labs | Platform |
|---|---|---|---|
| Day 1 — Internals & Networking | [`day-1-internals-and-networking/`](day-1-internals-and-networking/) | 1, 2, 4, 8 | 3 × kind, 1 × GKE |
| Day 2 — Stateful Storage & Exposure | [`day-2-stateful-storage-and-exposure/`](day-2-stateful-storage-and-exposure/) | 11, 12, 13, 14 | GKE + kind (Lab 11 uses both) |
| Day 3 — GitOps, Fleet & Governance | [`day-3-gitops-fleet-and-governance/`](day-3-gitops-fleet-and-governance/) | 15, 16, 17, 27, 29 | 3 × GKE, 2 × kind |

Two further collections exist and are **not** part of the three scheduled days:

- [`additional/optional-day-control-plane-and-war-room/`](additional/optional-day-control-plane-and-war-room/) — Labs 3, 6 and the Lab 26 capstone. Run these if the client adds an optional fourth day.
- [`additional/further-labs/`](additional/further-labs/) — 14 labs outside the current outline, kept for reuse.

**If you only have time to prepare for one thing, prepare Docker and `kind`.** More than half the course runs locally and costs nothing.

---

## 2. Hardware and OS

| Requirement | Minimum | Recommended |
|---|---|---|
| OS | macOS 13+, or Linux (Ubuntu 22.04+) | macOS on Apple Silicon, or Linux |
| CPU allocated to Docker | 4 cores | 8+ cores |
| RAM allocated to Docker | 8 GB | 16 GB |
| Disk free | 30 GB | 50 GB |

The heaviest moment in the course is **Lab 16**, which creates **three `kind` clusters at once**; Lab 29 creates two. Open **Docker Desktop → Settings → Resources** and confirm the allocation before Day 3. This course's content was built and verified with Docker Desktop given **12 CPUs / 8 GB RAM**.

> **Windows users:** run everything inside **WSL2** (Ubuntu). Native PowerShell / CMD is not covered by these labs.

---

## 3. Cloud account

**Six labs need a real GKE cluster:** 4, 11 (Steps 1–4), 12, 14, 15, 17 — plus Lab 6 in the optional day.

You need:

- A Google Cloud project with **billing enabled** and the **Kubernetes Engine API** turned on.
- Permission to create and delete a GKE cluster (`roles/container.admin`) and to read/write GCS if you extend the Velero lab.
- This course's shared cluster is `advk8s-lab` in project `dcproject-462806`, zone `us-central1-a`. If your instructor has already created it, you only need credentials to reach it — skip cluster creation.

A 2-node `e2-standard-4` cluster is sufficient for every GKE lab in the three scheduled days.

> 💰 **Cost control — this is the one thing that bites.** A GKE cluster bills whether or not anyone is using it. Delete it at the end of each day unless the instructor says otherwise:
>
> ```bash
> gcloud container clusters delete advk8s-lab --zone us-central1-a --project <your-project>
> ```
>
> Everything that runs on `kind` is **$0**.

---

## 4. Install the CLI tools

### What each tool is for

| Tool | Needed by | Why |
|---|---|---|
| `docker` | every `kind` lab | runs the cluster nodes as containers |
| `kind` | Labs 1, 2, 8, 13, 16, 27, 29 (+ 3, 26) and Lab 11 Steps 5–7 | local multi-node clusters |
| `kubectl` | all | talks to every cluster |
| `curl` | Lab 2 | drives the API-server load generator |
| `jq` | several, optional | reading JSON output |
| `gcloud` + `gke-gcloud-auth-plugin` | Labs 4, 11, 12, 14, 15, 17 (+ 6) | create and authenticate to GKE |
| `helm` | Labs 14, 16 | installs Loki and Rancher Fleet |
| `cilium` CLI + `hubble` CLI | Lab 8 | install Cilium, observe flows |
| `velero` | Lab 12 | backup/restore CLI |
| `logcli` | Lab 14 | LogQL queries from the terminal |
| `flux` | Labs 15, 27, 29 | bootstrap and inspect GitOps reconciliation |

### macOS (Homebrew) — tested

```bash
brew install --cask docker
brew install kind kubectl helm jq
brew install cilium-cli hubble
brew install velero logcli
brew install fluxcd/tap/flux
brew install --cask google-cloud-sdk
gcloud components install gke-gcloud-auth-plugin
```

Start Docker Desktop once from Applications before continuing — the CLI cannot talk to the daemon until the app has run.

### Linux (Ubuntu/Debian, x86_64) — official install methods

```bash
# Docker Engine
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"   # log out and back in

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64
sudo install -o root -g root -m 0755 kind /usr/local/bin/kind

# helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# flux
curl -s https://fluxcd.io/install.sh | sudo bash

# cilium + hubble CLIs
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
curl -L --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz
sudo tar xzvfC cilium-linux-amd64.tar.gz /usr/local/bin

HUBBLE_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/hubble/master/stable.txt)
curl -L --remote-name-all https://github.com/cilium/hubble/releases/download/${HUBBLE_VERSION}/hubble-linux-amd64.tar.gz
sudo tar xzvfC hubble-linux-amd64.tar.gz /usr/local/bin

# velero — check the latest release tag first
VELERO_VERSION=v1.18.2
curl -L https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/velero-${VELERO_VERSION}-linux-amd64.tar.gz \
  | tar xz && sudo install velero-${VELERO_VERSION}-linux-amd64/velero /usr/local/bin/velero

# logcli
curl -L https://github.com/grafana/loki/releases/latest/download/logcli-linux-amd64.zip -o logcli.zip
unzip -o logcli.zip && sudo install logcli-linux-amd64 /usr/local/bin/logcli

# gcloud
curl https://sdk.cloud.google.com | bash && exec -l $SHELL
gcloud components install gke-gcloud-auth-plugin
```

---

## 5. Authenticate

```bash
gcloud auth login
gcloud config set project <your-project-id>
gcloud config set compute/zone us-central1-a

# fetch credentials for the shared cluster (skip if you will create your own)
gcloud container clusters get-credentials advk8s-lab --zone us-central1-a
kubectl config get-contexts
```

`gke-gcloud-auth-plugin` must be on your `PATH` — since Kubernetes 1.26, `kubectl` will not authenticate to GKE without it. If `kubectl` returns *"no Auth Provider found for name gcp"*, the plugin is missing.

---

## 6. Verify before Day 1

Run this and compare. Exact versions do not need to match; anything materially older is worth upgrading.

```bash
docker --version
kind --version
kubectl version --client
helm version --short
flux --version
velero version --client-only
cilium version --client
hubble version
gcloud version | head -1
```

Versions this course was verified against (2026-09-27, macOS/Apple Silicon):

| Tool | Version used |
|---|---|
| Docker | 29.7.2 |
| kind | 0.33.0 |
| kubectl | v1.36.1 (clusters created were v1.37.0) |
| Helm | v4.2.4 |
| Flux | 2.9.5 |
| Velero | v1.18.2 |
| cilium-cli | v0.20.0 |
| hubble | 1.19.4 |
| gcloud SDK | 574.0.0 |
| jq | 1.7.1 |

### Smoke test: prove local Kubernetes works end-to-end

```bash
kind create cluster --name smoke
kubectl get nodes
kubectl create deployment web --image=nginx:1.27-alpine
kubectl rollout status deployment/web --timeout=120s
kubectl delete deployment web
kind delete cluster --name smoke
```

If `kind create cluster` hangs or the node never becomes `Ready`, the cause is almost always Docker resources — raise them and retry before the session.

### Smoke test: prove GKE access works

```bash
kubectl config use-context gke_<project>_us-central1-a_advk8s-lab
kubectl get nodes
kubectl auth can-i create deployments
```

---

## 7. What each lab needs

### Day 1 — Internals & Networking

| Lab | Platform | Tools beyond `kubectl` | Notes |
|---|---|---|---|
| [1 — Reconciliation Tracing](day-1-internals-and-networking/lab-01-reconciliation-tracing.md) | kind | `docker`, `kind` | creates `advk8s-day1`; **Step 3 needs two terminals side by side** |
| [2 — API Priority & Fairness](day-1-internals-and-networking/lab-02-api-priority-fairness.md) | kind | `curl` | **reuses Lab 1's cluster** — run Lab 1 first |
| [4 — Pending-Pod Diagnostics](day-1-internals-and-networking/lab-04-pending-pod-diagnostics.md) | GKE | `gcloud`, auth plugin | Step 6 adds KWOK simulated nodes |
| [8 — Cilium & Hubble](day-1-internals-and-networking/lab-08-cilium-hubble.md) | kind | `cilium`, `hubble` CLIs | its own cluster with the default CNI disabled |

### Day 2 — Stateful Storage & Exposure

| Lab | Platform | Tools beyond `kubectl` | Notes |
|---|---|---|---|
| [11 — StatefulSets & Snapshots](day-2-stateful-storage-and-exposure/lab-11-statefulsets-snapshots.md) | **both** | `gcloud` (Steps 1–4), `docker`+`kind` (Steps 5–7) | Steps 5–7 install the CSI hostpath driver on a fresh 3-node kind cluster |
| [12 — Velero Backup & Restore](day-2-stateful-storage-and-exposure/lab-12-velero-backup-restore.md) | GKE | `velero` | see the object-store note in §8 |
| [13 — MetalLB](day-2-stateful-storage-and-exposure/lab-13-metallb.md) | kind | `docker`, `kind` | reuses Lab 1's multi-node cluster; Step 4 builds a second cluster for the Cilium comparison |
| [14 — Loki](day-2-stateful-storage-and-exposure/lab-14-loki.md) | GKE | `helm`, `logcli` | |

### Day 3 — GitOps, Fleet & Governance

| Lab | Platform | Tools beyond `kubectl` | Notes |
|---|---|---|---|
| [15 — Flux](day-3-gitops-fleet-and-governance/lab-15-flux.md) | GKE | `flux` | |
| [16 — Rancher Fleet](day-3-gitops-fleet-and-governance/lab-16-fleet.md) | kind | `helm`, `kind` | **creates three kind clusters** — the heaviest lab in the course |
| [17 — Kueue](day-3-gitops-fleet-and-governance/lab-17-kueue.md) | GKE | `gcloud` | run **after** Lab 27 |
| [27 — Tenant Quota Governance](day-3-gitops-fleet-and-governance/lab-27-tenant-quota-governance.md) | kind | `flux` | runs Gitea in-cluster as the Git source; no external Git account needed |
| [29 — Flux Fleet, Two Clusters](day-3-gitops-fleet-and-governance/lab-29-flux-fleet-two-clusters.md) | kind | `flux` | creates two kind clusters |

> **Module 10 and Module 11 each have two labs.** For Module 10, run **Lab 29** (Flux — what the outline specifies); Lab 16 is the Rancher Fleet alternative. For Module 11, run **Lab 27 first** (it builds the quota contract), then **Lab 17** (the tenant borrows against it).

### Optional fourth day

| Lab | Platform | Tools |
|---|---|---|
| [3 — etcd Quota & Recovery](additional/optional-day-control-plane-and-war-room/lab-03-etcd-quota-recovery.md) | kind | `docker`, `kind` (`etcdctl` is used inside the container) |
| [6 — Operators & Finalizers](additional/optional-day-control-plane-and-war-room/lab-06-operators-finalizers.md) | GKE | `gcloud` |
| [26 — Capstone War-Room](additional/optional-day-control-plane-and-war-room/lab-26-capstone.md) | kind | `docker`, `kind`; the instructor runs `artifacts/lab-26/seed-warroom.sh` |

---

## 8. Known rough edges

These are real failures hit while building this course. Check them before you teach.

> 🚨 **MinIO's public container images have been withdrawn.** Verified again 2026-09-27: `minio/minio` returns *"pull access denied"*, and both `quay.io/minio/minio` and `quay.io/minio/mc` return **401 Unauthorized** — server and client, on both registries. **Lab 12 has been rewritten around SeaweedFS** (`chrislusf/seaweedfs`), which is verified working as a Velero target; `zenko/cloudserver` and `adobe/s3mock` also pull. If you follow any older copy of the lab that still installs MinIO, it will stop at Step 1.

> ⚠️ **`bitnami/kubectl` no longer pulls either.** Anywhere a lab needs a `kubectl`-in-a-Pod load generator it now uses `curlimages/curl` with a ServiceAccount token instead.

> ⚠️ **Test your image pulls the day before the session.** The two failures above cost the most time, and both are one-line checks:
> ```bash
> docker pull chrislusf/seaweedfs:3.80 && docker pull curlimages/curl:8.11.1 && echo "pulls OK"
> ```

> ⚠️ **kind's default StorageClass cannot do volume expansion, and defeats Velero file-system backup.** `rancher.io/local-path` has no `allowVolumeExpansion` field and provisions **hostPath** PVs, which Velero refuses to back up — the backup still reports `Completed`. Labs 11 and 12 both install the CSI hostpath driver for the parts that need a real CSI volume; don't substitute the default class.

> ⚠️ **`gke-gcloud-auth-plugin` is mandatory.** Without it on `PATH`, `kubectl` cannot authenticate to GKE at all.

> ⚠️ **Delete GKE clusters when you finish.** They bill continuously. `gcloud container clusters list` at the end of every day is a good habit.

> ⚠️ **Delete `kind` clusters between labs that build their own.** Labs 8, 11 (Steps 5–7), 13 (Step 4), 16, 27 and 29 each create clusters. Running several sets at once will exhaust Docker's memory. `kind get clusters` then `kind delete cluster --name <name>`.

---

## 9. If something doesn't match

1. Check the lab's own **Before you start** — it is authoritative.
2. Check [`COURSE-MAP.md`](COURSE-MAP.md) for which labs belong to which day.
3. Check the lab's evidence transcript under `artifacts/<lab>/evidence/` — it shows the exact output from a real run, with the versions used recorded at the top.

Version drift in fast-moving CLIs (`gcloud`, `cilium`, `flux`, `velero`) is the most common reason output differs from a lab.
