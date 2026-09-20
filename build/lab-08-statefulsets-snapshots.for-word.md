
**Day 3 · Stateful Workloads, Persistent Storage & Service Exposure**

> YES — **Tested end-to-end** on a **real GKE cluster** (`advk8s-lab`, `dcproject-462806`) using real Persistent Disks and CSI volume snapshots. Every screenshot is a real capture. The payoff you'll see: you write data, snapshot it, **delete the StatefulSet and its disk entirely**, then bring the data back from the snapshot onto a brand-new volume — `important-data-v1`, intact.

## What you'll learn

- How a **StatefulSet** gives each Pod its own stable **PVC** via a `volumeClaimTemplate`, backed by a real cloud disk.
- How to take a **`VolumeSnapshot`** of a live PVC through the CSI driver, and confirm it's `readyToUse`.
- How to **restore** a snapshot onto a *new* PVC using `dataSource`, and verify the data survived a full destroy/restore cycle.
- Why a snapshot in the same storage system is a fast recovery tool — and where its limits are (that's what Lab 9's Velero backup covers).

## What you'll do

You'll run a StatefulSet with a persistent volume, write a known value into it, snapshot the volume, then **delete the whole StatefulSet and its PVC** to simulate a disaster. Finally you'll restore the snapshot onto a fresh PVC and prove the original data is still there.

## Time & cost

- **Time:** ~40 minutes (much of it waiting for real disks to provision).
- **Cost:** a few cents of Persistent Disk on the shared GKE cluster.

---

## Before you start

- **Where you'll work:** in a **terminal** on your own machine.
- **Tools you need:** `gcloud`, `kubectl`.
- **Cluster:** a GKE cluster (this course's shared `advk8s-lab`). GKE ships the CSI snapshot CRDs but **no `VolumeSnapshotClass` by default** — you'll create one in Step 2.

> **Nutanix note.** StatefulSets, PVCs, `VolumeSnapshot`, and the `dataSource`-restore mechanism are all standard Kubernetes/CSI — identical on NKE. The only platform-specific piece is the **CSI driver** name: here it's `pd.csi.storage.gke.io` (Google Persistent Disk); on Nutanix it's the **Nutanix CSI driver** (`csi.nutanix.com`), which likewise supports `VolumeSnapshot`. Swap the driver name in the `VolumeSnapshotClass` and everything else in this lab is unchanged.

---

## The idea in 60 seconds

A **StatefulSet** is how you run stateful apps: each replica gets a stable identity (`db-0`, `db-1`, …) and its *own* PVC from a `volumeClaimTemplate`, so a Pod that restarts reattaches to the same disk. A **PVC** is bound to a real volume provisioned by a **CSI driver** (here Google Persistent Disk).

A **`VolumeSnapshot`** asks that CSI driver to take a point-in-time copy of the volume. It's fast and space-efficient, and — crucially — you can create a **new PVC from a snapshot** (`spec.dataSource`), which is how you recover. That's the cycle you'll run: snapshot → destroy → restore.

![Architecture diagram](artifacts/lab-08/diagrams/diagram.png)

---

## Step 1 — Run a StatefulSet and write data to its volume

**Goal:** create a StatefulSet whose Pod has its own persistent disk, and put a known value on it.

**1. Create the StatefulSet (it declares a `volumeClaimTemplate`), wait for it, then write a file:**

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata: {name: db}
spec:
  serviceName: db
  replicas: 1
  selector: {matchLabels: {app: db}}
  template:
    metadata: {labels: {app: db}}
    spec:
      containers:
        - name: app
          image: busybox:1.36
          command: ["sh","-c","sleep 3600"]
          volumeMounts: [{name: data, mountPath: /data}]
  volumeClaimTemplates:
    - metadata: {name: data}
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: standard-rwo
        resources: {requests: {storage: 1Gi}}
EOF
kubectl rollout status statefulset/db --timeout=120s

kubectl exec db-0 -- sh -c 'echo "important-data-v1" > /data/message; cat /data/message'
kubectl get pvc data-db-0
```

**What you should see:** the rollout completes, `cat /data/message` prints `important-data-v1`, and `kubectl get pvc data-db-0` shows a `Bound` 1Gi PVC.

![StatefulSet running, data written, PVC bound](artifacts/lab-08/screenshots/01-statefulset-data.png)

**What this means:** the StatefulSet created a PVC named `data-db-0` (template name + Pod name), CSI provisioned a real Persistent Disk for it, and your file lives on that disk — not in the Pod.

---

## Step 2 — Snapshot the volume

**Goal:** create a `VolumeSnapshot` of the PVC and confirm it's usable.

**1. Create a `VolumeSnapshotClass` (GKE doesn't ship one), then snapshot the PVC:**

```bash
kubectl apply -f - <<'EOF'
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata: {name: pd-snapclass}
driver: pd.csi.storage.gke.io
deletionPolicy: Delete
EOF

kubectl apply -f - <<'EOF'
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata: {name: db-snap}
spec:
  volumeSnapshotClassName: pd-snapclass
  source: {persistentVolumeClaimName: data-db-0}
EOF

kubectl wait --for=jsonpath='{.status.readyToUse}'=true volumesnapshot/db-snap --timeout=120s
kubectl get volumesnapshot db-snap
```

**What you should see:** `db-snap` with `READYTOUSE: true` and `RESTORESIZE: 1Gi`.

![Snapshot readyToUse=true, restoreSize 1Gi](artifacts/lab-08/screenshots/02-snapshot-ready.png)

**What this means:** the CSI driver captured a point-in-time copy of the disk. It exists independently of the PVC now — you could delete the original and still restore from this.

---

## Step 3 — Simulate a disaster

**Goal:** destroy the StatefulSet *and* its volume, so recovery has to come from the snapshot.

```bash
kubectl delete statefulset db
kubectl delete pvc data-db-0
kubectl get pvc data-db-0 --ignore-not-found
kubectl get volumesnapshot db-snap
```

**What you should see:** `data-db-0` is gone (no output), but `db-snap` is still present and ready.

![StatefulSet and PVC deleted; snapshot survives](artifacts/lab-08/screenshots/03-destroyed.png)

**What this means:** the live volume no longer exists — this is the "someone deleted the wrong thing" or "the disk is gone" scenario. The only copy of your data is the snapshot.

---

## Step 4 — Restore from the snapshot and verify

**Goal:** create a new PVC *from the snapshot* and prove the data survived.

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: data-restored}
spec:
  storageClassName: standard-rwo
  dataSource: {name: db-snap, kind: VolumeSnapshot, apiGroup: snapshot.storage.k8s.io}
  accessModes: ["ReadWriteOnce"]
  resources: {requests: {storage: 1Gi}}
---
apiVersion: v1
kind: Pod
metadata: {name: restore-check}
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh","-c","sleep 3600"]
      volumeMounts: [{name: data, mountPath: /data}]
  volumes:
    - name: data
      persistentVolumeClaim: {claimName: data-restored}
EOF
kubectl wait --for=condition=Ready pod/restore-check --timeout=120s

kubectl exec restore-check -- cat /data/message
```

**What you should see:** `cat /data/message` prints **`important-data-v1`** — the exact value from before the disaster.

![Restored volume — original data intact](artifacts/lab-08/screenshots/04-restored-verified.png)

**What this means:** the snapshot's `dataSource` pre-populated a brand-new disk with the snapshot's contents, so the data survived a *complete* destroy/restore cycle. This is the fast path for recovering a single volume.

> **Where snapshots stop.** A `VolumeSnapshot` lives in the *same* storage system and doesn't capture your Kubernetes objects (the StatefulSet, Services, ConfigMaps). For "restore a whole namespace, objects and data, possibly to another cluster," you need a backup tool that captures both — that's [Lab 9 (Velero)](lab-09-velero-backup-restore.docx).

---

## Step 5 — Clean up

```bash
kubectl delete pod restore-check --ignore-not-found
kubectl delete pvc data-restored --ignore-not-found
kubectl delete volumesnapshot db-snap --ignore-not-found
kubectl delete volumesnapshotclass pd-snapclass --ignore-not-found
```

---

## What you learned

| You saw… | in Step | proof |
|---|---|---|
| A StatefulSet gives each Pod its own PVC/disk | 1 | `data-db-0` Bound, file on the disk |
| You can snapshot a live PVC via CSI | 2 | `db-snap` `readyToUse=true`, 1Gi |
| A snapshot outlives its source volume | 3 | PVC deleted, snapshot remains |
| A snapshot restores onto a new PVC via `dataSource` | 4 | `data-restored` Bound, data intact |
| Data survives a full destroy/restore cycle | 4 | `important-data-v1` after restore |

## Evidence

Real screenshots for this lab are in [`artifacts/lab-08/screenshots/`](artifacts/lab-08/screenshots/) (4 images), and a command transcript is in [`artifacts/lab-08/evidence/lab-08-statefulsets-snapshots.txt`](artifacts/lab-08/evidence/lab-08-statefulsets-snapshots.txt).

---

**Next:** [Lab 9 — Backup & Restore with Velero](lab-09-velero-backup-restore.docx)
