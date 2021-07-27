#!/bin/bash
set -eux

pandora_fqdn="${1:-pandora.rancher.test}"; shift || true
pandora_ip_address="${1:-10.10.0.2}"; shift || true

# prevent apt-get et al from asking questions.
# NB even with this, you'll still get some warnings that you can ignore:
#     dpkg-preconfigure: unable to re-open stdin: No such file or directory
export DEBIAN_FRONTEND=noninteractive

# show mac addresses and the machine uuid to troubleshoot they are unique within the cluster.
ip link
cat /sys/class/dmi/id/product_uuid

# configure APT to use our cache APT proxy.
# NB we cannot use APT::Update::Pre-Invoke because that is invoked after sources.list is
#    loaded, so we had to override the apt-get command with our own version.
cat >/etc/apt/apt.conf.d/00aptproxy <<EOF
Acquire::http::Proxy "http://$pandora_fqdn:3142";
EOF
cat >/usr/local/bin/apt-get <<EOF
#!/bin/bash
if [ "\$1" == 'update' ]; then
    for p in \$(find /etc/apt/sources.list /etc/apt/sources.list.d -type f); do
        sed -i -E 's,(deb(-src)? .*)https://,\1http://$pandora_fqdn:3142/,g' \$p
    done
fi
exec /usr/bin/apt-get "\$@"
EOF
chmod +x /usr/local/bin/apt-get
hash -r
echo "$pandora_ip_address $pandora_fqdn" >>/etc/hosts

# update the package cache.
apt-get update

# install jq.
apt-get install -y jq

# install vim.
apt-get install -y --no-install-recommends vim
cat >/etc/vim/vimrc.local <<'EOF'
syntax on
set background=dark
set esckeys
set ruler
set laststatus=2
set nobackup
EOF

# configure the shell.
cat >/etc/profile.d/login.sh <<'EOF'
[[ "$-" != *i* ]] && return
export EDITOR=vim
export PAGER=less
alias l='ls -lF --color'
alias ll='l -a'
alias h='history 25'
alias j='jobs -l'
EOF

cat >/etc/inputrc <<'EOF'
set input-meta on
set output-meta on
set show-all-if-ambiguous on
set completion-ignore-case on
"\e[A": history-search-backward
"\e[B": history-search-forward
"\eOD": backward-word
"\eOC": forward-word
EOF
