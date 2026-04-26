#!/usr/bin/env bash
# =============================================================================
# SQLite3: required by Python's sqlite3 module.
# Built as autoconf amalgamation; pure C, no deps.
# Internal _deps helper, not installed into final toolchain.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/.."

source "${COMMON_DIR}/tool-versions.sh"
source "${SCRIPT_DIR}/_sandbox.sh"
source "${SCRIPT_DIR}/_download.sh"
source "${SCRIPT_DIR}/_relocate.sh"

TOOL_NAME="sqlite3"
VERSION="${TOOL_SQLITE_VERSION}"
SQLITE_YEAR="${TOOL_SQLITE_YEAR}"
PLATFORM="${PLATFORM:-linux-x86_64}"

# SQLite year-stamped autoconf amalgamation tarball
# Format: sqlite-autoconf-VVVNNNNNN.tar.gz where V=version components
# 3.51.0 → 3510000
SQLITE_VER_INT=$(printf "%d%02d%02d%02d" \
    $(echo "${VERSION}" | cut -d. -f1) \
    $(echo "${VERSION}" | cut -d. -f2) \
    $(echo "${VERSION}" | cut -d. -f3) \
    0)

ARCHIVE_NAME="sqlite-autoconf-${SQLITE_VER_INT}.tar.gz"
URL="https://www.sqlite.org/${SQLITE_YEAR}/${ARCHIVE_NAME}"

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

# 2. Configure (Python wants ENABLE_FTS{3,4,5} + ENABLE_RTREE + ENABLE_JSON1)
./configure \
    --prefix="${TOOL_DIR}" \
    --enable-shared \
    --enable-static \
    CFLAGS="${CFLAGS} -DSQLITE_ENABLE_FTS3=1 -DSQLITE_ENABLE_FTS4=1 -DSQLITE_ENABLE_FTS5=1 -DSQLITE_ENABLE_RTREE=1 -DSQLITE_ENABLE_JSON1=1 -DSQLITE_ENABLE_DBSTAT_VTAB=1"

# 3. Build + install
make -j"$(nproc)"

rm -rf "${TOOL_DIR}"
make install

# 4. Smoke test
"${TOOL_DIR}/bin/sqlite3" --version | head -1

log "${TOOL_NAME} (internal dep) installed to ${TOOL_DIR}"
ls "${TOOL_DIR}/lib/" | head
