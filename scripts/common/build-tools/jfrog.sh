#!/usr/bin/env bash
# =============================================================================
# jfrog CLI: Go-built static binary, zero deps.
# Distribution: single binary "jf" downloaded from JFrog releases CDN.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/.."

source "${COMMON_DIR}/tool-versions.sh"
source "${SCRIPT_DIR}/_download.sh"
source "${SCRIPT_DIR}/_relocate.sh"

TOOL_NAME="jfrog"
VERSION="${TOOL_JFROG_VERSION}"
PLATFORM="${PLATFORM:-linux-x86_64}"

case "${PLATFORM}" in
    linux-x86_64) ARCH_DIR="jfrog-cli-linux-amd64" ;;
    linux-aarch64) ARCH_DIR="jfrog-cli-linux-arm64" ;;
    *)
        echo "FATAL: unsupported PLATFORM=${PLATFORM} for jfrog" >&2
        exit 1
        ;;
esac

# Direct binary download (no archive)
URL="https://releases.jfrog.io/artifactory/jfrog-cli/v2-jf/${VERSION}/${ARCH_DIR}/jf"
DEST_NAME="jf-${VERSION}-${PLATFORM}"

TOOL_DIR="${TOOLS_CACHE_DIR:-/opt/tools-cache}/built/${TOOL_NAME}"

echo "===> Building ${TOOL_NAME} v${VERSION} for ${PLATFORM}"

# 1. Download single binary (cached)
download_file "${URL}" "${DEST_NAME}"

# 2. Install: bin/jf
rm -rf "${TOOL_DIR}"
mkdir -p "${TOOL_DIR}/bin"
cp "${SOURCES_DIR:-${TOOLS_CACHE_DIR:-/opt/tools-cache}/sources}/${DEST_NAME}" "${TOOL_DIR}/bin/jf"
chmod +x "${TOOL_DIR}/bin/jf"

# 3. Strip + verify (Go binaries are statically linked; should have zero deps)
strip_binaries "${TOOL_DIR}"
verify_no_forbidden_deps "${TOOL_DIR}"

# 4. Smoke test
"${TOOL_DIR}/bin/jf" --version | head -1

echo "===> ${TOOL_NAME} installed to ${TOOL_DIR}"
ls -la "${TOOL_DIR}" "${TOOL_DIR}/bin"
