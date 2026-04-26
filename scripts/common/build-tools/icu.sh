#!/usr/bin/env bash
# =============================================================================
# ICU (International Components for Unicode): required by .NET runtime in
# PowerShell. We build only the libs needed (icu-i18n, icu-uc, icu-data).
# Internal _deps helper, consumed by pwsh.sh.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/.."

source "${COMMON_DIR}/tool-versions.sh"
source "${SCRIPT_DIR}/_sandbox.sh"
source "${SCRIPT_DIR}/_download.sh"
source "${SCRIPT_DIR}/_relocate.sh"

TOOL_NAME="icu"
VERSION="${TOOL_ICU_VERSION}"
PLATFORM="${PLATFORM:-linux-x86_64}"

# ICU 77.1 → tag release-77-1, archive icu4c-77_1-src.tgz
ICU_TAG_TAR="${VERSION//./_}"      # 77.1 → 77_1
ICU_TAG_REL="${VERSION//./-}"      # 77.1 → 77-1

ARCHIVE_NAME="icu4c-${ICU_TAG_TAR}-src.tgz"
URL="https://github.com/unicode-org/icu/releases/download/release-${ICU_TAG_REL}/${ARCHIVE_NAME}"

TOOL_DIR="${TOOLS_CACHE_DIR}/built/_deps/${TOOL_NAME}"
WORK_DIR="${TOOLS_CACHE_DIR}/work/${TOOL_NAME}-${VERSION}"

log "Building ${TOOL_NAME} v${VERSION} (pwsh dep) for ${PLATFORM}"
sandbox_log

# 1. Source — note ICU tarball has source/ as top-level dir
download_file "${URL}" "${ARCHIVE_NAME}"
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
extract_archive "${SOURCES_DIR}/${ARCHIVE_NAME}" "${WORK_DIR}" 1

# After extract: ${WORK_DIR}/source/ contains configure script
cd "${WORK_DIR}/source"

# 2. Configure (autoconf)
./runConfigureICU Linux \
    --prefix="${TOOL_DIR}" \
    --enable-shared \
    --disable-static \
    --disable-tests \
    --disable-samples \
    --disable-extras \
    --disable-icuio \
    --disable-layoutex \
    --with-data-packaging=library

# 3. Build + install
make -j"$(nproc)"

rm -rf "${TOOL_DIR}"
make install

log "${TOOL_NAME} (internal dep) installed to ${TOOL_DIR}"
ls "${TOOL_DIR}/lib/" | grep -E '^libicu' | head
