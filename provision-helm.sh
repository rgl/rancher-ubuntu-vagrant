#!/bin/bash
set -eu

#
# deploy helm.
# see https://helm.sh/docs/using_helm/#quickstart-guide
# see https://rancher.com/docs/rancher/v2.x/en/installation/ha/helm-init/

rke_index="${1:-1}"; shift || true
helm_version="${1:-v2.14.3}"; shift || true

# install helm.
echo "installing helm $helm_version client..."
wget -qO- "https://get.helm.sh/helm-$helm_version-linux-amd64.tar.gz" | tar xzf - --strip-components=1 linux-amd64/helm
mv helm /usr/local/bin

# install the bash completion script.
helm completion bash >/etc/bash_completion.d/helm

if [ "$rke_index" == '0' ]; then
# create the tiller service account and bind it to the cluster-admin role.
echo "creating the helm tiller service account..."
kubectl apply --namespace kube-system -f - <<EOF
kind: ServiceAccount
apiVersion: v1
metadata:
  name: tiller
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: tiller
subjects:
  - kind: ServiceAccount
    name: tiller
    namespace: kube-system
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: ""
EOF

# initialize helm.
echo "initializing helm tiller..."
helm init \
    --service-account tiller \
    --history-max 200 \
    --wait
fi

# kick the tires.
printf "#\n# helm version\n#\n"
helm version
