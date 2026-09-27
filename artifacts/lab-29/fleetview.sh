for C in fleet-01 fleet-02; do
  R=$(kubectl --context kind-$C -n flux-system get kustomization fleet -o jsonpath='{.status.lastAppliedRevision}' 2>/dev/null)
  B=$(kubectl --context kind-$C -n flux-system get gitrepository fleet -o jsonpath='{.spec.ref.branch}' 2>/dev/null)
  RP=$(kubectl --context kind-$C -n storefront get deploy web -o jsonpath='{.spec.replicas}' 2>/dev/null)
  RD=$(kubectl --context kind-$C -n storefront get deploy web -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  IM=$(kubectl --context kind-$C -n storefront get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
  TR=$(kubectl --context kind-$C -n storefront get deploy web -o jsonpath='{.metadata.labels.tier}' 2>/dev/null)
  CL=$(kubectl --context kind-$C -n storefront get deploy web -o jsonpath='{.metadata.labels.cluster}' 2>/dev/null)
  R="${R%%%%.*}"; R=$(printf '%s' "$R" | cut -c1-22)
  printf 'kind-%-9s branch=%-8s %-23s cluster=%-9s tier=%-11s replicas=%-2s ready=%s/%s  image=%s\n' \
    "$C" "${B:--}" "${R:--}" "${CL:--}" "${TR:--}" "${RP:--}" "${RD:-0}" "${RP:--}" "${IM:--}"
done
