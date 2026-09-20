
**Day 2 · Extending and Operating the Platform Under Pressure**

> YES — **Tested end-to-end** on a real 3-node `kind` cluster running **Cilium 1.20.1** as its CNI (kube-proxy fully replaced) with **Hubble** enabled. Every screenshot is a real capture. The insight you'll reach: the fix for a blocked flow isn't editing the policy — it's changing the client's **labels**, which gives it a new Cilium **identity** (you'll watch it flip from `ID:1609` to `ID:18439`), and the verdict changes the instant that identity propagates.

## What you'll learn

- Why Cilium's network policy is **identity-based**, not IP-based: every Pod gets a numeric security **identity** from its labels, and policy is evaluated on identities — so rules keep working as Pods churn and IPs change.
- How to install Cilium as the CNI (replacing kube-proxy) and turn on **Hubble** for flow-level observability.
- How to read a `DROPPED` flow in Hubble and trace it to the exact verdict (`Policy denied`).
- The non-obvious fix — change the client's identity (labels) to match the policy — and the propagation delay to expect.

## What you'll do

You'll build a Cilium cluster, deploy a client and a backend, and watch normal traffic flow in Hubble. Then you'll apply a policy that blocks the client, trace the drop in Hubble, and fix it by changing the client's identity — watching the verdict flip from `DROPPED` back to `FORWARDED`.

## Time & cost

- **Time:** ~50 minutes.
- **Cost:** **$0** — runs on a local `kind` cluster.

---

## Before you start

- **Where you'll work:** in a **terminal** on your own machine. **One step needs a second terminal tab** (for Hubble's live feed).
- **Tools you need:** `docker`, `kind`, `kubectl`, the **`cilium`** CLI, and the **`hubble`** CLI — install the last two with `brew install cilium-cli hubble`.
- **⚠️ This lab uses its own dedicated `kind` cluster** (Cilium needs to *be* the CNI), separate from the Day-2 GKE cluster.

> **Nutanix note — and why this one is `kind`, not GKE.** Installing **upstream** Cilium and opening Hubble requires control of the cluster's CNI, which managed GKE doesn't give you (its CNI is fixed; GKE Dataplane V2 is Google's own locked-down Cilium with no upstream Hubble CLI/UI). So this lab runs on `kind`, where you own the datapath. On **Nutanix**, NKE lets you run Cilium as the CNI (or install it yourself), so everything here — identity-based policy, `hubble observe`, the drop/forward verdicts — transfers directly to NKE; only the cluster-creation step differs.

---

## The idea in 60 seconds

Cilium is an **eBPF-based CNI** that programs the Linux datapath directly and can fully replace kube-proxy. Its key idea for this lab is **identity**: Cilium doesn't write policy in terms of Pod IPs (which are ephemeral) — it gives every Pod a numeric **security identity** derived from its labels, and evaluates policy identity-to-identity. Change a Pod's labels and it gets a *new* identity.

**Hubble** is Cilium's observability layer: because Cilium already sees every packet, Hubble exports a live **flow log** — source identity, destination identity, port, and the **verdict** (`FORWARDED` / `DROPPED`) with a reason. That's what turns "my connection hangs" into "identity 1609 was denied by policy reaching backend:80."

![Architecture diagram](artifacts/lab-07/diagrams/diagram.png)

---

## Step 1 — Build a Cilium cluster and enable Hubble

**Goal:** create a `kind` cluster with no CNI, install Cilium (which becomes the CNI *and* replaces kube-proxy), and turn on Hubble.

**1. Create a cluster with the default CNI and kube-proxy disabled:**

```bash
cat > cilium-kind.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: cilium-lab
networking:
  disableDefaultCNI: true
  kubeProxyMode: none
nodes:
  - role: control-plane
  - role: worker
  - role: worker
EOF

kind create cluster --config cilium-kind.yaml
# the nodes will be NotReady until a CNI exists — that's expected
```

**2. Install Cilium with Hubble, and wait for it to come up:**

```bash
cilium install --set hubble.relay.enabled=true
cilium status --wait
```

**What you should see:** Cilium's image is large, so its Pods sit in `Init` for a minute or two while it downloads. Then `cilium status` reports `Cilium: OK`, `Operator: OK`, `Hubble Relay: OK`, all Pods "managed by Cilium," and the nodes flip from `NotReady` to `Ready`.

![Cilium OK, kube-proxy replaced, nodes Ready](artifacts/lab-07/screenshots/01-cilium-status.png)

**What this means:** Cilium is now the cluster's datapath — it provides Pod networking *and* service routing (it detected kube-proxy was absent and took over). Hubble is ready to show you flows.

---

## Step 2 — See what a *healthy* request looks like

**Goal:** before blocking anything, watch normal traffic so you know what "good" looks like in Hubble.

**1. Deploy a backend and a client:**

```bash
kubectl create deployment backend --image=nginx:1.27
kubectl expose deployment backend --port=80
kubectl run client --image=curlimages/curl --restart=Never -- sleep 3600
kubectl wait --for=condition=Ready pod/client --timeout=90s
```

**2. Open Hubble's live flow feed — leave this running in a *second* terminal tab:**

```bash
cilium hubble port-forward
```

**3. Back in your first terminal, send one request and look at the flow:**

```bash
kubectl exec client -- curl -s -o /dev/null -w "HTTP %{http_code}\n" http://backend
hubble observe --pod client --to-label app=backend --last 3
```

**What you should see:** `curl` prints **`HTTP 200`**, and Hubble prints three lines ending in **`FORWARDED`**, e.g. `default/client (ID:1609) -> default/backend:80 (ID:41353)`.

![Baseline: HTTP 200 and FORWARDED flows](artifacts/lab-07/screenshots/02-baseline-forwarded.png)

**What this means:** with no policy in place, Cilium forwards the client's packets. Note the identity numbers — client `ID:1609`, backend `ID:41353`. **Remember the client's number; it's about to change.**

---

## Step 3 — Apply a policy and trace the drop

**Goal:** apply a policy that only lets `role=frontend` reach the backend, and watch Hubble name the drop.

**1. Apply the policy, then try the request again:**

```bash
kubectl apply -f - <<'EOF'
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: backend-allow-frontend
spec:
  endpointSelector:
    matchLabels: {app: backend}
  ingress:
    - fromEndpoints:
        - matchLabels: {role: frontend}
EOF

kubectl exec client -- curl -s -o /dev/null -w "HTTP %{http_code}\n" --max-time 5 http://backend
hubble observe --pod client --verdict DROPPED --last 4
```

**What you should see:** `curl` now **times out (exit 28)** — the connection never establishes — and Hubble shows exactly why: `default/client (ID:1609) <> default/backend:80 (ID:41353)` **`Policy denied DROPPED (TCP Flags: SYN)`**.

![The request is DROPPED; Hubble names the verdict](artifacts/lab-07/screenshots/03-policy-dropped.png)

**What this means:** the client's `SYN` packets are dropped by the datapath before they reach the backend. This is the diagnosis Hubble gives you that plain `kubectl` never will — not "it's slow," but "identity 1609 is denied by policy."

> **The key mental model:** once *any* `CiliumNetworkPolicy` selects an endpoint (here `backend`), that endpoint switches to **default-deny** for the direction the policy covers. So this one rule didn't just "allow frontend" — it simultaneously *denied everything else*, which is why the previously-working client is now dropped.

---

## Step 4 — Fix it by changing the client's identity

**Goal:** give the client the identity the policy already trusts (`role=frontend`), and watch the verdict flip.

**1. Label the client, wait for the new identity to propagate, then retry:**

```bash
kubectl label pod client role=frontend --overwrite
sleep 12                                   # let the new identity propagate
kubectl exec client -- curl -s -o /dev/null -w "HTTP %{http_code}\n" --max-time 5 http://backend
hubble observe --pod client --to-label app=backend --last 3
```

**What you should see:** `curl` returns **`HTTP 200`** again, Hubble shows **`FORWARDED`** — and the client's identity has **changed from `ID:1609` to `ID:18439`**.

![Relabelled client gets a new identity and is FORWARDED](artifacts/lab-07/screenshots/04-fixed-forwarded.png)

**What this means:** adding the `role=frontend` label gave the client a *new Cilium identity*, and that new identity matches the policy's `fromEndpoints`. The verdict flipped because the **identity** changed, not because the policy did. That's identity-based networking in one screenshot.

> ⚠️ **Gotcha — identity propagation isn't instant.** Immediately after `kubectl label`, the very next `curl` can still be `DROPPED` for a few seconds: the Pod's new identity has to be computed and pushed to every node's datapath. In our run it took ~10 seconds. If you test too quickly you'll wrongly conclude the fix failed — wait a moment, or watch `hubble observe` until you see the identity number change.

---

## Step 5 — Clean up

```bash
kind delete cluster --name cilium-lab
```

---

## What you learned

| You saw… | in Step | proof |
|---|---|---|
| Cilium can be the CNI *and* replace kube-proxy | 1 | `cilium status: OK`, nodes Ready, kube-proxy absent |
| Hubble shows per-flow verdicts with identities | 2 | `FORWARDED` flows, client `ID:1609` |
| One policy flips the selected endpoint to default-deny | 3 | previously-working client now `DROPPED` |
| A drop is traceable to `Policy denied` in Hubble | 3 | `Policy denied DROPPED (TCP Flags: SYN)` |
| Policy is identity-based; labels drive identity | 4 | client `ID:1609` → `ID:18439` on relabel, verdict flips |
| Identity propagation has a short delay | 4 gotcha |

## Evidence

Real screenshots for this lab are in [`artifacts/lab-07/screenshots/`](artifacts/lab-07/screenshots/) (4 images), and a full command transcript is in [`artifacts/lab-07/evidence/lab-07-cilium-hubble.txt`](artifacts/lab-07/evidence/lab-07-cilium-hubble.txt).

---

**Next:** [Lab B — Multi-Cluster Service Mesh with Istio](lab-B-multicluster-service-mesh.docx)
