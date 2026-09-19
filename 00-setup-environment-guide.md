# Advanced Kubernetes — Environment Setup Guide

**Day 1: Multi-Cluster & Service Mesh · Day 2: Security & Scaling/Optimization · Day 3: AI/ML & Observability**

This guide gets your laptop ready for all sixteen labs across all three days. Work through it **before** the training session — several labs provision real cloud infrastructure, and getting stuck on tool installation during class eats into hands-on time.

> **All sixteen labs, across all three days, are now fully live-tested** — every line in this guide has been run for real. The one thing that could not be completed for real anywhere in this course is [Lab 13](lab-13-gpu-tpu-inference-gke.md)'s GPU-attached hardware check specifically, which this training project's own GCP account is blocked from (a real, confirmed `GPUS_ALL_REGIONS: 0` quota) — see that lab's own status note, and [Lab 11](lab-11-cluster-autoscaler-gpu-nodepools.md) for the equivalent check completed for real on AWS.

Every command in this guide, and in every lab document in this folder, was executed end-to-end on a real machine (macOS, Apple Silicon) against real clusters — local (kind/Docker) for the fully-local labs, and live GKE + EKS clusters for the cloud-dependent ones. Verified output is captured in [`evidence/`](evidence/) alongside each lab. If a command in a lab doesn't match what you see, check this guide first — version drift in fast-moving CLIs (`gcloud`, `eksctl`, `istioctl`, `kyverno`) is the most common cause.

---

## 1. Hardware and OS

| Requirement | Minimum | Recommended |
|---|---|---|
| OS | macOS 13+, or Linux (Ubuntu 22.04+) | macOS on Apple Silicon or Linux |
| CPU | 4 cores | 8+ cores |
| RAM | 8 GB free for Docker | 16 GB free for Docker |
| Disk | 20 GB free | 40 GB free |

Day 1's Labs 2-6 now run entirely on real GKE, not local `kind` — nothing in Day 1 stresses local Docker resources. Several Day 2 and Day 3 labs (7, 9, 10, 12, 14, 15, 16) do run local `kind` clusters, some of them multiple at once. Docker Desktop's default resource allocation is often too small for those — go to **Docker Desktop → Settings → Resources** and confirm at least 8 GB RAM / 4 CPUs is allocated before Day 2. This guide's tooling was validated with Docker Desktop given 12 CPUs / 8 GB RAM.

> Windows users: run everything inside **WSL2** (Ubuntu). Native Windows shells are not covered by these labs.

---

## 2. Cloud accounts you need

Day 1 (Labs 1-6) runs entirely on real GKE — Lab 1 creates its own two clusters, and Labs 2-6 share a separate two-cluster platform. Day 2's Lab 11 additionally needs a real AWS account. Before Day 1, make sure you (or your organization) have:

1. **A Google Cloud project** with billing enabled and permission to enable APIs and create GKE clusters (`roles/owner` or `roles/container.admin` + `roles/gkehub.admin` + `roles/serviceusage.serviceUsageAdmin`).
2. **An AWS account** (needed starting Day 2, for Lab 11) with permission to create VPCs, EKS clusters, and IAM roles (`AdministratorAccess`, or an equivalent scoped policy, is simplest for a training sandbox).

Use a **disposable sandbox project/account** for these labs if at all possible — Labs 2-6 create four real GKE clusters in total across the day (two for Lab 1, two for Labs 2-6's shared platform), and Lab 11 creates a real EKS cluster. Each lab document ends with a teardown section; running it promptly keeps cost to a few dollars per person.

Costs observed during testing (small clusters, torn down promptly after each lab/exercise): **under $10 total across the whole course.** Your cost will scale with how long you leave clusters running, so don't skip the teardown steps.

---

## 3. Install the CLI tools

All tools below were installed via [Homebrew](https://brew.sh) on macOS — that's the path actually tested for this guide. Linux users, use the equivalent block further down; it follows each project's own documented Linux install method but wasn't independently re-tested on a Linux box during this pass, so treat it as reliable-but-unverified relative to everything else in this guide.

### macOS (Homebrew) — tested

```bash
# Core Kubernetes tooling
brew install kubectl kind helm

# Cloud provider CLIs
brew install --cask google-cloud-sdk    # gcloud
brew install awscli                     # aws

# Service mesh
brew install istioctl

# AWS Kubernetes auth helper (Lab 11 only)
brew install eksctl

# GKE kubectl auth plugin and beta commands (via gcloud, not brew)
gcloud components install gke-gcloud-auth-plugin
gcloud components install beta

# Day 2: image scanning and policy-as-code CLIs
brew install trivy kyverno

# Day 3: Kubeflow Pipelines SDK (Lab 12) -- via pip, not brew
# kfp==2.7.0 requires Python <3.13 -- if your default python3 is newer (Homebrew's
# current Python, for instance), point this at an older interpreter instead, e.g.
# macOS's bundled /usr/bin/python3 via a dedicated venv:
#   /usr/bin/python3 -m venv ~/.venv-kfp && ~/.venv-kfp/bin/pip install kfp==2.7.0
python3 -m pip install kfp==2.7.0

# Optional but recommended: terminal cluster browser
brew install derailed/k9s/k9s
```

> `gcloud components install beta` is needed for [Lab 8](lab-08-gke-workload-identity-binary-authorization.md) (`gcloud beta container binauthz attestations sign-and-create` isn't in the stable command tree).

> Day 3's other tools — the Training Operator, Kubeflow Pipelines backend, OpenTelemetry Operator, Jaeger, and Chaos Mesh — install *into* their target cluster via `kubectl apply -k` / `helm install` inside each lab itself, rather than as a local CLI here. `helm` (already in the core list above) is the only shared local prerequisite they need beyond `kubectl`.

> If you already have `gcloud` installed some other way (not via the cask), just run the `gcloud components install gke-gcloud-auth-plugin` line — that's the piece people most often miss, and `kubectl` will fail against GKE with an opaque auth error without it.

### Linux (Ubuntu/Debian, x86_64) — official install methods, not independently re-tested

Each tool's own upstream-documented method, since there's no single package manager that covers all of these on Linux the way Homebrew does on macOS. Swap `linux_amd64`/`amd64` for `arm64` throughout if you're on an ARM machine (e.g. an AWS Graviton dev box).

```bash
# Core Kubernetes tooling
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl

curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64
chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh && ./get_helm.sh && rm get_helm.sh

# gcloud (adds Google's apt repo)
sudo apt-get install -y apt-transport-https ca-certificates gnupg curl
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
  | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
sudo apt-get update && sudo apt-get install -y google-cloud-cli

# aws
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install && rm -rf awscliv2.zip aws/

# istioctl
curl -L https://istio.io/downloadIstio | sh -
sudo mv istio-*/bin/istioctl /usr/local/bin/ && rm -rf istio-*/

# eksctl
curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz"
tar -xzf eksctl_Linux_amd64.tar.gz -C /tmp && rm eksctl_Linux_amd64.tar.gz
sudo mv /tmp/eksctl /usr/local/bin

# GKE kubectl auth plugin and beta commands (via gcloud, identical to macOS)
gcloud components install gke-gcloud-auth-plugin
gcloud components install beta

# Day 2: image scanning and policy-as-code CLIs
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sudo sh -s -- -b /usr/local/bin
# kyverno CLI: grab the current linux_x86_64 tarball listed at
# https://github.com/kyverno/kyverno/releases/latest — the exact filename changes per release,
# so there's no stable "latest" URL to curl directly the way the tools above have.

# Day 3: Kubeflow Pipelines SDK (Lab 12) -- identical to macOS, via pip
# Same Python <3.13 requirement noted above applies here too.
python3 -m pip install kfp==2.7.0

# Optional but recommended: terminal cluster browser
curl -sS https://webinstall.dev/k9s | bash
```

> **Unlike on macOS, `gke-gcloud-auth-plugin` landing off `PATH` generally isn't an issue on Linux** — the apt-installed `google-cloud-cli` package puts everything, including component binaries, under `/usr/lib/google-cloud-sdk/bin` with a symlink already on `PATH`. If you installed `gcloud` a different way (e.g. the standalone tarball) and hit `executable ... not found`, apply the same fix as the macOS gotcha further down: symlink the plugin from `$(gcloud info --format='value(installation.sdk_root)')/bin/` into a directory that's actually on your `PATH`.

> **Docker on Linux:** these labs just need a working Docker daemon reachable via the normal `docker` CLI and socket — Docker Desktop for Linux exists, but the far more common setup is [Docker Engine](https://docs.docker.com/engine/install/ubuntu/) directly (`sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin`, then add your user to the `docker` group: `sudo usermod -aG docker $USER` and re-log-in). Either way, the `docker info` check in §3's Docker section and the smoke test in §5 are what actually matter — if those pass, it doesn't matter which Docker distribution you used to get there.

### KubeFed CLI (referenced in Lab 3, legacy/reference only)

`kubefedctl` is **not** in Homebrew — the project was archived by Kubernetes SIG Multicluster in April 2023 and no longer ships current builds. Lab 3 explains why this matters and treats KubeFed as a boxed aside rather than the mechanism it actually uses, but if you want the CLI on your machine anyway:

**macOS:**

```bash
mkdir -p /tmp/kubefed-install && cd /tmp/kubefed-install
curl -sL -o kubefedctl.tgz \
  https://github.com/kubernetes-retired/kubefed/releases/download/v0.9.2/kubefedctl-0.9.2-darwin-amd64.tgz
tar xzf kubefedctl.tgz
sudo mv kubefedctl /usr/local/bin/kubefedctl   # or /opt/homebrew/bin on Apple Silicon
```

Only an `amd64` build exists (last released 2021). On Apple Silicon this runs under Rosetta 2 — install Rosetta first if you haven't: `softwareupdate --install-rosetta --agree-to-license`.

**Linux:** same idea, `linux-amd64` build — no Rosetta step needed:

```bash
mkdir -p /tmp/kubefed-install && cd /tmp/kubefed-install
curl -sL -o kubefedctl.tgz \
  https://github.com/kubernetes-retired/kubefed/releases/download/v0.9.2/kubefedctl-0.9.2-linux-amd64.tgz
tar xzf kubefedctl.tgz
sudo mv kubefedctl /usr/local/bin/kubefedctl
```

### Docker Desktop

Install from [docker.com](https://www.docker.com/products/docker-desktop/) if you don't have it. **Start it and confirm the daemon is running** before Day 1:

```bash
docker info >/dev/null 2>&1 && echo "Docker daemon: OK" || echo "Docker daemon: NOT RUNNING — start Docker Desktop"
```

---

## 4. Authenticate each CLI

Run these once per machine. Each opens a browser window for you to sign in.

```bash
# Google Cloud
gcloud auth login
gcloud config set project YOUR_GCP_PROJECT_ID
gcloud auth application-default login    # needed by some Terraform/SDK-based tools

# AWS
aws configure
#   -> enter your Access Key ID, Secret Access Key, default region (e.g. us-west-2), output format (json)
# Prefer an IAM user with programmatic access over root account keys, even in a sandbox account.
```

---

## 5. Verify everything before Day 1

Run this checklist top to bottom. Every line should print a version or a successful identity check — no errors.

```bash
echo "--- local tooling ---"
kubectl version --client
kind version
helm version
istioctl version --remote=false
docker info >/dev/null 2>&1 && echo "docker daemon: OK"

echo "--- cloud CLIs, authenticated ---"
gcloud config list
gcloud auth list
aws sts get-caller-identity

echo "--- cloud-specific k8s tooling ---"
which gke-gcloud-auth-plugin
eksctl version
```

Reference output (captured during testing of this guide — your versions may be newer, that's fine):

```
kubectl:    v1.36.1
kind:       v0.33.0
helm:       v4.2.4
istioctl:   1.31.0
eksctl:     0.230.0
gcloud:     Google Cloud SDK 574.0.0
aws-cli:    2.35.11
docker:     29.7.2
```

### Smoke test: local Kubernetes works end-to-end

This is the single fastest way to catch a broken Docker/kind setup before Day 1:

```bash
kind create cluster --name smoke-test
kubectl get nodes
kind delete cluster --name smoke-test
```

You should see one `Ready` node, then a clean deletion. If this fails, fix it before Day 1 — every local lab (1, 4, 5) depends on `kind` + Docker working.

---

## 6. What each lab needs

| Lab | Runs against | Real cost | Local resources |
|---|---|---|---|
| **Day 1** | | | |
| 1 — GKE cluster architecture (Autopilot vs Standard) | Real GKE | Yes — see lab doc | Minimal (CLI only) |
| 2 — Standing up the fleet | Real GKE (two clusters) | Yes — see lab doc | Minimal (CLI only) |
| 3 — Federating a real workload | Same two clusters as Lab 2 | Included in Lab 2 | Minimal (CLI only) |
| 4 — Installing the mesh | Same two clusters | Included in Lab 2 | Minimal (CLI + `istioctl`) |
| 5 — Securing and shaping traffic | Same two clusters | Included in Lab 2 | Minimal (CLI only) |
| 6 — Validating the platform | Same two clusters, torn down here | Included in Lab 2 | Minimal (`fortio` for load testing) |
| **Day 2** | | | |
| 7 — Image scanning + admission control | Local (`kind` + Docker) | $0 | ~2 GB RAM |
| 8 — Workload Identity Federation + Binary Authorization | Real GKE | Yes — see lab doc | Minimal (CLI + Docker for one image push) |
| 9 — Falco runtime security | Local (`kind` + Docker) | $0 | ~2 GB RAM |
| 10 — Advanced HPA/VPA autoscaling | Local (`kind` + Docker) | $0 | ~2 GB RAM |
| 11 — Cluster Autoscaler / Node Auto-Provisioning + GPU | Real GKE (CA/NAP mechanics) + real AWS EKS (GPU-specific proof) | Yes — see lab doc, and this is the priciest single lab (a real `g4dn.xlarge`) | Minimal (CLI only) |
| **Day 3** | | | |
| 12 — Kubeflow pipeline for distributed training | Local (`kind` + Docker) | $0 | ~4-6 GB RAM (full KFP backend + 3-Pod PyTorchJob) |
| 13 — GPU/TPU inference service on GKE | Real GKE (GPU node pool) | Yes — see lab doc | Minimal (CLI only) |
| 14 — Simple ML inference pipeline | Local (`kind` + Docker) | $0 | ~1 GB RAM, 3 small containers |
| 15 — OpenTelemetry observability | Local (`kind` + Docker) | $0 | ~2 GB RAM (cert-manager + OTel Operator + Jaeger) |
| 16 — Chaos engineering with Chaos Mesh | Local (`kind` + Docker) | $0 | ~2 GB RAM |

Lab 1 stands alone (its own two clusters, created and torn down within the lab). Labs 2 through 6 are one continuous platform build — the same two clusters, provisioned in Lab 2, are used and built on through Lab 6, torn down only at the end. Read all five lab documents before starting Lab 2 so you don't tear anything down early. Day 3's labs are each independent (no shared clusters), and only Lab 13 needs a cloud account.

---

## 7. Known rough edges (found during testing)

These aren't hypothetical — each one was hit while validating these labs and is called out again in context in the relevant lab document:

**Day 1**

- **`gcloud container clusters create/update --master-authorized-networks` fails outright unless you also pass `--enable-master-authorized-networks`** — several older docs and blog posts show only the CIDR-list flag on its own, which current `gcloud` rejects with `Cannot use --master-authorized-networks if --enable-master-authorized-networks is not specified`. Lab 1 hits this on both `create` and `update`.
- **A plain `curl ifconfig.me` can silently hand back an IPv6 address on a dual-stack network**, which then silently breaks `--master-authorized-networks` (it expects an IPv4 CIDR). Use `curl -4 -s ifconfig.me` explicitly. Lab 1 has the fix.
- **A GKE internal load balancer is regional by default — clients in a different region than the load balancer are silently blocked (connection timeout, not a clear error) unless you enable Global Access** (`networking.gke.io/internal-load-balancer-allow-global-access: "true"` on the Service). A genuinely cross-region multi-cluster platform hits this immediately. Lab 3 has the full detail.
- **GKE's auto-generated per-cluster firewall rules only permit traffic sourced from that same cluster's own Pod/Service CIDR** — cross-cluster Pod-to-Pod traffic (e.g. one cluster's Pod calling another cluster's internal load balancer) has no matching rule by default and needs an explicit firewall rule allowing both clusters' Pod ranges. Lab 3 has the exact commands.
- **`python:3.11-slim` (and most `-slim` base images) don't include `curl`.** Use `python3 -c "import urllib.request; ..."` for a quick in-container HTTP check instead of assuming `curl` is there.
- **`gcloud container fleet memberships register --enable-workload-identity` doesn't itself enable Workload Identity on the cluster** — that flag only tells registration to require and check for it; registering before enabling it fails with `FAILED_PRECONDITION: Workload Identity is not enabled`. Enable it directly first (`gcloud container clusters update ... --workload-pool=PROJECT_ID.svc.id.goog`), and budget real time for it — reconciling this change on an already-running cluster took 10-20+ minutes per cluster during testing, slower than creating the clusters themselves. Lab 2 has the full detail.
- **KubeFed does not currently install successfully** on any Kubernetes version we tested (both current-generation and the older version it originally targeted). Lab 3 documents the exact failure and why, and uses plain Kubernetes/GCP mechanisms plus Istio's own multi-cluster service discovery for the hands-on cross-cluster workload instead.
- **Istio fault-injection aborts are not retried**, even with a `retries` policy on the same route. If you want to demo retries working, do it against a real upstream failure (Lab 5 uses a pod deletion mid-traffic), not `fault.abort`.
- **`gke-gcloud-auth-plugin` can report "installed" via `gcloud components list` and still fail with `executable ... not found`.** On a Homebrew-cask install of `gcloud` on macOS, the plugin binary lands in `google-cloud-sdk/bin/`, which isn't itself on `PATH` — only the SDK root is. Symlink it: `ln -sf "$(gcloud info --format='value(installation.sdk_root)')/bin/gke-gcloud-auth-plugin" /opt/homebrew/bin/`.
- **Don't assume Connect Gateway access is scoped by per-user Kubernetes RBAC the way `generate-gateway-rbac`'s existence implies.** Tested directly with a real, narrowly-scoped service account (only `roles/gkehub.gatewayReader`, no Kubernetes RoleBinding anywhere): it got full cluster-admin-equivalent read **and write** access anyway. Verify this on your own cluster and account before relying on it as a security boundary — don't take the documented model on faith. Lab 2 has the full investigation.

**Day 2**

- **Kyverno's `kyverno.io/v1 ClusterPolicy` is deprecated as of 1.19 and gets removed in 1.20** — most tutorials you'll find online still use it. Lab 7 uses the current `policies.kyverno.io/v1 ValidatingPolicy` (CEL-based) type throughout.
- **An admission policy passing doesn't mean the workload will run.** `runAsNonRoot: true` against the stock `nginx` image gets admitted and then crashes (`mkdir() "/var/cache/nginx/client_temp" failed: Permission denied`) because the image itself was never built to run unprivileged. Lab 7 walks through the failure and the actual fix (a different base image).
- **VPA's `updateMode: Auto` is deprecated** in favor of explicit modes (`Recreate`, `Initial`, `InPlaceOrRecreate`). Use `InPlaceOrRecreate` — it resizes running pods live via Kubernetes' in-place resize feature, with zero restarts, which `Auto` never did. Lab 10 has the full before/after.
- **Binary Authorization requires images referenced by digest, never by tag** — `nginx:1.27-alpine` is rejected outright with `Expected digest with sha256 scheme, but got tag or malformed digest`, before it even checks for an attestation. Lab 8 shows the fix.
- **Pushing images from Apple Silicon to a registry a GKE amd64 node pool will pull from needs an explicit architecture check.** A plain `docker push` sends arm64 by default and the Pod crashes with `exec format error`; `docker pull --platform linux/amd64` doesn't reliably fix it once the tag is already cached locally. Lab 8 shows the `docker buildx imagetools` workaround.
- **GPU quota is very often 0 by default on a fresh GCP project**, even when individual GPU-type regional quota buckets show a nonzero limit — the project-wide `GPUS_ALL_REGIONS` bucket is the actual binding constraint, and it doesn't show up unless you specifically check it. Lab 11 shows how to check, and what NAP's own error output looks like when it hits this wall.
- **Cluster Autoscaler's IAM policy needs to go on the node group that's actually running the Autoscaler pod, not the node group you're trying to scale.** If you're scaling a group up from zero nodes, that's almost never the target group itself. Lab 11 has the exact `AccessDenied` error this produces when it's wrong.
- **Cluster Autoscaler's `latest`/default chart image isn't automatically compatible with your cluster's Kubernetes version.** We hit a permanent retry loop watching Dynamic Resource Allocation API types that didn't exist on the target EKS version, which silently prevented any real scaling decision from ever being evaluated. Pin `image.tag` to a Cluster Autoscaler release matching your cluster's Kubernetes **minor** version. Lab 11 has the detail.

**Day 3**

- **`kfp==2.7.0` requires Python `<3.13`** — on a machine whose default `python3` is newer, `pip install kfp==2.7.0` fails outright rather than silently installing an incompatible version. Use an older interpreter in a dedicated virtualenv (macOS's bundled `/usr/bin/python3` works). Lab 12 has the detail.
- **The canonical `kubeflow/pytorch-dist-mnist-test:latest` example image referenced in most Kubeflow tutorials doesn't exist**, and its corrected replacement (`kubeflow/pytorch-dist-mnist:latest`) is a 30GB multi-platform image that can fail to load into a local `kind` cluster on Apple Silicon (`ctr: content digest ... not found`) even after a successful `docker pull`. Lab 12 uses a lightweight custom script instead and shows why.
- **A Helm release's Deployment isn't always named after the release alone** — `helm install otel-operator ...` creates a Deployment named `otel-operator-opentelemetry-operator` (`<release>-<chart>`), not `otel-operator`. The Operator's own generated Collector resources follow the same `<name>-collector` pattern. Always check `kubectl get deployment` rather than assuming. Lab 15 hits this exact naming gotcha twice.
- **The official Kubeflow Pipelines standalone backend (the full multi-component KFP UI/API/MySQL/MinIO install) currently fails to install cleanly**, independent of this project: two of its own pinned container images (`gcr.io/ml-pipeline/minio:...`, `gcr.io/ml-pipeline/frontend:2.2.0`) no longer resolve on `gcr.io` — a known, already-filed upstream bug (kubeflow/pipelines#12638, #10994) — and a third component crashes under Apple Silicon/arm64 emulation. Lab 12 documents this as an honest dead end with full evidence, the same way Lab 3 treats KubeFed.
- **A `NetworkChaos` (or any) injected delay can silently take a Service to zero healthy endpoints, not just "slow it down"** — if a `readinessProbe`'s `timeoutSeconds` (default `1`) is shorter than the injected delay and `mode: all` affects every replica at once, every Pod fails readiness simultaneously and any client gets `connection refused`. Lab 16 has the full real event trail and the fix (`timeoutSeconds: 5`).
- **`GCE_STOCKOUT` can mean more than "your quota is 0."** This project's GPU node pool creation (Lab 11/13) failed with a 35-minute `GCE_STOCKOUT`-shaped timeout that traced back to a real `GPUS_ALL_REGIONS: 0` quota — but retrying with an entirely GPU-free cluster in a different zone hit the identical failure signature despite plentiful regional CPU quota (confirmed: `CPUS` limit 200, usage 0). Don't assume checking your own quota is sufficient diagnosis for this error class — sometimes it really is provider-side capacity, unrelated to anything in your account. Lab 13 has the full comparison.
- **NVIDIA Triton's default `model-control-mode` only loads models present at startup** — adding files to `/models` afterward via `kubectl exec` does nothing until you enable `--model-control-mode=explicit`, which adds a runtime `/v2/repository/models/<name>/load` endpoint. Lab 13 hits this.
- **`kubectl exec ... <<'EOF'` silently drops your heredoc unless you pass `-i`.** Without `--stdin`, the exec'd command's stdin is empty — `cat > file <<EOF ... EOF` "succeeds" and writes a 0-byte file, no error shown. Lab 13 caught this via a follow-up `cat` to confirm file contents, which is worth doing on principle any time a `kubectl exec` heredoc "worked."
- **A container image can be missing a directory its own default arguments expect to exist.** `tritonserver:24.08-py3`'s default `--model-repository=/models` path isn't actually present in the image — if nothing creates it before the server's first repository scan, the server latches into a permanently not-ready state that no later `mkdir` fixes. An `initContainer` + shared `emptyDir` ensuring the path exists at boot is the fix. Lab 13 has the full failure signature and the working manifest.

---

Once every command in §5 succeeds, you're ready for all three days. Start with [Lab 1](lab-01-gke-cluster-architecture.md) for Day 1, jump to [Lab 7](lab-07-image-scanning-admission-control.md) for Day 2, or [Lab 12](lab-12-kubeflow-distributed-training.md) for Day 3, if you're doing any of them on its own.
