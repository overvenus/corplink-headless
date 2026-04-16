#!/usr/bin/env bash
#
# Corplink headless runtime on macOS (Apple Silicon).
# This orchestrates an arm64 Ubuntu Minimal VM backed by Apple's Virtualization
# framework via Lima (vmType=vz), then installs the runtime stack.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly LIMA_TEMPLATE="${SCRIPT_DIR}/lima-vz.yaml.tmpl"

INSTANCE_NAME="${CORPLINK_VM_NAME:-corplink-headless}"
STATE_DIR="${CORPLINK_STATE_DIR:-${HOME}/.corplink-headless}"
ARTIFACT_DIR="${STATE_DIR}/artifacts"
LIMA_CONFIG="${STATE_DIR}/lima-vz.yaml"

CORPLINK_ARM64_DEB_URL="${CORPLINK_ARM64_DEB_URL:-https://cdn.isealsuite.com/linux/FeiLian_Linux_arm64_v2.1.27_r2711_d2baf1.deb}"
CORPLINK_ARM64_DEB_SHA256="${CORPLINK_ARM64_DEB_SHA256:-}"
HTTP_PORT="${CORPLINK_HTTP_PORT:-8888}"
SOCKS_PORT="${CORPLINK_SOCKS5_PORT:-1088}"

DEB_FILENAME=""

usage() {
    cat <<EOF
Usage:
  $(basename "$0") up --company-code <code> [--refresh-deb]
  $(basename "$0") logs [-f] [-n lines]
  $(basename "$0") status
  $(basename "$0") shell
  $(basename "$0") down
  $(basename "$0") destroy [--purge-state]
  $(basename "$0") doctor

Environment overrides:
  CORPLINK_VM_NAME           VM instance name (default: ${INSTANCE_NAME})
  CORPLINK_STATE_DIR         Local state dir (default: ${STATE_DIR})
  CORPLINK_ARM64_DEB_URL     Corplink arm64 package URL
  CORPLINK_ARM64_DEB_SHA256  Optional SHA256 verification for downloaded package
  CORPLINK_HTTP_PORT         Host port -> guest 8118 (default: ${HTTP_PORT})
  CORPLINK_SOCKS5_PORT       Host port -> guest 1080 (default: ${SOCKS_PORT})
EOF
}

die() {
    echo "Error: $*" >&2
    exit 1
}

need_cmd() {
    local cmd="$1"
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        die "Required command not found: ${cmd}"
    fi
}

check_host_platform() {
    [[ "$(uname -s)" == "Darwin" ]] || die "This command requires macOS."
    [[ "$(uname -m)" == "arm64" ]] || die "This command requires Apple Silicon (arm64)."
}

escape_sed() {
    printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

escape_shell_single_quoted() {
    # Return content safe for embedding inside single quotes in POSIX shell.
    printf '%s' "$1" | sed "s/'/'\"'\"'/g"
}

lima_shell() {
    # Avoid "cd /Users/...: No such file or directory" noise by forcing
    # guest working directory to root.
    if limactl shell --help 2>&1 | grep -q -- '--workdir'; then
        limactl shell --workdir / "${INSTANCE_NAME}" "$@"
    else
        LIMA_WORKDIR=/ limactl shell "${INSTANCE_NAME}" "$@"
    fi
}

instance_exists() {
    limactl list --json 2>/dev/null | grep -Fq "\"name\":\"${INSTANCE_NAME}\""
}

instance_running() {
    lima_shell true >/dev/null 2>&1
}

require_instance_running() {
    instance_running || die "VM '${INSTANCE_NAME}' is not running. Start it with: $0 up --company-code <code>"
}

validate_port() {
    local port="$1"
    [[ "${port}" =~ ^[0-9]+$ ]] || die "Invalid port: ${port}"
    ((port >= 1 && port <= 65535)) || die "Port out of range: ${port}"
}

prepare_state_dir() {
    mkdir -p "${ARTIFACT_DIR}"
}

prepare_binaries() {
    echo "Building corplink-headless (linux/arm64) ..."
    (
        cd "${REPO_ROOT}"
        GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
            go build -o "${ARTIFACT_DIR}/corplink-headless" .
    )
    chmod +x "${ARTIFACT_DIR}/corplink-headless"

    echo "Building socks5 helper (linux/arm64) ..."
    (
        cd "${REPO_ROOT}"
        GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
            go build -o "${ARTIFACT_DIR}/socks5" ./cmd/socks5
    )
    chmod +x "${ARTIFACT_DIR}/socks5"
}

prepare_corplink_deb() {
    local refresh="${1:-0}"
    DEB_FILENAME="$(basename "${CORPLINK_ARM64_DEB_URL%%\?*}")"
    local deb_path="${ARTIFACT_DIR}/${DEB_FILENAME}"
    if [[ "${refresh}" == "1" || ! -f "${deb_path}" ]]; then
        echo "Downloading corplink arm64 package ..."
        curl -fL --retry 3 --retry-delay 2 -o "${deb_path}" "${CORPLINK_ARM64_DEB_URL}"
    fi

    if [[ -n "${CORPLINK_ARM64_DEB_SHA256}" ]]; then
        local actual_sha256
        actual_sha256="$(shasum -a 256 "${deb_path}" | awk '{print $1}')"
        [[ "${actual_sha256}" == "${CORPLINK_ARM64_DEB_SHA256}" ]] || {
            die "SHA256 mismatch for ${deb_path}. expected=${CORPLINK_ARM64_DEB_SHA256} got=${actual_sha256}"
        }
    fi
}

render_lima_config() {
    local repo_escaped assets_escaped
    repo_escaped="$(escape_sed "${REPO_ROOT}")"
    assets_escaped="$(escape_sed "${STATE_DIR}")"
    sed \
        -e "s|__REPO_DIR__|${repo_escaped}|g" \
        -e "s|__ASSETS_DIR__|${assets_escaped}|g" \
        -e "s|__HTTP_PORT__|${HTTP_PORT}|g" \
        -e "s|__SOCKS_PORT__|${SOCKS_PORT}|g" \
        "${LIMA_TEMPLATE}" >"${LIMA_CONFIG}"
}

start_vm_if_needed() {
    if instance_running; then
        return
    fi
    if instance_exists; then
        echo "Starting existing VM '${INSTANCE_NAME}' ..."
        limactl start "${INSTANCE_NAME}"
        return
    fi
    echo "Creating VM '${INSTANCE_NAME}' with Apple Virtualization (vz) ..."
    render_lima_config
    limactl start --name "${INSTANCE_NAME}" "${LIMA_CONFIG}"
}

bootstrap_guest_runtime() {
    if ! lima_shell sh -c 'command -v apt-get >/dev/null 2>&1'; then
        die "VM '${INSTANCE_NAME}' is not Ubuntu-based. Run: $0 destroy --purge-state, then run up again."
    fi

    local attempts=5
    local i
    for i in $(seq 1 "${attempts}"); do
        if lima_shell \
            sudo \
            REPO_MOUNT=/mnt/corplink-repo \
            ASSETS_MOUNT=/mnt/corplink-assets \
            CORPLINK_DEB_FILENAME="${DEB_FILENAME}" \
            bash /mnt/corplink-repo/scripts/macos/guest-bootstrap.sh; then
            return
        fi
        if [[ "${i}" -lt "${attempts}" ]]; then
            echo "Guest bootstrap failed (attempt ${i}/${attempts}), retrying ..."
            sleep 5
        fi
    done
    die "Guest bootstrap failed after ${attempts} attempts."
}

configure_company_code() {
    local company_code="$1"
    local escaped_company_code
    escaped_company_code="$(escape_shell_single_quoted "${company_code}")"
    lima_shell \
        sudo bash -c "cat > /opt/Corplink/runtime.env <<EOF
COMPANY_CODE='${escaped_company_code}'
CONTAINER=1
CORPLINK_RUNTIME=vm
EOF
chmod 0600 /opt/Corplink/runtime.env"
}

restart_runtime_service() {
    lima_shell sudo systemctl daemon-reload
    lima_shell sudo systemctl restart corplink-headless.service
    lima_shell sudo systemctl is-active --quiet corplink-headless.service || {
        lima_shell sudo journalctl -u corplink-headless.service --no-pager -n 80
        lima_shell sudo tail -n 80 /var/log/corplink-headless/stderr.log 2>/dev/null || true
        lima_shell sudo tail -n 80 /var/log/corplink/stderr.log 2>/dev/null || true
        die "corplink-headless.service is not active."
    }
}

cmd_up() {
    local company_code="${COMPANY_CODE:-}"
    local refresh_deb=0
    need_cmd go
    need_cmd curl
    need_cmd shasum

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        --company-code)
            [[ "$#" -ge 2 ]] || die "Missing value for --company-code"
            company_code="$2"
            shift 2
            ;;
        --refresh-deb)
            refresh_deb=1
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            die "Unknown option for up: $1"
            ;;
        esac
    done
    [[ -n "${company_code}" ]] || die "company code is required. Use --company-code or COMPANY_CODE env."

    validate_port "${HTTP_PORT}"
    validate_port "${SOCKS_PORT}"
    prepare_state_dir
    prepare_binaries
    prepare_corplink_deb "${refresh_deb}"
    start_vm_if_needed
    bootstrap_guest_runtime
    configure_company_code "${company_code}"
    restart_runtime_service

    cat <<EOF
Corplink headless is running in VM '${INSTANCE_NAME}'.
HTTP proxy:  127.0.0.1:${HTTP_PORT}
SOCKS5 proxy: 127.0.0.1:${SOCKS_PORT}

To scan login QR code:
  $0 logs -f
EOF
}

cmd_logs() {
    local follow=0
    local lines=80
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        -f | --follow)
            follow=1
            shift
            ;;
        -n | --lines)
            [[ "$#" -ge 2 ]] || die "Missing value for --lines"
            lines="$2"
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            die "Unknown option for logs: $1"
            ;;
        esac
    done
    [[ "${lines}" =~ ^[0-9]+$ ]] || die "Invalid lines count: ${lines}"
    require_instance_running

    if [[ "${follow}" == "1" ]]; then
        lima_shell sudo tail -n "${lines}" -f /var/log/corplink-headless/stdout.log
    else
        lima_shell sudo tail -n "${lines}" /var/log/corplink-headless/stdout.log
    fi
}

cmd_status() {
    if ! instance_exists; then
        echo "VM '${INSTANCE_NAME}' does not exist."
        return
    fi
    limactl list
    if instance_running; then
        echo
        lima_shell sudo systemctl --no-pager status corplink-headless.service
    fi
}

cmd_shell() {
    require_instance_running
    lima_shell
}

cmd_down() {
    if ! instance_exists; then
        echo "VM '${INSTANCE_NAME}' does not exist."
        return
    fi
    limactl stop "${INSTANCE_NAME}"
}

cmd_destroy() {
    local purge_state=0
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        --purge-state)
            purge_state=1
            shift
            ;;
        *)
            die "Unknown option for destroy: $1"
            ;;
        esac
    done

    if instance_exists; then
        limactl delete --force "${INSTANCE_NAME}"
    fi
    if [[ "${purge_state}" == "1" ]]; then
        rm -rf "${STATE_DIR}"
    fi
}

cmd_doctor() {
    check_host_platform
    need_cmd limactl
    need_cmd go
    need_cmd curl
    need_cmd shasum
    echo "Host checks passed."
    echo "instance: ${INSTANCE_NAME}"
    echo "state dir: ${STATE_DIR}"
    echo "deb url: ${CORPLINK_ARM64_DEB_URL}"
}

main() {
    local command="${1:-}"
    if [[ -z "${command}" ]]; then
        usage
        exit 1
    fi
    shift || true

    check_host_platform
    need_cmd limactl

    case "${command}" in
    up)
        cmd_up "$@"
        ;;
    logs)
        cmd_logs "$@"
        ;;
    status)
        cmd_status "$@"
        ;;
    shell)
        cmd_shell "$@"
        ;;
    down)
        cmd_down "$@"
        ;;
    destroy)
        cmd_destroy "$@"
        ;;
    doctor)
        cmd_doctor "$@"
        ;;
    -h | --help | help)
        usage
        ;;
    *)
        die "Unknown command: ${command}"
        ;;
    esac
}

main "$@"
