# to make sure the nodes are created in order we have to force a --no-parallel execution.
ENV['VAGRANT_NO_PARALLEL'] = 'yes'

require 'ipaddr'

def generate_ip_addresses(base_ip_address, count)
  ip_address = IPAddr.new base_ip_address
  (1..count).map do |n|
    a, ip_address = ip_address.to_s, ip_address.succ
    a
  end
end

config_server_count = 1
config_master_count = 1
config_ubuntu_worker_count = 1
config_domain = 'rancher.test'
config_pandora_fqdn = "pandora.#{config_domain}"
config_pandora_ip_address = '10.10.0.2'
config_server_fqdn = "server.#{config_domain}"
config_server_ip_address = '10.10.0.3'
config_rancher_helm_chart_version = '2.5.9' # see https://github.com/rancher/rancher/releases
config_rancher_cli_version = 'v2.4.11' # see https://github.com/rancher/cli/releases
config_server_ip_addresses = generate_ip_addresses('10.10.0.5', config_server_count)
config_master_ip_addresses = generate_ip_addresses('10.10.0.10', config_master_count)
config_ubuntu_worker_ip_addresses = generate_ip_addresses('10.10.0.15', config_ubuntu_worker_count)
config_admin_password = 'admin'
config_docker_version = '20.10.8' # NB execute apt-cache madison docker-ce to known the available versions.
config_rke_version = 'v1.2.10' # see https://github.com/rancher/rke/releases
config_k8s_version = 'v1.20.9-rancher1-1' # see https://github.com/rancher/kontainer-driver-metadata/blob/release-v2.5/rke/k8s_rke_system_images.go of the version that ships with your rke version.
config_kubectl_version = '1.20.0-00' # NB execute apt-cache madison kubectl to known the available versions.
config_krew_version = 'v0.4.1' # see https://github.com/kubernetes-sigs/krew/releases
config_helm_version = 'v3.6.3' # see https://github.com/helm/helm/releases
config_metallb_helm_chart_version = '2.5.0' # see https://github.com/bitnami/charts/blob/master/bitnami/metallb/Chart.yaml
config_metallb_server_ip_addresses = '10.10.0.30-10.10.0.39' # MetalLB will allocate IP addresses from this range.
config_metallb_master_ip_addresses = '10.10.0.40-10.10.0.49' # MetalLB will allocate IP addresses from this range.
config_nfs_client_provisioner_version = '4.0.12' # version of https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner/blob/master/charts/nfs-subdir-external-provisioner/Chart.yaml

hosts = """
127.0.0.1	localhost
#{config_pandora_ip_address} #{config_pandora_fqdn}
#{config_server_ip_address} #{config_server_fqdn}
#{config_server_ip_addresses.map.with_index{|ip_address, i|"#{ip_address} server#{i+1}.#{config_domain}"}.join("\n")}
#{config_master_ip_addresses.map.with_index{|ip_address, i|"#{ip_address} master#{i+1}.#{config_domain}"}.join("\n")}
#{config_ubuntu_worker_ip_addresses.map.with_index{|ip_address, i|"#{ip_address} uworker#{i+1}.#{config_domain}"}.join("\n")}

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
"""

Vagrant.configure(2) do |config|
  config.vm.box = 'ubuntu-20.04-amd64'

  config.vm.provider 'libvirt' do |lv, config|
    lv.memory = 2*1024
    lv.cpus = 4
    lv.cpu_mode = 'host-passthrough'
    lv.nested = true
    lv.keymap = 'pt'
    config.vm.synced_folder '.', '/vagrant', type: 'nfs'
  end

  config.vm.provider 'virtualbox' do |vb|
    vb.linked_clone = true
    vb.memory = 2*1024
    vb.cpus = 4
  end

  config.vm.define :pandora do |config|
    config.vm.provider 'libvirt' do |lv, config|
      lv.memory = 1*1024
    end
    config.vm.provider 'virtualbox' do |vb|
      vb.memory = 1*1024
    end
    config.vm.hostname = config_pandora_fqdn
    config.vm.network :private_network, ip: config_pandora_ip_address, libvirt__forward_mode: 'route', libvirt__dhcp_enabled: false
    config.vm.network :private_network, ip: config_server_ip_address, libvirt__forward_mode: 'route', libvirt__dhcp_enabled: false
    config.vm.provision 'shell', inline: 'echo "$1" >/etc/hosts', args: [hosts]
    config.vm.provision 'shell', path: 'provision-apt-cacher.sh'
    config.vm.provision 'shell', path: 'provision-base.sh', args: [config_pandora_fqdn]
    config.vm.provision 'shell', path: 'provision-certificate.sh', args: [config_pandora_fqdn]
    config.vm.provision 'shell', path: 'provision-dns-server.sh', args: [config_pandora_ip_address, config_pandora_fqdn]
    config.vm.provision 'shell', path: 'provision-nfs-server.sh', args: [config_pandora_ip_address, "#{config_pandora_ip_address}/24"]
    config.vm.provision 'shell', path: 'provision-docker.sh', args: [config_docker_version]
    config.vm.provision 'shell', path: 'provision-registry-proxy.sh', args: [config_pandora_fqdn]
    config.vm.provision 'shell', path: 'provision-registry.sh', args: [config_pandora_fqdn]
    config.vm.provision 'shell', path: 'provision-haproxy.sh', args: [config_server_fqdn, config_server_ip_address, config_server_ip_addresses.join(',')]
  end

  config_server_ip_addresses.each_with_index do |ip_address, i|
    name = "server#{i+1}"
    fqdn = "#{name}.rancher.test"
    config.vm.define name do |config|
      config.vm.hostname = fqdn
      config.vm.network :private_network, ip: ip_address, libvirt__forward_mode: 'route', libvirt__dhcp_enabled: false
      config.vm.provision 'shell', path: 'provision-base.sh', args: [config_pandora_fqdn, config_pandora_ip_address]
      config.vm.provision 'shell', path: 'provision-certificate.sh', args: [config_server_fqdn]
      config.vm.provision 'shell', path: 'provision-dns-client.sh', args: [config_pandora_ip_address]
      config.vm.provision 'shell', path: 'provision-docker.sh', args: [config_docker_version, config_pandora_fqdn]
      config.vm.provision 'shell', path: 'provision-rke.sh', args: [
        config_pandora_fqdn,
        'controlplane,etcd,worker',
        i,
        ip_address,
        config_rke_version,
        config_k8s_version,
        config_kubectl_version,
        config_krew_version,
      ]
      config.vm.provision 'shell', path: 'provision-helm.sh', args: [config_helm_version]
      if i == 0
        config.vm.provision 'shell', path: 'provision-metallb.sh', args: [config_metallb_helm_chart_version, config_metallb_server_ip_addresses]
        config.vm.provision 'shell', path: 'provision-external-dns-pdns.sh', args: [config_pandora_fqdn, config_server_fqdn]
        config.vm.provision 'shell', path: 'provision-nfs-client.sh', args: [
          config_pandora_fqdn,
          config_nfs_client_provisioner_version,
        ]
        config.vm.provision 'shell', path: 'provision-rancher.sh', args: [
          config_pandora_fqdn,
          config_server_fqdn,
          config_admin_password,
          config_rancher_helm_chart_version,
          config_k8s_version,
        ]
        config.vm.provision 'shell', path: 'provision-rancher-cli.sh', args: [
          config_server_fqdn,
          config_rancher_cli_version,
          'local',
        ]
        config.vm.provision 'shell', path: 'provision-rancher-example-cluster.sh', args: [
          config_pandora_fqdn,
          config_server_fqdn,
          config_k8s_version,
        ]
      end
      config.vm.provision 'shell', path: 'summary.sh', args: [
        config_pandora_fqdn,
      ]
    end
  end

  config_master_ip_addresses.each_with_index do |ip_address, i|
    name = "master#{i+1}"
    fqdn = "#{name}.rancher.test"
    config.vm.define name do |config|
      config.vm.hostname = fqdn
      config.vm.network :private_network, ip: ip_address, libvirt__forward_mode: 'route', libvirt__dhcp_enabled: false
      config.vm.provision 'shell', path: 'provision-base.sh', args: [config_pandora_fqdn, config_pandora_ip_address]
      config.vm.provision 'shell', path: 'provision-certificate.sh', args: [config_server_fqdn]
      config.vm.provision 'shell', path: 'provision-dns-client.sh', args: [config_pandora_ip_address]
      config.vm.provision 'shell', path: 'provision-docker.sh', args: [config_docker_version, config_pandora_fqdn]
      config.vm.provision 'shell', path: 'provision-master.sh', args: [
        config_pandora_fqdn,
        config_server_fqdn,
        i,
        ip_address,
        config_kubectl_version,
        config_krew_version,
      ]
      config.vm.provision 'shell', path: 'provision-helm.sh', args: [config_helm_version]
      if i == 0
        config.vm.provision 'shell', path: 'provision-metallb.sh', args: [config_metallb_helm_chart_version, config_metallb_master_ip_addresses]
        config.vm.provision 'shell', path: 'provision-external-dns-pdns.sh', args: [config_pandora_fqdn, config_server_fqdn]
        config.vm.provision 'shell', path: 'provision-nfs-client.sh', args: [
          config_pandora_fqdn,
          config_nfs_client_provisioner_version,
        ]
        config.vm.provision 'shell', path: 'provision-rancher-cli.sh', args: [
          config_server_fqdn,
          config_rancher_cli_version,
          'example',
        ]
      end
    end
  end

  config_ubuntu_worker_ip_addresses.each_with_index do |ip_address, i|
    name = "uworker#{i+1}"
    fqdn = "#{name}.rancher.test"
    config.vm.define name do |config|
      config.vm.provider 'libvirt' do |lv, config|
        lv.memory = 1*1024
      end
      config.vm.provider 'virtualbox' do |vb|
        vb.memory = 1*1024
      end
      config.vm.hostname = fqdn
      config.vm.network :private_network, ip: ip_address, libvirt__forward_mode: 'route', libvirt__dhcp_enabled: false
      config.vm.provision 'shell', path: 'provision-base.sh', args: [config_pandora_fqdn, config_pandora_ip_address]
      config.vm.provision 'shell', path: 'provision-certificate.sh', args: [config_server_fqdn]
      config.vm.provision 'shell', path: 'provision-dns-client.sh', args: [config_pandora_ip_address]
      config.vm.provision 'shell', path: 'provision-docker.sh', args: [config_docker_version, config_pandora_fqdn]
      config.vm.provision 'shell', path: 'provision-ubuntu-worker.sh', args: [
        config_pandora_fqdn,
        ip_address,
        config_kubectl_version,
      ]
    end
  end
end
