#!/usr/bin/env bash
# =============================================================================
# OpenSSL 1.1.1w: required by PowerShell 7.5 (which is built against 1.1, not 3.x).
# Bootstrap already has OpenSSL 3.x; we build 1.1 as a parallel install ONLY
# for pwsh's private use. NOT shared with Python or other tools.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/.."

source "${COMMON_DIR}/tool-versions.sh"
source "${SCRIPT_DIR}/_sandbox.sh"
source "${SCRIPT_DIR}/_download.sh"
source "${SCRIPT_DIR}/_relocate.sh"

TOOL_NAME="openssl11"
VERSION="${TOOL_OPENSSL11_VERSION}"
PLATFORM="${PLATFORM:-linux-x86_64}"

ARCHIVE_NAME="openssl-${VERSION}.tar.gz"
URL="https://www.openssl.org/source/${ARCHIVE_NAME}"

# Internal helper dir (consumed by pwsh.sh)
TOOL_DIR="${TOOLS_CACHE_DIR}/built/_deps/${TOOL_NAME}"
WORK_DIR="${TOOLS_CACHE_DIR}/work/${TOOL_NAME}-${VERSION}"

log "Building ${TOOL_NAME} v${VERSION} (pwsh dep) for ${PLATFORM}"
sandbox_log

# 1. Source
download_file "${URL}" "${ARCHIVE_NAME}"
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
extract_archive "${SOURCES_DIR}/${ARCHIVE_NAME}" "${WORK_DIR}" 1

cd "${WORK_DIR}"

# 2. Configure
# OpenSSL 1.1.1 uses Configure (Perl). Targets:
#   linux-x86_64, linux-aarch64
case "${PLATFORM}" in
    linux-x86_64) OS_ARCH_TARGET="linux-x86_64" ;;
    linux-aarch64) OS_ARCH_TARGET="linux-aarch64" ;;
    *) err "unsupported PLATFORM=${PLATFORM} for openssl11"; exit 1 ;;
esac

./Configure "${OS_ARCH_TARGET}" \
    --prefix="${TOOL_DIR}" \
    --openssldir="${TOOL_DIR}/ssl" \
    no-shared no-static-engine no-tests no-docs \
    shared \
    -fPIC

# 3. Build + install (no docs, no tests for speed)
make -j"$(nproc)"

rm -rf "${TOOL_DIR}"
make install_sw   # install software only (no man pages)

log "${TOOL_NAME} (internal dep) installed to ${TOOL_DIR}"
ls "${TOOL_DIR}/lib/" | head
"${TOOL_DIR}/bin/openssl" version
