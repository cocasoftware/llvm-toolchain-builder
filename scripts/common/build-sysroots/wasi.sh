#!/usr/bin/env bash
# =============================================================================
# Build sysroots/wasm32-wasi from wasi-sdk official release tarball.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

WASI_SDK_VERSION="${SYSROOT_WASI_SDK_VERSION:-30.0}"
TRIPLE="wasm32-wasi"

SYSROOT_DIR="${SYSROOTS_CACHE_DIR}/${TRIPLE}"
WORK_DIR="${SYSROOTS_WORK_DIR}/${TRIPLE}"

log "Building sysroot ${TRIPLE} from wasi-sdk ${WASI_SDK_VERSION}"

rm -rf "${WORK_DIR}" "${SYSROOT_DIR}"
mkdir -p "${WORK_DIR}" "${SYSROOT_DIR}"

# wasi-sdk releases:
#   https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-30/wasi-sysroot-30.0.tar.gz
ARCHIVE_NAME="wasi-sysroot-${WASI_SDK_VERSION}.tar.gz"
URL="https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${WASI_SDK_VERSION%%.*}/${ARCHIVE_NAME}"

log "Downloading ${URL}"
curl --fail --location --silent --show-error \
     --output "${WORK_DIR}/${ARCHIVE_NAME}" "${URL}"

# Extract — wasi-sysroot tarball has a top-level wasi-sysroot/ dir
tar -xzf "${WORK_DIR}/${ARCHIVE_NAME}" -C "${WORK_DIR}"

# wasi-sysroot folder content goes directly to SYSROOT_DIR
if [[ -d "${WORK_DIR}/wasi-sysroot-${WASI_SDK_VERSION}" ]]; then
    cp -a "${WORK_DIR}/wasi-sysroot-${WASI_SDK_VERSION}/." "${SYSROOT_DIR}/"
elif [[ -d "${WORK_DIR}/wasi-sysroot" ]]; then
    cp -a "${WORK_DIR}/wasi-sysroot/." "${SYSROOT_DIR}/"
else
    err "wasi-sysroot dir not found in extracted archive"
    ls "${WORK_DIR}"
    exit 1
fi

# Verify
if [[ ! -e "${SYSROOT_DIR}/include/wasi/api.h" ]]; then
    err "wasi-sdk sysroot missing include/wasi/api.h"
    find "${SYSROOT_DIR}" -name 'api.h' 2>/dev/null
    exit 1
fi

log "sysroot ${TRIPLE} complete"
du -sh "${SYSROOT_DIR}"
