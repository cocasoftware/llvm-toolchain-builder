#!/usr/bin/env bash
# =============================================================================
# wasmtime: WASI runtime (statically-linked Rust binary, zero deps).
# Strategy: download official musl-static release, extract to tools-cache.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/.."

source "${COMMON_DIR}/tool-versions.sh"
source "${SCRIPT_DIR}/_download.sh"
source "${SCRIPT_DIR}/_relocate.sh"

TOOL_NAME="wasmtime"
VERSION="${TOOL_WASMTIME_VERSION}"
PLATFORM="${PLATFORM:-linux-x86_64}"

case "${PLATFORM}" in
    linux-x86_64)
        ARCH_TRIPLE="x86_64-linux"
        ;;
    linux-aarch64)
        ARCH_TRIPLE="aarch64-linux"
        ;;
    *)
        echo "FATAL: unsupported PLATFORM=${PLATFORM} for wasmtime" >&2
        exit 1
        ;;
esac

ARCHIVE_NAME="wasmtime-v${VERSION}-${ARCH_TRIPLE}.tar.xz"
URL="https://github.com/bytecodealliance/wasmtime/releases/download/v${VERSION}/${ARCHIVE_NAME}"

TOOL_DIR="${TOOLS_CACHE_DIR:-/opt/tools-cache}/built/${TOOL_NAME}"
WORK_DIR="${TOOLS_CACHE_DIR:-/opt/tools-cache}/work/${TOOL_NAME}-${VERSION}"

echo "===> Building ${TOOL_NAME} v${VERSION} for ${PLATFORM}"

# 1. Download
download_file "${URL}" "${ARCHIVE_NAME}"

# 2. Extract to work dir
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
extract_archive "${SOURCES_DIR:-${TOOLS_CACHE_DIR:-/opt/tools-cache}/sources}/${ARCHIVE_NAME}" "${WORK_DIR}" 1

# 3. Install: tools/wasmtime/wasmtime, tools/wasmtime/wasmtime-min, README, LICENSE
rm -rf "${TOOL_DIR}"
mkdir -p "${TOOL_DIR}"
cp "${WORK_DIR}/wasmtime"     "${TOOL_DIR}/wasmtime"
cp "${WORK_DIR}/LICENSE"      "${TOOL_DIR}/LICENSE" 2>/dev/null || true
cp "${WORK_DIR}/README.md"    "${TOOL_DIR}/README.md" 2>/dev/null || true
chmod +x "${TOOL_DIR}/wasmtime"

# 4. Verify (wasmtime is statically linked, should have zero dynamic deps beyond glibc)
verify_no_forbidden_deps "${TOOL_DIR}"

# 5. Smoke test
"${TOOL_DIR}/wasmtime" --version

echo "===> ${TOOL_NAME} installed to ${TOOL_DIR}"
ls -la "${TOOL_DIR}"
