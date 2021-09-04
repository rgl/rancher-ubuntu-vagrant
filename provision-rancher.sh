#!/bin/bash
source /vagrant/lib.sh

registry_domain="${1:-pandora.rancher.test}"; shift || true
rancher_server_domain="${1:-server.rancher.test}"; shift || true
rancher_server_url="https://$rancher_server_domain"
admin_password="${1:-admin}"; shift || true
rancher_helm_chart_version="${1:-2.6.0}"; shift || true
k8s_version="${1:-v1.21.4-rancher1-1}"; shift || true
rancher_domain="$(echo -n "$registry_domain" | sed -E 's,^[a-z0-9-]+\.(.+),\1,g')"
registry_host="$registry_domain:5000"
registry_url="https://$registry_host"
registry_username='vagrant'
registry_password='vagrant'

# add useful commands to the bash history.
# see https://kubernetes.github.io/ingress-nginx/kubectl-plugin/
# see https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/
# see https://github.com/rancher/ingress-nginx
cat >~/.bash_history <<'EOF'
cat /etc/resolv.conf
docker run -it --rm --name test debian:buster-slim cat /etc/resolv.conf
kubectl run --generator=run-pod/v1 --restart=Never --image=debian:buster-slim -it --rm test cat /etc/resolv.conf
kubectl --namespace ingress-nginx get pods -l app=ingress-nginx -o name | xargs -I% kubectl --namespace ingress-nginx exec % -- cat /etc/resolv.conf
kubectl --namespace ingress-nginx get pods -l app=ingress-nginx -o name | xargs -I% kubectl --namespace ingress-nginx exec % -- cat /etc/nginx/nginx.conf | grep resolver
kubectl --namespace ingress-nginx exec $(kubectl --namespace ingress-nginx get pods -l app=ingress-nginx -o name | head -1) -- cat /etc/nginx/nginx.conf | grep resolver
kubectl --namespace ingress-nginx get pods -o wide
kubectl ingress-nginx lint --show-all --all-namespaces
kubectl ingress-nginx ingresses --all-namespaces
EOF

# create the rancher cattle-system namespace.
kubectl create namespace cattle-system

# create the rancher certificate secrets.
# see https://rancher.com/docs/rancher/v2.x/en/installation/ha/helm-rancher/tls-secrets/
echo "create the rancher certificate secrets..."
kubectl \
    create secret tls tls-rancher-ingress \
    --namespace cattle-system \
    --cert=/vagrant/shared/tls/example-ca/$rancher_server_domain-crt.pem \
    --key=/vagrant/shared/tls/example-ca/$rancher_server_domain-key.pem
kubectl \
    create secret generic tls-ca \
    --namespace cattle-system \
    --from-file=cacerts.pem=/vagrant/shared/tls/example-ca/example-ca-crt.pem

# launch rancher.
# see https://rancher.com/docs/rancher/v2.x/en/installation/ha/helm-rancher/
# see https://rancher.com/docs/rancher/v2.x/en/installation/ha/helm-rancher/chart-options/
# see https://github.com/rancher/rancher/tree/master/chart
# see https://releases.rancher.com/server-charts/latest/index.yaml
echo "installing rancher..."
helm repo add rancher https://releases.rancher.com/server-charts/latest
helm search repo rancher/ --versions | head -10
helm install \
    rancher \
    rancher/rancher \
    --namespace cattle-system \
    --version $rancher_helm_chart_version \
    --set "hostname=$rancher_server_domain" \
    --set ingress.tls.source=secret \
    --set privateCA=true \
    --set replicas=1

# wait for it to be rolled out.
echo "waiting for rancher to be rolled out..."
kubectl --namespace cattle-system rollout status deploy/rancher

# wait for it to be ready.
echo "waiting for rancher to be ready..."
while [ "$(wget -qO- $rancher_server_url/ping)" != "pong" ]; do sleep 5; done;
echo "rancher is ready!"

# get the bootstrap password.
bootstrap_password="$(kubectl get secret --namespace cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}{{ "\n" }}')"

# get the admin login token.
echo "getting the admin login token..."
while true; do
    admin_login_token="$(
        wget -qO- \
            --header 'Content-Type: application/json' \
            --post-data '{"username":"admin","password":"'$bootstrap_password'"}' \
            "$rancher_server_url/v3-public/localProviders/local?action=login" \
        | jq -r .token)"
    [ "$admin_login_token" != 'null' ] && [ "$admin_login_token" != '' ] && break
    sleep 5
done

# set the admin password.
echo "setting the admin password..."
wget -qO- \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer $admin_login_token" \
    --post-data '{"currentPassword":"'$bootstrap_password'","newPassword":"'$admin_password'"}' \
    "$rancher_server_url/v3/users?action=changepassword"

# create the api token.
echo "creating the admin api token..."
admin_api_token="$(
    wget -qO- \
        --header 'Content-Type: application/json' \
        --header "Authorization: Bearer $admin_login_token" \
        --post-data '{"type":"token","description":"automation"}' \
        "$rancher_server_url/v3/token" \
    | jq -r .token)"
echo -n "$admin_api_token" >~/.rancher-admin-api-token
chmod 600 ~/.rancher-admin-api-token
echo -n "$admin_api_token" >/vagrant/shared/cluster-admin-api-token

# set the server-url.
# NB sometimes it seems the cluster is stuck waiting for the server-url setting,
#    the workaround is to login into rancher, edit the cluster, and just click
#    the save button.
#    see https://github.com/rancher/rancher/issues/16213
echo "setting the rancher server-url setting..."
wget -qO- \
    --method PUT \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer $admin_api_token" \
    --body-data '{"name":"server-url","value":"'$rancher_server_url'"}' \
    "$rancher_server_url/v3/settings/server-url"

# set the telemetry-opt.
echo "setting the rancher telemetry-opt setting..."
wget -qO- \
    --method PUT \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer $admin_api_token" \
    --body-data '{"name":"telemetry-opt","value":"out"}' \
    "$rancher_server_url/v3/settings/telemetry-opt"

# wait for the local cluster to be active.
# NB this can only complete after the rancher-agent (with the etcd and controlplane roles) is up.
cluster_id='local'
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
done
