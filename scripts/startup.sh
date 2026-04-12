#!/usr/bin/env sh
#
# Modified from https://github.com/sleepymole/docker-corplink

if [ -z "${CONTAINER:-}" ] && [ "${CORPLINK_RUNTIME:-}" != "vm" ]; then
    echo "Neither CONTAINER=1 nor CORPLINK_RUNTIME=vm is set"
    exit 1
fi

set -ex

# macOS VM runtime stores persistent env here. Export before launching supervisord
# so every managed process (especially corplink-headless) receives COMPANY_CODE.
if [ -f /opt/Corplink/runtime.env ]; then
    set -a
    . /opt/Corplink/runtime.env
    set +a
fi

iptables -t nat -F
iptables -t nat -A POSTROUTING -j MASQUERADE

if [ -f /etc/supervisord.conf ]; then
    /usr/bin/supervisord -c /etc/supervisord.conf 2>/dev/null || true
elif [ -f /etc/supervisor/supervisord.conf ]; then
    /usr/bin/supervisord -c /etc/supervisor/supervisord.conf 2>/dev/null || true
else
    /usr/bin/supervisord 2>/dev/null || true
fi

while true; do
    sleep 86400
done
