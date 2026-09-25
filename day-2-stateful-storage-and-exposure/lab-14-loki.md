# Lab 14 — Find the Failing Pod from Its Logs (Log-Based Diagnosis with Loki)

**Day 3 · Stateful Workloads, Persistent Storage & Service Exposure**

> ✅ **Tested end-to-end** on a **real GKE cluster** (`advk8s-lab`, `dcproject-462806`) with **Loki + Promtail** collecting logs cluster-wide. Every screenshot is a real capture. The payoff: an app is quietly failing every few seconds, and instead of `kubectl logs`-ing pod after pod, you'll ask Loki **one query** and get the exact error line — `ERROR payment failed: connection refused to db:5432` — with a timestamp.

## What you'll learn

- Why `kubectl logs` doesn't scale: it's one pod at a time, and the logs vanish when the pod restarts or is rescheduled.
- How **Loki + Promtail** turn every pod's stdout into a searchable, labelled store — the logging half of observability (metrics is the other half).
- How to write **LogQL**: a **label selector** to pick a stream, a **line filter** (`|=`) to find the smoking gun, and `count_over_time` to measure *how often* it's happening.

## What you'll do

You'll install Loki and Promtail, deploy a `payments` app that logs a recurring error, then use LogQL from the `logcli` CLI to (1) see everything the app is logging, (2) filter straight to the error, and (3) count how often it fires.

## Time & cost

- **Time:** ~35 minutes.
- **Cost:** negligible — Loki, Promtail, and the app are small Pods on the shared GKE cluster.

---

## Before you start

- **Where you'll work:** in a **terminal** on your own machine.
- **Tools you need:** `gcloud`, `kubectl`, `helm`, and the **`logcli`** CLI (`brew install logcli`).
- **Cluster:** a GKE cluster (this course's shared `advk8s-lab`).

> **Nutanix note.** Loki is platform-agnostic — it runs identically on **NKE**. Promtail is a DaemonSet, so it lands one Pod on every node and tails all container logs there; on an on-prem Nutanix cluster that's exactly how you'd get whole-cluster log search without shipping logs off-site. For long-term retention you'd point Loki's storage at **Nutanix Objects** (S3-compatible) — the same object-store pattern you used for Velero in Lab 12.

---

## The idea in 60 seconds

`kubectl logs <pod>` shows one container's output, right now. That's fine for a single pod you already suspect — but useless when you have dozens of pods across namespaces and you don't yet *know* which one is broken. And once a pod restarts, its old logs are gone.

**Promtail** runs on every node, tails every container's stdout, attaches **labels** (`namespace`, `pod`, `app`, `container`, …), and ships the lines to **Loki**, which indexes them by those labels. You then query with **LogQL**:

- a **label selector** — `{namespace="shop2"}` — picks the stream(s),
- a **line filter** — `|= "ERROR"` — keeps only matching lines,
- an aggregation — `count_over_time(... [5m])` — measures the rate.

```mermaid
flowchart TB
    P1["pod stdout<br/>(node 1)"] --> PT1["Promtail<br/>(DaemonSet)"]
    P2["pod stdout<br/>(node 2)"] --> PT2["Promtail<br/>(DaemonSet)"]
    PT1 -->|"lines + labels"| LOKI["Loki<br/>(indexes by label)"]
    PT2 -->|"lines + labels"| LOKI
    LOKI -->|"LogQL:<br/>{namespace=&quot;shop2&quot;} |= &quot;ERROR&quot;"| YOU["you — the exact<br/>failing line + timestamp"]
```

---

## Step 1 — Install Loki + Promtail, and deploy the app with the bug

**Goal:** get log aggregation running cluster-wide, then start an app that logs a recurring failure.

**1. Install Loki and Promtail with Helm:**

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install loki grafana/loki-stack \
  --namespace loki --create-namespace \
  --set promtail.enabled=true --set grafana.enabled=false
kubectl -n loki rollout status statefulset/loki --timeout=180s
```

**2. Deploy the `payments` app** — it prints an `INFO` line every 2 seconds and, on every 5th request, an `ERROR`:

```bash
kubectl create namespace shop2
kubectl -n shop2 apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: payments, labels: {app: payments}}
spec:
  replicas: 1
  selector: {matchLabels: {app: payments}}
  template:
    metadata: {labels: {app: payments}}
    spec:
      containers:
        - name: payments
          image: busybox:1.36
          command: ["sh","-c","i=0; while true; do i=$((i+1)); echo \"$(date -u +%H:%M:%S) INFO request $i handled\"; if [ $((i % 5)) -eq 0 ]; then echo \"$(date -u +%H:%M:%S) ERROR payment failed: connection refused to db:5432\"; fi; sleep 2; done"]
EOF
kubectl -n shop2 rollout status deployment/payments --timeout=90s
```

**3. Confirm everything is up and the app is logging** (`kubectl logs` here is just to show the raw stream — the whole point of the lab is to *stop* doing this):

```bash
kubectl -n loki get pods
kubectl -n shop2 logs deploy/payments --tail=6
```

**What you should see:** `loki-0` and one `loki-promtail-*` Pod **per node** all `Running`, and the app's log stream showing `INFO request N handled` lines with a recurring `ERROR payment failed: connection refused to db:5432`.

![Loki + Promtail running, and the payments app emitting INFO lines plus a recurring ERROR](../artifacts/lab-14/screenshots/01-loki-setup.png)

**What this means:** Promtail is already tailing this app's stdout on whatever node it landed on and shipping it to Loki — you didn't configure anything per-app. Now you can query it centrally.

---

## Step 2 — Ask Loki what the app is logging (LogQL label selector)

**Goal:** pull the app's recent logs *without* knowing or naming the pod — just the namespace.

First, point `logcli` at Loki. In one terminal, open a port-forward and leave it running:

```bash
kubectl -n loki port-forward svc/loki 3100:3100
```

In a **second** terminal, tell `logcli` where Loki is, then query by label:

```bash
export LOKI_ADDR=http://localhost:3100
logcli query --since=2m --limit=5 '{namespace="shop2"}'
```

**What you should see:** the five most recent lines from **every** pod in `shop2` — a mix of `INFO request N handled` and the `ERROR payment failed: ...` line, newest first, each tagged with its timestamp.

**What this means:** `{namespace="shop2"}` is a **label selector** — it matched the stream by label, not by pod name. You never had to know which pod, node, or container it was. That's the difference from `kubectl logs`.

---

## Step 3 — Pinpoint the root cause with a line filter

**Goal:** cut through the noise and see only the failures.

```bash
logcli query --since=10m --limit=4 '{namespace="shop2"} |= "ERROR"'
```

**What you should see:** only the `ERROR payment failed: connection refused to db:5432` lines — the `|= "ERROR"` line filter dropped every `INFO` line. The message tells you the root cause directly: the app can't reach its database at `db:5432`.

![All logs by label selector, then filtered to just the ERROR lines with a LogQL line filter](../artifacts/lab-14/screenshots/02-logql-root-cause.png)

**What this means:** `|=` keeps only lines containing the substring. In one query, across the whole namespace, you went from "something's wrong" to the exact error and its timestamp — no pod-by-pod hunting. (Loki also has `|~` for regex, `!=` to exclude, and `| json` to parse structured logs into fields.)

---

## Step 4 — Measure how often it's failing (count_over_time)

**Goal:** turn logs into a number — is this a one-off or a storm?

```bash
logcli query 'sum(count_over_time({namespace="shop2"} |= "ERROR" [5m]))'
```

**What you should see:** a single value — the number of `ERROR` lines in the last 5 minutes. With this app firing an error on every 5th 2-second request (one every ~10 seconds), a full 5-minute window reads **about 30**.

**What this means:** `count_over_time(...[5m])` counts matching lines per stream over a rolling window, and `sum(...)` collapses them to one number. This is a **metric derived from logs** — the exact thing you'd graph in Grafana or alert on ("page me if payment errors exceed 20 in 5 minutes").

---

## Step 5 — Clean up

Stop the port-forward (`Ctrl-C` in its terminal), then:

```bash
kubectl delete namespace shop2 --ignore-not-found
# to remove Loki + Promtail entirely:
# helm uninstall loki -n loki && kubectl delete namespace loki
```

---

## What you learned

| You saw… | in Step | proof |
|---|---|---|
| Promtail collects every pod's logs with no per-app config | 1 | `loki-promtail` on each node; app logs searchable |
| A LogQL label selector queries by label, not pod name | 2 | `{namespace="shop2"}` returns the app's lines |
| A line filter pinpoints the root cause | 3 | `\|= "ERROR"` → `connection refused to db:5432` |
| Logs become metrics you can alert on | 4 | `count_over_time` → ~30 errors / 5m |

## Evidence

Real screenshots for this lab are in [`artifacts/lab-14/screenshots/`](../artifacts/lab-14/screenshots/) (2 images), and a command transcript is in [`artifacts/lab-14/evidence/lab-11-loki.txt`](../artifacts/lab-14/evidence/lab-11-loki.txt).

---

---

**Next:** [Lab 15 — Let Git Drive the Cluster (GitOps Delivery with Flux)](../day-3-gitops-fleet-and-governance/lab-15-flux.md)
