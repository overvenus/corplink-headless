#!/usr/bin/env bash

set -euo pipefail

readonly RELEASE_DIR="/opt/corplink-release"
readonly RUNTIME_ASSET="corplink-headless-runtime-linux-arm64.tar.gz"
readonly RUNTIME_URL="https://github.com/overvenus/corplink-headless/releases/latest/download/${RUNTIME_ASSET}"
readonly CHECKSUMS_URL="https://github.com/overvenus/corplink-headless/releases/latest/download/corplink-headless-runtime-sha256sum.txt"
readonly CORPLINK_DEB_URL="https://cdn.isealsuite.com/linux/FeiLian_Linux_arm64_v2.1.27_r2711_d2baf1.deb"
readonly CORPLINK_DEB_PATH="${RELEASE_DIR}/$(basename "${CORPLINK_DEB_URL}")"
readonly RUNTIME_TAR_PATH="${RELEASE_DIR}/${RUNTIME_ASSET}"
readonly CHECKSUMS_PATH="${RELEASE_DIR}/corplink-headless-runtime-sha256sum.txt"

download() {
    local url="$1"
    local output="$2"
    curl -fsSL --retry 3 --retry-delay 2 -o "${output}" "${url}"
}

export DEBIAN_FRONTEND=noninteractive
if ! command -v curl >/dev/null 2>&1; then
    apt-get update
    apt-get install -y --no-install-recommends curl ca-certificates
    rm -rf /var/lib/apt/lists/*
fi

mkdir -p "${RELEASE_DIR}"

download "${CHECKSUMS_URL}" "${CHECKSUMS_PATH}"
expected_checksum="$(awk -v asset="${RUNTIME_ASSET}" '$2 == asset { print $1; exit }' "${CHECKSUMS_PATH}")"
[ -n "${expected_checksum}" ] || {
    echo "Failed to find checksum for ${RUNTIME_ASSET}" >&2
    exit 1
}

if [ -f "${RUNTIME_TAR_PATH}" ]; then
    local_checksum="$(sha256sum "${RUNTIME_TAR_PATH}" | awk '{ print $1 }')"
else
    local_checksum=""
fi

if [ "${local_checksum}" != "${expected_checksum}" ]; then
    download "${RUNTIME_URL}" "${RUNTIME_TAR_PATH}"
fi

(cd "${RELEASE_DIR}" && grep " ${RUNTIME_ASSET}\$" "${CHECKSUMS_PATH}" | sha256sum -c -)
tar -xzf "${RUNTIME_TAR_PATH}" -C "${RELEASE_DIR}"

if [ ! -f "${CORPLINK_DEB_PATH}" ]; then
    download "${CORPLINK_DEB_URL}" "${CORPLINK_DEB_PATH}"
fi

CORPLINK_RUNTIME=vm \
COMPANY_CODE="${PARAM_COMPANY_CODE:-}" \
CORPLINK_HEADLESS_BIN="${RELEASE_DIR}/corplink-headless" \
CORPLINK_SOCKS5_BIN="${RELEASE_DIR}/socks5" \
CORPLINK_STARTUP_SCRIPT="${RELEASE_DIR}/startup.sh" \
CORPLINK_PACKAGE_DEB="${CORPLINK_DEB_PATH}" \
bash "${RELEASE_DIR}/install_service.sh"
