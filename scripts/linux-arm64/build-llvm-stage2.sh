#!/usr/bin/env bash
# =============================================================================
# LLVM Stage 2 Build — full self-hosted toolchain using Stage 1 clang
# Platform: Linux AArch64 (Ubuntu 16.04 ARM64)
#
# Supports: VARIANT=main | p2996
#
# Usage:
#   BOOTSTRAP_PREFIX=/opt/bootstrap STAGE1_PREFIX=/opt/stage1 \
#   INSTALL_PREFIX=/opt/coca-toolchain VARIANT=main \
#   ./scripts/linux-arm64/build-llvm-stage2.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/../common"

: "${BOOTSTRAP_PREFIX:=/opt/bootstrap}"
: "${STAGE1_PREFIX:=/opt/stage1}"
: "${INSTALL_PREFIX:=/opt/coca-toolchain}"
: "${VARIANT:=main}"
: "${LLVM_SRC:=/tmp/llvm-project}"
: "${P2996_SRC:=/tmp/llvm-p2996}"
: "${STAGE2_BUILD:=/tmp/stage2-build}"
: "${NPROC:=$(nproc)}"

export PLATFORM="linux-arm64"
export STAGE="stage2"

export PATH="${STAGE1_PREFIX}/bin:${BOOTSTRAP_PREFIX}/bin:${PATH}"
export LD_LIBRARY_PATH="${STAGE1_PREFIX}/lib:${STAGE1_PREFIX}/lib/aarch64-unknown-linux-gnu:${BOOTSTRAP_PREFIX}/lib64:${BOOTSTRAP_PREFIX}/lib:${LD_LIBRARY_PATH:-}"

source "${COMMON_DIR}/versions.sh"
source "${COMMON_DIR}/source.sh"
source "${COMMON_DIR}/llvm-config.sh"
source "${COMMON_DIR}/post-install.sh"

log() { echo "===> $(date '+%H:%M:%S') $*"; }

# Validate Stage 1
if [[ ! -x "${STAGE1_PREFIX}/bin/clang" ]]; then
    echo "ERROR: Stage 1 clang not found at ${STAGE1_PREFIX}/bin/clang" >&2
    exit 1
fi

main() {
    log "LLVM Stage 2 build starting (${PLATFORM}, variant=${VARIANT})"
    log "  BOOTSTRAP_PREFIX: ${BOOTSTRAP_PREFIX}"
    log "  STAGE1_PREFIX:    ${STAGE1_PREFIX}"
    log "  INSTALL_PREFIX:   ${INSTALL_PREFIX}"
    log "  NPROC:            ${NPROC}"

    # Obtain source
    local src_dir
    if [[ "${VARIANT}" == "p2996" ]]; then
        obtain_llvm_source "${P2996_SRC}"
        src_dir="${P2996_SRC}"
    else
        obtain_llvm_source "${LLVM_SRC}"
        src_dir="${LLVM_SRC}"
    fi
    export SOURCE_DIR="${src_dir}"
    export BUILD_DIR="${STAGE2_BUILD}"

    mkdir -p "${STAGE2_BUILD}"

    generate_cmake_args

    log "Configuring LLVM Stage 2..."
    cmake -G Ninja -S "${SOURCE_DIR}/llvm" -B "${STAGE2_BUILD}" "${CMAKE_ARGS[@]}"

    log "Building LLVM Stage 2..."
    cmake --build "${STAGE2_BUILD}" -j"${NPROC}"

    log "Installing LLVM Stage 2..."
    cmake --install "${STAGE2_BUILD}"

    log "Stage 2 installed to ${INSTALL_PREFIX}"

    # Post-install
    run_post_install

    # Verification
    log "Toolchain verification:"
    "${INSTALL_PREFIX}/bin/clang" --version
    "${INSTALL_PREFIX}/bin/lld" --version || true
    "${INSTALL_PREFIX}/bin/lldb" --version || true

    log "Stage 2 build complete!"
}

main "$@"
