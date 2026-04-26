#!/usr/bin/env bash
# =============================================================================
# Build sysroots/x86_64-linux-gnu and sysroots/aarch64-linux-gnu from
# Ubuntu 16.04 (xenial) packages.
#
# Why Ubuntu 16.04?
#   - GLIBC 2.23 baseline (compatible with most modern Linux)
#   - LTS until 2021, packages stable
#   - matches the actions repo's Stage 2 build container
#
# Output:
#   /opt/tools-cache/sysroots/x86_64-linux-gnu/
#     ├── lib/
#     ├── usr/include/
#     ├── usr/lib/x86_64-linux-gnu/
#     └── ...
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

UBUNTU_VERSION="${SYSROOT_UBUNTU_VERSION:-16.04}"
UBUNTU_CODENAME="xenial"   # 16.04 = xenial
ARCH="${1:-x86_64}"

case "${ARCH}" in
    x86_64) DEB_ARCH="amd64";  TRIPLE="x86_64-linux-gnu" ;;
    aarch64) DEB_ARCH="arm64"; TRIPLE="aarch64-linux-gnu" ;;
    *) echo "FATAL: unsupported ARCH=${ARCH}"; exit 1 ;;
esac

SYSROOT_DIR="${SYSROOTS_CACHE_DIR}/${TRIPLE}"
WORK_DIR="${SYSROOTS_WORK_DIR}/${TRIPLE}"

log "Building sysroot ${TRIPLE} from Ubuntu ${UBUNTU_VERSION}"

rm -rf "${WORK_DIR}" "${SYSROOT_DIR}"
mkdir -p "${WORK_DIR}/debs" "${SYSROOT_DIR}"

# Ubuntu 16.04 mirror
# x86_64: archive.ubuntu.com  |  arm64: ports.ubuntu.com
if [[ "${DEB_ARCH}" == "amd64" ]]; then
    MIRROR="http://archive.ubuntu.com/ubuntu"
else
    MIRROR="http://ports.ubuntu.com/ubuntu-ports"
fi

# ── Required packages (minimal set for C/C++ compilation) ───────────────────
# libc6, libc6-dev:        glibc shared libs + headers
# linux-libc-dev:          kernel UAPI headers (sys/, linux/, asm/)
# libgcc-5-dev:            libgcc_s.so + crtbegin.o/crtend.o
# libstdc++-5-dev:         libstdc++.so + headers (NOTE: only used by users,
#                          our toolchain itself uses libc++)
# libc6-pic, libc-bin:     misc support
PACKAGES_BASE=(
    "libc6"
    "libc6-dev"
    "linux-libc-dev"
    "libgcc-5-dev"
    "libstdc++-5-dev"
    "zlib1g"
    "zlib1g-dev"
)

# Additional X11/Vulkan/XCB packages for GUI cross-compilation
PACKAGES_GUI=(
    "libx11-6"           "libx11-dev"
    "libxcb1"            "libxcb1-dev"
    "libxext6"           "libxext-dev"
    "libxrandr2"         "libxrandr-dev"
    "libxinerama1"       "libxinerama-dev"
    "libxcursor1"        "libxcursor-dev"
    "libxi6"             "libxi-dev"
    "libxfixes3"         "libxfixes-dev"
    "libxrender1"        "libxrender-dev"
    "libxss1"            "libxss-dev"
    "libxxf86vm1"        "libxxf86vm-dev"
)

PACKAGES=("${PACKAGES_BASE[@]}" "${PACKAGES_GUI[@]}")

# ── Resolve and download .deb files ─────────────────────────────────────────
# Always use direct mirror download (Packages.gz parser).
# This works uniformly across host architectures (no need for dpkg
# --add-architecture or apt sources fiddling) and is deterministic.
log "Downloading Packages.gz from ${MIRROR}"

# Main repository
PKG_LIST_URL="${MIRROR}/dists/${UBUNTU_CODENAME}/main/binary-${DEB_ARCH}/Packages.gz"
curl --fail --location --silent --show-error \
     --output "${WORK_DIR}/main-Packages.gz" "${PKG_LIST_URL}"
gunzip -f "${WORK_DIR}/main-Packages.gz"

# Universe (some packages like libstdc++-5-dev live here)
PKG_LIST_UNIVERSE="${MIRROR}/dists/${UBUNTU_CODENAME}/universe/binary-${DEB_ARCH}/Packages.gz"
curl --fail --location --silent --show-error \
     --output "${WORK_DIR}/universe-Packages.gz" "${PKG_LIST_UNIVERSE}" || true
[[ -f "${WORK_DIR}/universe-Packages.gz" ]] && gunzip -f "${WORK_DIR}/universe-Packages.gz"

# Updates pocket (security/bug fixes for xenial)
PKG_LIST_UPDATES="${MIRROR}/dists/${UBUNTU_CODENAME}-updates/main/binary-${DEB_ARCH}/Packages.gz"
curl --fail --location --silent --show-error \
     --output "${WORK_DIR}/updates-Packages.gz" "${PKG_LIST_UPDATES}" || true
[[ -f "${WORK_DIR}/updates-Packages.gz" ]] && gunzip -f "${WORK_DIR}/updates-Packages.gz"

cat "${WORK_DIR}/main-Packages" \
    "${WORK_DIR}/universe-Packages" \
    "${WORK_DIR}/updates-Packages" 2>/dev/null > "${WORK_DIR}/all-Packages"

for pkg in "${PACKAGES[@]}"; do
    # Find LAST Filename: line (later entries are newer in -updates pocket)
    deb_path=$(awk -v pkg="${pkg}" '
        /^Package: / { is_match = ($2 == pkg); next }
        is_match && /^Filename: / { print $2 }
    ' "${WORK_DIR}/all-Packages" | tail -1)
    if [[ -n "${deb_path}" ]]; then
        log "  fetching ${pkg}"
        curl --fail --location --silent --show-error \
             --output "${WORK_DIR}/debs/$(basename "${deb_path}")" \
             "${MIRROR}/${deb_path}"
    else
        log "  WARN: ${pkg} not found in Packages list"
    fi
done

# ── Extract all .deb files into sysroot ─────────────────────────────────────
log "Extracting .debs into ${SYSROOT_DIR}"
for deb in "${WORK_DIR}/debs/"*.deb; do
    [[ -f "${deb}" ]] || continue
    extract_deb "${deb}" "${SYSROOT_DIR}"
done

# ── Cleanup unnecessary files ───────────────────────────────────────────────
prune_sysroot "${SYSROOT_DIR}"
fix_absolute_symlinks "${SYSROOT_DIR}"

# ── Verify essential files ──────────────────────────────────────────────────
ESSENTIAL=(
    "${SYSROOT_DIR}/usr/include/stdio.h"
    "${SYSROOT_DIR}/usr/include/${TRIPLE}/sys/types.h"
    "${SYSROOT_DIR}/usr/lib/${TRIPLE}/libc.so.6"
    "${SYSROOT_DIR}/usr/lib/${TRIPLE}/crt1.o"
)
for f in "${ESSENTIAL[@]}"; do
    if [[ ! -e "${f}" ]]; then
        echo "ERROR: essential file missing: ${f}" >&2
        find "${SYSROOT_DIR}" -name "$(basename "${f}")" 2>/dev/null | head -3
        exit 1
    fi
done

log "sysroot ${TRIPLE} complete"
du -sh "${SYSROOT_DIR}"
