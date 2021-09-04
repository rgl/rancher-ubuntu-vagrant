#!/bin/bash
source /vagrant/lib.sh

registry_domain="${1:-pandora.rancher.test}"; shift || true
rancher_server_domain="${1:-server.rancher.test}"; shift || true
rancher_server_url="https://$rancher_server_domain"
node_index="${1:-0}"; shift || true
node_ip_address="${1:-10.10.0.10}"; shift || true
kubectl_version="${1:-1.20.0-00}"; shift # NB execute apt-cache madison kubectl to known the available versions.
krew_version="${1:-v0.4.1}"; shift # NB see https://github.com/kubernetes-sigs/krew
registry_host="$registry_domain:5000"
registry_url="https://$registry_host"
registry_username='vagrant'
registry_password='vagrant'
admin_api_token="$(cat /vagrant/shared/cluster-admin-api-token)"
cluster_id="$(cat /vagrant/shared/example-cluster-id)"

# add useful commands to the bash history.
# see https://kubernetes.github.io/ingress-nginx/kubectl-plugin/
# see https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/
cat >~/.bash_history <<'EOF'
cat /etc/resolv.conf
docker run -it --rm --name test debian:buster-slim cat /etc/resolv.conf
kubectl run --generator=run-pod/v1 --restart=Never --image=debian:buster-slim -it --rm test -- cat /etc/resolv.conf
kubectl --namespace ingress-nginx exec $(kubectl --namespace ingress-nginx get pods -l app=ingress-nginx -o name) -- cat /etc/resolv.conf
kubectl --namespace ingress-nginx exec $(kubectl --namespace ingress-nginx get pods -l app=ingress-nginx -o name) -- cat /etc/nginx/nginx.conf | grep resolver
kubectl --namespace ingress-nginx get pods
kubectl ingress-nginx lint --show-all --all-namespaces
kubectl ingress-nginx ingresses --all-namespaces
EOF

# install kubectl.
echo "installing kubectl $kubectl_version..."
wget -qO- https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" >/etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y "kubectl=$kubectl_version"

# install the bash completion script.
kubectl completion bash >/etc/bash_completion.d/kubectl

# register this node as a rancher-agent.
rancher_node_command="$(cat /vagrant/shared/rancher-ubuntu-registration-node-command.sh)"
# TODO try --hostname-override $(hostname) to fix the external-ip address reported by kubectl get nodes -o wide?
# NB due to the way we are launching the cluster (one node at a time, starting
#    with master, then the worker) we must create a master with all the roles
#    because the cluster can only become active after all the roles (etcd,
#    controlplane and worker) are up.
#    see https://github.com/rancher/rancher/issues/31244#issuecomment-790274280
rancher_agent_registration_command="
    $rancher_node_command
        --address $node_ip_address
        --internal-address $node_ip_address
        --etcd
        --controlplane
        --worker"
echo "registering this node as a rancher-agent with $rancher_agent_registration_command..."
$rancher_agent_registration_command

# wait for the cluster to be active.
# NB this only completes after all the roles (etcd, controlplane and worker) are up.
#    see https://github.com/rancher/rancher/issues/31244#issuecomment-790274280
# NB if this gets stuck in this step, see the rancher-agent logs with:
#       rancher_agent_id="$(docker ps --no-trunc --format '{{.ID}} {{.Image}}' | awk ' /rancher\/rancher-agent:/{print $1}')"
#       docker logs $rancher_agent_id
#    try troubleshoot from inside the container with:
#       docker exec -it $rancher_agent_id bash
#       apt-get update
#       apt-get install -y iputils-ping dnsutils
#       cat /etc/resolv.conf
#       ping 10.10.0.2
#       ping pandora.rancher.test
#       ping server.rancher.test
#    try to restart the container with:
#       docker kill $rancher_agent_id
#       sleep 10
#       docker start $rancher_agent_id
echo "waiting for cluster $cluster_id to be active..."
previous_message=""
while true; do
    cluster_response="$(
        wget -qO- \
            --header 'Content-Type: application/json' \
            --header "Authorization: Bearer $admin_api_token" \
            "$rancher_server_url/v3/cluster/$cluster_id")"
    cluster_state="$(echo "$cluster_response" | jq -r .state)"
    cluster_transitioning_message="$(echo "$cluster_response" | jq -r .transitioningMessage)"
    message="cluster $cluster_id state: $cluster_state $cluster_transitioning_message"
    if [ "$message" != "$previous_message" ]; then
        previous_message="$message"
        echo "$message"
    fi
    [ "$cluster_state" = 'active' ] && break
    sleep .5
    # TODO instead of a busy wait to get all messages how can we tail the cluster events?
    #      kubectl get events --watch --all-namespaces --output wide --sort-by=.metadata.creationTimestamp
done

# save kubeconfig.
echo "saving ~/.kube/config..."
kubeconfig_response="$(
    wget -qO- \
        --method POST \
        --header "Authorization: Bearer $admin_api_token" \
        "$rancher_server_url/v3/clusters/$cluster_id?action=generateKubeconfig")"
install -d -m 700 ~/.kube
install -m 600 /dev/null ~/.kube/config
echo "$kubeconfig_response" | jq -r .config >~/.kube/config
# also save the kubectl configuration on the host, so we can access it there.
cp ~/.kube/config /vagrant/shared/example-cluster-admin.conf

if [ "$node_index" == '0' ]; then
# register custom registry for all namespaces inside the created cluster Default project.
registry_name="$(echo "$registry_host" | sed -E 's,[^a-z0-9],-,g')"
echo "getting the $cluster_id cluster Default project..."
project_response="$(
    wget -qO- \
        --header 'Content-Type: application/json' \
        --header "Authorization: Bearer $admin_api_token" \
        "$rancher_server_url/v3/projects?clusterId=$cluster_id&name=Default")"
echo "registering the $registry_host registry..."
docker_credentials_url="$(echo "$project_response" | jq -r .data[].links.dockerCredentials)"
docker_credentials_response="$(
    wget -qO- \
        --header 'Content-Type: application/json' \
        --header "Authorization: Bearer $admin_api_token" \
        --post-data '{"type":"dockerCredential","registries":{"'$registry_host'":{"username":"'$registry_username'","password":"'$registry_password'"}},"name":"'$registry_name'"}' \
        "$docker_credentials_url")"

# add the custom registry to the default service account.
# see https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/
# NB without this you need to explicitly add imagePullSecrets to your pod definitions, e.g.:
#       apiVersion: apps/v1
#       kind: Pod
#       spec:
#           imagePullSecrets:
#               - name: pandora-rancher-test-5000
kubectl patch serviceaccount default -p '{"imagePullSecrets":[{"name":"'$registry_name'"}]}'
#kubectl get serviceaccount default -o yaml
fi

# wait for this node to be Ready.
# e.g. master1   Ready    controlplane,etcd,worker   2m9s   v1.20.9
$SHELL -c 'node_name=$(hostname); echo "waiting for node $node_name to be ready..."; while [ -z "$(kubectl get nodes $node_name 2>/dev/null | grep -E "$node_name\s+Ready\s+")" ]; do sleep 3; done; echo "node ready!"'

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
