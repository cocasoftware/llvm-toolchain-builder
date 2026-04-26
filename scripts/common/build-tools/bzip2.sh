#!/usr/bin/env bash
# =============================================================================
# bzip2: tiny C library, dependency of Python's _bz2 module.
# Built as both static (.a) and shared (.so) into a tools-cache helper dir.
# Output is consumed by python.sh, NOT bundled into the final toolchain.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/.."

source "${COMMON_DIR}/tool-versions.sh"
source "${SCRIPT_DIR}/_sandbox.sh"
source "${SCRIPT_DIR}/_download.sh"
source "${SCRIPT_DIR}/_relocate.sh"

TOOL_NAME="bzip2"
VERSION="${TOOL_BZIP2_VERSION}"
PLATFORM="${PLATFORM:-linux-x86_64}"

ARCHIVE_NAME="bzip2-${VERSION}.tar.gz"
URL="https://sourceware.org/pub/bzip2/${ARCHIVE_NAME}"

# Internal helper dir (used during python build, NOT installed in final toolchain)
TOOL_DIR="${TOOLS_CACHE_DIR}/built/_deps/${TOOL_NAME}"
WORK_DIR="${TOOLS_CACHE_DIR}/work/${TOOL_NAME}-${VERSION}"

log "Building ${TOOL_NAME} v${VERSION} (Python dep) for ${PLATFORM}"
sandbox_log

# 1. Source
download_file "${URL}" "${ARCHIVE_NAME}"
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
extract_archive "${SOURCES_DIR}/${ARCHIVE_NAME}" "${WORK_DIR}" 1

cd "${WORK_DIR}"

# 2. Build static + shared (bzip2's Makefile is hand-written, not autotools)
# The shared library Makefile is Makefile-libbz2_so.
make CC="${CC}" CFLAGS="${CFLAGS}" -j"$(nproc)"
make -f Makefile-libbz2_so CC="${CC}" CFLAGS="${CFLAGS}" -j"$(nproc)"

# 3. Install
rm -rf "${TOOL_DIR}"
mkdir -p "${TOOL_DIR}/bin" "${TOOL_DIR}/include" "${TOOL_DIR}/lib"

cp libbz2.a "${TOOL_DIR}/lib/"
cp libbz2.so.1.0.* "${TOOL_DIR}/lib/" 2>/dev/null || cp libbz2.so.* "${TOOL_DIR}/lib/"
ln -sf "$(basename "${TOOL_DIR}/lib/"libbz2.so.*.0)" "${TOOL_DIR}/lib/libbz2.so.1.0" 2>/dev/null || true
ln -sf libbz2.so.1.0 "${TOOL_DIR}/lib/libbz2.so" 2>/dev/null || true

cp bzlib.h "${TOOL_DIR}/include/"
cp bzip2 bzip2recover bunzip2 bzcat bzdiff bzgrep bzmore "${TOOL_DIR}/bin/" 2>/dev/null || true

# 4. Smoke test
"${TOOL_DIR}/bin/bzip2" --version 2>&1 | head -1 || true

log "${TOOL_NAME} (internal dep) installed to ${TOOL_DIR}"
ls "${TOOL_DIR}/lib/"
