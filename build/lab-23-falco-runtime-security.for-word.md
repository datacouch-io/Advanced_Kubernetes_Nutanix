
**Day 5 · Kubernetes as the AI-Native Platform**

> YES — **Tested end-to-end** on a real `kind` cluster. Every screenshot is a real capture of a genuine **kernel-level Falco alert** — not a simulated log line. The payoff: you'll read `/etc/shadow` inside a container, install a tool *after* it started, and read a decoy file — and watch Falco fire a precise, context-rich alert on each, including one your own custom rule catches.

## What you'll learn

- What Falco actually watches — **kernel syscalls via eBPF** — and why that catches things happening *inside a running container*, which admission control (Lab C's Kyverno) structurally cannot see.
- How to read a real Falco alert: process, parent, command line, container, image, and Kubernetes pod/namespace, all in one line.
- How to write and deploy your own detection rule.

## What you'll do

You'll install Falco with its modern eBPF driver, trigger two built-in detections (sensitive-file read; a binary installed and run after startup), then write a custom "canary file" rule and trigger it.

## Time & cost

- **Time:** ~40 minutes.
- **Cost:** **$0** — runs entirely on a local `kind` cluster.

---

## Before you start

- **Where you'll work:** in a **terminal** on your own machine.
- **Tools you need:** `docker`, `kind`, `kubectl`, `helm`.
- **Cluster:** you'll create a fresh `kind` cluster in Step 1.
- **Feasibility note:** Falco hooks kernel syscalls, which sounds like it wouldn't work inside a container on Docker Desktop's virtualised Linux. It does — this was fully verified on Docker Desktop for Mac (Apple Silicon) using the `modern_ebpf` driver, with real detections of real events. On native Linux it works at least as well.

> **Nutanix note.** Falco is CNCF-graduated and completely platform-agnostic — it runs the same on **NKE**. Runtime security is arguably *more* important on-prem, where you own the whole stack: Falco gives you kernel-level visibility into what containers actually do on your Nutanix nodes, feeding the same alerts into your SIEM. This lab is `kind` only because it needs no cloud features; the install and rules are identical on a Nutanix cluster.

---

## The idea in 60 seconds

Lab C's Kyverno is an **admission controller**: it inspects a Pod *spec* once, before the Pod exists, and can only reason about what's declared. It has no idea what the container *does* once running.

**Falco** is **runtime security**. It taps the kernel via eBPF and watches actual syscalls — file opens, process launches, network connections — as they happen. That catches things no spec could predict: a container reading `/etc/shadow`, a binary installed and executed *after* startup, a shell spawned in a stateless web server. The two layers are complementary: admission control stops bad *configuration*; Falco catches bad *behaviour* in configurations that looked fine at admission time.

![Architecture diagram](artifacts/lab-23/diagrams/diagram.png)

---

## Step 1 — Install Falco with the eBPF driver

**Goal:** get Falco watching syscalls on the node.

```bash
kind create cluster --name falco-lab

helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update
helm install falco falcosecurity/falco \
  --namespace falco --create-namespace \
  --set driver.kind=modern_ebpf \
  --set tty=true
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=falco -n falco --timeout=120s
kubectl get pods -n falco
```

**What you should see:** the `falco` Pod `Running`. You may see startup warnings about `failed to determine tracepoint … creat` / `TOCTOU mitigation` — these are **expected and non-fatal**; Falco names exactly what's degraded (a race-condition mitigation for two syscalls) and confirms detection itself is unaffected.

**What this means:** `driver.kind=modern_ebpf` is the CO-RE (Compile Once, Run Everywhere) probe — it needs no matching kernel headers, which is what makes Falco viable inside a `kind` node on a virtualised kernel. Falco is now watching every syscall on the node.

---

## Step 2 — Trigger a built-in detection: reading a sensitive file

**Goal:** do something that looks like post-compromise reconnaissance and watch Falco catch it.

```bash
kubectl run alpine-test --image=alpine:3.20 --restart=Never -- sleep 3600
kubectl wait --for=condition=Ready pod/alpine-test --timeout=60s

kubectl exec alpine-test -- cat /etc/shadow
```

![Triggering the read of /etc/shadow inside the container](artifacts/lab-23/screenshots/01-sensitive-file-trigger.png)

Now read Falco's log:

```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco --tail=20
```

**What you should see:** a `Warning` alert — **`Sensitive file opened for reading by non-trusted program`** — naming `file=/etc/shadow`, `process=cat`, its parent, the full command, the container, image, and the Kubernetes pod/namespace.

![Falco alert: sensitive file opened for reading, with full context](artifacts/lab-23/screenshots/02-sensitive-file-alert.png)

```
Warning Sensitive file opened for reading by non-trusted program | file=/etc/shadow
  process=cat parent=sh command=cat /etc/shadow container_name=alpine-test
  container_image_repository=docker.io/library/alpine k8s_pod_name=alpine-test k8s_ns_name=default
```

**What this means:** one alert carries everything you need to act — which file, which process, its parent, the exact command, the container/image, and the pod/namespace — no cross-referencing three systems.

---

## Step 3 — Trigger a built-in detection: runtime tampering

**Goal:** install and run a tool *after* the container started — the exact move an attacker makes for a foothold — and see why Falco flags it.

```bash
kubectl exec alpine-test -- sh -c "apk add --no-cache netcat-openbsd; nc -h"
```

![Installing netcat live into the already-running container](artifacts/lab-23/screenshots/03-runtime-install-trigger.png)

```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco --tail=30 | grep -i "not part of base"
```

**What you should see:** a `Critical` alert — **`Executing binary not part of base image`** — with `exe_flags=EXE_WRITABLE|EXE_UPPER_LAYER`.

![Falco Critical: executing binary not part of base image, EXE_WRITABLE|EXE_UPPER_LAYER](artifacts/lab-23/screenshots/04-runtime-tampering-alert.png)

```
Critical Executing binary not part of base image | proc_exe=nc
  exe_flags=EXE_WRITABLE|EXE_UPPER_LAYER command=nc -h
  container_name=alpine-test container_image_repository=docker.io/library/alpine
```

**What this means:** `alpine:3.20` doesn't ship `netcat-openbsd` — we installed it live. The flags say *why* it's suspicious: the binary lives in the container's **writable overlay layer**, not the read-only image layer. A well-built image's processes never need this; an attacker planting a reverse shell or scanner very often does. **Lab C's image scan structurally cannot catch this** — the scan runs against the image; this behaviour only exists once the container is a running, mutated instance.

---

## Step 4 — Write your own detection rule

**Goal:** add a workload-specific rule — a decoy ("canary") file nothing legitimate should ever read.

```bash
cat > /tmp/falco-custom-rules.yaml <<'EOF'
customRules:
  rules-custom.yaml: |-
    - rule: Canary File Accessed
      desc: Detect any read of our planted decoy file -- nothing legitimate should ever touch it
      condition: >
        open_read and container and fd.name = "/etc/canary-do-not-read.txt"
      output: >
        Canary file was read (user=%user.name command=%proc.cmdline
        container=%container.name image=%container.image.repository)
      priority: CRITICAL
      tags: [container, canary, mitre_discovery]
EOF

helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --set driver.kind=modern_ebpf --set tty=true \
  -f /tmp/falco-custom-rules.yaml
kubectl rollout status daemonset/falco -n falco --timeout=90s
```

Trigger it:

```bash
kubectl exec alpine-test -- sh -c "echo secret > /etc/canary-do-not-read.txt"
kubectl exec alpine-test -- cat /etc/canary-do-not-read.txt
kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco --tail=10
```

![Falco Critical: canary file was read (custom rule fired)](artifacts/lab-23/screenshots/06-canary-alert.png)

**What you should see:** a `Critical` alert from *your* rule — **`Canary file was read`** — with the user, command, container, and image.

```
Critical Canary file was read (user=root command=cat /etc/canary-do-not-read.txt
  container_name=alpine-test image=docker.io/library/alpine)
```

**What this means:** built-in rules are general-purpose; real deployments add high-signal rules for what a *specific* workload should never do. A canary file is one of the highest-signal, lowest-noise detections you can add.

> ⚠️ **Gotcha — a rule that loads cleanly can still silently never fire.** An earlier version of this rule matched process execution (`spawned_process and container and proc.name = "nc"`). It loaded with `schema validation: ok` but **never fired**, even though the same `nc` run was independently caught by the built-in rule in Step 3. Rephrasing it around a different event class (`open_read` / `fd.name`, as above) worked immediately. **If your custom rule loads fine but never triggers, restructure the condition around a different event type before assuming your YAML syntax is broken.** Full evidence (including the failed attempt): [`artifacts/lab-23/evidence/lab-E-falco-runtime-security.txt`](artifacts/lab-23/evidence/lab-E-falco-runtime-security.txt).

---

## Step 5 — Clean up

```bash
kind delete cluster --name falco-lab
```

---

## What you learned

| You saw… | in Step | proof |
|---|---|---|
| Falco watches live syscalls, not just specs | 1 | eBPF probe running on the node |
| A built-in rule catches a sensitive-file read | 2 | `Sensitive file opened … /etc/shadow` |
| A built-in rule catches a binary added after startup | 3 | `not part of base image`, `EXE_WRITABLE\|EXE_UPPER_LAYER` |
| A custom rule catches workload-specific behaviour | 4 | `Canary file was read` from your rule |

## Evidence

Real screenshots for this lab are in [`artifacts/lab-23/screenshots/`](artifacts/lab-23/screenshots/) (7 images), and a command transcript is in [`artifacts/lab-23/evidence/lab-E-falco-runtime-security.txt`](artifacts/lab-23/evidence/lab-E-falco-runtime-security.txt).

---

---

**Next:** [Lab 24 — Let an AI Agent Read the Cluster but Never Change It (Guardrailed Agentic Kubernetes)](lab-24-agentic-guardrails.docx)
