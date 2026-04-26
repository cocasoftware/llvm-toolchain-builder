#!/usr/bin/env bash
# =============================================================================
# Build sysroots/x86_64-linux-musl and sysroots/aarch64-linux-musl from
# Alpine Linux packages (musl 1.2.5 baseline).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

ALPINE_VERSION="${SYSROOT_ALPINE_VERSION:-3.20}"
ARCH="${1:-x86_64}"

case "${ARCH}" in
    x86_64) APK_ARCH="x86_64";  TRIPLE="x86_64-linux-musl" ;;
    aarch64) APK_ARCH="aarch64"; TRIPLE="aarch64-linux-musl" ;;
    *) echo "FATAL: unsupported ARCH=${ARCH}"; exit 1 ;;
esac

SYSROOT_DIR="${SYSROOTS_CACHE_DIR}/${TRIPLE}"
WORK_DIR="${SYSROOTS_WORK_DIR}/${TRIPLE}"

log "Building sysroot ${TRIPLE} from Alpine ${ALPINE_VERSION}"

rm -rf "${WORK_DIR}" "${SYSROOT_DIR}"
mkdir -p "${WORK_DIR}/apks" "${SYSROOT_DIR}"

# Alpine package mirror
ALPINE_MIRROR="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/main"

# Required packages for C/C++ static cross-compilation
PACKAGES=(
    "musl"          # libc.musl-{arch}.so
    "musl-dev"      # headers + crt
    "linux-headers" # kernel UAPI headers
    "zlib"
    "zlib-dev"
)

# ── Download APKINDEX to resolve package versions ───────────────────────────
APKINDEX_URL="${ALPINE_MIRROR}/${APK_ARCH}/APKINDEX.tar.gz"
curl --fail --location --silent --show-error \
     --output "${WORK_DIR}/APKINDEX.tar.gz" "${APKINDEX_URL}"

mkdir -p "${WORK_DIR}/apkindex"
tar -xzf "${WORK_DIR}/APKINDEX.tar.gz" -C "${WORK_DIR}/apkindex" APKINDEX

# Parse: APKINDEX format has lines like:
#   P:musl
#   V:1.2.5-r0
#   ...
# We need to find the V: line that follows P:<pkgname> for each package.
declare -A PKG_VERSIONS
while IFS= read -r line; do
    if [[ "${line}" == "P:"* ]]; then
        current_pkg="${line#P:}"
    elif [[ "${line}" == "V:"* ]]; then
        PKG_VERSIONS["${current_pkg}"]="${line#V:}"
    fi
done < "${WORK_DIR}/apkindex/APKINDEX"

# ── Download .apk files ─────────────────────────────────────────────────────
for pkg in "${PACKAGES[@]}"; do
    ver="${PKG_VERSIONS[${pkg}]:-}"
    if [[ -z "${ver}" ]]; then
        log "  WARN: ${pkg} version not found in APKINDEX"
        continue
    fi
    apk_name="${pkg}-${ver}.apk"
    apk_url="${ALPINE_MIRROR}/${APK_ARCH}/${apk_name}"
    log "  fetching ${apk_name}"
    curl --fail --location --silent --show-error \
         --output "${WORK_DIR}/apks/${apk_name}" "${apk_url}" || \
        log "  WARN: failed to fetch ${apk_name}"
done

# ── Extract APKs ────────────────────────────────────────────────────────────
log "Extracting APKs into ${SYSROOT_DIR}"
for apk in "${WORK_DIR}/apks/"*.apk; do
    [[ -f "${apk}" ]] || continue
    extract_apk "${apk}" "${SYSROOT_DIR}"
done

# Remove APK metadata
rm -f "${SYSROOT_DIR}/.PKGINFO" "${SYSROOT_DIR}/.SIGN."* 2>/dev/null || true

prune_sysroot "${SYSROOT_DIR}"
fix_absolute_symlinks "${SYSROOT_DIR}"

# ── Verify essentials ───────────────────────────────────────────────────────
ESSENTIAL=(
    "${SYSROOT_DIR}/usr/include/stdio.h"
    "${SYSROOT_DIR}/lib/ld-musl-${APK_ARCH}.so.1"
)
for f in "${ESSENTIAL[@]}"; do
    if [[ ! -e "${f}" ]]; then
        echo "ERROR: essential file missing: ${f}" >&2
        exit 1
    fi
done

log "sysroot ${TRIPLE} complete"
du -sh "${SYSROOT_DIR}"
