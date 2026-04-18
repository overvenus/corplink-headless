#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: $(basename "$0") <amd64|arm64> <output-tar.gz>" >&2
    exit 1
fi

readonly ARCH="$1"
readonly OUTPUT_TAR="$2"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly VERSION="${VERSION:-$(git -C "${REPO_ROOT}" describe --tags --always --dirty)}"

case "${ARCH}" in
amd64 | arm64)
    ;;
*)
    echo "Unsupported architecture: ${ARCH}" >&2
    exit 1
    ;;
esac

tmp_dir="$(mktemp -d)"
cleanup() {
    rm -rf "${tmp_dir}"
}
trap cleanup EXIT

mkdir -p "$(dirname "${OUTPUT_TAR}")"

(
    cd "${REPO_ROOT}"
    CGO_ENABLED=0 GOOS=linux GOARCH="${ARCH}" go build -o "${tmp_dir}/corplink-headless" .
    CGO_ENABLED=0 GOOS=linux GOARCH="${ARCH}" go build -o "${tmp_dir}/socks5" ./cmd/socks5
)

install -m 0755 "${REPO_ROOT}/scripts/install_service.sh" "${tmp_dir}/install_service.sh"
install -m 0755 "${REPO_ROOT}/scripts/startup.sh" "${tmp_dir}/startup.sh"
printf '%s\n' "${VERSION}" >"${tmp_dir}/VERSION"

tar -C "${tmp_dir}" -czf "${OUTPUT_TAR}" \
    corplink-headless \
    socks5 \
    install_service.sh \
    startup.sh \
    VERSION
