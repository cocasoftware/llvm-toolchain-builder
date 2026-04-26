#!/usr/bin/env bash
# =============================================================================
# Local orchestrator: build all bundled tools sequentially.
# Mainly for local testing — in CI we use the composite action per-tool.
#
# Required env:
#   STAGE2_PREFIX     — Stage 2 LLVM install prefix
# Optional env:
#   BOOTSTRAP_PREFIX  — bootstrap GCC + libs (default: /opt/bootstrap)
#   TOOLS_CACHE_DIR   — /opt/tools-cache
#   PLATFORM          — linux-x86_64 or linux-aarch64 (auto-detected)
#   TOOLS_TO_BUILD    — space-separated tool names to build (default: all in topological order)
#
# Topological order (deps first):
#   Tier 0: wasmtime jfrog glab rust ninja cmake rsync perl graphviz git
#           bzip2 sqlite3 expat openssl11 icu krb5
#   Tier 1: doxygen python pwsh
#   Tier 2: conan emsdk
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/../common"
BUILD_TOOLS_DIR="${COMMON_DIR}/build-tools"

source "${COMMON_DIR}/tool-versions.sh"

: "${STAGE2_PREFIX:?must be set}"
: "${BOOTSTRAP_PREFIX:=/opt/bootstrap}"
: "${TOOLS_CACHE_DIR:=/opt/tools-cache}"

# Auto-detect platform if not set
if [[ -z "${PLATFORM:-}" ]]; then
    case "$(uname -m)" in
        x86_64)  PLATFORM="linux-x86_64" ;;
        aarch64) PLATFORM="linux-aarch64" ;;
        *)       echo "FATAL: unsupported arch $(uname -m)" >&2; exit 1 ;;
    esac
fi
export PLATFORM STAGE2_PREFIX BOOTSTRAP_PREFIX TOOLS_CACHE_DIR

# Default tool order (deps first)
DEFAULT_TOOLS=(
    # Tier 0 — independent
    wasmtime jfrog glab rust
    ninja cmake rsync perl graphviz git
    bzip2 sqlite3 expat
    openssl11 icu krb5
    # Tier 1 — depend on Tier 0
    doxygen python pwsh
    # Tier 2 — depend on Python
    conan emsdk
)

TOOLS_TO_BUILD="${TOOLS_TO_BUILD:-${DEFAULT_TOOLS[*]}}"

log() { echo "===> $(date '+%H:%M:%S') $*"; }

mkdir -p "${TOOLS_CACHE_DIR}"/{sources,built,work}

log "Build environment:"
log "  PLATFORM         = ${PLATFORM}"
log "  STAGE2_PREFIX    = ${STAGE2_PREFIX}"
log "  BOOTSTRAP_PREFIX = ${BOOTSTRAP_PREFIX}"
log "  TOOLS_CACHE_DIR  = ${TOOLS_CACHE_DIR}"
log "  TOOLS_TO_BUILD   = ${TOOLS_TO_BUILD}"

failed_tools=()
succeeded_tools=()
skipped_tools=()

for tool in ${TOOLS_TO_BUILD}; do
    script="${BUILD_TOOLS_DIR}/${tool}.sh"
    if [[ ! -f "${script}" ]]; then
        log "SKIP: no build script for ${tool} at ${script}"
        skipped_tools+=("${tool}")
        continue
    fi

    log "================================================================="
    log " Building tool: ${tool}"
    log "================================================================="
    if bash "${script}"; then
        succeeded_tools+=("${tool}")
    else
        log "FAIL: ${tool}"
        failed_tools+=("${tool}")
    fi
done

# ── Summary ─────────────────────────────────────────────────────────────────
log "================================================================="
log " Build summary:"
log "  succeeded: ${#succeeded_tools[@]}  (${succeeded_tools[*]:-})"
log "  skipped:   ${#skipped_tools[@]}    (${skipped_tools[*]:-})"
log "  failed:    ${#failed_tools[@]}     (${failed_tools[*]:-})"

if (( ${#failed_tools[@]} > 0 )); then
    exit 1
fi

log "Built tools available in ${TOOLS_CACHE_DIR}/built/"
ls -la "${TOOLS_CACHE_DIR}/built/" || true
