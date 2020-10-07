#!/bin/bash
set -eu

#
# deploy the MetalLB LoadBalancer.
# NB MetalLB is not yet fully multiple-interface aware until, at least, the
#    following issues are resolved:
#      https://github.com/danderson/metallb/issues/277
#      https://github.com/danderson/metallb/issues/465
# NB there are multiple-interfaces on this vagrant machine and, at least, when the
#    canal/calico cni is installed (like we do on this environment).
# see https://metallb.universe.tf/configuration/#layer-2-configuration

config_metallb_helm_chart_version="${1:-0.12.1}"; shift || true
metallb_ip_addresses="${1:-10.1.0.10-10.1.0.20}"; shift || true

# deploy the metallb helm chart.
# NB this creates the app inside the current rancher cli project (the one returned by rancher context current).
# see https://github.com/helm/charts/tree/master/stable/metallb
# see https://github.com/helm/charts/commits/master/stable/metallb
# see https://github.com/helm/charts/tree/b0f9cb2d7af822e0031f632f2faa0cbb53167770/stable/metallb
echo "deploying the metallb app..."
kubectl create namespace metallb-system
helm install \
    metallb \
    stable/metallb \
    --wait \
    --namespace metallb-system \
    --version $config_metallb_helm_chart_version \
    --values <(cat <<EOF
configInline:
  address-pools:
    - name: default
      protocol: layer2
      addresses:
        - $metallb_ip_addresses
EOF
)
