#!/bin/bash
source /vagrant/lib.sh

#
# deploy helm.

helm_version="${1:-v3.6.3}"; shift || true

# install helm.
# see https://helm.sh/docs/intro/install/
echo "installing helm $helm_version client..."
wget -qO- "https://get.helm.sh/helm-$helm_version-linux-amd64.tar.gz" | tar xzf - --strip-components=1 linux-amd64/helm
install helm /usr/local/bin

# install the bash completion script.
apt-get install -y bash-completion
helm completion bash >/usr/share/bash-completion/completions/helm

# add chart repositories.
# see https://helm.sh/docs/intro/quickstart/
# see https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner
echo "adding repositories..."
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm repo update

# kick the tires.
printf "#\n# helm version\n#\n"
helm version
