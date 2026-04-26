#!/usr/bin/env bash
# =============================================================================
# Graphviz: large C/C++ project (autotools).
# Provides `dot` for Doxygen graph generation. Other layout engines optional.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/.."

source "${COMMON_DIR}/tool-versions.sh"
source "${SCRIPT_DIR}/_sandbox.sh"
source "${SCRIPT_DIR}/_download.sh"
source "${SCRIPT_DIR}/_relocate.sh"

TOOL_NAME="graphviz"
VERSION="${TOOL_GRAPHVIZ_VERSION}"
PLATFORM="${PLATFORM:-linux-x86_64}"

# Graphviz from gitlab releases (mirror)
ARCHIVE_NAME="graphviz-${VERSION}.tar.xz"
URL="https://gitlab.com/api/v4/projects/4207231/packages/generic/graphviz-releases/${VERSION}/${ARCHIVE_NAME}"

TOOL_DIR="${TOOLS_CACHE_DIR}/built/${TOOL_NAME}"
WORK_DIR="${TOOLS_CACHE_DIR}/work/${TOOL_NAME}-${VERSION}"

log "Building ${TOOL_NAME} v${VERSION} for ${PLATFORM}"
sandbox_log

# 1. Source
download_file "${URL}" "${ARCHIVE_NAME}"
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
extract_archive "${SOURCES_DIR}/${ARCHIVE_NAME}" "${WORK_DIR}" 1

cd "${WORK_DIR}"

# 2. Configure: minimal feature set
# Disable: GUI (gtk, qt), language bindings (perl, python, tcl, ruby, java),
# image formats requiring external libs (libgd, ghostscript), docs.
./configure \
    --prefix="${TOOL_DIR}" \
    --disable-shared \
    --enable-static \
    --without-x \
    --without-expat \
    --without-libgd \
    --without-poppler \
    --without-pangocairo \
    --without-rsvg \
    --without-ghostscript \
    --without-quartz \
    --without-gtk \
    --without-gtkgl \
    --without-gtkglext \
    --without-glade \
    --without-gts \
    --without-ann \
    --without-glut \
    --without-smyrna \
    --without-ortho \
    --without-tcl \
    --without-tk \
    --without-perl \
    --without-php \
    --without-python \
    --without-r \
    --without-ruby \
    --without-lua \
    --without-go \
    --without-guile \
    --without-d \
    --disable-swig \
    --disable-ltdl

# 3. Build + install
make -j"$(nproc)"

rm -rf "${TOOL_DIR}"
make install

# 4. Run dot -c (post-install hook to register plugins)
# Skip in cross-compile or sandboxed contexts.
"${TOOL_DIR}/bin/dot" -c 2>/dev/null || true

# 5. Relocate + verify
relocate_and_verify "${TOOL_DIR}"

# 6. Smoke test
"${TOOL_DIR}/bin/dot" -V 2>&1 | head -1

log "${TOOL_NAME} installed to ${TOOL_DIR}"
du -sh "${TOOL_DIR}"
ls -la "${TOOL_DIR}/bin/" | head
