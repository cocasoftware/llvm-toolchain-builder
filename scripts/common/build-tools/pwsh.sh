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
# These are normally FORBIDDEN at the toolchain level; we bundle into the
# pwsh dir ONLY so .NET's C++ runtime can resolve them via LD_LIBRARY_PATH
# without polluting the parent toolchain.
# Try lib64 first (common for GCC), then lib.
copy_gcc_runtime_lib() {
    local libname="$1"
    for d in "${BOOTSTRAP_PREFIX}/lib64" "${BOOTSTRAP_PREFIX}/lib"; do
        for f in "${d}/${libname}".so* "${d}/${libname}".[0-9]; do
            [[ -f "${f}" ]] || continue
            cp -aL "${f}" "${TOOL_DIR}/lib/" 2>/dev/null && return 0
        done
    done
    err "Could not locate ${libname}.so* under ${BOOTSTRAP_PREFIX}/{lib,lib64}"
    return 1
}
copy_gcc_runtime_lib libstdc++ || true
copy_gcc_runtime_lib libgcc_s  || true

# 5. Patch ALL ELF objects in tools/pwsh/ to use $ORIGIN/lib for rpath
# .NET's native libs are in tools/pwsh/, and they need to find our bundled libs.
log "Patching rpath of pwsh ELF objects to \$ORIGIN/lib"
patch_count=0
while IFS= read -r -d '' obj; do
    if file "${obj}" 2>/dev/null | grep -qE "ELF.*(executable|shared)"; then
        # pwsh binary: rpath = $ORIGIN/lib (so it finds our bundles)
        # .NET .so libs: same
        patchelf --force-rpath --set-rpath '$ORIGIN/lib:$ORIGIN' "${obj}" 2>/dev/null || true
        patch_count=$((patch_count + 1))
    fi
done < <(find "${TOOL_DIR}" -type f -print0)
log "Patched rpath on ${patch_count} ELF objects"

# Lib subdir: each shared lib's rpath is $ORIGIN (siblings)
while IFS= read -r -d '' lib; do
    if file "${lib}" 2>/dev/null | grep -q "ELF.*shared"; then
        patchelf --force-rpath --set-rpath '$ORIGIN' "${lib}" 2>/dev/null || true
    fi
done < <(find "${TOOL_DIR}/lib" -type f -name '*.so*' -print0 2>/dev/null)

# 6. Verify pwsh resolves all deps with bundled libs
log "Verifying pwsh dependencies (allow libstdc++/libgcc_s INSIDE pwsh dir only)"
verify_no_forbidden_deps "${TOOL_DIR}" "libstdc++|libgcc_s"

# 7. Smoke test — pwsh binary should run; --version prints PowerShell version
chmod +x "${TOOL_DIR}/pwsh"
"${TOOL_DIR}/pwsh" --version

log "${TOOL_NAME} installed to ${TOOL_DIR}"
du -sh "${TOOL_DIR}"
