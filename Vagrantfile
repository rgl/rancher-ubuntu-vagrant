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

config_windows_prefered_cluster = true
config_server_count = 1
config_master_count = 1
config_ubuntu_worker_count = 0
config_windows_worker_count = 1
config_domain = 'rancher.test'
config_pandora_fqdn = "pandora.#{config_domain}"
config_pandora_ip_address = '10.1.0.2'
config_server_fqdn = "server.#{config_domain}"
config_server_ip_address = '10.1.0.3'
config_rancher_helm_chart_version = '2.3.1'
config_rancher_cli_version = 'v2.3.0' # see https://github.com/rancher/cli/releases
config_server_ip_addresses = generate_ip_addresses('10.1.0.5', config_server_count)
config_master_ip_addresses = generate_ip_addresses('10.1.0.10', config_master_count)
config_ubuntu_worker_ip_addresses = generate_ip_addresses('10.1.0.15', config_ubuntu_worker_count)
config_windows_worker_ip_addresses = generate_ip_addresses('10.1.0.20', config_windows_worker_count)
config_admin_password = 'admin'
config_docker_version = '5:19.03.4~3-0~ubuntu-bionic' # NB execute apt-cache madison docker-ce to known the available versions.
config_docker_version_windows = '19.03.4' # see https://github.com/rgl/docker-ce-windows-binaries-vagrant/releases
config_rke_version = 'v0.3.1' # see https://github.com/rancher/rke/releases
config_k8s_version = 'v1.16.2-rancher1-1' # see https://github.com/rancher/kontainer-driver-metadata/blob/master/rke/k8s_rke_system_images.go of the version that ships with your rke version.
config_kubectl_version = '1.16.2-00' # NB execute apt-cache madison kubectl to known the available versions.
config_kubectl_version_windows = '1.16.2' # NB see https://chocolatey.org/packages/kubernetes-cli
config_krew_version = 'v0.3.1' # NB see https://github.com/kubernetes-sigs/krew
config_helm_version = 'v2.14.3' # see https://github.com/helm/helm/releases/latest
config_metallb_helm_chart_version = '0.11.2' # see https://github.com/helm/charts/blob/master/stable/metallb/Chart.yaml
config_metallb_ip_addresses = '10.1.0.30-10.1.0.40' # MetalLB will allocate IP addresses from this range.
config_nfs_client_provisioner_version = '1.2.6' # version of https://github.com/helm/charts/blob/master/stable/nfs-client-provisioner/Chart.yaml

hosts = """
127.0.0.1	localhost
#{config_pandora_ip_address} #{config_pandora_fqdn}
#{config_server_ip_address} #{config_server_fqdn}
#{config_server_ip_addresses.map.with_index{|ip_address, i|"#{ip_address} server#{i+1}.#{config_domain}"}.join("\n")}
#{config_master_ip_addresses.map.with_index{|ip_address, i|"#{ip_address} master#{i+1}.#{config_domain}"}.join("\n")}
#{config_ubuntu_worker_ip_addresses.map.with_index{|ip_address, i|"#{ip_address} uworker#{i+1}.#{config_domain}"}.join("\n")}
#{config_windows_worker_ip_addresses.map.with_index{|ip_address, i|"#{ip_address} wworker#{i+1}.#{config_domain}"}.join("\n")}

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
"""

Vagrant.configure(2) do |config|
  config.vm.box = 'ubuntu-18.04-amd64'

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
      config.vm.provision 'shell', path: 'provision-base.sh', args: [config_pandora_fqdn]
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
      config.vm.provision 'shell', path: 'provision-helm.sh', args: [i, config_helm_version]
      if i == 0
        config.vm.provision 'shell', path: 'provision-metallb.sh', args: [config_metallb_helm_chart_version, config_metallb_ip_addresses]
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
          config_rancher_cli_version,
          config_k8s_version,
        ]
        config.vm.provision 'shell', path: 'provision-rancher-example-cluster.sh', args: [
          config_pandora_fqdn,
          config_server_fqdn,
          config_k8s_version,
          config_windows_prefered_cluster && 'true' || 'false',
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
      config.vm.provider 'libvirt' do |lv, config|
        lv.memory = 1*1024
      end
      config.vm.provider 'virtualbox' do |vb|
        vb.memory = 1*1024
      end
      config.vm.hostname = fqdn
      config.vm.network :private_network, ip: ip_address, libvirt__forward_mode: 'route', libvirt__dhcp_enabled: false
      config.vm.provision 'shell', path: 'provision-base.sh', args: [config_pandora_fqdn]
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
      config.vm.provision 'shell', path: 'provision-base.sh', args: [config_pandora_fqdn]
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

  if config_windows_prefered_cluster
    config_windows_worker_ip_addresses.each_with_index do |ip_address, i|
      name = "wworker#{i+1}"
      fqdn = "#{name}.rancher.test"
      config.vm.define name do |config|
        config.vm.provider 'libvirt' do |lv, config|
          lv.memory = 5*1024
          config.vm.synced_folder '.', '/vagrant', type: 'smb', smb_username: ENV['USER'], smb_password: ENV['VAGRANT_SMB_PASSWORD']
        end
        config.vm.provider 'virtualbox' do |vb|
          vb.memory = 5*1024
        end
        config.vm.box = 'windows-2019-amd64'
        config.vm.hostname = fqdn.split('.').first
        config.vm.network :private_network, ip: ip_address, libvirt__forward_mode: 'route', libvirt__dhcp_enabled: false
        config.vm.provision 'shell', path: 'ps.ps1', args: 'provision-certificates.ps1'
        config.vm.provision 'shell', path: 'ps.ps1', args: 'provision-containers-feature.ps1', reboot: true
        config.vm.provision 'shell', path: 'ps.ps1', args: ['provision-dns-client.ps1', config_pandora_ip_address]
        config.vm.provision 'shell', inline: "$env:chocolateyVersion='0.10.15'; iwr https://chocolatey.org/install.ps1 -UseBasicParsing | iex", name: "Install Chocolatey"
        config.vm.provision 'shell', path: 'ps.ps1', args: 'provision-base.ps1'
        # NB as of rancher 2.3.0 requires Docker EE.
        #    see https://github.com/rancher/rancher/issues/23418
        #config.vm.provision 'shell', path: 'ps.ps1', args: ['provision-docker-ce.ps1', config_docker_version_windows]
        config.vm.provision 'shell', path: 'ps.ps1', args: ['provision-docker-ee.ps1', config_docker_version_windows]
        config.vm.provision 'shell', path: 'ps.ps1', args: ['provision-windows-worker.ps1',
          config_pandora_fqdn,
          ip_address,
          config_kubectl_version_windows,
        ]
      end
    end
  end
end
