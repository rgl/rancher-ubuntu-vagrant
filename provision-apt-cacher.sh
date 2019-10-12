#!/bin/bash
set -eux

# provision apt-cacher-ng.
# see https://www.unix-ag.uni-kl.de/~bloch/acng/
# see https://www.unix-ag.uni-kl.de/~bloch/acng/html/index.html
apt-get install -y --no-install-recommends apt-cacher-ng

# disable all mirrors (except ubuntu).
sed -i -E 's,^(Remap-.+),#\1,' /etc/apt-cacher-ng/acng.conf 
sed -i -E 's,^#(Remap-uburep.+),\1,' /etc/apt-cacher-ng/acng.conf

# set the APT mirror that apt-cacher-ng uses.
echo 'http://nl.archive.ubuntu.com/ubuntu/' >/etc/apt-cacher-ng/backends_ubuntu

systemctl restart apt-cacher-ng
