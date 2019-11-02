#!/bin/bash
set -eu

#
# deploy helm.
# see https://helm.sh/docs/using_helm/#quickstart-guide
# see https://rancher.com/docs/rancher/v2.x/en/installation/ha/helm-init/

rke_index="${1:-1}"; shift || true
helm_version="${1:-v2.15.2}"; shift || true

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
# workaround for installing tiller in k8s 1.16.
# see https://github.com/helm/helm/issues/6374#issuecomment-533186177
helm init \
  --service-account tiller \
  --history-max 200 \
  --output yaml \
  | sed 's@apiVersion: extensions/v1beta1@apiVersion: apps/v1@' \
  | sed 's@  replicas: 1@  replicas: 1\n  selector: {"matchLabels": {"app": "helm", "name": "tiller"}}@' \
  | kubectl apply -f -
kubectl wait --for=condition=available --timeout=1h deployment/tiller-deploy -n kube-system
helm init --client-only
helm repo update
fi

# kick the tires.
printf "#\n# helm version\n#\n"
helm version
