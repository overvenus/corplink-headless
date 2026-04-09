#!/usr/bin/env bash
#
# Bootstraps the Linux guest used by macOS hosts.
# This script mirrors the container runtime stack from Dockerfile:
# - corplink-service from official arm64 .deb
# - corplink-headless binary from local source
# - socks5 + privoxy + supervisor + network fixers

set -euo pipefail

readonly REPO_MOUNT="${REPO_MOUNT:-/mnt/corplink-repo}"
readonly ASSETS_MOUNT="${ASSETS_MOUNT:-/mnt/corplink-assets}"
readonly ARTIFACT_DIR="${ASSETS_MOUNT}/artifacts"
readonly DEB_FILENAME="${CORPLINK_DEB_FILENAME:?CORPLINK_DEB_FILENAME is required}"
readonly HEADLESS_BIN="${ARTIFACT_DIR}/corplink-headless"
readonly SOCKS5_BIN="${ARTIFACT_DIR}/socks5"
readonly CORPLINK_DEB="${ARTIFACT_DIR}/${DEB_FILENAME}"

if [[ "${EUID}" -ne 0 ]]; then
    echo "guest-bootstrap.sh must run as root" >&2
    exit 1
fi

require_file() {
    local file="$1"
    if [[ ! -f "${file}" ]]; then
        echo "Required file not found: ${file}" >&2
        exit 1
    fi
}

install_runtime_dependencies() {
    local packages=(
        supervisor
        privoxy
        jq
        iptables
        iproute2
        net-tools
        iputils-ping
        less
        ca-certificates
    )
    local missing=()
    local pkg
    for pkg in "${packages[@]}"; do
        if ! dpkg -s "${pkg}" >/dev/null 2>&1; then
            missing+=("${pkg}")
        fi
    done

    if [[ "${#missing[@]}" -eq 0 ]]; then
        return
    fi

    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y "${missing[@]}"
    rm -rf /var/lib/apt/lists/*
}

install_binaries() {
    mkdir -p /opt/Corplink
    install -m 0755 "${HEADLESS_BIN}" /opt/Corplink/corplink-headless
    install -m 0755 "${SOCKS5_BIN}" /usr/local/bin/socks5

    # Follow Dockerfile behavior: extract files from the official package.
    dpkg-deb -x "${CORPLINK_DEB}" /
    if [[ ! -x /opt/Corplink/corplink-service ]]; then
        echo "corplink-service was not found after extracting ${CORPLINK_DEB}" >&2
        exit 1
    fi
}

configure_services() {
    CONTAINER=1 CORPLINK_RUNTIME=vm SKIP_APT_INSTALL=1 \
        bash "${REPO_MOUNT}/scripts/install_service.sh"
    install -m 0755 "${REPO_MOUNT}/scripts/startup.sh" /startup.sh
}

write_systemd_unit() {
    cat <<'EOF' >/etc/systemd/system/corplink-headless.service
[Unit]
Description=Corplink headless runtime stack
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=CONTAINER=1
Environment=CORPLINK_RUNTIME=vm
EnvironmentFile=-/etc/default/corplink-headless
WorkingDirectory=/opt/Corplink
ExecStart=/startup.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    mkdir -p /etc/default
    touch /etc/default/corplink-headless
    chmod 0644 /etc/default/corplink-headless
}

require_file "${HEADLESS_BIN}"
require_file "${SOCKS5_BIN}"
require_file "${CORPLINK_DEB}"
require_file "${REPO_MOUNT}/scripts/install_service.sh"
require_file "${REPO_MOUNT}/scripts/startup.sh"

install_runtime_dependencies
install_binaries
configure_services
write_systemd_unit

systemctl daemon-reload
systemctl enable corplink-headless.service >/dev/null
