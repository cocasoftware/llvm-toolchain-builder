#!/usr/bin/env bash
# =============================================================================
# MIT Kerberos 5 (libgssapi_krb5, libkrb5, libk5crypto): required by .NET
# runtime in PowerShell for SSL/SPNEGO authentication.
# Internal _deps helper, consumed by pwsh.sh.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/.."

source "${COMMON_DIR}/tool-versions.sh"
source "${SCRIPT_DIR}/_sandbox.sh"
source "${SCRIPT_DIR}/_download.sh"
source "${SCRIPT_DIR}/_relocate.sh"

TOOL_NAME="krb5"
VERSION="${TOOL_KRB5_VERSION}"
PLATFORM="${PLATFORM:-linux-x86_64}"

# MIT Kerberos download URL pattern
# Example: https://kerberos.org/dist/krb5/1.21/krb5-1.21.3.tar.gz
MAJOR_MINOR=$(echo "${VERSION}" | awk -F. '{print $1"."$2}')
ARCHIVE_NAME="krb5-${VERSION}.tar.gz"
URL="https://kerberos.org/dist/krb5/${MAJOR_MINOR}/${ARCHIVE_NAME}"

TOOL_DIR="${TOOLS_CACHE_DIR}/built/_deps/${TOOL_NAME}"
WORK_DIR="${TOOLS_CACHE_DIR}/work/${TOOL_NAME}-${VERSION}"

log "Building ${TOOL_NAME} v${VERSION} (pwsh dep) for ${PLATFORM}"
sandbox_log

# 1. Source — krb5 tarball has src/ subdir
download_file "${URL}" "${ARCHIVE_NAME}"
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
extract_archive "${SOURCES_DIR}/${ARCHIVE_NAME}" "${WORK_DIR}" 1

# After extract: ${WORK_DIR}/src/ contains configure
cd "${WORK_DIR}/src"

# 2. Configure (autoconf)
# Disable: kadm5, ldap support, kdc (server), tcl, libedit dep — keep client only
./configure \
    --prefix="${TOOL_DIR}" \
    --enable-shared \
    --disable-static \
    --without-system-verto \
    --without-libedit \
    --without-readline \
    --without-tcl

# 3. Build + install
make -j"$(nproc)"

rm -rf "${TOOL_DIR}"
make install

log "${TOOL_NAME} (internal dep) installed to ${TOOL_DIR}"
ls "${TOOL_DIR}/lib/" | grep -E '^lib(gssapi|krb5|k5crypto)' | head
