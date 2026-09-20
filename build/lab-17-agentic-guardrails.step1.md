# Lab 17 — Let an AI Agent Read the Cluster but Never Change It (Guardrailed Agentic Kubernetes)

**Day 5 · Kubernetes as the AI-Native Platform**

> ✅ **Tested end-to-end** on a **real GKE cluster** (`advk8s-lab`) using native **ValidatingAdmissionPolicy** (GA). Every screenshot is a real capture. The payoff: an "agent" identity that RBAC *would* let mutate the cluster has every write **denied and audited** by an admission-time guardrail — while its reads keep working normally.

## What you'll learn

- Why giving an AI agent a `kubectl` credential is risky: an over-broad (or compromised) agent can delete, scale, or reconfigure things.
- How to build a guardrail that is **independent of the agent's RBAC** — a `ValidatingAdmissionPolicy` that denies *mutations* from the agent's identity at admission time, and **audits** the attempt.
- Why admission-time policy is the right layer for this: it catches the action regardless of how the agent got its permissions.

## What you'll do

You'll create an agent ServiceAccount with *deliberately over-broad* RBAC (it can read and write), then add a ValidatingAdmissionPolicy that denies any create/update/delete from that identity. You'll confirm the agent still reads fine, but every mutation is denied and logged — and that normal admins are unaffected.

## Time & cost

- **Time:** ~30 minutes.
- **Cost:** negligible — a ServiceAccount, a policy, and one small Deployment.

---

## Before you start

- **Where you'll work:** in a **terminal** with `kubectl` pointed at a GKE cluster (Kubernetes 1.30+ for ValidatingAdmissionPolicy).
- **Tools you need:** `gcloud`, `kubectl`.
- **Cluster:** a GKE cluster (this course's shared `advk8s-lab`).

> **Nutanix note.** As teams wire LLM agents and autonomous operators into their clusters, the question "what can this agent actually do?" becomes a real security control. On **NKE** you'd apply exactly this pattern: `ValidatingAdmissionPolicy` is **built into Kubernetes** (no external controller like Kyverno/OPA needed), so it's the lightest way to put an identity-scoped, audited guardrail on agent actions on-prem. The key idea — enforce at *admission* on the *identity*, not only via RBAC — means the guardrail holds even if someone later widens the agent's RBAC or its token leaks.

---

## The idea in 60 seconds

RBAC decides *whether an identity is allowed* to do something. But RBAC is easy to over-grant ("just give the agent edit so it stops erroring"), and a leaked agent token inherits whatever RBAC the agent had. A **ValidatingAdmissionPolicy (VAP)** adds a second, independent gate: after authz, the API server evaluates a CEL policy against the request — including **who** is making it (`request.userInfo`) — and can **deny** it, **audit** it, or both.

So even if the agent's RBAC says "yes, you may delete," the VAP says "not from *this* identity" — and records the attempt.

![Architecture diagram](artifacts/lab-17/diagrams/diagram.png)

---

## Step 1 — Create an (over-permissioned) agent identity

**Goal:** give the agent a ServiceAccount whose RBAC allows *both* reads and writes — the realistic "we granted it too much" starting point.

```bash
kubectl create namespace agent-workspace
kubectl -n agent-workspace create serviceaccount k8s-agent

kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: {name: agent-role, namespace: agent-workspace}
rules:
- apiGroups: [""]
  resources: ["pods","configmaps","services"]
  verbs: ["get","list","watch","create","update","patch","delete"]   # <-- includes writes
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get","list","watch","create","update","patch","delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {name: agent-binding, namespace: agent-workspace}
subjects:
- {kind: ServiceAccount, name: k8s-agent, namespace: agent-workspace}
roleRef: {kind: Role, name: agent-role, apiGroup: rbac.authorization.k8s.io}
EOF

kubectl -n agent-workspace create deployment web --image=nginx:1.27-alpine

# confirm RBAC really would allow both:
kubectl auth can-i list pods        --as=system:serviceaccount:agent-workspace:k8s-agent -n agent-workspace
kubectl auth can-i delete deployments --as=system:serviceaccount:agent-workspace:k8s-agent -n agent-workspace
```

**What you should see:** both `auth can-i` checks return **`yes`** — the agent can read *and* write, and it reads a demo Deployment fine.

![Agent RBAC allows list (yes) and delete (yes); agent reads deploy/pods](artifacts/lab-17/screenshots/01-reads-allowed.png)

**What this means:** this is the danger. With this RBAC alone, an agent that decides (or is tricked into deciding) to `delete deployment web` would succeed. RBAC is not enough of a guardrail here.

---

## Step 2 — Add an identity-scoped guardrail

**Goal:** deny *mutations* from the agent identity at admission, and audit them — regardless of RBAC.

```bash
kubectl apply -f - <<'EOF'
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata: {name: agent-readonly-guardrail}
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
    - apiGroups: ["", "apps"]
      apiVersions: ["*"]
      operations: ["CREATE","UPDATE","DELETE"]     # only mutating verbs
      resources: ["*"]
  matchConditions:
    - name: only-the-agent
      expression: "request.userInfo.username == 'system:serviceaccount:agent-workspace:k8s-agent'"
  validations:
    - expression: "false"                          # anything reaching here is denied
      message: "Guardrail: the k8s-agent identity is read-only. Mutation denied and audited."
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata: {name: agent-readonly-guardrail-binding}
spec:
  policyName: agent-readonly-guardrail
  validationActions: ["Deny","Audit"]              # deny AND record it in the audit log
EOF
```

**What this means:** the policy only *evaluates* requests where the user is the agent **and** the verb is mutating (`matchConditions` + `operations`). For those, the validation is hard-coded `false`, so they're denied — and `validationActions: ["Deny","Audit"]` means each denied attempt is also written to the API audit log.

---

## Step 3 — Prove reads work, mutations are denied and logged

**Goal:** confirm the guardrail blocks the agent's writes (with a clear reason) but not its reads or anyone else's writes.

```bash
AGENT=system:serviceaccount:agent-workspace:k8s-agent
kubectl get validatingadmissionpolicybinding agent-readonly-guardrail-binding -o jsonpath='{.spec.validationActions}'; echo

# a mutation RBAC allows — but the guardrail denies:
kubectl --as=$AGENT -n agent-workspace delete deployment web
kubectl --as=$AGENT -n agent-workspace create configmap x --from-literal=a=b

# a normal admin is unaffected:
kubectl -n agent-workspace label deployment web tier=frontend --overwrite
```

**What you should see:** the binding reports `["Deny","Audit"]`; both agent mutations are **denied** with `ValidatingAdmissionPolicy 'agent-readonly-guardrail' … denied request: Guardrail: the k8s-agent identity is read-only. Mutation denied and audited.`; and the admin's `label` succeeds.

![Guardrail denies agent delete and create (denied + audited); admin write still works](artifacts/lab-17/screenshots/02-mutation-denied.png)

**What this means:** the guardrail stopped the agent's writes **even though RBAC allowed them** — the exact defence-in-depth you want around an autonomous identity. The denial carries a human-readable reason (useful to feed back to the agent), and the `Audit` action means every attempt is logged for review. The scoping is precise: reads and other users are untouched.

> ⚠️ **Gotcha — RBAC-only "read-only" is fragile for agents.** It's tempting to just give the agent a view-only Role and call it done. But agent RBAC drifts (someone widens it to fix an error), and a leaked token inherits whatever RBAC exists at that moment. An admission-time guardrail keyed on the *identity* holds regardless — it's the difference between "we hope its RBAC stays narrow" and "its writes are structurally refused." Keep both: least-privilege RBAC *and* the guardrail.

---

## Step 4 — Clean up

```bash
kubectl delete validatingadmissionpolicybinding agent-readonly-guardrail-binding --ignore-not-found
kubectl delete validatingadmissionpolicy agent-readonly-guardrail --ignore-not-found
kubectl delete namespace agent-workspace --ignore-not-found
```

---

## What you learned

| You saw… | in Step | proof |
|---|---|---|
| An agent's RBAC can be over-broad (reads *and* writes) | 1 | `can-i delete deployments` → `yes` |
| A VAP guardrail denies mutations from the agent identity | 3 | delete/create → `denied request: Guardrail …` |
| Denials are audited, not just blocked | 2–3 | binding `validationActions: ["Deny","Audit"]` |
| Reads and other users are unaffected | 1,3 | agent `get` works; admin `label` succeeds |

## Evidence

Real screenshots for this lab are in [`artifacts/lab-17/screenshots/`](artifacts/lab-17/screenshots/) (2 images), and a command transcript is in [`artifacts/lab-17/evidence/lab-17-agentic-guardrails.txt`](artifacts/lab-17/evidence/lab-17-agentic-guardrails.txt).

---

**Next:** [Lab 18 — Capstone: Production War-Room](lab-18-capstone.md)
