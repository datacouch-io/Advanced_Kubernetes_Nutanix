# Lab 22 — Give Each Pod Only Its Own Identity, and Run Only Signed Images (Workload Identity + Binary Authorization)

**Day 5 · Kubernetes as the AI-Native Platform**

> ✅ **Tested end-to-end** on a **real GKE cluster**. Every screenshot is a real capture. Two payoffs: a Pod bound to a specific Google identity reads a bucket while an *unbound* Pod gets **403 with no usable identity at all**; and an unsigned image is **denied admission** until you sign its exact digest — then the same image runs.

## What you'll learn

- How **Workload Identity Federation** maps a specific Kubernetes ServiceAccount to a specific Google service account — and what identity *every other* Pod gets instead (a placeholder, **not** the node's powerful default).
- How **Binary Authorization** enforces "only images signed by a trusted attestor may run", end to end: a Cloud KMS signing key, an attestor, a cluster policy, and the full **deny → sign → allow** cycle.
- Two real gotchas you'll hit in practice: Binary Authorization's digest-only requirement, and cross-architecture image pushes from Apple Silicon.

## What you'll do

You'll create a Workload-Identity-enabled GKE cluster, bind a KSA to a GSA and prove access from both a bound and an unbound Pod, then turn on Binary Authorization and walk an image through deny (by tag), deny (unsigned), sign, and allow.

## Time & cost

- **Time:** ~75 minutes.
- **Cost:** small — one 2-node `e2-medium` cluster + a Cloud KMS key (a few cents) + free-tier API usage. A few dollars if you tear down promptly.

---

## Before you start

- **Where you'll work:** in a **terminal**, with `gcloud` authenticated to a real GCP project with billing enabled.
- **Tools you need:** `gcloud` (with `beta`: `gcloud components install beta`), `kubectl`, and **Docker running locally** (to push a test image).

> **Nutanix note — this lab is the most GCP-specific in the course, deliberately.** Workload Identity Federation and Binary Authorization are *managed GKE features*, so you see the polished version of two ideas you'll implement differently on **NKE**: on Nutanix, per-Pod identity is typically done with **SPIFFE/SPIRE** (issuing short-lived SVIDs to workloads), and image-signing enforcement with **cosign** (Sigstore) signatures verified by a **Kyverno** `verifyImages` policy at admission (see Lab C for Kyverno). The *concepts* — least-privilege per-workload identity, and admit-only-signed-images — are exactly the same; only the implementing components change. Learn the model here, then map it to SPIRE + cosign/Kyverno on-prem.

---

## The idea in 60 seconds

Two independent trust controls:

- **Workload Identity** stops every Pod from inheriting the node's powerful identity. You bind one **KSA** to one **GSA**; only Pods using that KSA get that GSA's permissions. Everyone else resolves to a placeholder that can't do anything.
- **Binary Authorization** stops unvetted images from running. An **attestor** (a Container Analysis note + a KMS public key) must have a valid signature over an image's **digest** before the cluster admits it.

![Architecture diagram](artifacts/lab-22/diagrams/diagram.png)

---

## Step 1 — Create a Workload-Identity-enabled cluster

**Goal:** stand up a GKE cluster with a workload pool (this is what turns Workload Identity on).

```bash
export PROJECT_ID=YOUR_GCP_PROJECT_ID

gcloud services enable \
  binaryauthorization.googleapis.com containeranalysis.googleapis.com cloudkms.googleapis.com \
  --project=$PROJECT_ID

gcloud container clusters create advk8s-security \
  --project=$PROJECT_ID --zone=us-central1-a \
  --num-nodes=2 --machine-type=e2-medium --disk-size=30 \
  --workload-pool=${PROJECT_ID}.svc.id.goog \
  --release-channel=regular

gcloud container clusters get-credentials advk8s-security --zone us-central1-a --project=$PROJECT_ID
kubectl get nodes
```

**What you should see:** two nodes, `Ready`.

![Two GKE nodes, Ready](artifacts/lab-22/screenshots/01-gke-nodes.png)

**What this means:** `--workload-pool` is the flag that enables Workload Identity for the cluster. (You can add it later with `clusters update`, but setting it at creation avoids a second wait.)

---

## Step 2 — Bind an identity, and prove it from both sides

**Goal:** bind one KSA to one GSA, then show a bound Pod can read a bucket and an unbound Pod cannot.

**1. Create and bind the identities:**

```bash
kubectl create serviceaccount wi-demo-ksa
gcloud iam service-accounts create wi-demo-gsa --project=$PROJECT_ID --display-name="WI demo GSA"
gcloud iam service-accounts add-iam-policy-binding \
  wi-demo-gsa@${PROJECT_ID}.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:${PROJECT_ID}.svc.id.goog[default/wi-demo-ksa]" --project=$PROJECT_ID
kubectl annotate serviceaccount wi-demo-ksa \
  iam.gke.io/gcp-service-account=wi-demo-gsa@${PROJECT_ID}.iam.gserviceaccount.com
```

**2. Give the GSA a real bucket to read:**

```bash
BUCKET="gs://${PROJECT_ID}-wi-demo-$(date +%s)"
gcloud storage buckets create $BUCKET --project=$PROJECT_ID --location=us-central1
echo "hello from workload identity federation" | gcloud storage cp - ${BUCKET}/test-file.txt
gcloud storage buckets add-iam-policy-binding $BUCKET \
  --member="serviceAccount:wi-demo-gsa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"
```

**3. Run a Pod using the *bound* KSA and check its identity + access:**

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata: {name: wi-test}
spec:
  serviceAccountName: wi-demo-ksa
  containers:
  - {name: gcloud, image: google/cloud-sdk:slim, command: ["sleep","3600"]}
EOF
kubectl wait --for=condition=Ready pod/wi-test --timeout=90s
kubectl exec wi-test -- curl -sS -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email"
kubectl exec wi-test -- gcloud storage cat "${BUCKET}/test-file.txt"
```

**What you should see:** the Pod's identity resolves to `wi-demo-gsa@…` and it reads the file: `hello from workload identity federation`.

![Bound pod resolves to the GSA and reads the bucket](artifacts/lab-22/screenshots/02-wi-bound-success.png)

> ⚠️ **Gotcha — a brand-new cluster's metadata server needs a moment.** On a *freshly created* cluster, the first `gcloud storage cat` inside the Pod can fail with `MetadataServerException: … metadata server is concealed`, even though the `curl` identity check already returns the correct GSA. It's a propagation delay in the metadata proxy sidecar settling on a new node — wait a few seconds and retry before suspecting your IAM bindings.

**4. Now run a Pod using the *default, unbound* KSA:**

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata: {name: wi-test-unbound}
spec:
  containers:
  - {name: gcloud, image: google/cloud-sdk:slim, command: ["sleep","3600"]}
EOF
kubectl wait --for=condition=Ready pod/wi-test-unbound --timeout=90s
kubectl exec wi-test-unbound -- curl -sS -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email"
kubectl exec wi-test-unbound -- gcloud storage cat "${BUCKET}/test-file.txt"
```

**What you should see:** the identity resolves to the placeholder `PROJECT_ID.svc.id.goog`, and the read is **denied with HTTP 403** (`Caller does not have storage.objects.get access`).

![Unbound pod: placeholder identity, 403 denied](artifacts/lab-22/screenshots/03-wi-unbound-denied.png)

**What this means:** the unbound Pod does **not** fall back to the node's identity — it gets a placeholder that's usable for nothing. That's the security property: a compromised Pod's blast radius shrinks from "the whole node's identity" to "nothing, unless that Pod was explicitly bound." Clean up: `kubectl delete pod wi-test wi-test-unbound`.

---

## Step 3 — Turn on Binary Authorization with a KMS-backed attestor

**Goal:** require that images be signed by a trusted attestor before they can run.

**1. Enable enforcement** (a real control-plane update — takes several minutes):

```bash
gcloud container clusters update advk8s-security --zone us-central1-a \
  --binauthz-evaluation-mode=PROJECT_SINGLETON_POLICY_ENFORCE --project=$PROJECT_ID
```

**2. Create the attestor, a KMS signing key, and attach the public key:**

```bash
export NOTE_ID=advk8s-attestor-note ATTESTOR_NAME=advk8s-attestor
cat > /tmp/note_payload.json <<EOF
{"name":"projects/${PROJECT_ID}/notes/${NOTE_ID}","attestation":{"hint":{"human_readable_name":"AdvK8s lab attestor"}}}
EOF
curl -sS -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "x-goog-user-project: ${PROJECT_ID}" --data-binary @/tmp/note_payload.json \
  "https://containeranalysis.googleapis.com/v1/projects/${PROJECT_ID}/notes/?noteId=${NOTE_ID}"
gcloud --project="${PROJECT_ID}" container binauthz attestors create "${ATTESTOR_NAME}" \
  --attestation-authority-note="${NOTE_ID}" --attestation-authority-note-project="${PROJECT_ID}"

gcloud kms keyrings create advk8s-binauthz-keyring --location us-central1 --project=$PROJECT_ID
gcloud kms keys create advk8s-attestor-key --location us-central1 \
  --keyring advk8s-binauthz-keyring --purpose asymmetric-signing \
  --default-algorithm ec-sign-p256-sha256 --protection-level software --project=$PROJECT_ID
gcloud --project="${PROJECT_ID}" container binauthz attestors public-keys add \
  --attestor="${ATTESTOR_NAME}" --keyversion-project="${PROJECT_ID}" \
  --keyversion-location=us-central1 --keyversion-keyring=advk8s-binauthz-keyring \
  --keyversion-key=advk8s-attestor-key --keyversion=1
```

**3. Set a policy requiring this attestor** (whitelist your distro's *system* image registries, or the cluster's own internals break):

```bash
cat > /tmp/binauthz-policy.yaml <<EOF
defaultAdmissionRule:
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
  evaluationMode: REQUIRE_ATTESTATION
  requireAttestationsBy:
  - projects/${PROJECT_ID}/attestors/${ATTESTOR_NAME}
globalPolicyEvaluationMode: ENABLE
name: projects/${PROJECT_ID}/policy
admissionWhitelistPatterns:
- {namePattern: gcr.io/gke-release/*}
- {namePattern: registry.k8s.io/*}
- {namePattern: gke.gcr.io/*}
EOF
gcloud container binauthz policy import /tmp/binauthz-policy.yaml --project=$PROJECT_ID
```

**4. Push a test image to Artifact Registry:**

```bash
gcloud artifacts repositories create advk8s-images --repository-format=docker --location=us-central1 --project=$PROJECT_ID
gcloud auth configure-docker us-central1-docker.pkg.dev --quiet
docker tag nginx:1.27-alpine us-central1-docker.pkg.dev/${PROJECT_ID}/advk8s-images/nginx:1.27-alpine
docker push us-central1-docker.pkg.dev/${PROJECT_ID}/advk8s-images/nginx:1.27-alpine
```

> ⚠️ **Gotcha — Apple Silicon pushes an arm64 image; GKE nodes are amd64.** From an M-series Mac, `docker push` sends **arm64** by default. Binary Authorization only checks the *digest*, so the Pod admits — then crashes with `exec format error`. Fix by resolving and copying the amd64-specific digest directly (a plain `docker pull --platform linux/amd64` does **not** reliably fix a cached arm64 tag):
> ```bash
> docker buildx imagetools inspect nginx:1.27-alpine | grep -A3 "linux/amd64"   # get the amd64 digest
> docker buildx imagetools create \
>   --tag us-central1-docker.pkg.dev/${PROJECT_ID}/advk8s-images/nginx:1.27-alpine-amd64 \
>   docker.io/library/nginx:1.27-alpine@sha256:<amd64-digest>
> ```

**What this means:** the attestor is the unit of trust — a KMS key pair whose public half the cluster trusts. Nothing is signed yet, so nothing custom can run.

---

## Step 4 — The deny → sign → allow cycle

**Goal:** walk one image from rejected to running by signing its digest.

```bash
IMAGE="us-central1-docker.pkg.dev/${PROJECT_ID}/advk8s-images/nginx:1.27-alpine-amd64"
DIGEST=$(gcloud artifacts docker images describe $IMAGE --format='value(image_summary.digest)')
IMAGE_BY_DIGEST="us-central1-docker.pkg.dev/${PROJECT_ID}/advk8s-images/nginx@${DIGEST}"
```

**Attempt 1 — by mutable tag:**

```bash
kubectl run unattested-test --image="$IMAGE" --restart=Never
```

**What you should see:** `VIOLATES_POLICY: Expected digest with sha256 scheme, but got tag or malformed digest`.

![Denied: image referenced by tag, not digest](artifacts/lab-22/screenshots/04-binauthz-attempt1-tag.png)

**Attempt 2 — by digest, but unsigned:**

```bash
kubectl run binauthz-test --image="$IMAGE_BY_DIGEST" --restart=Never
```

**What you should see:** `VIOLATES_POLICY: No attestations found that were valid and signed by a key trusted by the attestor`.

![Denied: no attestation for this digest](artifacts/lab-22/screenshots/05-binauthz-attempt2-unattested.png)

**Sign the digest, then Attempt 3:**

```bash
gcloud beta container binauthz attestations sign-and-create \
  --project=$PROJECT_ID --artifact-url="$IMAGE_BY_DIGEST" \
  --attestor=advk8s-attestor --attestor-project=$PROJECT_ID \
  --keyversion-project=$PROJECT_ID --keyversion-location=us-central1 \
  --keyversion-keyring=advk8s-binauthz-keyring --keyversion-key=advk8s-attestor-key --keyversion=1

kubectl run binauthz-test --image="$IMAGE_BY_DIGEST" --restart=Never
kubectl get pod binauthz-test
```

**What you should see:** the same digest that was denied twice is now **admitted and `Running`**.

![Signed image admitted and Running](artifacts/lab-22/screenshots/06-binauthz-attempt3-signed-running.png)

**What this means:** admission is bound to an **immutable digest with a valid signature** — never a tag (which could point at different content tomorrow) and never an unsigned image. Sign in CI only after your scans pass, and only vetted images ever reach the cluster.

---

## Step 5 — Clean up

```bash
kubectl delete pod wi-test wi-test-unbound binauthz-test 2>/dev/null
gcloud storage rm -r $BUCKET
gcloud iam service-accounts delete wi-demo-gsa@${PROJECT_ID}.iam.gserviceaccount.com --quiet
gcloud container binauthz attestors delete advk8s-attestor --project=$PROJECT_ID --quiet
gcloud kms keys versions destroy 1 --key=advk8s-attestor-key --keyring=advk8s-binauthz-keyring --location=us-central1 --project=$PROJECT_ID --quiet
gcloud artifacts repositories delete advk8s-images --location=us-central1 --project=$PROJECT_ID --quiet
gcloud container clusters delete advk8s-security --zone us-central1-a --project=$PROJECT_ID --quiet
```

(A KMS key *version* can be scheduled for destruction, but the keyring itself can't be deleted — that's deliberate GCP behaviour. An empty keyring costs nothing.)

---

## What you learned

| You saw… | in Step | proof |
|---|---|---|
| A bound KSA Pod acts as its GSA and can access granted resources | 2 | resolves to `wi-demo-gsa@…`, reads the bucket |
| An unbound Pod gets no usable identity | 2 | placeholder `svc.id.goog`, 403 denied |
| Binary Authorization rejects tag references | 4 | `Expected digest with sha256 scheme` |
| It rejects unsigned images | 4 | `No attestations found … trusted by the attestor` |
| A signed digest is admitted and runs | 4 | `binauthz-test 1/1 Running` |

## Evidence

Real screenshots for this lab are in [`artifacts/lab-22/screenshots/`](artifacts/lab-22/screenshots/) (6 images), and command transcripts are in [`artifacts/lab-22/evidence/`](artifacts/lab-22/evidence/).

---

---

**Next:** [Lab 23 — Catch a Container Misbehaving at Runtime (Falco)](lab-23-falco-runtime-security.md)
