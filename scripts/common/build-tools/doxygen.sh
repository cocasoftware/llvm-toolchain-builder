#!/usr/bin/env bash
# =============================================================================
# Doxygen: C++ project, CMake-based.
# Requires: bison, flex (apt installed in build container), libiconv (optional).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/.."

source "${COMMON_DIR}/tool-versions.sh"
source "${SCRIPT_DIR}/_sandbox.sh"
source "${SCRIPT_DIR}/_download.sh"
source "${SCRIPT_DIR}/_relocate.sh"

TOOL_NAME="doxygen"
VERSION="${TOOL_DOXYGEN_VERSION}"
PLATFORM="${PLATFORM:-linux-x86_64}"

# Doxygen tarball naming: 1.16.1 → Release_1_16_1
TAG_NAME="Release_${VERSION//./_}"
ARCHIVE_NAME="doxygen-${VERSION}.src.tar.gz"
URL="https://github.com/doxygen/doxygen/archive/refs/tags/${TAG_NAME}.tar.gz"

TOOL_DIR="${TOOLS_CACHE_DIR}/built/${TOOL_NAME}"
WORK_DIR="${TOOLS_CACHE_DIR}/work/${TOOL_NAME}-${VERSION}"

log "Building ${TOOL_NAME} v${VERSION} for ${PLATFORM}"
sandbox_log

# 1. Source
download_file "${URL}" "${ARCHIVE_NAME}"
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
extract_archive "${SOURCES_DIR}/${ARCHIVE_NAME}" "${WORK_DIR}" 1

# 2. Use cmake from tools-cache (must be built before doxygen)
CMAKE_BIN="${TOOLS_CACHE_DIR}/built/cmake/bin/cmake"
if [[ ! -x "${CMAKE_BIN}" ]]; then
    err "Doxygen requires cmake to be built first; ${CMAKE_BIN} not found"
    exit 1
fi

# Use ninja from tools-cache too (built before doxygen)
NINJA_BIN="${TOOLS_CACHE_DIR}/built/ninja/ninja"
GENERATOR="Unix Makefiles"
if [[ -x "${NINJA_BIN}" ]]; then
    PATH="${TOOLS_CACHE_DIR}/built/ninja:${PATH}"
    GENERATOR="Ninja"
fi

BUILD_DIR="${WORK_DIR}/build"
mkdir -p "${BUILD_DIR}"

"${CMAKE_BIN}" -S "${WORK_DIR}" -B "${BUILD_DIR}" -G "${GENERATOR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${TOOL_DIR}" \
    -DCMAKE_C_COMPILER="${CC}" \
    -DCMAKE_CXX_COMPILER="${CXX}" \
    -DCMAKE_C_FLAGS="${CFLAGS}" \
    -DCMAKE_CXX_FLAGS="${CXXFLAGS}" \
    -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" \
    -DCMAKE_INSTALL_RPATH='$ORIGIN/../lib' \
    -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
    -Dbuild_xmlparser=ON \
    -Dbuild_search=OFF \
    -Dbuild_doc=OFF \
    -Dbuild_wizard=OFF

"${CMAKE_BIN}" --build "${BUILD_DIR}" -j"$(nproc)"

rm -rf "${TOOL_DIR}"
"${CMAKE_BIN}" --install "${BUILD_DIR}"

# 3. Relocate + verify
relocate_and_verify "${TOOL_DIR}"

# 4. Smoke test
"${TOOL_DIR}/bin/doxygen" --version

log "${TOOL_NAME} installed to ${TOOL_DIR}"
ls -la "${TOOL_DIR}/bin/"
