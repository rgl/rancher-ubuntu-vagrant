# About

This is a [ha rancher](https://rancher.com/docs/rancher/v2.x/en/installation/ha/) environment.

## Usage

Install the [ubuntu-20.04-amd64](https://github.com/rgl/ubuntu-vagrant) box.

Launch the environment:

```bash
vagrant up --no-destroy-on-error --provider=libvirt # or --provider=virtualbox
```

Configure your host DNS resolver to delegate the `rancher.test` domain to the `pandora` machine like described in this document. Or add the environment hosts to your machine `hosts` file:

```plain
10.10.0.2 pandora.rancher.test
10.10.0.3 server.rancher.test
10.10.0.5 server1.rancher.test
10.10.0.6 server2.rancher.test
10.10.0.7 server3.rancher.test
```

Access the rancher server at https://server.rancher.test and login with the default `admin` username and password.

The rancher load balancer statistics are at http://server.rancher.test:9000.

The docker registry is at https://pandora.rancher.test:5000.

The apt-cacher is at http://pandora.rancher.test:3142/acng-report.html (click the "Count Data" button to see the cache statistics).

You can access the example cluster from the host with, e.g.:

```bash
export KUBECONFIG=$PWD/shared/admin.conf
kubectl version --short
kubectl cluster-info
kubectl api-versions
kubectl api-resources -o wide
kubectl get namespaces
kubectl get all --all-namespaces -o wide
kubectl get events --all-namespaces --sort-by=.metadata.creationTimestamp
```

## DNS

Make sure that all of the following commands return the IP address of our `pandora` dns server:

```bash
docker run -it --rm --name test debian:buster-slim cat /etc/resolv.conf # => nameserver 10.10.0.2
kubectl --namespace ingress-nginx \
    exec \
    $(kubectl --namespace ingress-nginx get pods -l app=ingress-nginx -o name) \
    -- \
    cat /etc/resolv.conf # => nameserver 10.10.0.2
kubectl --namespace ingress-nginx \
    exec \
    $(kubectl --namespace ingress-nginx get pods -l app=ingress-nginx -o name) \
    -- \
    cat /etc/nginx/nginx.conf | grep resolver # => resolver 10.10.0.2 valid=30s;
```

## Host DNS resolver

To delegate the `rancher.test` zone to the kubernetes managed external dns server (running in pandora) you need to configure your system to delegate that DNS zone to the pandora DNS server, for that, you can configure your system to only use dnsmasq.

For example, on my Ubuntu 20.04 Desktop, I have uninstalled `resolvconf`, disabled `NetworkManager`, and manually configured the network interfaces:

```bash
sudo su -l
for n in NetworkManager NetworkManager-wait-online NetworkManager-dispatcher network-manager; do
    systemctl mask --now $n
done
apt-get remove --purge resolvconf
cat >/etc/network/interfaces <<'EOF'
# interfaces(5) file used by ifup(8) and ifdown(8)
auto lo
iface lo inet loopback

auto enp3s0
iface enp3s0 inet dhcp
EOF
reboot
```

Then, replaced `systemd-resolved` with `dnsmasq`:

```bash
sudo su -l
apt-get install -y --no-install-recommends dnsutils dnsmasq
systemctl mask --now systemd-resolved
cat >/etc/dnsmasq.d/local.conf <<EOF
no-resolv
bind-interfaces
interface=lo
listen-address=127.0.0.1
# delegate the rancher.test zone to the pandora DNS server IP address.
server=/rancher.test/10.10.0.2
# delegate to the Cloudflare/APNIC Public DNS IP addresses.
# NB iif there's no entry in /etc/hosts.
server=1.1.1.1
server=1.0.0.1
# delegate to the Google Public DNS IP addresses.
# NB iif there's no entry in /etc/hosts.
#server=8.8.8.8
#server=8.8.4.4
EOF
rm /etc/resolv.conf
cat >/etc/resolv.conf <<EOF
nameserver 127.0.0.1
EOF
systemctl restart dnsmasq
exit
```

Then start all the machines and test the DNS resolution:

```bash
vagrant up
dig pandora.rancher.test
dig server.rancher.test
```

## References

* https://rancher.com/docs/rancher/v2.x/en/troubleshooting/kubernetes-components/
* https://github.com/rancher/quickstart
* https://github.com/rancher/api-spec
* https://kubernetes.io/docs/reference/kubectl/cheatsheet/
* https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/
