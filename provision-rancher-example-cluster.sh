#!/bin/bash
source /vagrant/lib.sh

registry_domain="${1:-pandora.rancher.test}"; shift || true
rancher_server_domain="${1:-server.rancher.test}"; shift || true
rancher_server_url="https://$rancher_server_domain"
k8s_version="${1:-v1.20.9-rancher1-1}"; shift || true
pod_network_cidr='10.62.0.0/16'       # default is 10.42.0.0/16.
service_network_cidr='10.63.0.0/16'   # default is 10.43.0.0/16.
service_node_port_range='30000-32767' # default is 30000-32767
dns_service_ip_address='10.63.0.10'   # default is 10.43.0.10.
cluster_domain='example.domain'       # default is cluster.local.
cluster_name='example'
admin_api_token="$(cat ~/.rancher-admin-api-token)"

# create the cluster.
# NB this JSON can be obtained by observing the network when manually creating a cluster from the rancher UI.
#    NB also use the schemas browser at https://server.rancher.test:8443/v3/schemas.
# NB to troubleshoot why the cluster provisioning is failing with something like:
#       cluster c-fhrlt state: provisioning Failed to get job complete status for job rke-network-plugin-deploy-job in namespace kube-system
#    execute:
#       docker ps -a -f status=exited --format '{{.Names}} {{.Command}}' --no-trunc | grep -v /pause | grep rke-network-plugin
#    then get the logs with, e.g.:
#       docker logs k8s_rke-network-plugin-pod_rke-network-plugin-deploy-job-tcm8p_kube-system_ac5adeb3-16ca-417d-b899-f51f14d5c712_0
# see https://server.rancher.test:8443/v3/schemas/cluster
# see https://server.rancher.test:8443/v3/schemas/rancherKubernetesEngineConfig
# see https://server.rancher.test:8443/v3/schemas/rkeConfigServices
# see https://server.rancher.test:8443/v3/schemas/kubeAPIService
# see https://server.rancher.test:8443/v3/schemas/kubeControllerService
# see https://server.rancher.test:8443/v3/schemas/kubeletService
# see https://rancher.com/docs/rancher/v2.x/en/cluster-provisioning/rke-clusters/windows-clusters/
# see docker ps --format '{{.Image}} {{.Names}} {{.Command}}' --no-trunc
# see docker logs kubelet
# see find /opt -type f | grep -v /catalog-cache
# see /etc/cni
echo "creating the cluster..."
cluster_response="$(wget -qO- \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer $admin_api_token" \
    --post-data '{
        "type": "cluster",
        "name": "'$cluster_name'",
        "description": "hello world",
        "dockerRootDir": "/var/lib/docker",
        "enableClusterAlerting": false,
        "enableClusterMonitoring": false,
        "enableNetworkPolicy": false,
        "windowsPreferedCluster": false,
        "rancherKubernetesEngineConfig": {
            "type": "rancherKubernetesEngineConfig",
            "kubernetesVersion": "'$k8s_version'",
            "addonJobTimeout": 45,
            "ignoreDockerVersion": true,
            "rotateEncryptionKey": false,
            "sshAgentAuth": false,
            "authentication": {
                "type": "authnConfig",
                "strategy": "x509"
            },
            "dns": {
                "type": "dnsConfig",
                "nodelocal": {
                    "type": "nodelocal",
                    "ip_address": "",
                    "node_selector": null,
                    "update_strategy": {}
                }
            },
            "network": {
                "type": "networkConfig",
                "mtu": 0,
                "plugin": "flannel",
                "options": {
                    "flannel_backend_type": "host-gw",
                    "flannel_iface": "eth1"
                }
            },
            "ingress": {
                "type": "ingressConfig",
                "provider": "nginx",
                "defaultBackend": false,
                "httpPort": 0,
                "httpsPort": 0
            },
            "monitoring": {
                "type": "monitoringConfig",
                "provider": "metrics-server",
                "replicas": 1
            },
            "services": {
                "type": "rkeConfigServices",
                "kubeApi": {
                    "type": "kubeAPIService",
                    "alwaysPullImages": false,
                    "podSecurityPolicy": false,
                    "serviceClusterIpRange": "'$service_network_cidr'",
                    "serviceNodePortRange": "'$service_node_port_range'",
                    "secretsEncryptionConfig": {
                        "enabled": false,
                        "type": "secretsEncryptionConfig"
                    }
                },
                "kubeController": {
                    "type": "kubeControllerService",
                    "clusterCidr": "'$pod_network_cidr'",
                    "serviceClusterIpRange": "'$service_network_cidr'"
                },
                "kubelet": {
                    "type": "kubeletService",
                    "clusterDnsServer": "'$dns_service_ip_address'",
                    "clusterDomain": "'$cluster_domain'"
                },
                "etcd": {
                    "creation": "12h",
                    "extraArgs": {
                        "heartbeat-interval": 500,
                        "election-timeout": 5000
                    },
                    "gid": 0,
                    "retention": "72h",
                    "snapshot": false,
                    "uid": 0,
                    "type": "etcdService",
                    "backupConfig": {
                        "type": "backupConfig",
                        "enabled": true,
                        "intervalHours": 12,
                        "retention": 6,
                        "safeTimestamp": false,
                        "timeout": 300
                    }
                }
            },
            "upgradeStrategy": {
                "maxUnavailableControlplane": "1",
                "maxUnavailableWorker": "10%",
                "drain": "false",
                "nodeDrainInput": {
                    "deleteLocalData": false,
                    "force": false,
                    "gracePeriod": -1,
                    "ignoreDaemonSets": true,
                    "timeout": 120,
                    "type": "nodeDrainInput"
                },
                "maxUnavailableUnit": "percentage"
            }
        },
        "localClusterAuthEndpoint": {
            "enabled": true,
            "type": "localClusterAuthEndpoint"
        },
        "labels": {},
        "annotations": {},
        "agentEnvVars": [],
        "scheduledClusterScan": {
            "enabled": false,
            "scheduleConfig": null,
            "scanConfig": null
        }
    }' \
    "$rancher_server_url/v3/cluster")"
cluster_id="$(echo "$cluster_response" | jq -r .id)"
echo "$cluster_id" >/vagrant/shared/example-cluster-id

# save the registration node commands.
echo "getting the rancher-agent registration command..."
cluster_registration_response="$(
    wget -qO- \
        --header 'Content-Type: application/json' \
        --header "Authorization: Bearer $admin_api_token" \
        --post-data '{"type":"clusterRegistrationToken","clusterId":"'$cluster_id'"}' \
        "$rancher_server_url/v3/clusterregistrationtoken")"
rancher_node_command="$(echo "$cluster_registration_response" | jq -r .nodeCommand)"
echo "$rancher_node_command" >/vagrant/shared/rancher-ubuntu-registration-node-command.sh
