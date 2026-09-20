# Lab 16 — Watch Inference Latency Spike, Then Scale It Away (Inference Autoscaling Signals)

**Day 5 · Kubernetes as the AI-Native Platform**

> ✅ **Tested end-to-end** on a **real GKE cluster** (`advk8s-lab`). Every screenshot is a real capture. The payoff: you send the *same* burst of traffic at one inference replica and at four, and watch the signal that matters for LLM serving — **time-to-first-token** — collapse from **~8s to ~1.6s** as the request **queue depth** spreads across replicas.

## What you'll learn

- Which signal actually tells you an inference service is overloaded: not CPU%, but **queue depth** (requests waiting for an accelerator) and **time-to-first-token (TTFT)**.
- Why a single inference replica *serialises* requests — one "accelerator" processes one generation at a time, so extra requests queue and TTFT climbs linearly with the queue.
- How **scaling out** drains the queue and restores TTFT — the basis for autoscaling an inference deployment on queue depth.

## What you'll do

You'll deploy a small inference service that simulates a single-accelerator worker, drive a fixed concurrent burst at it, measure the TTFT spike and queue depth, then scale to four replicas and re-run the identical burst to watch it recover.

## Time & cost

- **Time:** ~35 minutes.
- **Cost:** negligible — small CPU-only Pods on the shared GKE cluster.

> **Honest scope note.** This lab uses a **simulated** inference server (a single-worker service where each request takes a fixed "generation" time) rather than a real GPU-backed model, so it runs anywhere with no accelerator and no multi-GB model download. The *behaviour it reproduces is real*: the queue-depth-and-TTFT signal, and its recovery under scale-out, are exactly what you see with a real LLM server (vLLM, TGI, Triton) — see the Nutanix note for the real metric names.

---

## Before you start

- **Where you'll work:** in a **terminal** with `kubectl` pointed at a GKE cluster.
- **Tools you need:** `gcloud`, `kubectl`.
- **Cluster:** a GKE cluster (this course's shared `advk8s-lab`).

> **Nutanix note.** On a real Nutanix GPU-inference platform you'd serve models with **vLLM**, **TGI**, or **Triton**, which expose exactly these signals as Prometheus metrics — vLLM publishes `vllm:num_requests_waiting` (queue depth) and `vllm:time_to_first_token_seconds`. You'd wire those into an HPA (via prometheus-adapter or **KEDA**) so the deployment scales on *queue depth*, not CPU — because a GPU can be 100% "busy" and still have a growing queue, and CPU utilisation tells you nothing about TTFT. This lab teaches the signal; on-prem you point the same autoscaling logic at the real metric.

---

## The idea in 60 seconds

An inference replica has a **worker** (a GPU, here simulated) that generates one response at a time. Send more concurrent requests than there are workers and the extras **queue**. Each queued request's **time-to-first-token** is roughly `(its queue position) × (generation time)` — so TTFT climbs linearly with load on a fixed number of replicas.

CPU utilisation is a poor signal here (a saturated GPU reads ~100% whether the queue is empty or 50 deep). The signals that matter are **queue depth** and **TTFT**. When they spike, you **scale out**: more replicas = more workers = shorter queue per replica = lower TTFT.

![Architecture diagram](artifacts/lab-16/diagrams/diagram.png)

---

## Step 1 — Deploy the inference service

**Goal:** stand up a single-replica service that serialises "generation" like one accelerator would.

The app (a FastAPI service) holds a **worker semaphore of 1** — each `/infer` acquires it, "generates" for 0.4s, releases it. Concurrent requests queue on that semaphore, and `/stats` reports the peak queue depth seen.

```bash
kubectl create namespace inference
# app.py served from a ConfigMap (semaphore=1 worker; /infer, /stats, /healthz) —
# see artifacts/lab-16/evidence for the full app.py
kubectl -n inference create configmap infer-app --from-file=app.py=/path/to/app.py

kubectl -n inference apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: llm, labels: {app: llm}}
spec:
  replicas: 1
  selector: {matchLabels: {app: llm}}
  template:
    metadata: {labels: {app: llm}}
    spec:
      containers:
      - name: llm
        image: python:3.11-slim
        command: ["sh","-c","pip install --quiet fastapi uvicorn && uvicorn app:app --host 0.0.0.0 --port 8000 --app-dir /code"]
        ports: [{containerPort: 8000}]
        resources: {requests: {cpu: 200m}}
        readinessProbe: {httpGet: {path: /healthz, port: 8000}, initialDelaySeconds: 5, periodSeconds: 3}
        volumeMounts: [{name: code, mountPath: /code}]
      volumes: [{name: code, configMap: {name: infer-app}}]
---
apiVersion: v1
kind: Service
metadata: {name: llm}
spec:
  selector: {app: llm}
  ports: [{port: 80, targetPort: 8000}]
EOF
kubectl -n inference rollout status deploy/llm --timeout=150s
```

**What you should see:** one `llm` Pod `Running` and `Ready`.

**What this means:** you have one inference "accelerator." It can generate one response at a time — anything beyond that will queue.

---

## Step 2 — Drive load at one replica and watch TTFT spike

**Goal:** send a fixed concurrent burst and measure the latency signal.

The load client fires 200 requests at concurrency 20 and reports TTFT percentiles:

```bash
# load.py (from a ConfigMap): 200 requests, 20 concurrent, prints TTFT p50/p95/max
kubectl -n inference run loadtest --image=python:3.11-slim --restart=Never --rm -i \
  --overrides='{"spec":{"volumes":[{"name":"s","configMap":{"name":"load-script"}}],"containers":[{"name":"loadtest","image":"python:3.11-slim","command":["python","/s/load.py","200","20"],"volumeMounts":[{"name":"s","mountPath":"/s"}]}]}}'

# then check the queue depth the replica saw:
POD=$(kubectl -n inference get pod -l app=llm -o jsonpath='{.items[0].metadata.name}')
kubectl -n inference exec "$POD" -- python -c "import urllib.request;print(urllib.request.urlopen('http://localhost:8000/stats').read().decode())"
```

**What you should see:** **TTFT p50 ≈ 8.0s** (p95 and max also ~8s), and the replica's **`peak_queue_depth: 20`** — all 20 concurrent requests piled up behind the single worker.

![One replica under load: TTFT ~8s, peak queue depth 20](artifacts/lab-16/screenshots/01-spike.png)

**What this means:** the service is *up* and returning correct responses, but every user waits ~8 seconds for their first token. CPU wouldn't have warned you clearly — the queue depth and TTFT do. This is the "spike under load" you'd alert on.

---

## Step 3 — Scale out and re-run the identical burst

**Goal:** add workers and watch TTFT recover.

```bash
kubectl -n inference scale deploy/llm --replicas=4
kubectl -n inference rollout status deploy/llm --timeout=180s

# exactly the same load as before:
kubectl -n inference run loadtest --image=python:3.11-slim --restart=Never --rm -i \
  --overrides='{"spec":{"volumes":[{"name":"s","configMap":{"name":"load-script"}}],"containers":[{"name":"loadtest","image":"python:3.11-slim","command":["python","/s/load.py","200","20"],"volumeMounts":[{"name":"s","mountPath":"/s"}]}]}}'

# queue depth per replica now:
for p in $(kubectl -n inference get pod -l app=llm -o jsonpath='{.items[*].metadata.name}'); do
  echo -n "$p  "; kubectl -n inference exec "$p" -- python -c "import urllib.request,json;print('peak_queue_depth='+str(json.load(urllib.request.urlopen('http://localhost:8000/stats'))['peak_queue_depth']))"
done
```

**What you should see:** under the **same** burst, **TTFT p50 drops to ~1.6s** (from ~8s), and the queue is **spread across the four replicas** — none sees the full depth of 20.

![Four replicas under the same load: TTFT p50 ~1.6s, queue spread across replicas](artifacts/lab-16/screenshots/02-recover.png)

**What this means:** four workers drain the queue roughly four times faster, so time-to-first-token recovers to an acceptable range. This is the whole basis of inference autoscaling: **watch queue depth / TTFT, scale replicas when they spike.** (Load-balancing across replicas is L4 and slightly uneven, so per-replica peaks vary — but no replica carries the full queue, and the aggregate TTFT recovers.)

> ⚠️ **Gotcha — don't autoscale inference on CPU.** A busy accelerator reads ~100% CPU whether its queue is empty or 50 deep, so a CPU-target HPA reacts late or not at all. Scale on **queue depth** (or TTFT/pending-requests) exposed by the model server, via a custom-metrics HPA or KEDA. CPU-based autoscaling is the classic reason an inference service "wasn't scaling" while users watched TTFT climb.

---

## Step 4 — Clean up

```bash
kubectl delete namespace inference --ignore-not-found
```

---

## What you learned

| You saw… | in Step | proof |
|---|---|---|
| A single inference replica serialises requests | 1–2 | `peak_queue_depth: 20` on one replica |
| Overload shows up as TTFT + queue depth, not CPU | 2 | TTFT p50 ~8s under a 20-concurrent burst |
| Scaling out drains the queue and restores TTFT | 3 | TTFT p50 ~8s → ~1.6s on the same load |
| The queue spreads across replicas after scale-out | 3 | no replica sees the full depth of 20 |

## Evidence

Real screenshots for this lab are in [`artifacts/lab-16/screenshots/`](artifacts/lab-16/screenshots/) (2 images), and the app/load code plus a command transcript are in [`artifacts/lab-16/evidence/`](artifacts/lab-16/evidence/).

---

**Next:** [Lab 17 — Guardrailed Agentic Kubernetes](lab-17-agentic-guardrails.md)
