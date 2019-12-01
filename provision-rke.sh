#!/bin/bash
set -eu

registry_domain="${1:-pandora.rancher.test}"; shift || true
rke_roles="${1:-controlplane,etcd,worker}"; shift || true
rke_index="${1:-0}"; shift || true
node_ip_address="${1:-10.1.0.3}"; shift || true
rke_version="${1:-v1.0.0}"; shift || true
k8s_version="${1:-v1.16.3-rancher1-1}"; shift || true
kubectl_version="${1:-1.16.3-00}"; shift # NB execute apt-cache madison kubectl to known the available versions.
krew_version="${1:-v0.3.2}"; shift # NB see https://github.com/kubernetes-sigs/krew
pod_network_cidr='10.52.0.0/16'       # default is 10.42.0.0/16.
service_network_cidr='10.53.0.0/16'   # default is 10.43.0.0/16.
service_node_port_range='30000-32767' # default is 30000-32767
dns_service_ip_address='10.53.0.10'   # default is 10.43.0.10.
cluster_domain='local.domain'         # default is cluster.local.
rancher_domain="$(echo -n "$registry_domain" | sed -E 's,^[a-z0-9-]+\.(.+),\1,g')"
registry_host="$registry_domain:5000"
registry_url="https://$registry_host"
registry_username='vagrant'
registry_password='vagrant'
cluster_name='local'

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

# add useful commands to the bash history.
# see https://kubernetes.github.io/ingress-nginx/kubectl-plugin/
# see https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/
cat >~/.bash_history <<'EOF'
cat /etc/resolv.conf
docker run -it --rm --name test debian:buster-slim cat /etc/resolv.conf
kubectl run --generator=run-pod/v1 --restart=Never --image=debian:buster-slim -it --rm test cat /etc/resolv.conf
kubectl --namespace ingress-nginx exec $(kubectl --namespace ingress-nginx get pods -l app=ingress-nginx -o name) cat /etc/resolv.conf
kubectl --namespace ingress-nginx exec $(kubectl --namespace ingress-nginx get pods -l app=ingress-nginx -o name) cat /etc/nginx/nginx.conf | grep resolver
kubectl --namespace ingress-nginx get pods
kubectl ingress-nginx lint --show-all --all-namespaces
kubectl ingress-nginx ingresses --all-namespaces
EOF

# generate the rke ssh key that can be used to connect to the nodes.
if [ ! -f /vagrant/shared/ssh/rke_rsa ]; then
    mkdir -p /vagrant/shared/ssh
    ssh-keygen -f /vagrant/shared/ssh/rke_rsa -t rsa -b 2048 -C "rke" -N ''
fi
# configure this host to be accessed by the rke ssh key.
cat /vagrant/shared/ssh/rke_rsa.pub >>/home/vagrant/.ssh/authorized_keys

# install rke.
echo "installing rke $rke_version..."
wget -qO rke "https://github.com/rancher/rke/releases/download/$rke_version/rke_linux-amd64"
install -m 555 -o root -g root rke /usr/local/bin && rm rke
rke --version
rke config --list-version --all                   # list supported k8s versions.
rke config --system-images --version $k8s_version # list the system images.

# create the rke configuration.
if [[ "$rke_roles" == *'controlplane'* ]] && [[ "$rke_index" == '0' ]]; then
# NB always leave the "nodes:" line at the end of cluster.yaml because we will append nodes to it later.
# see https://rancher.com/docs/rke/latest/en/example-yamls/
# see https://rancher.com/docs/rke/latest/en/config-options/add-ons/network-plugins/#network-plug-in-options
cat >cluster.yaml <<EOF
cluster_name: $cluster_name
kubernetes_version: $k8s_version
ssh_key_path: /vagrant/shared/ssh/rke_rsa
services:
  kube-api:
    service_cluster_ip_range: $service_network_cidr
    service_node_port_range: $service_node_port_range
  kube-controller:
    cluster_cidr: $pod_network_cidr
    service_cluster_ip_range: $service_network_cidr
  kubelet:
    cluster_domain: $cluster_domain
    cluster_dns_server: $dns_service_ip_address
network:
  plugin: flannel
  options:
    flannel_iface: eth1
    flannel_backend_type: host-gw
nodes:
EOF
else
cp /vagrant/shared/cluster.rkestate .
cp /vagrant/shared/cluster.yaml .
fi

# append the current host as an rke node.
# NB due to https://github.com/rancher/rke/issues/900 its only possible to set the
#    kubelet node-ip iif address is different than internal_address, as such,
#    in address we've used a DNS name and in internal_address an IP address.
#    this ends up with an node annotation name rke.cattle.io/external-ip which is not really an IP, e.g.:
#       kubectl describe nodes server1
#       Name:               server1
#       Roles:              controlplane,etcd,worker
#       Labels:             beta.kubernetes.io/arch=amd64
#                           beta.kubernetes.io/os=linux
#                           kubernetes.io/arch=amd64
#                           kubernetes.io/hostname=server1
#                           kubernetes.io/os=linux
#                           node-role.kubernetes.io/controlplane=true
#                           node-role.kubernetes.io/etcd=true
#                           node-role.kubernetes.io/worker=true
#       Annotations:        flannel.alpha.coreos.com/backend-data: null
#                           flannel.alpha.coreos.com/backend-type: host-gw
#                           flannel.alpha.coreos.com/kube-subnet-manager: true
#                           flannel.alpha.coreos.com/public-ip: 10.1.0.3
#                           node.alpha.kubernetes.io/ttl: 0
#                           rke.cattle.io/external-ip: server1.rancher.test
#                           rke.cattle.io/internal-ip: 10.1.0.3
#                           volumes.kubernetes.io/controller-managed-attach-detach: true
# NB kubectl get node $(hostname) -o wide must return $node_ip_address as INTERNAL-IP.
#    in the end kubectl get nodes -o wide must report something like:
#       NAME   STATUS   ROLES                      AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
#       server1   Ready    controlplane,etcd,worker   19m   v1.15.4   10.1.0.3      <none>        Ubuntu 18.04.3 LTS   4.15.0-62-generic   docker://19.3.2
#    also do a ps -wwxo pid,cmd | grep kubelet and ensure the value of the --node-ip argument is correct.
cat >>cluster.yaml <<EOF
  - hostname_override: $(hostname)
    address: $(hostname --fqdn)
    internal_address: $node_ip_address
    user: vagrant
    role:
$(
      for rke_role in `echo "$rke_roles" | tr , ' '`; do
        echo "      - $rke_role"
      done
)
EOF

# bring up the cluster.
rke up --config cluster.yaml

# save kubeconfig.
echo "saving ~/.kube/config..."
install -d -m 700 ~/.kube
cp kube_config_cluster.yaml ~/.kube/config

# also save the cluster configuration on the host.
cp cluster.rkestate /vagrant/shared
cp cluster.yaml /vagrant/shared
cp ~/.kube/config /vagrant/shared/admin.conf

# install kubectl.
echo "installing kubectl $kubectl_version..."
wget -qO- https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" >/etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y "kubectl=$kubectl_version"

# install the bash completion script.
kubectl completion bash >/etc/bash_completion.d/kubectl

# wait for this node to be Ready.
# e.g. server1   Ready    controlplane,etcd,worker   22m   v1.15.4
echo "waiting for this node to be ready..."
$SHELL -c 'node_name=$(hostname); while [ -z "$(kubectl get nodes $node_name 2>/dev/null | grep -E "$node_name\s+Ready\s+")" ]; do sleep 3; done'

# install the krew kubectl package manager.
echo "installing the krew $krew_version kubectl package manager..."
wget -qO- "https://github.com/kubernetes-sigs/krew/releases/download/$krew_version/krew.tar.gz" | tar xzf - ./krew-linux_amd64
wget -q "https://github.com/kubernetes-sigs/krew/releases/download/$krew_version/krew.yaml"
./krew-linux_amd64 install --manifest=krew.yaml
cat >/etc/profile.d/krew.sh <<'EOF'
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
EOF
source /etc/profile.d/krew.sh
kubectl krew version

# install the ingress-nginx kubectl plugin.
# see https://kubernetes.github.io/ingress-nginx/kubectl-plugin/
echo "install the kubectl ingress-nginx plugin..."
kubectl krew install ingress-nginx

# login into the registry.
# TODO do this in cluster.yaml?
echo "logging in the registry..."
docker login $registry_host --username "$registry_username" --password-stdin <<EOF
$registry_password
EOF

# show summary.
printf "#\n# kubernetes nodes\n#\n"
kubectl get nodes -o wide
kubectl describe nodes $(hostname)
flannel_iface="$(ps -wwxo cmd | perl -ne '/flanneld .+--iface=(\w+)/ && print $1')"
printf "#\n# flannel interface\n#\n$flannel_iface\n"
printf "#\n# kubernetes configmap/rke-network-plugin\n#\n"
kubectl get --namespace kube-system configmap/rke-network-plugin -o jsonpath='{.data.rke-network-plugin}' | sed -E 's,(.+),  \1,g'
