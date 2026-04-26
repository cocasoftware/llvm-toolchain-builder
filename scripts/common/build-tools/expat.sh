#!/usr/bin/env bash
# =============================================================================
# expat: XML parser, required by Python's _elementtree / pyexpat modules
#        AND by git (already linked from bootstrap).
# Internal _deps helper.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/.."

source "${COMMON_DIR}/tool-versions.sh"
source "${SCRIPT_DIR}/_sandbox.sh"
source "${SCRIPT_DIR}/_download.sh"
source "${SCRIPT_DIR}/_relocate.sh"

TOOL_NAME="expat"
VERSION="${TOOL_EXPAT_VERSION}"
PLATFORM="${PLATFORM:-linux-x86_64}"

# expat tag format: R_2_7_1
TAG_NAME="R_${VERSION//./_}"
ARCHIVE_NAME="expat-${VERSION}.tar.xz"
URL="https://github.com/libexpat/libexpat/releases/download/${TAG_NAME}/${ARCHIVE_NAME}"

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

# 2. Configure
./configure \
    --prefix="${TOOL_DIR}" \
    --enable-shared \
    --enable-static \
    --without-docbook \
    --without-examples \
    --without-tests

# 3. Build + install
make -j"$(nproc)"

rm -rf "${TOOL_DIR}"
make install

log "${TOOL_NAME} (internal dep) installed to ${TOOL_DIR}"
ls "${TOOL_DIR}/lib/"
