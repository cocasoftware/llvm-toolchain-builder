#!/usr/bin/env bash
# =============================================================================
# Perl 5: needed for OpenSSL builds and some legacy CMake operations.
# Compiled with Stage 2 clang.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/.."

source "${COMMON_DIR}/tool-versions.sh"
source "${SCRIPT_DIR}/_sandbox.sh"
source "${SCRIPT_DIR}/_download.sh"
source "${SCRIPT_DIR}/_relocate.sh"

TOOL_NAME="perl"
VERSION="${TOOL_PERL_VERSION}"
PLATFORM="${PLATFORM:-linux-x86_64}"

ARCHIVE_NAME="perl-${VERSION}.tar.xz"
URL="https://www.cpan.org/src/5.0/${ARCHIVE_NAME}"

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

# 2. Configure (Perl uses a custom Configure script)
# -des: defaults, no questions, silent
# -Dprefix: install root
# -Dcc: compiler
# -Dcccdlflags: position-independent code
# -Duseshrplib: build shared libperl.so
# -Dusethreads: required for some modules
# -Dprivlib/archlib: relative paths from $ORIGIN/../
./Configure -des \
    -Dprefix="${TOOL_DIR}/perl" \
    -Dcc="${CC}" \
    -Doptimize="-O2" \
    -Duseshrplib \
    -Dusethreads \
    -Dccflags="-fPIC" \
    -Dlddlflags="-shared ${LDFLAGS}" \
    -Dldflags="${LDFLAGS}" \
    -Dman1dir=none \
    -Dman3dir=none \
    -A 'eval:scriptdir=${TOOL_DIR}/perl/bin'

# 3. Build + install
make -j"$(nproc)"

rm -rf "${TOOL_DIR}"
mkdir -p "${TOOL_DIR}"

# Install (Perl install layout: prefix/bin, prefix/lib, prefix/share/man)
make install

# 4. Verify dirs match Strawberry Perl convention used by COCA toolchain:
#    tools/perl/perl/bin/perl  (note double 'perl')
#    tools/perl/perl/lib/...
# Already matches because we set Dprefix=${TOOL_DIR}/perl
ls "${TOOL_DIR}/perl/bin/perl" >/dev/null

# 5. Relocate + verify
relocate_and_verify "${TOOL_DIR}"

# 6. Smoke test
"${TOOL_DIR}/perl/bin/perl" --version | head -2

log "${TOOL_NAME} installed to ${TOOL_DIR}"
du -sh "${TOOL_DIR}"
