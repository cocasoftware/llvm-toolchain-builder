#!/usr/bin/env bash
# =============================================================================
# PowerShell 7.5: download official tarball + bundle non-glibc system deps.
#
# pwsh ships its own .NET runtime (~120MB self-contained) but dynamically
# links to several Linux libs from the host:
#   - libssl.so.1.1 / libcrypto.so.1.1  (OpenSSL 1.1, NOT 3.x)
#   - libicu*.so.{60..77}                (Unicode)
#   - libgssapi_krb5.so.2 / libkrb5.so.3 / libk5crypto.so.3  (Kerberos)
#   - libstdc++.so.6                     (C++ runtime — pwsh's .NET binaries)
#   - libgcc_s.so.1                      (GCC unwinder used by .NET)
#   - liblttng-ust.so.0                  (optional, tracing — we omit)
#
# Strategy: bundle all these into tools/pwsh/lib/ and use a launcher script
# that sets LD_LIBRARY_PATH=$ORIGIN/lib for pwsh and pwsh ONLY. The host
# system libs (libstdc++/libgcc_s) are NEVER added to the toolchain's top-level
# lib/ dir — they live ONLY in tools/pwsh/lib/.
#
# This is the ONE exception to the "no libstdc++/libgcc_s" rule, justified by
# pwsh being a leaf user-facing tool, not part of the C++ compilation pipeline.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/.."

source "${COMMON_DIR}/tool-versions.sh"
source "${SCRIPT_DIR}/_download.sh"
source "${SCRIPT_DIR}/_relocate.sh"

# Note: NOT sourcing _sandbox.sh — we don't compile pwsh, we just extract.
log() { echo "===> $(date '+%H:%M:%S') $*"; }
err() { echo "ERROR: $*" >&2; }

TOOL_NAME="pwsh"
VERSION="${TOOL_PWSH_VERSION}"
PLATFORM="${PLATFORM:-linux-x86_64}"

case "${PLATFORM}" in
    linux-x86_64) PWSH_ARCH="x64" ;;
    linux-aarch64) PWSH_ARCH="arm64" ;;
    *) err "unsupported PLATFORM=${PLATFORM} for pwsh"; exit 1 ;;
esac

ARCHIVE_NAME="powershell-${VERSION}-linux-${PWSH_ARCH}.tar.gz"
URL="https://github.com/PowerShell/PowerShell/releases/download/v${VERSION}/${ARCHIVE_NAME}"

TOOL_DIR="${TOOLS_CACHE_DIR}/built/${TOOL_NAME}"
WORK_DIR="${TOOLS_CACHE_DIR}/work/${TOOL_NAME}-${VERSION}"

# Internal deps (built by openssl11.sh / icu.sh / krb5.sh)
DEPS_OPENSSL11="${TOOLS_CACHE_DIR}/built/_deps/openssl11"
DEPS_ICU="${TOOLS_CACHE_DIR}/built/_deps/icu"
DEPS_KRB5="${TOOLS_CACHE_DIR}/built/_deps/krb5"

for d in "${DEPS_OPENSSL11}" "${DEPS_ICU}" "${DEPS_KRB5}"; do
    if [[ ! -d "${d}" ]]; then
        err "pwsh dep ${d} not found; build openssl11/icu/krb5 first"
        exit 1
    fi
done

log "Installing ${TOOL_NAME} v${VERSION} for ${PLATFORM}"

# 1. Download
download_file "${URL}" "${ARCHIVE_NAME}"

# 2. Extract: pwsh tarball does NOT have a top-level dir
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
tar -xzf "${SOURCES_DIR:-${TOOLS_CACHE_DIR}/sources}/${ARCHIVE_NAME}" -C "${WORK_DIR}"

# 3. Install layout: tools/pwsh/{pwsh,lib/,Modules/,...}
rm -rf "${TOOL_DIR}"
mkdir -p "${TOOL_DIR}"
cp -a "${WORK_DIR}/." "${TOOL_DIR}/"

# 4. Bundle dependency libs into tools/pwsh/lib/
mkdir -p "${TOOL_DIR}/lib"

# OpenSSL 1.1
for libfile in "${DEPS_OPENSSL11}/lib/libssl.so"* "${DEPS_OPENSSL11}/lib/libcrypto.so"*; do
    [[ -f "${libfile}" ]] || continue
    cp -aL "${libfile}" "${TOOL_DIR}/lib/"
done

# ICU (data + libraries — pwsh needs ALL of icu-i18n, icu-uc, icu-data)
for libfile in "${DEPS_ICU}/lib/libicu"*.so*; do
    [[ -f "${libfile}" ]] || continue
    cp -aL "${libfile}" "${TOOL_DIR}/lib/"
done

# Kerberos
for libfile in "${DEPS_KRB5}/lib/libgssapi_krb5.so"* \
               "${DEPS_KRB5}/lib/libkrb5.so"* \
               "${DEPS_KRB5}/lib/libkrb5support.so"* \
               "${DEPS_KRB5}/lib/libk5crypto.so"* \
               "${DEPS_KRB5}/lib/libcom_err.so"*; do
    [[ -f "${libfile}" ]] || continue
    cp -aL "${libfile}" "${TOOL_DIR}/lib/"
done

# libstdc++.so.6 + libgcc_s.so.1 — extract from bootstrap GCC's runtime.
# These are normally FORBIDDEN at the toolchain level; we bundle them ONLY
# into tools/pwsh/lib/ where .NET's CoreCLR resolves them via local rpath.
# verify_no_forbidden_deps then accepts them because they sit INSIDE tool_dir.
bundle_gcc_runtime_into_tool "${TOOL_DIR}" libgcc_s libstdc++

# 5. Patch rpath on every ELF in tools/pwsh/ so they find tools/pwsh/lib/.
#    pwsh binary lives at tools/pwsh/pwsh (top level, NOT bin/), so rpath is
#    $ORIGIN/lib. .NET .so libs scattered under tools/pwsh/ also resolve via
#    $ORIGIN/lib (relative paths computed by add_rpath_to_lib_dir).
add_rpath_to_lib_dir "${TOOL_DIR}" "${TOOL_DIR}/lib"

# Shared libs in tools/pwsh/lib/ resolve siblings via $ORIGIN
while IFS= read -r -d '' lib; do
    if file "${lib}" 2>/dev/null | grep -q "ELF.*shared"; then
        _patchelf_set_rpath "${lib}" '$ORIGIN'
    fi
done < <(find "${TOOL_DIR}/lib" -type f -name '*.so*' -print0 2>/dev/null)

# 6. Verify pwsh has no forbidden system deps (libstdc++/libgcc_s are OK
#    only because they resolve to ${TOOL_DIR}/lib/, not from the host).
verify_no_forbidden_deps "${TOOL_DIR}"

# 7. Smoke test — pwsh binary should run; --version prints PowerShell version
chmod +x "${TOOL_DIR}/pwsh"
"${TOOL_DIR}/pwsh" --version

log "${TOOL_NAME} installed to ${TOOL_DIR}"
du -sh "${TOOL_DIR}"
