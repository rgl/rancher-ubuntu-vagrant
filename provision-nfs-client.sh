#!/bin/bash
set -eu

nfs_server="${1:-pandora.rancher.test}"; shift || true
nfs_path='/var/nfs'
nfs_client_provisioner_version="${1:-1.2.9}"; shift || true

# wrap commands in a way that their output is correctly (most of the time) displayed on the vagrant up output.
# see https://github.com/hashicorp/vagrant/issues/11047
function _wrap_command {
    local output_path=$(mktemp _wrap_command.XXXXXXXX)
    "$@" >$output_path
    local exit_code=$?
    cat $output_path
    rm $output_path
    return $exit_code
}
function docker {
    _wrap_command /usr/bin/docker "$@"
}
function kubectl {
    _wrap_command /usr/bin/kubectl "$@"
}
function helm {
    _wrap_command /usr/local/bin/helm "$@"
}

#
# deploy the nfs-client-provisioner persistent NFS volume provider.
# see https://github.com/kubernetes-incubator/external-storage/tree/master/nfs

# deploy the nfs-client-provisioner helm chart.
echo "deploying the nfs-client-provisioner app..."
kubectl create namespace nfs-client-provisioner-system
helm install \
    nfs-client-provisioner \
    stable/nfs-client-provisioner \
    --namespace nfs-client-provisioner-system \
    --wait \
    --version $nfs_client_provisioner_version \
    --set "nfs.server=$nfs_server" \
    --set "nfs.path=$nfs_path"
