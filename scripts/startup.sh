#!/usr/bin/env bash
#
# Modified from https://github.com/sleepymole/docker-corplink

if [ -z "$CONTAINER" ]; then
    echo "CONTAINER is not set, it should be run in a docker container"
    exit 1
fi

set -ex

iptables -t nat -F
iptables -t nat -A POSTROUTING -j MASQUERADE
/usr/bin/supervisord 2>/dev/null || true

while true; do {
    sleep 86400;
} done
