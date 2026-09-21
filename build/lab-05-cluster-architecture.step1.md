# Lab 5 — Autopilot vs Standard, Private Clusters & Release Channels

**Day 1 · How Kubernetes Really Works**

> ✅ **Tested end-to-end** against two real GKE clusters. Every screenshot is a real capture — including a deliberate lockout-and-recovery of the control plane, and a privileged container that Standard runs happily but Autopilot rejects by name.

## What you'll learn

- The real difference between GKE's two modes — **Standard** (you manage node pools and machine shapes) and **Autopilot** (Google manages nodes; you only think in Pods) — and how to choose.
- What a **private cluster** actually restricts, and how **master authorized networks** gates who can reach the control plane — including how to lock *yourself* out and recover.
- **Release channels** as GKE's managed-upgrade mechanism.
- Concretely, what Autopilot's built-in Pod security blocks that Standard allows — as a real admission-time rejection you trigger yourself.

## What you'll do

You'll create a private Standard cluster on a release channel, deliberately lock yourself out of its API server and recover, then create an Autopilot cluster and prove — by deploying the *same* privileged Pod to both — that Autopilot's built-in guardrails reject what Standard permits. Finally you'll inspect a Standard node pool and tear both clusters down.

## Time & cost

- **Time:** ~60 minutes.
- **Cost:** real but small — two small GKE clusters up for under 20 minutes total, then deleted (a few dollars if you tear down promptly, per Step 6).

---

## Before you start

- **Where you'll work:** in a **terminal** on your own machine.
- **Tools you need:** `gcloud` authenticated against a real GCP project with billing enabled and the Kubernetes Engine API on; `kubectl` with the `gke-gcloud-auth-plugin`.
- **Note:** Lab 5 closes Day 1 (after the local Labs 1–4). It creates its own two clusters and deletes them at the end — independent of every other lab.

> **Nutanix note.** Autopilot is GKE-specific, so this lab is deliberately a GKE lab. The transferable ideas — private control-plane endpoints and authorized-network allow-lists, managed upgrade channels, and a hardened Pod-admission baseline — all have NKE equivalents (NKE cluster tiers, Prism-managed networking, and Pod Security Admission / Kyverno for the guardrails). Lab 10 covers the platform-agnostic way to enforce Autopilot-style Pod rules with Kyverno.

---

## The idea in 60 seconds

**Standard mode** is "a GKE cluster" in the classic sense: you choose machine types, node counts, and autoscaling for one or more **node pools**, and you're billed for those VMs. You can run privileged/host-networked Pods and treat the nodes as yours.

**Autopilot** inverts this: there are no node pools to configure. You submit Pod specs; GKE provisions and bills for exactly the compute they need, per-Pod. In exchange, Autopilot enforces a hardened Pod baseline by default via **GKE Warden** — no privileged containers, among other rules — because Google operates the nodes.

**Private clusters** are a networking property (both modes support them): nodes get no public IP, and the control plane's public endpoint is gated by **master authorized networks** — an allow-list of CIDRs. Get that list wrong and you lock yourself out (you'll do exactly that, on purpose, in Step 2). **Release channels** (`rapid`/`regular`/`stable`) opt you into a managed upgrade cadence instead of pinning versions yourself.

![Architecture diagram](artifacts/lab-05/diagrams/diagram.png)

---

## Step 1 — Create a private Standard cluster on a release channel

**Goal:** stand up a Standard cluster with private nodes, gated to your IP, on the `regular` release channel.

**1. Set your project and find your public IP** (use `-4` — on a dual-stack network a plain lookup can hand back an IPv6 address, which silently breaks `--master-authorized-networks`):

```bash
export PROJECT_ID=YOUR_GCP_PROJECT_ID
gcloud services enable container.googleapis.com --project=$PROJECT_ID

MY_IP=$(curl -4 -s ifconfig.me)
echo "Your current public IPv4: $MY_IP"
```

**2. Create the cluster:**

```bash
gcloud container clusters create advk8s-standard \
  --project=$PROJECT_ID \
  --zone=us-central1-a \
  --release-channel=regular \
  --enable-private-nodes \
  --enable-master-authorized-networks \
  --master-authorized-networks="${MY_IP}/32" \
  --enable-ip-alias \
  --num-nodes=2 \
  --machine-type=e2-medium \
  --disk-size=30
```

> ⚠️ **Gotcha — two flags, always together.** `--master-authorized-networks` is rejected outright (`Cannot use --master-authorized-networks if --enable-master-authorized-networks is not specified`) unless you *also* pass `--enable-master-authorized-networks`. Many older docs show only the CIDR flag; both are required, on `create` **and** on any later `update`.

**3. Connect and look at the nodes:**

```bash
gcloud container clusters get-credentials advk8s-standard --zone us-central1-a --project=$PROJECT_ID
kubectl config rename-context gke_${PROJECT_ID}_us-central1-a_advk8s-standard advk8s-standard
kubectl --context advk8s-standard get nodes -o wide
```

**What you should see:** two `Ready` nodes with **no `EXTERNAL-IP`** — confirming they're private.

![Two nodes, Ready, no EXTERNAL-IP — confirmed private](artifacts/lab-05/screenshots/01-standard-nodes.png)

**4. Confirm the config — release channel, private nodes, authorized network:**

```bash
gcloud container clusters describe advk8s-standard --zone us-central1-a --project=$PROJECT_ID \
  --format="yaml(releaseChannel, privateClusterConfig, masterAuthorizedNetworksConfig)"
```

**What you should see:** `releaseChannel: channel: REGULAR`, `privateClusterConfig: enablePrivateNodes: true`, and your IP in `masterAuthorizedNetworksConfig.cidrBlocks`.

![releaseChannel: REGULAR, enablePrivateNodes: true, authorized CIDR matches our IP](artifacts/lab-05/screenshots/02-cluster-config.png)

**What this means:** the nodes have no public IP, the control plane keeps a public endpoint gated to your IP only, and GKE will manage version upgrades on the `regular` cadence.

---

## Step 2 — Lock yourself out (on purpose) and recover

**Goal:** reproduce the most common private-cluster mistake — an authorized-networks list that excludes you — so you recognise it instantly.

**1. Change the allow-list to a CIDR that is *not* your IP, then try to use the cluster:**

```bash
gcloud container clusters update advk8s-standard \
  --zone us-central1-a --project=$PROJECT_ID \
  --enable-master-authorized-networks \
  --master-authorized-networks="203.0.113.0/32"

kubectl --context advk8s-standard --request-timeout=15s get nodes
```

**What you should see:** `Unable to connect to the server: context deadline exceeded`.

![Unable to connect to the server: context deadline exceeded](artifacts/lab-05/screenshots/03-lockout.png)

**What this means:** this is a **connection timeout, not an RBAC `Forbidden`** — the control plane's load balancer drops your connection before authentication even happens, because your IP isn't on the list. That's the detail that trips people up: they go looking for an RBAC fix to what is actually a networking block.

**2. Put your IP back and confirm recovery:**

```bash
gcloud container clusters update advk8s-standard \
  --zone us-central1-a --project=$PROJECT_ID \
  --enable-master-authorized-networks \
  --master-authorized-networks="${MY_IP}/32"

kubectl --context advk8s-standard get nodes
```

**What you should see:** both nodes `Ready` again, within about a minute.

![Recovered: both nodes Ready again](artifacts/lab-05/screenshots/04-recovery.png)

---

## Step 3 — Create an Autopilot cluster

**Goal:** create an Autopilot cluster and notice how different it is from the moment it exists.

```bash
gcloud container clusters create-auto advk8s-autopilot \
  --project=$PROJECT_ID \
  --region=us-central1 \
  --release-channel=regular

gcloud container clusters get-credentials advk8s-autopilot --region us-central1 --project=$PROJECT_ID
kubectl config rename-context gke_${PROJECT_ID}_us-central1_advk8s-autopilot advk8s-autopilot
kubectl --context advk8s-autopilot get nodes
```

**What you should see:** at least one node already `Ready` before you've deployed anything.

![One node already present before any workload was deployed](artifacts/lab-05/screenshots/05-autopilot-nodes.png)

**What this means:** this is `create-auto` (Autopilot), which is **regional** by default (not zonal), and it pre-provisions a little system capacity for its own managed components. You never chose a machine type — that's Autopilot's whole premise.

---

## Step 4 — The real difference: a privileged container

**Goal:** deploy the *identical* privileged Pod to both clusters and watch only Autopilot reject it.

**1. Write the manifest and apply it to both clusters:**

```bash
cat > /tmp/privileged-test.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: privileged-test
spec:
  containers:
  - name: test
    image: busybox
    command: ["sleep", "3600"]
    securityContext:
      privileged: true
EOF

echo "--- Standard ---"
kubectl --context advk8s-standard apply -f /tmp/privileged-test.yaml
kubectl --context advk8s-standard get pod privileged-test

echo "--- Autopilot ---"
kubectl --context advk8s-autopilot apply -f /tmp/privileged-test.yaml
```

**What you should see:** on **Standard** the Pod is created and reaches `Running`. On **Autopilot** the apply is **rejected at admission** by GKE Warden:
```
Error from server (GKE Warden constraints violations): ... admission webhook
"warden-validating.common-webhooks.networking.gke.io" denied the request:
Violations details: {"[denied by autogke-disallow-privilege]":["container test is privileged; not allowed in Autopilot"]}
```

![Standard: 1/1 Running. Autopilot: denied by GKE Warden, autogke-disallow-privilege](artifacts/lab-05/screenshots/06-privileged-comparison.png)

**What this means:** Standard treats a privileged container as a normal request. Autopilot's built-in admission control rejects it by name (`autogke-disallow-privilege`) — a hard constraint you didn't opt into. Google can guarantee this precisely because you never had node-level access. Clean up the Standard Pod:

```bash
kubectl --context advk8s-standard delete pod privileged-test
```

---

## Step 5 — Inspect a node pool (Standard only)

**Goal:** see where machine type, disk, spot pricing, and auto-repair/upgrade live — the decisions Autopilot makes for you.

```bash
gcloud container node-pools list --cluster advk8s-standard --zone us-central1-a --project=$PROJECT_ID
gcloud container node-pools describe default-pool --cluster advk8s-standard --zone us-central1-a --project=$PROJECT_ID \
  --format="yaml(config.machineType, config.diskSizeGb, config.spot, management)"
```

**What you should see:** `config.machineType: e2-medium`, `config.diskSizeGb: 30`, and `management: autoRepair: true, autoUpgrade: true`. (`config.spot` is simply absent when it's `false` — normal YAML omission, not a missing field.)

![default-pool: e2-medium, 30GB disk, autoRepair/autoUpgrade true](artifacts/lab-05/screenshots/07-node-pool.png)

**What this means:** every one of these is a knob you own in Standard and Autopilot decides for you. This is also the object the later cluster-scaling and autoscaling labs operate on.

---

## Step 6 — Clean up both clusters

**Goal:** delete both clusters and verify nothing is left billing.

```bash
kubectl --context advk8s-standard delete pod privileged-test --ignore-not-found
kubectl --context advk8s-autopilot delete pod privileged-test --ignore-not-found

gcloud container clusters delete advk8s-standard --zone us-central1-a --project=$PROJECT_ID --quiet
gcloud container clusters delete advk8s-autopilot --region us-central1 --project=$PROJECT_ID --quiet

gcloud container clusters list --project=$PROJECT_ID
```

**What you should see:** an empty cluster list.

![Empty list — both clusters confirmed gone](artifacts/lab-05/screenshots/08-teardown-verified.png)

**What this means:** both clusters are gone. (Notice Autopilot has no separate node pools to clean up first — one `delete` is the whole teardown, itself a small illustration of the trade-off this lab is about.)

---

## What you learned

| | Standard | Autopilot |
|---|---|---|
| Node pools you manage | ✅ | None — fully managed |
| Privileged containers | ✅ Allowed | ❌ Blocked by GKE Warden (`autogke-disallow-privilege`) |
| Billing granularity | Per-node | Per-Pod resource request |
| Cluster scope | Zonal (as created here) | Regional by default |
| Private nodes + authorized networks | ✅ tested, incl. a real lockout/recovery | Same mechanism, not exercised here |
| Release channel | ✅ `regular` | ✅ `regular` |

## Evidence

Real screenshots for this lab are in [`artifacts/lab-05/screenshots/`](artifacts/lab-05/screenshots/) (8 images).

---

---

**Next:** [Lab 6 — Why Won't This Delete? (Operators, Finalizers & Stuck Deletions)](lab-06-operators-finalizers.md)
