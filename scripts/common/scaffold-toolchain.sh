#!/usr/bin/env bash
# =============================================================================
# Scaffold a toolchain root directory from templates + tools-cache.
#
# This is the assembly step that turns a Stage 2 LLVM install + a populated
# /opt/tools-cache/built/ into a complete toolchain with the expected layout
# (tools/, scripts/, cmake/, tests/, setup.py, toolchain.json, manifest.json).
#
# Required env:
#   INSTALL_PREFIX       — final toolchain root (will be modified in-place)
#   VARIANT              — "main" or "p2996"
#   TEMPLATES_DIR        — repo root /templates dir
# Optional env:
#   TOOLS_CACHE_DIR      — /opt/tools-cache (default)
#   TOOLS_TO_INSTALL     — space-separated tool names; default: all under built/
#
# Usage:
#   INSTALL_PREFIX=/opt/coca-toolchain-linux-x86_64 \
#   VARIANT=main \
#   TEMPLATES_DIR=/src/templates \
#   bash scripts/common/scaffold-toolchain.sh
# =============================================================================
set -euo pipefail

: "${INSTALL_PREFIX:?must be set}"
: "${VARIANT:?must be set}"
: "${TEMPLATES_DIR:?must be set}"
: "${TOOLS_CACHE_DIR:=/opt/tools-cache}"

log() { echo "===> $(date '+%H:%M:%S') $*"; }

# ── Validate inputs ────────────────────────────────────────────────────────
case "${VARIANT}" in
    main|p2996) ;;
    *) echo "FATAL: VARIANT must be 'main' or 'p2996', got '${VARIANT}'" >&2; exit 1 ;;
esac

if [[ ! -d "${TEMPLATES_DIR}/shared" ]]; then
    echo "FATAL: ${TEMPLATES_DIR}/shared not found" >&2
    exit 1
fi
if [[ ! -d "${TEMPLATES_DIR}/${VARIANT}" ]]; then
    echo "FATAL: ${TEMPLATES_DIR}/${VARIANT} not found" >&2
    exit 1
fi

mkdir -p "${INSTALL_PREFIX}"

# ── 1. Copy shared template files (setup.py, scripts/, cmake/, tests/) ─────
log "Scaffolding shared templates → ${INSTALL_PREFIX}"
cp -a "${TEMPLATES_DIR}/shared/setup.py"   "${INSTALL_PREFIX}/setup.py"
cp -a "${TEMPLATES_DIR}/shared/setup.sh"   "${INSTALL_PREFIX}/setup.sh"
chmod +x "${INSTALL_PREFIX}/setup.sh"

mkdir -p "${INSTALL_PREFIX}/scripts" "${INSTALL_PREFIX}/cmake" "${INSTALL_PREFIX}/tests"
cp -a "${TEMPLATES_DIR}/shared/scripts/." "${INSTALL_PREFIX}/scripts/"
cp -a "${TEMPLATES_DIR}/shared/cmake/."   "${INSTALL_PREFIX}/cmake/"
cp -a "${TEMPLATES_DIR}/shared/tests/."   "${INSTALL_PREFIX}/tests/"

# ── 2. Copy variant-specific files (toolchain.json, README.md) ─────────────
log "Scaffolding variant-specific files (${VARIANT}) → ${INSTALL_PREFIX}"
cp -a "${TEMPLATES_DIR}/${VARIANT}/toolchain.json" "${INSTALL_PREFIX}/toolchain.json"
cp -a "${TEMPLATES_DIR}/${VARIANT}/README.md"      "${INSTALL_PREFIX}/README.md"

# ── 3. Install tools from /opt/tools-cache/built/ ──────────────────────────
mkdir -p "${INSTALL_PREFIX}/tools"

tools_built_dir="${TOOLS_CACHE_DIR}/built"
if [[ ! -d "${tools_built_dir}" ]]; then
    log "WARN: ${tools_built_dir} does not exist; tools/ will be empty"
else
    if [[ -n "${TOOLS_TO_INSTALL:-}" ]]; then
        # User-specified subset
        for tool in ${TOOLS_TO_INSTALL}; do
            if [[ -d "${tools_built_dir}/${tool}" ]]; then
                log "  installing tool: ${tool}"
                rm -rf "${INSTALL_PREFIX}/tools/${tool}"
                cp -a "${tools_built_dir}/${tool}" "${INSTALL_PREFIX}/tools/${tool}"
            else
                log "  WARN: requested tool '${tool}' not found in ${tools_built_dir}"
            fi
        done
    else
        # All tools present in cache
        # Skip _deps/ (internal helpers like bzip2/sqlite3/expat/openssl11/icu/krb5
        # that are bundled INTO python.sh / pwsh.sh, not exposed as tools).
        for tool_dir in "${tools_built_dir}"/*/; do
            [[ -d "${tool_dir}" ]] || continue
            tool=$(basename "${tool_dir}")
            if [[ "${tool}" == _* ]]; then
                log "  skipping internal: ${tool}"
                continue
            fi
            log "  installing tool: ${tool}"
            rm -rf "${INSTALL_PREFIX}/tools/${tool}"
            cp -a "${tool_dir%/}" "${INSTALL_PREFIX}/tools/${tool}"
        done
    fi
fi

# ── 4. Create .gitignore inside toolchain (for users who init git inside) ──
cat > "${INSTALL_PREFIX}/.gitignore" << 'EOF'
*.tar.xz
*.tar.gz
__pycache__/
*.pyc
.venv*/
build/
EOF

# ── 5. Detect if we have a bundled Python; if so, regenerate manifest.json ──
bundled_py=""
for cand in "${INSTALL_PREFIX}/tools/python/bin/python3" \
            "${INSTALL_PREFIX}/tools/python/bin/python" \
            "${INSTALL_PREFIX}/tools/python/python3"; do
    if [[ -x "${cand}" ]]; then
        bundled_py="${cand}"
        break
    fi
done

if [[ -n "${bundled_py}" ]]; then
    log "Regenerating manifest.json via bundled Python"
    "${bundled_py}" "${INSTALL_PREFIX}/setup.py" update-manifest || \
        log "WARN: setup.py update-manifest failed; manifest.json may be stale"
else
    log "No bundled Python found yet; skipping manifest.json regeneration"
fi

log "Scaffold complete: ${INSTALL_PREFIX}"
ls -la "${INSTALL_PREFIX}" | head -20
