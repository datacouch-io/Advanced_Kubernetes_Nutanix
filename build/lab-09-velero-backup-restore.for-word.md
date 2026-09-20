
**Day 3 · Stateful Workloads, Persistent Storage & Service Exposure**

> YES — **Tested end-to-end** on a **real GKE cluster** (`advk8s-lab`, `dcproject-462806`) with **Velero** backing up to an **in-cluster MinIO** (S3-compatible) bucket. Every screenshot is a real capture. The payoff: you `kubectl delete namespace` an entire application, then bring it *all* back — Deployment, Service, and its data — from a backup, with `catalog: widget-9000=42.00` intact.

## What you'll learn

- The difference between a **volume snapshot** (Lab 8 — one disk, same storage system) and a **backup** (this lab — whole namespaces of *objects and data*, in external object storage you can restore anywhere).
- How to run **Velero** against **S3-compatible object storage** — here in-cluster MinIO, exactly the pattern you'd use with **Nutanix Objects**.
- How to back up a namespace, prove it's stored, delete the namespace completely, and restore it.

## What you'll do

You'll stand up MinIO as an S3 target and install Velero pointing at it. Then you'll create an app with data, back up its namespace, **delete the whole namespace**, and restore it from the backup — verifying every object and its data returns.

## Time & cost

- **Time:** ~45 minutes.
- **Cost:** negligible — MinIO and Velero run as small Pods on the shared GKE cluster; no cloud object storage needed.

---

## Before you start

- **Where you'll work:** in a **terminal** on your own machine.
- **Tools you need:** `gcloud`, `kubectl`, and the **`velero`** CLI (`brew install velero`).
- **Cluster:** a GKE cluster (this course's shared `advk8s-lab`).

> **Nutanix note.** Velero is the standard Kubernetes backup tool and is platform-agnostic. We back up to in-cluster **MinIO** here so the lab is self-contained and needs no cloud credentials — but the object-store config is *identical* for **Nutanix Objects** (also S3-compatible): you'd just point `s3Url` at your Nutanix Objects endpoint and use its access keys. Everything else in this lab is unchanged on NKE.

---

## The idea in 60 seconds

A **snapshot** (Lab 8) copies one volume within the same storage system — great for fast single-disk recovery, useless if the whole cluster or namespace is gone. A **backup** captures your Kubernetes **objects** (Deployments, Services, ConfigMaps, …) *and* volume data, and writes them to **external object storage**. Because the backup lives outside the cluster, you can restore a deleted namespace — or rebuild onto a brand-new cluster entirely.

**Velero** is the tool: it watches for `Backup`/`Restore` custom resources, serialises the selected objects, and stores them in an S3 bucket. Here that bucket is MinIO running in the cluster.

![Architecture diagram](artifacts/lab-09/diagrams/diagram.png)

---

## Step 1 — Stand up the backup target (MinIO) and install Velero

**Goal:** deploy MinIO as an S3 target, create a bucket, and install Velero pointing at it.

**1. Deploy MinIO and a Service** (MinIO dropped its `latest` tag, so use a current `RELEASE.*` image — the quay.io mirror is reliable):

```bash
kubectl create namespace velero
kubectl apply -n velero -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: minio, labels: {app: minio}}
spec:
  replicas: 1
  selector: {matchLabels: {app: minio}}
  template:
    metadata: {labels: {app: minio}}
    spec:
      containers:
        - name: minio
          image: quay.io/minio/minio:RELEASE.2025-09-07T16-13-09Z-cpuv1
          args: ["server", "/data", "--console-address", ":9001"]
          env:
            - {name: MINIO_ROOT_USER, value: minioadmin}
            - {name: MINIO_ROOT_PASSWORD, value: minioadmin}
          ports: [{containerPort: 9000}]
---
apiVersion: v1
kind: Service
metadata: {name: minio}
spec:
  selector: {app: minio}
  ports: [{port: 9000, targetPort: 9000}]
EOF
kubectl -n velero rollout status deployment/minio --timeout=150s
```

**2. Create the `velero` bucket** with a one-shot `mc` (MinIO client) Job:

```bash
kubectl -n velero apply -f - <<'EOF'
apiVersion: batch/v1
kind: Job
metadata: {name: mc-mkbucket}
spec:
  backoffLimit: 3
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: mc
          image: quay.io/minio/mc:RELEASE.2025-08-13T08-35-41Z-cpuv1
          command: ["sh","-c","until mc alias set local http://minio:9000 minioadmin minioadmin; do sleep 2; done; mc mb -p local/velero; mc ls local"]
EOF
kubectl -n velero wait --for=condition=complete job/mc-mkbucket --timeout=120s
```

**3. Install Velero** pointing at MinIO (these are throwaway MinIO creds, not cloud credentials):

```bash
cat > /tmp/velero-creds <<'EOF'
[default]
aws_access_key_id=minioadmin
aws_secret_access_key=minioadmin
EOF

velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.11.1 \
  --bucket velero \
  --secret-file /tmp/velero-creds \
  --use-volume-snapshots=false \
  --use-node-agent \
  --backup-location-config region=minio,s3ForcePathStyle=true,s3Url=http://minio.velero.svc:9000 \
  --namespace velero

kubectl -n velero rollout status deployment/velero --timeout=150s
velero backup-location get
```

**What you should see:** the backup location `default` reports **`PHASE: Available`** — Velero can reach the MinIO bucket.

**What this means:** Velero is installed and its S3 target is validated. On NKE you'd point `s3Url` at Nutanix Objects instead; nothing else changes.

---

## Step 2 — Create an app with data, and back it up

**Goal:** back up a whole namespace to MinIO.

```bash
kubectl create namespace shop
kubectl -n shop create deployment web --image=nginx:1.27-alpine
kubectl -n shop create configmap catalog --from-literal=featured="widget-9000" --from-literal=price="42.00"
kubectl -n shop expose deployment web --port=80

velero backup create shop-backup --include-namespaces shop --wait
velero backup describe shop-backup
```

**What you should see:** the backup reaches **`Phase: Completed`**, with something like **16 items backed up** (the namespace and everything in it), and the `catalog` data is `widget-9000=42.00`.

![Namespace backed up to MinIO — Completed, 16 items](artifacts/lab-09/screenshots/01-backup-completed.png)

**What this means:** Velero serialised every object in `shop` and wrote them to the MinIO bucket. That backup now exists *independently of the cluster*.

---

## Step 3 — Delete the entire namespace

**Goal:** simulate a real disaster — the whole namespace is gone.

```bash
kubectl delete namespace shop
kubectl get ns shop --ignore-not-found
velero backup get
```

**What you should see:** `shop` is gone (no output), but `shop-backup` is still listed as `Completed`.

![Namespace deleted; the backup survives in MinIO](artifacts/lab-09/screenshots/02-namespace-deleted.png)

**What this means:** the live application is completely gone — Deployment, Service, ConfigMap, all of it. The only copy is the backup in MinIO.

---

## Step 4 — Restore, and verify the data came back

**Goal:** restore the namespace from the backup and prove everything returned.

```bash
velero restore create shop-restore --from-backup shop-backup --wait

kubectl get ns shop
kubectl -n shop get deploy,svc,cm
kubectl -n shop get cm catalog -o jsonpath='{.data.featured}={.data.price}{"\n"}'
```

**What you should see:** the restore completes, `shop` is `Active` again, `web` (Deployment + Service) and `catalog` are back, and the ConfigMap data reads **`widget-9000=42.00`** — exactly as before.

![Namespace restored — objects and data intact](artifacts/lab-09/screenshots/03-restored-with-data.png)

**What this means:** a fully deleted namespace came back, objects and data intact, from external storage. Because the backup lives in object storage, the very same command could restore this app onto a *different* cluster — which is the real power of a backup over a snapshot.

---

## Step 5 — Clean up

```bash
kubectl delete namespace shop --ignore-not-found
velero backup delete shop-backup --confirm
# to remove Velero + MinIO entirely:
# kubectl delete namespace velero
```

---

## What you learned

| You saw… | in Step | proof |
|---|---|---|
| Velero backs up to S3-compatible storage (MinIO / Nutanix Objects) | 1 | backup location `Available` |
| A namespace backup captures all its objects | 2 | `Completed`, 16 items |
| The backup survives the cluster's objects | 3 | namespace deleted, backup remains |
| A deleted namespace restores with data intact | 4 | `shop` Active, `catalog=widget-9000=42.00` |
| Backups (unlike snapshots) can restore to another cluster | 4 |

## Evidence

Real screenshots for this lab are in [`artifacts/lab-09/screenshots/`](artifacts/lab-09/screenshots/) (3 images), and a command transcript is in [`artifacts/lab-09/evidence/lab-09-velero-backup-restore.txt`](artifacts/lab-09/evidence/lab-09-velero-backup-restore.txt).

---

**Next:** [Lab 10 — Bare-Metal LoadBalancer with MetalLB](lab-10-metallb.docx)
