#!/bin/bash
source /vagrant/lib.sh

nfs_server="${1:-pandora.rancher.test}"; shift || true
nfs_path='/var/nfs'
nfs_client_provisioner_version="${1:-4.0.12}"; shift || true

#
# deploy the nfs-client-provisioner persistent NFS volume provider.
# see https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner

# deploy the nfs-client-provisioner helm chart.
echo "deploying the nfs-client-provisioner app..."
kubectl create namespace nfs-client-provisioner-system
helm install \
    nfs-client-provisioner \
    nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
    --namespace nfs-client-provisioner-system \
    --wait \
    --version $nfs_client_provisioner_version \
    --set "nfs.server=$nfs_server" \
    --set "nfs.path=$nfs_path"
