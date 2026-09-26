#!/usr/bin/env bash
# seed-warroom.sh — build the Lab 26 war-room cluster and inject six faults.
#
# INSTRUCTOR ONLY. Do not give this to teams; it names every fault.
# Tested 2026-09-25 on kind v1.37.0 / Kueue v0.14.2.
#
#   ./seed-warroom.sh            # create cluster + seed
#   ./seed-warroom.sh --seed     # seed an existing 'warroom' cluster
set -euo pipefail
CLUSTER=warroom

if [ "${1:-}" != "--seed" ]; then
  cat > /tmp/warroom-kind.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: warroom
nodes: [{ role: control-plane }, { role: worker }, { role: worker }]
EOF
  kind create cluster --config /tmp/warroom-kind.yaml
  kubectl wait --for=condition=Ready node --all --timeout=300s
fi

echo "==> installing Kueue (needed by fault 6)"
kubectl apply --server-side -f https://github.com/kubernetes-sigs/kueue/releases/download/v0.14.2/manifests.yaml >/dev/null
kubectl -n kueue-system wait --for=condition=Available deploy/kueue-controller-manager --timeout=300s

echo "==> namespace + healthy services"
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: Namespace
metadata: { name: shop }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: catalog, namespace: shop }
spec:
  replicas: 1
  selector: { matchLabels: { app: catalog } }
  template:
    metadata: { labels: { app: catalog } }
    spec: { containers: [{ name: app, image: nginx:1.27 }] }
---
apiVersion: v1
kind: Service
metadata: { name: catalog, namespace: shop }
spec:
  selector: { app: catalog }
  ports: [{ port: 80 }]
---
apiVersion: v1
kind: Pod
metadata: { name: shopper, namespace: shop, labels: { app: shopper } }
spec: { containers: [{ name: c, image: curlimages/curl, command: ["sleep","86400"] }] }
EOF

echo "==> FAULT 4 — scheduling: nodeSelector for a decommissioned tier"
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: { name: checkout, namespace: shop }
spec:
  replicas: 2
  selector: { matchLabels: { app: checkout } }
  template:
    metadata: { labels: { app: checkout } }
    spec:
      nodeSelector: { disktype: nvme-tier0 }
      containers:
        - { name: app, image: nginx:1.27, resources: { requests: { cpu: 250m } } }
EOF

echo "==> FAULT 5 — NetworkPolicy that forgets DNS"
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: shopper-egress, namespace: shop }
spec:
  podSelector: { matchLabels: { app: shopper } }
  policyTypes: [Egress]
  egress:
    - to: [{ podSelector: { matchLabels: { app: catalog } } }]
      ports: [{ port: 80, protocol: TCP }]
EOF

echo "==> FAULT 3 — operator: CR with an orphaned finalizer"
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata: { name: ledgers.finance.shop.io }
spec:
  group: finance.shop.io
  names: { kind: Ledger, plural: ledgers, singular: ledger }
  scope: Namespaced
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec: { type: object, properties: { retentionDays: { type: integer } } }
EOF
kubectl wait --for=condition=Established crd/ledgers.finance.shop.io --timeout=90s >/dev/null
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: finance.shop.io/v1
kind: Ledger
metadata:
  name: nightly-close
  namespace: shop
  finalizers: ["finance.shop.io/archive-before-delete"]
spec: { retentionDays: 30 }
EOF
kubectl -n shop delete ledger nightly-close --timeout=10s >/dev/null 2>&1 || true

echo "==> FAULT 6 — Kueue: a Job that cannot be admitted"
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: kueue.x-k8s.io/v1beta1
kind: ResourceFlavor
metadata: { name: default-flavor }
---
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata: { name: nightly-batch }
spec:
  namespaceSelector: {}
  resourceGroups:
    - coveredResources: ["cpu","memory"]
      flavors:
        - name: default-flavor
          resources:
            - { name: cpu,    nominalQuota: "1" }
            - { name: memory, nominalQuota: 1Gi }
---
apiVersion: kueue.x-k8s.io/v1beta1
kind: LocalQueue
metadata: { name: nightly, namespace: shop }
spec: { clusterQueue: nightly-batch }
---
apiVersion: batch/v1
kind: Job
metadata:
  name: revenue-rollup
  namespace: shop
  labels: { kueue.x-k8s.io/queue-name: nightly }
spec:
  parallelism: 2
  completions: 2
  suspend: true
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: rollup
          image: busybox:1.36
          command: ["sh","-c","echo rolling up; sleep 120"]
          resources: { requests: { cpu: "2", memory: 512Mi } }
EOF

echo "==> FAULT 1 — API pressure: a starved APF lane + a hot client"
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata: { name: shop-reporter, namespace: shop }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: { name: shop-reporter-view }
roleRef: { apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: view }
subjects: [{ kind: ServiceAccount, name: shop-reporter, namespace: shop }]
---
apiVersion: flowcontrol.apiserver.k8s.io/v1
kind: PriorityLevelConfiguration
metadata: { name: shop-reporting }
spec:
  type: Limited
  limited:
    nominalConcurrencyShares: 1
    lendablePercent: 0
    borrowingLimitPercent: 0
    limitResponse: { type: Reject }
---
apiVersion: flowcontrol.apiserver.k8s.io/v1
kind: FlowSchema
metadata: { name: shop-reporting }
spec:
  matchingPrecedence: 100
  priorityLevelConfiguration: { name: shop-reporting }
  distinguisherMethod: { type: ByUser }
  rules:
    - subjects:
        - kind: ServiceAccount
          serviceAccount: { name: shop-reporter, namespace: shop }
      resourceRules:
        - verbs: ["*"]
          apiGroups: ["*"]
          resources: ["*"]
          clusterScope: true
          namespaces: ["*"]
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: reporter, namespace: shop }
spec:
  replicas: 4
  selector: { matchLabels: { app: reporter } }
  template:
    metadata: { labels: { app: reporter } }
    spec:
      serviceAccountName: shop-reporter
      containers:
        - name: c
          image: curlimages/curl:8.11.1
          command: ["sh","-c"]
          args:
            - |
              T=/var/run/secrets/kubernetes.io/serviceaccount/token
              CA=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
              while true; do
                CODE=$(curl -s -o /dev/null -w '%{http_code}' --cacert $CA \
                  -H "Authorization: Bearer $(cat $T)" \
                  "https://kubernetes.default.svc/api/v1/pods?limit=500")
                [ "$CODE" = "429" ] && echo "$(date +%T) API REJECTED 429 Too Many Requests"
              done
EOF

echo "==> FAULT 2 — etcd: low backend quota + accumulated dead space"
docker exec ${CLUSTER}-control-plane sh -c \
  "grep -q quota-backend-bytes /etc/kubernetes/manifests/etcd.yaml || \
   sed -i 's|    - --data-dir=/var/lib/etcd|    - --data-dir=/var/lib/etcd\\n    - --quota-backend-bytes=16777216|' /etc/kubernetes/manifests/etcd.yaml"
echo "    waiting for etcd to restart with the new quota..."
until kubectl get --raw /readyz >/dev/null 2>&1; do sleep 5; done
sleep 20
kubectl create ns etcd-filler >/dev/null 2>&1 || true
PAYLOAD=$(head -c 100000 /dev/urandom | base64 | tr -d '\n')
for i in $(seq 1 45); do
  kubectl -n etcd-filler create cm churn-$i --from-literal=b="$PAYLOAD" >/dev/null 2>&1 || true
done
kubectl delete ns etcd-filler --wait=false >/dev/null 2>&1 || true

echo
echo "==> seeded. Six faults are live. Give teams the cluster, not this script."
