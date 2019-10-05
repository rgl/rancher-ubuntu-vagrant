#!/bin/bash
set -eux

server_fqdn="${1:-server.rancher.test}"; shift || true
server_ip_address="${1:-10.1.0.3}"; shift || true
ip_addresses="${1:-10.1.0.5,10.1.0.6,10.1.0.7}"; shift || true

# install and configure haproxy as L4 TCP forwarding load balancer.
# see https://cbonte.github.io/haproxy-dconv/1.8/configuration.html#4-option%20httpchk
apt-get install -y haproxy
haproxy -vv
mv /etc/haproxy/haproxy.cfg{,.ubuntu}
cat >/etc/haproxy/haproxy.cfg <<EOF
global
  log /dev/log local0
  log /dev/log local1 notice
  chroot /var/lib/haproxy
  stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
  stats timeout 30s
  user haproxy
  group haproxy
  daemon

defaults
  log     global
  mode    http
  option  httplog
  option  dontlognull
  option  log-health-checks
  timeout connect 5000
  timeout client  50000
  timeout server  50000
  errorfile 400 /etc/haproxy/errors/400.http
  errorfile 403 /etc/haproxy/errors/403.http
  errorfile 408 /etc/haproxy/errors/408.http
  errorfile 500 /etc/haproxy/errors/500.http
  errorfile 502 /etc/haproxy/errors/502.http
  errorfile 503 /etc/haproxy/errors/503.http
  errorfile 504 /etc/haproxy/errors/504.http

defaults
  mode tcp
  timeout client 20s
  timeout server 20s
  timeout connect 4s

listen stats
  bind $server_ip_address:9000
  mode http
  stats enable
  stats uri /

listen rancher
  bind $server_ip_address:443 name rancher
  option tcplog
  log global
  option httpchk GET /healthz "HTTP/1.0\r\nHost:$server_fqdn"
  http-check expect string ok
  timeout server 1h
  balance roundrobin
  default-server inter 10s rise 3 fall 3 slowstart 60s maxconn 250 maxqueue 256 weight 100
EOF
(
  i=0
  for ip_address in `echo "$ip_addresses" | tr , ' '`; do
    ((i=i+1))
    echo "  # verify the health check with: (printf \"GET /healthz HTTP/1.0\r\nHost:$server_fqdn\r\n\r\n\"; sleep 2) | openssl s_client -connect $ip_address:443 -servername $server_fqdn -CAfile /etc/ssl/certs/ca-certificates.crt"
    echo "  server rke$i $ip_address:443 check port 443 check-ssl check-sni $server_fqdn ca-file /etc/ssl/certs/ca-certificates.crt"
  done
)>>/etc/haproxy/haproxy.cfg

# restart to apply changes.
systemctl restart haproxy

# show current statistics.
# NB this is also available at $server_ip_address:9000.
echo 'show stat' | nc -U /run/haproxy/admin.sock
