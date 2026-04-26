#!/usr/bin/env bash
# =============================================================================
# Orchestrate construction of all 5 sysroots:
#   - x86_64-linux-gnu, aarch64-linux-gnu     (Ubuntu 16.04 / glibc 2.23)
#   - x86_64-linux-musl, aarch64-linux-musl   (Alpine 3.20 / musl 1.2.5)
#   - x86_64-w64-mingw32-{ucrt,msvcrt}        (llvm-mingw)
#   - wasm32-wasi                              (wasi-sdk 30)
#
# Output: /opt/tools-cache/sysroots/<triple>/  (each independently cacheable)
#
# Usage: bash scripts/linux/build-sysroots.sh [--only TRIPLE]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/../common"

source "${COMMON_DIR}/tool-versions.sh"

ONLY=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --only) ONLY="$2"; shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

run_step() {
    local name="$1"; shift
    if [[ -n "${ONLY}" && "${ONLY}" != "${name}" ]]; then
        echo "[skip] sysroot ${name}"
        return 0
    fi
    echo "==============================================================="
    echo " Building sysroot: ${name}"
    echo "==============================================================="
    "$@"
}

# 1. Linux glibc
run_step "x86_64-linux-gnu"     bash "${COMMON_DIR}/build-sysroots/linux-gnu.sh"  x86_64
run_step "aarch64-linux-gnu"    bash "${COMMON_DIR}/build-sysroots/linux-gnu.sh"  aarch64

# 2. Linux musl
run_step "x86_64-linux-musl"    bash "${COMMON_DIR}/build-sysroots/linux-musl.sh" x86_64
run_step "aarch64-linux-musl"   bash "${COMMON_DIR}/build-sysroots/linux-musl.sh" aarch64

# 3. mingw-w64 (UCRT + MSVCRT)
run_step "x86_64-w64-mingw32"   bash "${COMMON_DIR}/build-sysroots/mingw64.sh"    x86_64

# 4. wasi
run_step "wasm32-wasi"          bash "${COMMON_DIR}/build-sysroots/wasi.sh"

echo "==============================================================="
echo " All sysroots built. Summary:"
echo "==============================================================="
ls -la "${SYSROOTS_CACHE_DIR:-/opt/tools-cache/sysroots}/"
