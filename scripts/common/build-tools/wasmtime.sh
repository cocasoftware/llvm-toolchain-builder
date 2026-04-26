#!/usr/bin/env bash
# =============================================================================
# wasmtime: WASI runtime — official prebuilt binary.
# x86_64 Linux release is musl-static (zero non-libc deps).
# aarch64 Linux release links dynamically against libgcc_s — we bundle that
# from the bootstrap GCC into tools/wasmtime/lib/ and patch rpath so the
# tool is fully self-contained (no system libgcc_s required).
# Layout: tools/wasmtime/bin/wasmtime + tools/wasmtime/lib/libgcc_s.so.1
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

# 3. Install: bin/wasmtime + LICENSE + README
rm -rf "${TOOL_DIR}"
mkdir -p "${TOOL_DIR}/bin"
cp "${WORK_DIR}/wasmtime"     "${TOOL_DIR}/bin/wasmtime"
cp "${WORK_DIR}/LICENSE"      "${TOOL_DIR}/LICENSE" 2>/dev/null || true
cp "${WORK_DIR}/README.md"    "${TOOL_DIR}/README.md" 2>/dev/null || true
chmod +x "${TOOL_DIR}/bin/wasmtime"

# 4. Bundle libgcc_s.so.1 from bootstrap GCC into tools/wasmtime/lib/
#    so that the tool is self-contained on any 2015+ glibc system without
#    requiring system libgcc_s. Idempotent: aarch64 needs it; x86_64 has
#    a musl-static binary so libgcc_s is unused but harmless to bundle.
bundle_gcc_runtime_into_tool "${TOOL_DIR}" libgcc_s

# 5. Patch rpath: bin/wasmtime → $ORIGIN/../lib (resolves to tools/wasmtime/lib/)
set_rpath_origin "${TOOL_DIR}"
strip_binaries   "${TOOL_DIR}"

# 6. Verify: must have NO forbidden deps from the system, and NO unresolved
verify_no_forbidden_deps "${TOOL_DIR}"

# 7. Smoke test
"${TOOL_DIR}/bin/wasmtime" --version

echo "===> ${TOOL_NAME} installed to ${TOOL_DIR}"
ls -la "${TOOL_DIR}" "${TOOL_DIR}/bin"
[[ -d "${TOOL_DIR}/lib" ]] && ls -la "${TOOL_DIR}/lib"
