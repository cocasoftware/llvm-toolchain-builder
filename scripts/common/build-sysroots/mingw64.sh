#!/usr/bin/env bash
# =============================================================================
# Build sysroots/x86_64-w64-mingw32-{ucrt,msvcrt} from llvm-mingw release.
#
# llvm-mingw is the most convenient way to get a complete mingw-w64 sysroot
# for both UCRT and MSVCRT variants in one shot. Distributed as a tarball.
#
# Reference: https://github.com/mstorsjo/llvm-mingw
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

MINGW_VERSION="${SYSROOT_MINGW_VERSION:-12.0.0}"
LLVM_MINGW_RELEASE="${LLVM_MINGW_RELEASE:-20240619}"

# llvm-mingw release tarball
HOST_ARCH="${1:-x86_64}"  # We want a Linux-x86_64 host but Windows-x86_64 target
case "${HOST_ARCH}" in
    x86_64) HOST_TAG="ubuntu-20.04-x86_64" ;;
    aarch64) HOST_TAG="ubuntu-20.04-aarch64" ;;
    *) echo "FATAL: unsupported HOST_ARCH=${HOST_ARCH}"; exit 1 ;;
esac

ARCHIVE_NAME="llvm-mingw-${LLVM_MINGW_RELEASE}-ucrt-${HOST_TAG}.tar.xz"
URL="https://github.com/mstorsjo/llvm-mingw/releases/download/${LLVM_MINGW_RELEASE}/${ARCHIVE_NAME}"

WORK_DIR="${SYSROOTS_WORK_DIR}/llvm-mingw-${LLVM_MINGW_RELEASE}"

log "Downloading llvm-mingw ${LLVM_MINGW_RELEASE} (${HOST_TAG})"

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"

curl --fail --location --silent --show-error \
     --output "${WORK_DIR}/llvm-mingw.tar.xz" "${URL}"

# Extract: tarball has a top-level llvm-mingw-VVV-ucrt-HOST/ dir
tar -xJf "${WORK_DIR}/llvm-mingw.tar.xz" -C "${WORK_DIR}" --strip-components=1

# llvm-mingw layout has:
#   x86_64-w64-mingw32/  (UCRT runtime)
#   include/, lib/ (subset of MSVCRT not always available — varies by release)
#
# We extract the relevant cross-target sysroot for both UCRT and MSVCRT.
# UCRT is the default in modern llvm-mingw; MSVCRT requires a separate release.

# UCRT sysroot
SYSROOT_UCRT="${SYSROOTS_CACHE_DIR}/x86_64-w64-mingw32-ucrt"
rm -rf "${SYSROOT_UCRT}"
mkdir -p "${SYSROOT_UCRT}"

# Copy x86_64-w64-mingw32/{include,lib} into sysroot
if [[ -d "${WORK_DIR}/x86_64-w64-mingw32" ]]; then
    cp -a "${WORK_DIR}/x86_64-w64-mingw32/." "${SYSROOT_UCRT}/"
else
    echo "ERROR: x86_64-w64-mingw32 dir not found in llvm-mingw" >&2
    ls "${WORK_DIR}"
    exit 1
fi

# clang resource dir (compiler-rt builtins for mingw)
if [[ -d "${WORK_DIR}/lib/clang" ]]; then
    mkdir -p "${SYSROOT_UCRT}/lib/clang"
    cp -a "${WORK_DIR}/lib/clang/." "${SYSROOT_UCRT}/lib/clang/"
fi

# ── MSVCRT variant: download a separate llvm-mingw msvcrt release ───────────
ARCHIVE_NAME_MSVCRT="llvm-mingw-${LLVM_MINGW_RELEASE}-msvcrt-${HOST_TAG}.tar.xz"
URL_MSVCRT="https://github.com/mstorsjo/llvm-mingw/releases/download/${LLVM_MINGW_RELEASE}/${ARCHIVE_NAME_MSVCRT}"

WORK_MSVCRT="${SYSROOTS_WORK_DIR}/llvm-mingw-${LLVM_MINGW_RELEASE}-msvcrt"
rm -rf "${WORK_MSVCRT}"
mkdir -p "${WORK_MSVCRT}"

if curl --fail --location --silent --show-error \
        --output "${WORK_MSVCRT}/llvm-mingw.tar.xz" "${URL_MSVCRT}"; then
    tar -xJf "${WORK_MSVCRT}/llvm-mingw.tar.xz" -C "${WORK_MSVCRT}" --strip-components=1

    SYSROOT_MSVCRT="${SYSROOTS_CACHE_DIR}/x86_64-w64-mingw32-msvcrt"
    rm -rf "${SYSROOT_MSVCRT}"
    mkdir -p "${SYSROOT_MSVCRT}"

    if [[ -d "${WORK_MSVCRT}/x86_64-w64-mingw32" ]]; then
        cp -a "${WORK_MSVCRT}/x86_64-w64-mingw32/." "${SYSROOT_MSVCRT}/"
    fi
    if [[ -d "${WORK_MSVCRT}/lib/clang" ]]; then
        mkdir -p "${SYSROOT_MSVCRT}/lib/clang"
        cp -a "${WORK_MSVCRT}/lib/clang/." "${SYSROOT_MSVCRT}/lib/clang/"
    fi
    log "MSVCRT sysroot installed"
else
    log "WARN: MSVCRT release ${URL_MSVCRT} not available; skipping MSVCRT variant"
fi

log "mingw64 sysroots complete"
du -sh "${SYSROOT_UCRT}" 2>/dev/null
du -sh "${SYSROOTS_CACHE_DIR}/x86_64-w64-mingw32-msvcrt" 2>/dev/null || true
