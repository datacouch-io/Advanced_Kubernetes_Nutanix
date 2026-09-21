
**Day 5 · Kubernetes as the AI-Native Platform**

> YES — **Tested end-to-end** on a real `kind` cluster. Every command was run start to finish and every screenshot is a real capture — including a live GUI view of the VPA object. The payoff: you'll watch an HPA drive a Deployment **1 → 6 replicas in ~90 seconds** under load and then step it back down *without flapping*, and watch a VPA **resize a running Pod's CPU/memory with zero restarts**.

## What you'll learn

- How to tune **HorizontalPodAutoscaler** *behavior* beyond the default: fast, aggressive **scale-up** and slow, cautious **scale-down** with a stabilization window, so a brief dip in load doesn't collapse your replicas.
- How the **Vertical Pod Autoscaler** *recommends* right-sized requests from real measured usage — and then *applies* them **in place** (the `/resize` subresource) with no Pod restart.
- Why you don't point HPA and VPA at the *same* metric on the *same* workload.

## What you'll do

You'll install metrics-server, apply an HPA with asymmetric behaviour and drive it up and down with a load generator, then use a VPA (recommendation first, then live in-place resize) on a deliberately under-provisioned app.

## Time & cost

- **Time:** ~40 minutes.
- **Cost:** **$0** — runs entirely on a local `kind` cluster.

---

## Before you start

- **Where you'll work:** in a **terminal** on your own machine.
- **Tools you need:** `docker`, `kind`, `kubectl`, `helm`, `git`.
- **Cluster:** you'll create a fresh `kind` cluster in Step 1.

> **Nutanix note.** HPA and VPA are core/standard Kubernetes and behave identically on **NKE** — this lab is `kind` only because it needs no cloud features. The one thing that changes on-prem is *what backs the scaling*: HPA adds Pods, and if the cluster runs out of node capacity those Pods sit `Pending` until a node appears. On Nutanix that means pairing this with node auto-provisioning (Karpenter-style, or NKE node pools) so horizontal scaling has somewhere to land. VPA's in-place resize is especially valuable on fixed on-prem capacity, where right-sizing requests reclaims stranded headroom without disruptive restarts.

---

## The idea in 60 seconds

Two different axes of autoscaling:

- **HPA** scales **out** — more replicas — when a per-Pod metric (here CPU utilisation) crosses a target. Its `behavior` block lets you make scale-up and scale-down *asymmetric*: jump up fast to absorb a spike, but come down slowly and in steps so you don't thrash.
- **VPA** scales **up** — bigger requests/limits on the *same* Pod — based on observed usage. Its modern `InPlaceOrRecreate` mode resizes a live container instead of evicting it.

Both need a metrics source (`metrics-server`). And you keep them apart: if HPA and VPA both act on CPU for one workload, they chase each other's tails.

![Architecture diagram](artifacts/lab-20/diagrams/diagram.png)

---

## Step 1 — Create the cluster and install metrics-server

**Goal:** get a cluster that actually reports CPU/memory numbers — nothing autoscales without them.

```bash
kind create cluster --name autoscale-lab

kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl wait --for=condition=Available --timeout=120s -n kube-system deployment/metrics-server
kubectl top nodes
```

**What you should see:** `kubectl top nodes` returns real CPU/memory numbers (not an error) — metrics-server is reporting.

**What this means:** the autoscalers now have data to act on. `--kubelet-insecure-tls` is the standard `kind` accommodation (the kubelet's serving cert isn't signed for what metrics-server verifies by default); it's not a real security compromise on localhost.

> ⚠️ **Gotcha — cloud provisioning silently steals your kubectl context.** If you also have a GKE/EKS/AKS cluster creating in another terminal, `gcloud container clusters create` (and equivalents) **switch your `kubectl` current-context** to the new cluster the moment it finishes — even in the background. We hit exactly this: commands started hitting the wrong cluster until `kubectl config current-context` gave it away. Check your context before any command whose blast radius matters.

---

## Step 2 — Advanced HPA: fast up, slow down

**Goal:** make an HPA that absorbs a spike instantly but refuses to thrash on the way down.

**1. Deploy a CPU-bound app:**

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: php-apache}
spec:
  replicas: 1
  selector: {matchLabels: {run: php-apache}}
  template:
    metadata: {labels: {run: php-apache}}
    spec:
      containers:
      - name: php-apache
        image: registry.k8s.io/hpa-example
        ports: [{containerPort: 80}]
        resources:
          requests: {cpu: 200m, memory: 64Mi}
          limits: {cpu: 500m, memory: 128Mi}
---
apiVersion: v1
kind: Service
metadata: {name: php-apache}
spec:
  ports: [{port: 80}]
  selector: {run: php-apache}
EOF
kubectl wait --for=condition=Available --timeout=90s deployment/php-apache
```

**2. Apply the HPA with asymmetric `behavior`** — scale up instantly (`stabilizationWindowSeconds: 0`, up to +100%/15s), scale down slowly (60s window, then only −50%/30s):

```bash
kubectl apply -f - <<'EOF'
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: {name: php-apache-hpa}
spec:
  scaleTargetRef: {apiVersion: apps/v1, kind: Deployment, name: php-apache}
  minReplicas: 1
  maxReplicas: 6
  metrics:
  - type: Resource
    resource: {name: cpu, target: {type: Utilization, averageUtilization: 50}}
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - {type: Percent, value: 100, periodSeconds: 15}
      - {type: Pods, value: 2, periodSeconds: 15}
      selectPolicy: Max
    scaleDown:
      stabilizationWindowSeconds: 60
      policies:
      - {type: Percent, value: 50, periodSeconds: 30}
      selectPolicy: Min
EOF
kubectl get hpa php-apache-hpa
```

**What you should see:** a baseline of **1 replica** at low CPU (well under the 50% target).

![HPA baseline: 1 replica, cpu 8%/50%](artifacts/lab-20/screenshots/01-hpa-initial.png)

**3. Generate load and watch it climb:**

```bash
kubectl run load-generator --image=busybox --restart=Never -- \
  /bin/sh -c "while true; do wget -q -O- http://php-apache; done"
watch kubectl get hpa php-apache-hpa
```

**What you should see:** CPU shoots past target and the HPA scales **1 → 6 within about 90 seconds** — the aggressive `Percent 100/15s` + `Pods 2/15s` policies (whichever is bigger, `selectPolicy: Max`) let it climb fast.

![Under load: CPU ~250%, HPA drives replicas up to 6](artifacts/lab-20/screenshots/02-hpa-scaleup.png)

| Time | CPU | Replicas |
|---|---|---|
| t+20s | 121%/50% | 1 |
| t+40s | 153%/50% | 3 |
| t+60s | 85%/50% | 6 |

**4. Remove the load and watch the *controlled* descent:**

```bash
kubectl delete pod load-generator
watch kubectl get hpa php-apache-hpa
```

**What you should see:** CPU drops to 0% almost instantly, but replicas **hold at 6 for a full 60 seconds** (the stabilization window), then step down `6 → 3 → 1` in 50% increments — never collapsing straight to `minReplicas`.

![Scale-down: CPU 0% but replicas hold, then step 6→3→1](artifacts/lab-20/screenshots/03-hpa-scaledown.png)

| Time since load removed | CPU | Replicas |
|---|---|---|
| t+0s | 61%/50% | 6 |
| t+20s | 0%/50% | 6 (inside the 60s window — no action despite 0% CPU) |
| t+80s | 0%/50% | 3 (window expired; −50% step) |
| t+100s | 0%/50% | 1 (second −50% step) |

**What this means:** this asymmetry is the whole point. Scale-up is instant so users don't feel a spike; scale-down is deliberate so a momentary lull doesn't tear down capacity you'll need again seconds later. Full data: [`artifacts/lab-20/evidence/lab-F-advanced-hpa-behavior.txt`](artifacts/lab-20/evidence/lab-F-advanced-hpa-behavior.txt).

---

## Step 3 — VPA: right-size from real usage, then resize live

**Goal:** let the VPA recommend correct requests for an under-provisioned app, then apply them to a running Pod with no restart.

**1. Deploy a deliberately under-provisioned app** (asks for 100m CPU but burns a whole core) — on a *separate* Deployment from the HPA, so they don't fight:

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: vpa-demo}
spec:
  replicas: 2
  selector: {matchLabels: {app: vpa-demo}}
  template:
    metadata: {labels: {app: vpa-demo}}
    spec:
      containers:
      - name: stress
        image: polinux/stress
        resources:
          requests: {cpu: 100m, memory: 50Mi}
          limits: {cpu: 200m, memory: 100Mi}
        command: ["stress"]
        args: ["--cpu", "1", "--timeout", "999999s"]
EOF
kubectl wait --for=condition=Available --timeout=90s deployment/vpa-demo
```

**2. Install the VPA** from the canonical in-tree chart:

```bash
git clone --depth 1 https://github.com/kubernetes/autoscaler.git /tmp/autoscaler-repo
helm install vpa /tmp/autoscaler-repo/vertical-pod-autoscaler/charts/vertical-pod-autoscaler -n kube-system
kubectl wait --for=condition=Ready pod -n kube-system -l app.kubernetes.io/instance=vpa --timeout=120s
```

> ⚠️ **Gotcha — don't use `hack/vpa-up.sh` on a shallow clone.** That other "official" installer fails with `fatal: invalid reference: vertical-pod-autoscaler-1.7.1` on a `--depth 1` clone, because it resolves an image tag from a git tag the shallow clone doesn't have. The in-repo Helm chart above avoids this.

**3. Start in recommendation-only mode** (`updateMode: "Off"` — observe, don't act):

```bash
kubectl apply -f - <<'EOF'
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata: {name: vpa-demo}
spec:
  targetRef: {apiVersion: apps/v1, kind: Deployment, name: vpa-demo}
  updatePolicy: {updateMode: "Off"}
EOF
# ...wait several minutes for it to build a usage history...
kubectl describe vpa vpa-demo
```

**What you should see:** a recommendation targeting roughly **cpu=247m, memory=250Mi** — about 2.5× the CPU and 5× the memory originally requested, derived purely from observed usage.

![VPA recommendation: target cpu=247m, memory=250Mi](artifacts/lab-20/screenshots/04-vpa-recommendation.png)

```
Recommendation:
  Container Name:  stress
  Lower Bound:   cpu=170m    memory=250Mi
  Target:        cpu=247m    memory=250Mi
  Upper Bound:   cpu=50460m  memory=2349382352
```

**4. Switch to `InPlaceOrRecreate` and watch a live resize.** First record the *before* requests:

```bash
kubectl patch vpa vpa-demo --type=merge -p '{"spec":{"updatePolicy":{"updateMode":"InPlaceOrRecreate"}}}'
kubectl get pods -l app=vpa-demo -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.spec.containers[0].resources.requests}{"\n"}{end}'
```

![Before resize: both pods request cpu=100m, memory=50Mi](artifacts/lab-20/screenshots/05-before-resize.png)

Wait ~1 minute for the updater's loop, then check again:

```bash
kubectl get pods -l app=vpa-demo
kubectl get pods -l app=vpa-demo -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.spec.containers[0].resources.requests}{"\n"}{end}'
```

**What you should see:** the **same Pod names**, **`RESTARTS: 0`**, but requests now `cpu=587m, memory=250Mi` — the resources changed underneath live, running containers.

![After resize: same pods, RESTARTS 0, requests now cpu=587m memory=250Mi](artifacts/lab-20/screenshots/06-after-resize.png)

```
NAME                        READY   STATUS    RESTARTS   AGE
vpa-demo-54ddbf7868-9rqhm   1/1     Running   0          5m14s
vpa-demo-54ddbf7868-jl265   1/1     Running   0          5m14s
# requests: {"cpu":"587m","memory":"250Mi"}  (both pods)
```

**What this means:** `InPlaceOrRecreate` isn't a rename of the deprecated `Auto` mode — it uses the `/resize` subresource to change a running container's resources with **zero disruption**, only falling back to evict-and-recreate when a live resize isn't possible. (The applied 587m is higher than the earlier 247m target because the `stress` load kept running, so the recommender's target kept climbing — expected, not a discrepancy.) The updater log confirms `In-place patched pod /resize subresource` and an `InPlaceResizedByVPA` event. Full data: [`artifacts/lab-20/evidence/lab-F-vpa-recommendation.txt`](artifacts/lab-20/evidence/lab-F-vpa-recommendation.txt), [`artifacts/lab-20/evidence/lab-F-vpa-inplace-resize.txt`](artifacts/lab-20/evidence/lab-F-vpa-inplace-resize.txt).

**5. (Optional) see the VPA object in a GUI** — [Headlamp](https://headlamp.dev/) → Configuration → VPAs shows the same object live:

![Headlamp showing the vpa-demo object, Provided: True](artifacts/lab-20/screenshots/07-headlamp-vpa.png)

---

## Step 4 — Clean up

```bash
kind delete cluster --name autoscale-lab
```

![Cluster deleted, no kind clusters remain](artifacts/lab-20/screenshots/08-cleanup.png)

---

## What you learned

| You saw… | in Step | proof |
|---|---|---|
| HPA scale-up can be tuned fast and aggressive | 2 | 1 → 6 replicas in ~90s |
| HPA scale-down uses a stabilization window + steps | 2 | held 60s, then 6→3→1 |
| VPA recommends right-sized requests from real usage | 3 | cpu 100m→247m, mem 50Mi→250Mi |
| VPA `InPlaceOrRecreate` resizes a live Pod, no restart | 3 | same pods, `RESTARTS: 0`, requests changed |
| HPA and VPA are kept on separate workloads | 3 | different Deployments, no metric conflict |

## Evidence

Real screenshots for this lab are in [`artifacts/lab-20/screenshots/`](artifacts/lab-20/screenshots/) (8 images), and command transcripts are in [`artifacts/lab-20/evidence/`](artifacts/lab-20/evidence/).

---

---

**Next:** [Lab 21 — Watch Inference Latency Spike, Then Scale It Away (Inference Autoscaling Signals)](lab-21-inference-autoscaling.docx)
