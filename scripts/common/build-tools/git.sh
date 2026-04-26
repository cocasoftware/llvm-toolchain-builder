#!/usr/bin/env bash
# =============================================================================
# Git: C-only autoconf project. Compiled with Stage 2 clang.
# Optional features (NLS/Tcl-Tk/Perl/Python) disabled to keep self-contained.
# Network features (HTTPS, SSH) require curl + openssl from bootstrap.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/.."

source "${COMMON_DIR}/tool-versions.sh"
source "${SCRIPT_DIR}/_sandbox.sh"
source "${SCRIPT_DIR}/_download.sh"
source "${SCRIPT_DIR}/_relocate.sh"

TOOL_NAME="git"
VERSION="${TOOL_GIT_VERSION}"
PLATFORM="${PLATFORM:-linux-x86_64}"

# Git releases: download from kernel.org tarball mirror
ARCHIVE_NAME="git-${VERSION}.tar.xz"
URL="https://mirrors.edge.kernel.org/pub/software/scm/git/${ARCHIVE_NAME}"

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
# - Use bootstrap's curl/openssl/zlib (already there) for HTTPS/HTTP support.
# - Disable: NLS (gettext), iconv, tcl-tk gitk, perl, python.
# - Static-link as much as possible to reduce runtime deps.
make configure

# CC for git is set via env var, but also explicitly here for clarity.
./configure \
    --prefix="${TOOL_DIR}" \
    --without-tcltk \
    --without-iconv \
    --without-libpcre \
    --with-openssl="${BOOTSTRAP_PREFIX}" \
    --with-curl="${BOOTSTRAP_PREFIX}" \
    --with-expat="${BOOTSTRAP_PREFIX}" \
    --without-libpcre2 \
    NO_GETTEXT=1 \
    NO_PERL=1 \
    NO_PYTHON=1 \
    NO_TCLTK=1 \
    NO_INSTALL_HARDLINKS=1

# 3. Build (git's makefile uses CC/CFLAGS/LDFLAGS)
make -j"$(nproc)" \
    NO_GETTEXT=1 NO_PERL=1 NO_PYTHON=1 NO_TCLTK=1 NO_INSTALL_HARDLINKS=1

# 4. Install
rm -rf "${TOOL_DIR}"
make install \
    NO_GETTEXT=1 NO_PERL=1 NO_PYTHON=1 NO_TCLTK=1 NO_INSTALL_HARDLINKS=1

# 5. Bundle bootstrap libs that git needs at runtime
# git binaries dynamically link: libcurl, libssl, libcrypto, libz (from bootstrap)
mkdir -p "${TOOL_DIR}/lib"
for libname in libcurl libssl libcrypto libz libexpat; do
    for libfile in "${BOOTSTRAP_PREFIX}/lib/${libname}".so*; do
        [[ -f "${libfile}" ]] || continue
        cp -aL "${libfile}" "${TOOL_DIR}/lib/" 2>/dev/null || true
    done
done

# 6. Relocate + verify
relocate_and_verify "${TOOL_DIR}"

# 7. Smoke test
"${TOOL_DIR}/bin/git" --version

log "${TOOL_NAME} installed to ${TOOL_DIR}"
du -sh "${TOOL_DIR}"
ls -la "${TOOL_DIR}/bin/" | head -10
