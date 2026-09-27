printf 'etcd      : '; /tmp/ecstat | tail -1
printf 'apf       : '; kubectl get prioritylevelconfiguration shop-reporting -o jsonpath='shares={.spec.limited.nominalConcurrencyShares} response={.spec.limited.limitResponse.type}'; echo
printf 'finalizer : '; kubectl -n shop get ledger 2>&1 | tail -1
printf 'scheduling: '; kubectl -n shop get deploy checkout --no-headers
printf 'dns       : '; kubectl -n shop exec shopper -- curl -s --max-time 6 -o /dev/null -w 'by name http=%{http_code}\n' http://catalog
printf 'kueue     : '; kubectl -n shop get job revenue-rollup --no-headers
