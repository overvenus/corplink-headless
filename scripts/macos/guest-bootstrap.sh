#!/usr/bin/env bash
#
# Bootstraps the Ubuntu Minimal guest used by macOS hosts.
# Runtime intent:
# - Keep the VM lean (minimal base image)
# - Keep runtime behavior aligned with container setup
# - Use systemd to supervise the top-level stack entrypoint

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

ensure_hostname_resolution() {
    local host_name short_name
    host_name="$(hostname)"
    short_name="$(hostname -s)"
    if awk -v h1="${host_name}" -v h2="${short_name}" '
        {
            for (i = 2; i <= NF; i++) {
                if ($i == h1 || $i == h2) {
                    found = 1
                }
            }
        }
        END { exit found ? 0 : 1 }
    ' /etc/hosts; then
        return
    fi
    echo "127.0.1.1 ${host_name} ${short_name}" >>/etc/hosts
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
EnvironmentFile=-/opt/Corplink/runtime.env
WorkingDirectory=/opt/Corplink
ExecStart=/startup.sh
Restart=always
RestartSec=5
KillMode=control-group

[Install]
WantedBy=multi-user.target
EOF

    # startup.sh sources runtime.env and exports all keys for child processes.
    cat <<'EOF' >/opt/Corplink/runtime.env
COMPANY_CODE=''
CONTAINER=1
CORPLINK_RUNTIME=vm
EOF
    chmod 0600 /opt/Corplink/runtime.env
}

require_file "${HEADLESS_BIN}"
require_file "${SOCKS5_BIN}"
require_file "${CORPLINK_DEB}"
require_file "${REPO_MOUNT}/scripts/install_service.sh"
require_file "${REPO_MOUNT}/scripts/startup.sh"

ensure_hostname_resolution
install_runtime_dependencies
install_binaries
configure_services
write_systemd_unit

systemctl daemon-reload
systemctl enable corplink-headless.service >/dev/null
