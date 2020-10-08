#!/bin/bash
set -eu

registry_domain="${1:-pandora.rancher.test}"; shift || true
node_ip_address="${1:-10.1.0.15}"; shift || true
kubectl_version="${1:-1.19.2-00}"; shift # NB execute apt-cache madison kubectl to known the available versions.
registry_host="$registry_domain:5000"
registry_username='vagrant'
registry_password='vagrant'

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

# add useful commands to the bash history.
# see https://kubernetes.github.io/ingress-nginx/kubectl-plugin/
# see https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/
cat >~/.bash_history <<'EOF'
cat /etc/resolv.conf
docker run -it --rm --name test debian:buster-slim cat /etc/resolv.conf
kubectl run --restart=Never --image=debian:buster-slim -it --rm test cat /etc/resolv.conf
kubectl --namespace ingress-nginx exec $(kubectl --namespace ingress-nginx get pods -l app=ingress-nginx -o name) -- cat /etc/resolv.conf
kubectl --namespace ingress-nginx exec $(kubectl --namespace ingress-nginx get pods -l app=ingress-nginx -o name) -- cat /etc/nginx/nginx.conf | grep resolver
kubectl --namespace ingress-nginx get pods
EOF

# install kubectl.
echo "installing kubectl $kubectl_version..."
wget -qO- https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" >/etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y "kubectl=$kubectl_version"

# install the bash completion script.
kubectl completion bash >/etc/bash_completion.d/kubectl

# copy kubectl configuration.
install -d -m 700 ~/.kube
install -m 600 /vagrant/shared/example-cluster-admin.conf ~/.kube/config

# register this node as an ubuntu worker.
rancher_node_command="$(cat /vagrant/shared/rancher-ubuntu-registration-node-command.sh)"
rancher_agent_registration_command="
    $rancher_node_command
        --address $node_ip_address
        --internal-address $node_ip_address
        --worker"
echo "registering this node as a rancher-agent with $rancher_agent_registration_command..."
$rancher_agent_registration_command

# wait for this node to be Ready.
# e.g. uworker1   Ready    worker   2m9s   v1.19.2
$SHELL -c 'node_name=$(hostname); echo "waiting for node $node_name to be ready..."; while [ -z "$(kubectl get nodes $node_name 2>/dev/null | grep -E "$node_name\s+Ready\s+")" ]; do sleep 3; done; echo "node ready!"'

# login into the registry.
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
