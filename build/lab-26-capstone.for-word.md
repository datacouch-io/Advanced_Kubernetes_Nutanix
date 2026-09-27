
**Optional Additional Day · Control-Plane Internals & Production War-Room — Module 14**

> YES — **Built and verified end-to-end** on a 3-node `kind` cluster (Kubernetes 1.37.0, Kueue v0.14.2) on 2026-09-25. Every symptom, message and number below was captured from that run. The six faults span **API pressure, etcd, an operator, scheduling, CoreDNS/NetworkPolicy and a Kueue-managed workload** — one from each major theme of the course.

## What you'll do

Your team inherits a cluster that is already broken. Nobody tells you how many things are wrong or where. You will triage it, establish evidence, fix what you find, and write a one-page postmortem — working the way a real incident demands rather than the way a lab usually allows.

**You are scored on method, not speed.** A team that fixes four faults with clean evidence and a clear decision log beats a team that fixes six by guessing.

## Time & cost

- **Time:** ~120 minutes — 15 triage, 75 diagnosis and repair, 15 verification, 15 postmortem.
- **Cost:** **$0** — runs on a local `kind` cluster.

---

## Before you start

- **Where you'll work:** a terminal, with your team. One person drives `kubectl`; everyone else reads.
- **Tools you need:** `docker`, `kind`, `kubectl`. `etcdctl` is reached inside the etcd container — you do not install it.
- **The cluster:** your instructor gives you a seeded `warroom` cluster. **Do not read the seed script.** It names every fault.
- **Prior labs:** this integrates Modules 2, 3, 4, 11, 12 and 13. You do not need to have run every one, but a team with nobody who has seen Hubble or `etcdctl` will struggle.

> **Nutanix note.** Every fault here is upstream Kubernetes behaviour and reproduces identically on NKE. Two differ in *consequence* on-prem: the etcd quota is yours to size rather than a managed service's, and there is no cloud autoscaler to absorb the scheduling fault while you diagnose it.

---

## The scenario

> **08:40.** Checkout is not deploying. The overnight revenue rollup has not run. A reporting job is "getting errors from Kubernetes." Someone tried to clean up an old ledger object yesterday and says the delete "hung."
>
> You have the cluster. You do not have the person who changed it.

Six fault domains are live. They are **not** independent: one of them, left alone, will stop you fixing any of the others.

---

## The method

Work this loop, out loud, for every fault:

**Observe → hypothesise → isolate → remediate → verify**

Three rules the scoring rewards:

1. **Establish evidence before you change anything.** A fix applied before the symptom is recorded is a fix you cannot prove worked — and cannot undo with confidence.
2. **One change at a time.** Two simultaneous fixes mean you learn nothing about either.
3. **Say what you are about to do before you do it.** The driver narrates; the team can object.

**Assign roles before you touch the keyboard:**

| Role | Owns |
|---|---|
| **Incident lead** | The order of work. Decides what gets fixed next and what gets left |
| **Driver** | The only person typing. Narrates every command before running it |
| **Scribe** | The decision log — time, what was observed, what was changed, what happened |
| **Comms** | A status line every 15 minutes, in business terms, that a manager could read aloud |

---

## Step 1 — Triage (15 min)

**Goal:** a written inventory of symptoms. **Fix nothing in this step.**

```bash
kubectl -n shop get pods
kubectl -n shop get deploy,job
kubectl -n shop get workloads
kubectl get nodes
kubectl get events -A --sort-by=.lastTimestamp | tail -30
```

**What you should see:** a mixed picture — some Pods Running, at least one Pending, a Job that is neither running nor failing, and a Deployment stuck mid-rollout.

**What this means.** Note that `kubectl get pods` does **not** show you three of the six faults. Two of them have no Pod at all, and one is a cluster-level condition with no object in this namespace. A triage that only lists unhealthy Pods will miss half of this incident.

![Triage by Pod alone: catalog, reporter and shopper Running, two checkout Pods Pending — three of the six faults are invisible here](../../artifacts/lab-26/screenshots/01-triage-pods.png)

![The same cluster beyond Pods: checkout stuck at 0/2, a Job reporting Suspended, and a Kueue Workload that was never admitted](../../artifacts/lab-26/screenshots/02-triage-beyond-pods.png)


> ⚠️ **Gotcha — events expire.** Default TTL is one hour. Capture what you need into your decision log now; a cluster that has been broken since last night has already lost its earliest evidence.

**Deliverable before moving on:** a list of distinct symptoms, each with the command that shows it.

---

## Step 2 — Find the one that blocks the others (10 min)

**Goal:** identify the fault that must be fixed first, and say why.

One of these six can stop every remediation you are about to attempt. Look at the control plane, not the workloads:

```bash
CID=$(docker exec warroom-control-plane crictl ps --name etcd -q | head -1)
docker exec warroom-control-plane crictl exec $CID etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint status --write-out=table
```

**What you should see:**

```
│ DB SIZE │ IN USE │ PERCENTAGE NOT IN USE │ QUOTA │
│  8.7 MB │ 7.8 MB │                   11% │ 17 MB │
```

**What this means.** The backend quota is **16.7 MB** — not the 2.1 GB default. Someone left a tuning experiment in the static pod manifest. The database is already over half of it, and every object you create while fixing the other five faults pushes it closer. When it arrives, etcd arms the `NOSPACE` alarm and **goes read-only**: no fix, no rollback, no `kubectl apply` will work until it is cleared.

**Remediate — reclaim the space before you do anything else:**

```bash
# compact history to the current revision, then defragment the file
REV=$(docker exec warroom-control-plane crictl exec $CID etcdctl ... endpoint status \
      --write-out=json | sed -n 's/.*"revision":\([0-9]*\).*/\1/p' | head -1)
docker exec warroom-control-plane crictl exec $CID etcdctl ... compact $REV
docker exec warroom-control-plane crictl exec $CID etcdctl ... defrag
```

**Verify — measured on the reference cluster:**

| | dbSize | in use | not in use |
|---|---|---|---|
| after `compact`, before `defrag` | 4.6 MB | 1.5 MB | **67%** |
| after `defrag` | **1.4 MB** | 1.4 MB | **1%** |

Defrag took **29.85 ms**. (An earlier reference run measured 5.8 MB → 1.4 MB, 53% → 1%, in 16.5 ms;
the exact figures depend on how much churn the seeder has accumulated.)

> ⚠️ **Gotcha — run `compact` first or `defrag` looks like it did nothing.** Straight after seeding,
> `endpoint status` reports close to **0% not in use**: the deleted ConfigMaps are still held as
> retained revisions, so they count as *in use*. Compaction is what turns them into free pages —
> only then does the 67% appear for `defrag` to reclaim.

![Compaction exposes the dead space and defrag reclaims it: 4.6 MB with 67% unused becomes 1.4 MB with 1%, in 29.85 ms](../../artifacts/lab-26/screenshots/03-etcd-compact-and-defrag.png)


> ⚠️ **Gotcha — compaction and defragmentation are not the same operation.** `compact` discards old
> revisions; it does **not** return disk to the filesystem. `defrag` is what shrinks the file, and it
> briefly blocks writes on the member it runs against. On a multi-member cluster, defrag one member
> at a time, never all at once.

**Also fix the cause, not just the symptom:** the `--quota-backend-bytes=16777216` line is still in
`/etc/kubernetes/manifests/etcd.yaml`. Decide as a team whether to raise it, and record the decision.

---

## Step 3 — The API server is refusing a client (15 min)

**Symptom:** the reporting workload logs errors.

```bash
kubectl -n shop logs -l app=reporter --tail=5
```

```
11:15:01 API REJECTED 429 Too Many Requests
11:15:01 API REJECTED 429 Too Many Requests
```

**Observe before hypothesising.** `429` is not "the API server is overloaded" — it is API Priority and Fairness refusing this *particular* flow. Everyone else is fine.

```bash
kubectl get --raw /debug/api_priority_and_fairness/dump_priority_levels
```

```
PriorityLevelName, ActiveQueues, IsIdle, ..., DispatchedRequests, RejectedRequests, ...
shop-reporting,    0,            true,   ..., 37734,              94345,            ...
```

**94,345 rejected against 37,734 dispatched.** Now find out why that lane is so narrow:

```bash
kubectl get flowschema shop-reporting -o jsonpath='{.spec.priorityLevelConfiguration.name}'
kubectl get prioritylevelconfiguration shop-reporting \
  -o jsonpath='shares={.spec.limited.nominalConcurrencyShares} response={.spec.limited.limitResponse.type}'
```

```
shop-reporting
shares=1 response=Reject
```

**What this means.** A FlowSchema routes this ServiceAccount into a priority level with **one** concurrency share and `limitResponse: Reject` — so anything beyond a single in-flight request is refused immediately rather than queued. The client is not misbehaving; the lane was built too narrow.

![The reporter logging 429s, and the priority-level dump showing 47,251 rejected against 22,187 dispatched for this one flow](../../artifacts/lab-26/screenshots/04-apf-rejecting-one-flow.png)

![The cause: the flow routes to a priority level with shares=1 and limitResponse=Reject](../../artifacts/lab-26/screenshots/05-the-lane-is-one-share-reject.png)


**Remediate.** Raise `nominalConcurrencyShares`, or change `limitResponse` to `Queue`, or remove the FlowSchema so the client falls back to `catch-all`. **Say which you chose and why** — they have different failure behaviour under real load, and the scoring cares about that reasoning more than the fix.

---

## Step 4 — A delete that never finished (10 min)

```bash
kubectl -n shop get ledger
kubectl -n shop get ledger nightly-close -o jsonpath='{.metadata.deletionTimestamp}'
kubectl -n shop get ledger nightly-close -o jsonpath='{.metadata.finalizers}'
```

```
NAME            AGE
nightly-close   8m19s

2026-09-25T11:05:10Z
["finance.shop.io/archive-before-delete"]
```

**What this means.** The object has a `deletionTimestamp` — the delete *was* accepted — but a finalizer is still present and no controller exists to clear it. The API server will not remove the object until that list is empty. It will sit there forever.

![The ledger still listed, carrying a deletionTimestamp and an unclearable finance.shop.io/archive-before-delete finalizer](../../artifacts/lab-26/screenshots/06-delete-blocked-by-finalizer.png)


**Before you remove it, answer the question the finalizer is asking.** `archive-before-delete` claims something must be archived first. Establish whether that archive matters, and record the answer. Stripping a finalizer is the standard fix and also the standard way to silently skip a data-safety step.

**Remediate:**

```bash
kubectl -n shop patch ledger nightly-close --type merge -p '{"metadata":{"finalizers":[]}}'
```

> ⚠️ **Gotcha — this is the pattern behind a namespace stuck `Terminating`.** A namespace will not delete while any object inside it holds a finalizer. If you meet that in production, the object is what to look for, not the namespace.

---

## Step 5 — Checkout will not schedule (10 min)

```bash
kubectl -n shop get pods -l app=checkout
kubectl -n shop get events --field-selector reason=FailedScheduling \
  -o jsonpath='{.items[-1:].message}'
```

```
0/3 nodes are available: 1 node(s) had untolerated taint(s),
2 node(s) didn't match Pod's node affinity/selector.
preemption: 0/3 nodes are available: 3 Preemption is not helpful for scheduling.
```

**Read the message carefully — it names two different causes.** One node is excluded by a taint (the control plane, correctly). The other two are excluded by a selector.

```bash
kubectl get nodes -l disktype=nvme-tier0
kubectl -n shop get deploy checkout -o jsonpath='{.spec.template.spec.nodeSelector}'
```

```
No resources found
{"disktype":"nvme-tier0"}
```

**What this means.** The Deployment pins itself to a storage tier that no node carries — a label left behind after hardware was decommissioned. The old ReplicaSet is still serving, which is why nobody noticed until the rollout stalled.

![FailedScheduling naming two separate causes, no node carrying disktype=nvme-tier0, and the nodeSelector that demands it](../../artifacts/lab-26/screenshots/07-checkout-selector-matches-no-node.png)


**Remediate.** Remove the selector, or label a node if the tier genuinely exists. Note which you chose: labelling a node to satisfy a stale selector is how these survive for years.

---

## Step 6 — The name fails but the address works (15 min)

```bash
kubectl -n shop exec shopper -- curl -s --max-time 6 -o /dev/null -w "exit=%{exitcode}\n" http://catalog

CIP=$(kubectl -n shop get svc catalog -o jsonpath='{.spec.clusterIP}')
kubectl -n shop exec shopper -- curl -s --max-time 6 -o /dev/null -w "http=%{http_code}\n" http://$CIP
```

```
exit=6      # by name  — could not resolve host
http=200    # by IP    — works perfectly
```

**What this means.** The service is up and reachable. **Only name resolution is broken**, which narrows the search from "the network" to "DNS" in one command.

![The same Service: exit=6 by name, http=200 by ClusterIP — the network is fine, the lookup is not](../../artifacts/lab-26/screenshots/08-name-fails-address-works.png)


```bash
kubectl -n shop get networkpolicy shopper-egress -o yaml
```

The egress rule permits the catalog on TCP/80 — and nothing else.

**An egress NetworkPolicy is default-deny the moment it selects a Pod.** Everything not listed is denied, including UDP/53 to CoreDNS in `kube-system`. The author allowed the traffic they were thinking about and silently removed the lookup that finds it.

**Remediate** — add the rule that is always forgotten:

```yaml
  egress:
    - to: [{ podSelector: { matchLabels: { app: catalog } } }]
      ports: [{ port: 80, protocol: TCP }]
    # the one everyone forgets
    - to:
        - namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: kube-system } }
          podSelector: { matchLabels: { k8s-app: kube-dns } }
      ports: [{ port: 53, protocol: UDP }]
```

> **Cross-reference.** [Lab 8 Steps 5–9](../../day-1-internals-and-networking/lab-08-cilium-hubble.docx) is the long-form version of this fault, including why one hostname becomes eight queries and where the five-second DNS stall comes from.

---

## Step 7 — The batch job that is neither running nor failing (10 min)

```bash
kubectl -n shop get job revenue-rollup
kubectl -n shop get workloads
kubectl -n shop get workloads -o jsonpath='{.items[0].status.conditions[-1:].message}'
```

```
NAME             STATUS      COMPLETIONS
revenue-rollup   Suspended   0/2

couldn't assign flavors to pod set main: insufficient quota for cpu in flavor
default-flavor, previously considered podsets requests (0) + current podset
request (4) > maximum capacity (1)
```

**What this means.** The Job is **Suspended**, not failed. Kueue is holding it because the ClusterQueue's nominal quota is **1 CPU** and the Job needs **4** (2 CPU × 2 parallel pods). There are no Pods, no errors and no events in the namespace — which is exactly why teams miss this one in triage.

![The Job reporting Suspended 0/2, and Kueue's reason: current podset request (4) exceeds a maximum capacity of (1)](../../artifacts/lab-26/screenshots/09-job-suspended-by-kueue.png)


```bash
kubectl get clusterqueue nightly-batch \
  -o jsonpath='{.spec.resourceGroups[0].flavors[0].resources}'
```

**Remediate.** Raise the ClusterQueue quota, lower the Job's request, or reduce parallelism. All three work; they are not equivalent. Record which you chose and what it implies for the *next* job in that queue.

---

## Step 8 — Verify the whole cluster, not just your last fix (15 min)

**Goal:** prove it is healthy, with commands, not impressions.

```bash
kubectl -n shop get pods                    # all Running, none Pending
kubectl -n shop get job revenue-rollup      # admitted and completing
kubectl -n shop get ledger                  # gone
kubectl -n shop exec shopper -- curl -s -o /dev/null -w "%{http_code}\n" http://catalog   # 200
kubectl -n shop logs -l app=reporter --tail=5                                             # no 429s
docker exec warroom-control-plane crictl exec $CID etcdctl ... endpoint status            # low free space
```

**The check teams skip:** re-run the *first* fault's verification last. Fixing the scheduling fault created Pods; creating Pods wrote to etcd. Confirm etcd is still healthy after everything else you did.

A one-screen check across all six domains — [`artifacts/lab-26/verify.sh`](../../artifacts/lab-26/verify.sh)
runs exactly these, using the [`ec`](../../artifacts/lab-26/ec) wrapper for the long `etcdctl` invocation:

![All six domains verified after remediation: etcd 2.1 MB with 0% unused, APF widened to shares=20 response=Queue, the ledger gone, checkout 2/2, DNS resolving by name, and the batch Job admitted and Running](../../artifacts/lab-26/screenshots/10-all-six-resolved.png)

![The shop namespace with every Pod Running, including both checkout replicas and both revenue-rollup Pods](../../artifacts/lab-26/screenshots/11-cluster-healthy.png)

> ⚠️ **Note on the etcd numbers.** The capture above shows **2.1 MB** — larger than the 1.4 MB
> straight after the defrag, because the five later fixes each wrote to etcd. That growth is the
> point of the check: verify the first fault last.

---

## Step 9 — The postmortem (15 min)

**One page. No blame. Write it as a team.**

```
INCIDENT — <date>, <duration>

WHAT USERS SAW
  <two sentences, in business terms>

TIMELINE
  <time>  <observation or action>   (from the scribe's log)

ROOT CAUSES  (there were six; list only those you confirmed)
  1. <fault> — evidence: <command and output>

WHAT WE CHANGED
  <each change, and why that option over the alternatives>

WHAT WE DID NOT FIX, AND WHY
  <the honest part>

WHAT WOULD HAVE CAUGHT THIS EARLIER
  <a check, an alert, or a policy — one per root cause>
```

The last two sections carry the marks. A postmortem that lists six fixes and no detection gaps has described the work without learning from it.

---

## Scoring

Marked on **method, safety and communication** — not time-to-fix.

| Criterion | Weight | Full marks |
|---|---|---|
| **Evidence before action** | 25% | Every fix has a recorded symptom captured *before* the change |
| **Diagnostic reasoning** | 25% | Hypotheses stated and tested; the right fault fixed first |
| **Safety** | 20% | No destructive action without stating the risk; finalizer and quota decisions justified |
| **Communication** | 15% | Status updates a non-engineer could follow; a usable decision log |
| **Repair completeness** | 15% | Faults fixed and verified |

**Note the weighting.** Repair is the *smallest* component. A team that fixes four faults with clean evidence and a clear log scores higher than one that fixes six by trial and error — because only the first team could do it again on a cluster they had never seen.

> **Instructors:** the seed script is at [`artifacts/lab-26/seed-warroom.sh`](../../artifacts/lab-26/seed-warroom.sh). It names every fault — do not distribute it. Re-seed between teams with `./seed-warroom.sh` for a fresh cluster or `--seed` to re-break an existing one.

---

## Step 10 — Clean up

```bash
kind delete cluster --name warroom
```

---

## What you learned

| You saw… | in Step | proof |
|---|---|---|
| Triage on Pods alone misses half an incident | 1 | three of six faults have no unhealthy Pod |
| One fault can block every other remediation | 2 | etcd at 8.7 MB of a 16.7 MB quota, heading for read-only |
| Compaction and defragmentation do different jobs | 2 | 5.8 MB → 1.4 MB, 53% → 1% free, defrag 16.5 ms |
| A 429 is one starved APF lane, not a busy API server | 3 | `shop-reporting` 94,345 rejected, `shares=1 Reject` |
| A finalizer with no controller blocks deletion forever | 4 | `deletionTimestamp` set, finalizer still present |
| A scheduling message can name two causes at once | 5 | taint *and* selector in one `FailedScheduling` event |
| Name fails + IP works isolates DNS in one command | 6 | `exit=6` by name, `http=200` by IP |
| An egress NetworkPolicy silently denies DNS | 6 | egress rule lists only the catalog |
| A Kueue-suspended Job produces no Pods and no events | 7 | `Suspended 0/2`, quota 1 CPU vs 4 requested |

## Evidence

A full command transcript is in [`artifacts/lab-26/evidence/lab-26-warroom-six-faults.txt`](../../artifacts/lab-26/evidence/lab-26-warroom-six-faults.txt) — 115 lines captured on 2026-09-25, covering the triage view and all six faults with the exact output quoted above.

The instructor seed script is [`artifacts/lab-26/seed-warroom.sh`](../../artifacts/lab-26/seed-warroom.sh).

Real terminal captures are in [`artifacts/lab-26/screenshots/`](../../artifacts/lab-26/screenshots/)
(11 images) from a live war-room run on 2026-09-27 — a fresh 3-node `kind` cluster seeded with
`seed-warroom.sh`, Kubernetes 1.37.0, Kueue v0.14.2. All six faults were diagnosed and remediated in
that run; the last two images are the verification.

---

**Alternative:** [Lab 28 — Capstone, GKE variant](../further-labs/lab-28-capstone-gke-six-domains.docx) runs a different six fault domains (scheduling, image, config, networking, storage, lifecycle) on a cloud cluster.
