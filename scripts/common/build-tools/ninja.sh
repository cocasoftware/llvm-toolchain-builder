#!/usr/bin/env bash
# =============================================================================
# ninja: small build tool, single C++ binary.
# Compiled with Stage 2 clang++ + libc++.
#
# IMPORTANT: ninja is built BEFORE cmake (chicken-and-egg). We use ninja's
# own configure.py --bootstrap (Python 3 only, no cmake required).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/.."

source "${COMMON_DIR}/tool-versions.sh"
source "${SCRIPT_DIR}/_sandbox.sh"
source "${SCRIPT_DIR}/_download.sh"
source "${SCRIPT_DIR}/_relocate.sh"

TOOL_NAME="ninja"
VERSION="${TOOL_NINJA_VERSION}"
PLATFORM="${PLATFORM:-linux-x86_64}"

ARCHIVE_NAME="ninja-${VERSION}.tar.gz"
URL="https://github.com/ninja-build/ninja/archive/refs/tags/v${VERSION}.tar.gz"

TOOL_DIR="${TOOLS_CACHE_DIR}/built/${TOOL_NAME}"
WORK_DIR="${TOOLS_CACHE_DIR}/work/${TOOL_NAME}-${VERSION}"

log "Building ${TOOL_NAME} v${VERSION} for ${PLATFORM}"
sandbox_log

# 1. Source
download_file "${URL}" "${ARCHIVE_NAME}"
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
extract_archive "${SOURCES_DIR}/${ARCHIVE_NAME}" "${WORK_DIR}" 1

# 2. Bootstrap build (Python only, no cmake/make required)
cd "${WORK_DIR}"

# configure.py respects $CXX, $CXXFLAGS, $LDFLAGS environment variables
python3 ./configure.py --bootstrap

# 3. Install
rm -rf "${TOOL_DIR}"
mkdir -p "${TOOL_DIR}"
cp "${WORK_DIR}/ninja" "${TOOL_DIR}/ninja"
chmod +x "${TOOL_DIR}/ninja"

[[ -f "${WORK_DIR}/COPYING" ]] && cp "${WORK_DIR}/COPYING" "${TOOL_DIR}/COPYING"
[[ -f "${WORK_DIR}/README.md" ]] && cp "${WORK_DIR}/README.md" "${TOOL_DIR}/README.md"

# 4. Relocate + verify
relocate_and_verify "${TOOL_DIR}"

# 5. Smoke test
"${TOOL_DIR}/ninja" --version

log "${TOOL_NAME} installed to ${TOOL_DIR}"
ls -la "${TOOL_DIR}"
