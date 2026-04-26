#!/usr/bin/env bash
# =============================================================================
# CPython 3.14.4: built from source with Stage 2 LLVM + libc++.
#
# This replaces the python-build-standalone download approach. Building from
# source ensures:
#   - GLIBC floor matches Stage 2 (Ubuntu 16.04 = 2.23)
#   - C++ extensions (_test_capi, etc.) use libc++ consistently
#   - All system deps come from bootstrap (zlib/zstd/openssl/libffi/...)
#     plus our own builds (bzip2/sqlite3/expat)
#   - No mystery binary blobs from upstream
#
# Required dependencies (must be built first):
#   - bzip2  (tools-cache/built/_deps/bzip2)
#   - sqlite3 (tools-cache/built/_deps/sqlite3)
#   - expat  (tools-cache/built/_deps/expat)
# Bootstrap-provided:
#   - zlib, libffi, openssl, ncurses, lzma, libxml2, libedit
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/.."

source "${COMMON_DIR}/tool-versions.sh"
source "${SCRIPT_DIR}/_sandbox.sh"
source "${SCRIPT_DIR}/_download.sh"
source "${SCRIPT_DIR}/_relocate.sh"

TOOL_NAME="python"
VERSION="${TOOL_PYTHON_VERSION}"
PLATFORM="${PLATFORM:-linux-x86_64}"

ARCHIVE_NAME="Python-${VERSION}.tar.xz"
URL="https://www.python.org/ftp/python/${VERSION}/${ARCHIVE_NAME}"

TOOL_DIR="${TOOLS_CACHE_DIR}/built/${TOOL_NAME}"
WORK_DIR="${TOOLS_CACHE_DIR}/work/${TOOL_NAME}-${VERSION}"

# Internal deps (built by bzip2.sh / sqlite3.sh / expat.sh)
DEPS_BZIP2="${TOOLS_CACHE_DIR}/built/_deps/bzip2"
DEPS_SQLITE="${TOOLS_CACHE_DIR}/built/_deps/sqlite3"
DEPS_EXPAT="${TOOLS_CACHE_DIR}/built/_deps/expat"

for d in "${DEPS_BZIP2}" "${DEPS_SQLITE}" "${DEPS_EXPAT}"; do
    if [[ ! -d "${d}" ]]; then
        err "Python dep dir ${d} not found; build bzip2/sqlite3/expat first"
        exit 1
    fi
done

log "Building ${TOOL_NAME} v${VERSION} for ${PLATFORM}"
sandbox_log

# 1. Source
download_file "${URL}" "${ARCHIVE_NAME}"
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
extract_archive "${SOURCES_DIR}/${ARCHIVE_NAME}" "${WORK_DIR}" 1

cd "${WORK_DIR}"

# 2. Augment include/lib search paths with our internal deps
# CPython's configure looks for headers/libs in CPATH/LIBRARY_PATH (and
# pkg-config). Since the deps are in non-standard prefixes, we add them.
PY_CPPFLAGS="-I${DEPS_BZIP2}/include -I${DEPS_SQLITE}/include -I${DEPS_EXPAT}/include"
PY_LDFLAGS="-L${DEPS_BZIP2}/lib -L${DEPS_SQLITE}/lib -L${DEPS_EXPAT}/lib ${LDFLAGS}"
PY_CPPFLAGS="${PY_CPPFLAGS} -I${BOOTSTRAP_PREFIX}/include"
PY_LDFLAGS="-L${BOOTSTRAP_PREFIX}/lib ${PY_LDFLAGS}"

# 3. Configure
# --enable-shared          build libpython3.14.so (needed by lldb embedding)
# --enable-optimizations   PGO (skipped for time? — keep enabled if time permits)
# --with-lto               LTO across stdlib
# --with-system-expat      use our expat
# --with-system-ffi        use bootstrap libffi
# --with-openssl=...       use bootstrap openssl 3.x
# --without-static-libpython  use shared
# --with-ensurepip=install bundle pip
# --enable-loadable-sqlite-extensions  enable sqlite extension loading
./configure \
    --prefix="${TOOL_DIR}" \
    --enable-shared \
    --enable-optimizations \
    --with-lto=full \
    --with-computed-gotos \
    --enable-loadable-sqlite-extensions \
    --with-system-expat \
    --with-system-ffi \
    --with-openssl="${BOOTSTRAP_PREFIX}" \
    --with-openssl-rpath=auto \
    --with-ensurepip=install \
    --without-doc-strings \
    CFLAGS="${CFLAGS} ${PY_CPPFLAGS}" \
    CXXFLAGS="${CXXFLAGS} ${PY_CPPFLAGS}" \
    CPPFLAGS="${PY_CPPFLAGS}" \
    LDFLAGS="${PY_LDFLAGS}"

# 4. Build (PGO + LTO can take 20+ min; consider env override for fast iter)
if [[ "${PYTHON_FAST_BUILD:-0}" == "1" ]]; then
    make -j"$(nproc)"
else
    # PGO + LTO produces a profiled, optimized binary
    make -j"$(nproc)" profile-opt || make -j"$(nproc)"
fi

# 5. Install
rm -rf "${TOOL_DIR}"
make install

# 6. Bundle runtime libs that Python links against (from bootstrap + _deps)
# Python's extension modules .so files dlopen these at runtime.
mkdir -p "${TOOL_DIR}/lib"
for libname in libssl libcrypto libffi libz libzstd liblzma libxml2 libncurses libedit libtinfo libpanel; do
    for libfile in "${BOOTSTRAP_PREFIX}/lib/${libname}".so* "${BOOTSTRAP_PREFIX}/lib64/${libname}".so*; do
        [[ -f "${libfile}" ]] || continue
        cp -aL "${libfile}" "${TOOL_DIR}/lib/" 2>/dev/null || true
    done
done

# Also bundle libbz2, libsqlite3, libexpat from our _deps builds
for dep_dir in "${DEPS_BZIP2}" "${DEPS_SQLITE}" "${DEPS_EXPAT}"; do
    for libfile in "${dep_dir}/lib/"*.so*; do
        [[ -f "${libfile}" ]] || continue
        cp -aL "${libfile}" "${TOOL_DIR}/lib/" 2>/dev/null || true
    done
done

# 7. Symlink: tools/python/bin/python3 → python3.14
# Provide the canonical "python3" (and "python") names if not already present.
if [[ ! -e "${TOOL_DIR}/bin/python3" && -x "${TOOL_DIR}/bin/python3.14" ]]; then
    ln -sf python3.14 "${TOOL_DIR}/bin/python3"
fi
if [[ ! -e "${TOOL_DIR}/bin/python" && -x "${TOOL_DIR}/bin/python3" ]]; then
    ln -sf python3 "${TOOL_DIR}/bin/python"
fi

# 8. Strip bytecode test directories (bulky)
find "${TOOL_DIR}/lib/python3.14" -type d -name 'test' -prune -exec rm -rf {} + 2>/dev/null || true
find "${TOOL_DIR}/lib/python3.14" -type d -name 'tests' -prune -exec rm -rf {} + 2>/dev/null || true
rm -rf "${TOOL_DIR}/lib/python3.14/turtledemo" \
       "${TOOL_DIR}/lib/python3.14/tkinter" \
       "${TOOL_DIR}/lib/python3.14/idlelib"

# Pre-compile .pyc for faster startup
"${TOOL_DIR}/bin/python3" -O -m compileall -q "${TOOL_DIR}/lib/python3.14" 2>/dev/null || true

# 9. Relocate + verify
relocate_and_verify "${TOOL_DIR}"

# 10. Smoke tests
"${TOOL_DIR}/bin/python3" --version
"${TOOL_DIR}/bin/python3" -c "import ssl; print('ssl OK:', ssl.OPENSSL_VERSION)"
"${TOOL_DIR}/bin/python3" -c "import sqlite3; print('sqlite3 OK:', sqlite3.sqlite_version)"
"${TOOL_DIR}/bin/python3" -c "import bz2; print('bz2 OK')"
"${TOOL_DIR}/bin/python3" -c "import lzma; print('lzma OK')"
"${TOOL_DIR}/bin/python3" -c "import zlib; print('zlib OK')"
"${TOOL_DIR}/bin/python3" -c "import xml.etree.ElementTree; print('expat OK')"
"${TOOL_DIR}/bin/python3" -c "import ctypes; print('ctypes OK (libffi):', ctypes.__version__)"
"${TOOL_DIR}/bin/python3" -m pip --version

log "${TOOL_NAME} installed to ${TOOL_DIR}"
du -sh "${TOOL_DIR}"
