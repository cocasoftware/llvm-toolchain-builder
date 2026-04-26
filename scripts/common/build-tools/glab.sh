#!/usr/bin/env bash
# =============================================================================
# glab: GitLab CLI (Go-built static binary, zero deps).
# Distribution: tarball from GitLab releases CDN.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/.."

source "${COMMON_DIR}/tool-versions.sh"
source "${SCRIPT_DIR}/_download.sh"
source "${SCRIPT_DIR}/_relocate.sh"

TOOL_NAME="glab"
VERSION="${TOOL_GLAB_VERSION}"
PLATFORM="${PLATFORM:-linux-x86_64}"

case "${PLATFORM}" in
    linux-x86_64) ARCH_TAG="Linux_x86_64" ;;
    linux-aarch64) ARCH_TAG="Linux_arm64" ;;
    *)
        echo "FATAL: unsupported PLATFORM=${PLATFORM} for glab" >&2
        exit 1
        ;;
esac

ARCHIVE_NAME="glab_${VERSION}_${ARCH_TAG}.tar.gz"
URL="https://gitlab.com/gitlab-org/cli/-/releases/v${VERSION}/downloads/${ARCHIVE_NAME}"

TOOL_DIR="${TOOLS_CACHE_DIR:-/opt/tools-cache}/built/${TOOL_NAME}"
WORK_DIR="${TOOLS_CACHE_DIR:-/opt/tools-cache}/work/${TOOL_NAME}-${VERSION}"

echo "===> Building ${TOOL_NAME} v${VERSION} for ${PLATFORM}"

# 1. Download
download_file "${URL}" "${ARCHIVE_NAME}"

# 2. Extract (glab tarball does NOT have a top-level dir wrapper as of v1.x — adjust strip)
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
tar -xzf "${SOURCES_DIR:-${TOOLS_CACHE_DIR:-/opt/tools-cache}/sources}/${ARCHIVE_NAME}" -C "${WORK_DIR}"

# 3. Install: glab → bin/glab
rm -rf "${TOOL_DIR}"
mkdir -p "${TOOL_DIR}/bin"
if [[ -f "${WORK_DIR}/bin/glab" ]]; then
    cp "${WORK_DIR}/bin/glab" "${TOOL_DIR}/bin/glab"
elif [[ -f "${WORK_DIR}/glab" ]]; then
    cp "${WORK_DIR}/glab" "${TOOL_DIR}/bin/glab"
else
    echo "FATAL: glab binary not found in extracted archive" >&2
    find "${WORK_DIR}" -name 'glab*' -type f 2>/dev/null
    exit 1
fi
chmod +x "${TOOL_DIR}/bin/glab"

# Copy LICENSE if present
[[ -f "${WORK_DIR}/LICENSE" ]] && cp "${WORK_DIR}/LICENSE" "${TOOL_DIR}/LICENSE"
[[ -f "${WORK_DIR}/LICENSE.txt" ]] && cp "${WORK_DIR}/LICENSE.txt" "${TOOL_DIR}/LICENSE.txt"

# 4. Strip + verify (Go binary, statically linked, should have no deps)
strip_binaries "${TOOL_DIR}"
verify_no_forbidden_deps "${TOOL_DIR}"

# 5. Smoke test
"${TOOL_DIR}/bin/glab" --version | head -1

echo "===> ${TOOL_NAME} installed to ${TOOL_DIR}"
ls -la "${TOOL_DIR}" "${TOOL_DIR}/bin"
