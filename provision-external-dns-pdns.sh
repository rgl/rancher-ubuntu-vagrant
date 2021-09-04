#!/bin/bash
source /vagrant/lib.sh

pdns_domain="${1:-pandora.rancher.test}"; shift || true
domain="$(echo -n "$pdns_domain" | sed -E 's,^[a-z0-9-]+\.(.+),\1,g')"
external_dns_namespace='kube-system'

# install the PowerDNS external-dns provider.
# see https://github.com/kubernetes-incubator/external-dns/blob/master/docs/tutorials/pdns.md
# see https://github.com/kubernetes-incubator/external-dns/blob/master/docs/initial-design.md
kubectl apply --namespace "$external_dns_namespace" -f - <<EOF
$(
    cat /vagrant/external-dns-pdns.yaml \
        | sed -E "s,@@namespace@@,$external_dns_namespace,g" \
        | sed -E "s,@@pdns-server@@,http://$pdns_domain:8081,g" \
        | sed -E "s,@@pdns-api-key@@,vagrant,g" \
        | sed -E "s,@@txt-owner-id@@,rancher,g" \
        | sed -E "s,@@domain-filter@@,$domain,g"
)
EOF
