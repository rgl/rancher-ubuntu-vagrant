#!/bin/bash
set -eu

rancher_server_domain="${1:-server.rancher.test}"; shift || true
rancher_server_url="https://$rancher_server_domain"
rancher_cli_version="${1:-v2.4.11}"; shift || true
cluster_name="${1:-local}"; shift || true
admin_api_token="$(cat /vagrant/shared/cluster-admin-api-token)"

# install the rancher cli.
echo "installing rancher cli..."
wget -qO- "https://github.com/rancher/cli/releases/download/$rancher_cli_version/rancher-linux-amd64-$rancher_cli_version.tar.xz" \
    | tar xJf - --strip-components 2
mv rancher /usr/local/bin

echo "logging on rancher $cluster_name cluster and System project..."
while true; do
    # rancher login output will be something like:
    #   NUMBER    CLUSTER NAME   PROJECT ID        PROJECT NAME   PROJECT DESCRIPTION
    #   1         example        c-8gkqh:p-dd52m   Default        Default project created for the cluster
    #   2         example        c-8gkqh:p-zvkgw   System         System project created for the cluster
    #   3         local          local:p-gdrm5     System         System project created for the cluster
    #   4         local          local:p-jrg8d     Default        Default project created for the cluster
    #   Select a Project:
    # we will extract the cluster name, project name, project id, and will switch to the intended one.
    # NB when there is a single cluster (e.g. the local one) rancher cli will not prompt/output anything.
    output="$(echo 1 | rancher login "$rancher_server_url" --token "$admin_api_token" --name 'example')"
    if [ "$cluster_name" == 'local' ]; then
        # rancher projects ls output will be something like:
        #   ID              NAME      STATE     DESCRIPTION
        #   local:p-cszvx   System    active    System project created for the cluster
        #   local:p-fbcc4   Default   active    Default project created for the cluster
        project_id="$(rancher projects ls | grep -E '^local:' | awk "{if (\$2 == \"System\"){print \$1}}")"
    else
        project_id="$(echo "$output" | awk "{if (\$2 == \"$cluster_name\" && \$4 == \"System\"){print \$3}}")"
    fi
    if [ ! -z "$project_id" ]; then
        rancher context switch "$project_id"
    fi
    output="$(rancher context current | grep -E "Cluster:$cluster_name Project:System")"
    if [ -z "$output" ]; then
        sleep 3
        continue
    fi
    break
done

# move namespaces that aren't in a project to the System project.
# NB we ignore all the cattle- namespaces which are reserved for rancher.
#    as-of rancher 2.3.3 only the cattle-global-nt is not in a project.
rancher namespaces ls --all-namespaces --format '{{if not .Namespace.ProjectID}}{{.Namespace.ID}}{{end}}' \
    | grep -v -E '^cattle-' \
    | xargs -I% bash -c "echo 'moving the % namespace to the System project...'; rancher namespaces move % '$project_id'"
