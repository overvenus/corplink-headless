#!/usr/bin/env bash
#
# Modified from https://github.com/sleepymole/docker-corplink

if [ -z "$CONTAINER" ]; then
    echo "CONTAINER is not set, it should be run in a docker container"
    exit 1
fi

set -ex

apt-get update
apt-get install -y \
    supervisor \
    privoxy \
    jq \
    iptables \
    iproute2 \
    net-tools \
    iputils-ping \
    less \
    ca-certificates && \
rm -rf /var/lib/apt/lists/*

# corplink-service
mkdir -p /var/log/corplink/
cat <<EOF >/etc/supervisor/conf.d/corplink.conf
[program:corplink]
command=/opt/Corplink/corplink-service
autostart=true
autorestart=true
stderr_logfile=/var/log/corplink/stderr.log
stdout_logfile=/var/log/corplink/stdout.log
priority=1
startsecs=3
EOF

# corplink-headless
mkdir -p /var/log/corplink-headless/
cat <<EOF >/etc/supervisor/conf.d/corplink-headless.conf
[program:corplink-headless]
command=/opt/Corplink/corplink-headless
autostart=true
autorestart=true
stderr_logfile=/var/log/corplink-headless/stderr.log
stdout_logfile=/var/log/corplink-headless/stdout.log
priority=2
EOF

# Privoxy
mkdir -p /var/log/privoxy
cat <<EOF >/etc/supervisor/conf.d/privoxy.conf
[program:privoxy]
command=/usr/sbin/privoxy --no-daemon /etc/privoxy/config
autostart=true
autorestart=true
stderr_logfile=/var/log/privoxy/stderr.log
stdout_logfile=/var/log/privoxy/stdout.log
EOF
sed -i '/^listen-address/d' /etc/privoxy/config
echo 'listen-address 0.0.0.0:8118' >>/etc/privoxy/config

# Socks5 server
mkdir -p /var/log/socks5/
cat <<EOF >/etc/supervisor/conf.d/socks5.conf
[program:socks5]
command=/usr/local/bin/socks5
autostart=true
autorestart=true
stderr_logfile=/var/log/socks5/stderr.log
stdout_logfile=/var/log/socks5/stdout.log
EOF

# Automatic fix dns
cat <<EOF >/usr/local/bin/fixdns.sh
#!/bin/bash
set -x
while true; do
  sleep 5
  dns=\$(jq -r '.DNS[0]' /opt/Corplink/vpn.conf  2>/dev/null)
  [ -z "\$dns" ] && continue
  grep -q "\$dns" /etc/resolv.conf && continue
  echo "nameserver \${dns}" >/etc/resolv.conf
  echo "nameserver 114.114.114.114" >>/etc/resolv.conf
  echo "nameserver 1.1.1.1" >>/etc/resolv.conf
done
EOF
chmod +x /usr/local/bin/fixdns.sh
mkdir -p /var/log/fixdns/
cat <<EOF >/etc/supervisor/conf.d/fixdns.conf
[program:fixdns]
command=/usr/local/bin/fixdns.sh
autostart=true
autorestart=true
stderr_logfile=/var/log/fixdns/stderr.log
stdout_logfile=/var/log/fixdns/stdout.log
EOF

# Fix ssh stuck at debug1: expecting SSH2_MSG_KEX_DH_GEX_REPLY
# See https://serverfault.com/a/670081
cat <<EOF >/usr/local/bin/fixsshmtu.sh
#!/bin/bash
set -x
while true; do
  sleep 10
  mtu=\$(cat /sys/class/net/utun/mtu  2>/dev/null)
  [[ "\$mtu" -eq 1200 ]] && continue
  ifconfig utun mtu 1200
done
EOF
chmod +x /usr/local/bin/fixsshmtu.sh
mkdir -p /var/log/fixsshmtu/
cat <<EOF >/etc/supervisor/conf.d/fixsshmtu.conf
[program:fixsshmtu]
command=/usr/local/bin/fixsshmtu.sh
autostart=true
autorestart=true
stderr_logfile=/var/log/fixsshmtu/stderr.log
stdout_logfile=/var/log/fixsshmtu/stdout.log
EOF
