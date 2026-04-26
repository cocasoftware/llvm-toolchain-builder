#!/usr/bin/env bash
# =============================================================================
# Emscripten SDK: clone from upstream + install fixed version via emsdk.
# emsdk itself is a Python wrapper; the actual toolchain is downloaded by
# emsdk on first use. We pre-download a specific version to make the
# toolchain self-contained.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/.."

source "${COMMON_DIR}/tool-versions.sh"

log() { echo "===> $(date '+%H:%M:%S') $*"; }

TOOL_NAME="emsdk"
VERSION="${TOOL_EMSDK_VERSION}"
PLATFORM="${PLATFORM:-linux-x86_64}"

EMSDK_REPO="https://github.com/emscripten-core/emsdk.git"

TOOL_DIR="${TOOLS_CACHE_DIR}/built/${TOOL_NAME}"

log "Installing Emscripten SDK ${VERSION} for ${PLATFORM}"

# 1. Clone emsdk wrapper
rm -rf "${TOOL_DIR}"
git clone --depth=1 --branch="${VERSION}" "${EMSDK_REPO}" "${TOOL_DIR}" || \
    git clone "${EMSDK_REPO}" "${TOOL_DIR}"

cd "${TOOL_DIR}"

# 2. Use bundled Python from tools-cache if available, else system python3
PY_BIN="python3"
if [[ -x "${TOOLS_CACHE_DIR}/built/python/bin/python3" ]]; then
    PY_BIN="${TOOLS_CACHE_DIR}/built/python/bin/python3"
fi

# 3. Pin the emsdk core version (sdk-VERSION-64bit)
"${PY_BIN}" emsdk.py install "${VERSION}"
"${PY_BIN}" emsdk.py activate "${VERSION}"

# 4. Verify by sourcing the env
source "${TOOL_DIR}/emsdk_env.sh"

# Sanity check
"${TOOL_DIR}/upstream/emscripten/emcc" --version | head -1 || \
    log "WARN: emcc smoke test failed; check ${TOOL_DIR}/upstream/emscripten/"

log "${TOOL_NAME} installed to ${TOOL_DIR}"
du -sh "${TOOL_DIR}"
