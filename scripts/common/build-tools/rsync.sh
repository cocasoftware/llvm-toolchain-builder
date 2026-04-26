#!/usr/bin/env bash
# =============================================================================
# rsync: small C tool, autoconf-based.
# Compiled with Stage 2 clang. Pure C, no libc++ dep.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/.."

source "${COMMON_DIR}/tool-versions.sh"
source "${SCRIPT_DIR}/_sandbox.sh"
source "${SCRIPT_DIR}/_download.sh"
source "${SCRIPT_DIR}/_relocate.sh"

TOOL_NAME="rsync"
VERSION="${TOOL_RSYNC_VERSION}"
PLATFORM="${PLATFORM:-linux-x86_64}"

ARCHIVE_NAME="rsync-${VERSION}.tar.gz"
URL="https://download.samba.org/pub/rsync/src/${ARCHIVE_NAME}"

TOOL_DIR="${TOOLS_CACHE_DIR}/built/${TOOL_NAME}"
WORK_DIR="${TOOLS_CACHE_DIR}/work/${TOOL_NAME}-${VERSION}"

log "Building ${TOOL_NAME} v${VERSION} for ${PLATFORM}"
sandbox_log

# 1. Source
download_file "${URL}" "${ARCHIVE_NAME}"
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
extract_archive "${SOURCES_DIR}/${ARCHIVE_NAME}" "${WORK_DIR}" 1

# 2. Configure (rsync optionally links against zlib/popt/zstd/lz4/openssl/xxhash)
# Disable optional features that pull external deps to keep self-contained.
cd "${WORK_DIR}"

# rsync 3.x configure quirk: it has its own bundled zlib, popt, etc.
./configure \
    --prefix="${TOOL_DIR}-staging" \
    --disable-acl-support \
    --disable-xattr-support \
    --disable-iconv \
    --disable-md2man \
    --disable-zstd \
    --disable-lz4 \
    --disable-xxhash \
    --disable-openssl \
    --with-included-zlib \
    --with-included-popt

# 3. Build + install to staging
make -j"$(nproc)"

rm -rf "${TOOL_DIR}-staging" "${TOOL_DIR}"
mkdir -p "${TOOL_DIR}-staging"
make install

# rsync staging produces:
#   bin/rsync, bin/rsync-ssl
#   share/man/...
# Move to canonical layout: tools/rsync/bin/, tools/rsync/etc/
mkdir -p "${TOOL_DIR}/bin" "${TOOL_DIR}/share"
cp -a "${TOOL_DIR}-staging/bin/." "${TOOL_DIR}/bin/" 2>/dev/null || true
[[ -d "${TOOL_DIR}-staging/share" ]] && cp -a "${TOOL_DIR}-staging/share/." "${TOOL_DIR}/share/"

[[ -f "${WORK_DIR}/COPYING" ]] && cp "${WORK_DIR}/COPYING" "${TOOL_DIR}/COPYING"

rm -rf "${TOOL_DIR}-staging"

# 4. Relocate + verify (rsync is C-only, glibc-only deps)
relocate_and_verify "${TOOL_DIR}"

# 5. Smoke test
"${TOOL_DIR}/bin/rsync" --version | head -1

log "${TOOL_NAME} installed to ${TOOL_DIR}"
ls -la "${TOOL_DIR}/bin/"
