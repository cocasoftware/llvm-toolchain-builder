#!/usr/bin/env bash
# =============================================================================
# CMake: large C++ build system.
# Compiled with Stage 2 clang++ + libc++.
#
# CMake has its own bootstrap: ./bootstrap --prefix=... --parallel=N
# This avoids needing a pre-existing cmake.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/.."

source "${COMMON_DIR}/tool-versions.sh"
source "${SCRIPT_DIR}/_sandbox.sh"
source "${SCRIPT_DIR}/_download.sh"
source "${SCRIPT_DIR}/_relocate.sh"

TOOL_NAME="cmake"
VERSION="${TOOL_CMAKE_VERSION}"
PLATFORM="${PLATFORM:-linux-x86_64}"

# CMake source tarballs from Kitware
ARCHIVE_NAME="cmake-${VERSION}.tar.gz"
URL="https://github.com/Kitware/CMake/releases/download/v${VERSION}/${ARCHIVE_NAME}"

TOOL_DIR="${TOOLS_CACHE_DIR}/built/${TOOL_NAME}"
WORK_DIR="${TOOLS_CACHE_DIR}/work/${TOOL_NAME}-${VERSION}"

log "Building ${TOOL_NAME} v${VERSION} for ${PLATFORM}"
sandbox_log

# 1. Source
download_file "${URL}" "${ARCHIVE_NAME}"
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
extract_archive "${SOURCES_DIR}/${ARCHIVE_NAME}" "${WORK_DIR}" 1

# 2. Bootstrap + build
cd "${WORK_DIR}"

# CMake bootstrap respects CC, CXX, CFLAGS, CXXFLAGS, LDFLAGS env.
# We disable cmake-gui (Qt dep), Sphinx docs, and tests to minimize footprint.
./bootstrap \
    --prefix="${TOOL_DIR}" \
    --parallel="$(nproc)" \
    --no-qt-gui \
    -- \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_RPATH='$ORIGIN/../lib' \
    -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
    -DBUILD_CursesDialog=OFF \
    -DCMake_BUILD_LTO=ON \
    -DCMAKE_USE_OPENSSL=OFF

make -j"$(nproc)"

rm -rf "${TOOL_DIR}"
make install

# 3. Smoke test
"${TOOL_DIR}/bin/cmake" --version
"${TOOL_DIR}/bin/ctest" --version

# 4. Relocate + verify
relocate_and_verify "${TOOL_DIR}"

log "${TOOL_NAME} installed to ${TOOL_DIR}"
du -sh "${TOOL_DIR}"
ls -la "${TOOL_DIR}/bin/"
