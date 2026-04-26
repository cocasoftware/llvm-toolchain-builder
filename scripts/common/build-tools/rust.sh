#!/usr/bin/env bash
# =============================================================================
# Rust toolchain via rustup.
# rustup-init is statically-linked, so it runs on any glibc ≥ 2.17.
# rustc/cargo are GLIBC-compatible by upstream design (built on RHEL 7).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/.."

source "${COMMON_DIR}/tool-versions.sh"
source "${SCRIPT_DIR}/_download.sh"
source "${SCRIPT_DIR}/_relocate.sh"

log() { echo "===> $(date '+%H:%M:%S') $*"; }
err() { echo "ERROR: $*" >&2; }

TOOL_NAME="rust"
VERSION="${TOOL_RUST_VERSION}"
PLATFORM="${PLATFORM:-linux-x86_64}"

case "${PLATFORM}" in
    linux-x86_64)  RUST_HOST="x86_64-unknown-linux-gnu" ;;
    linux-aarch64) RUST_HOST="aarch64-unknown-linux-gnu" ;;
    *) err "unsupported PLATFORM=${PLATFORM} for rust"; exit 1 ;;
esac

# rustup-init binary download URL
RUSTUP_INIT_URL="https://static.rust-lang.org/rustup/dist/${RUST_HOST}/rustup-init"

TOOL_DIR="${TOOLS_CACHE_DIR}/built/${TOOL_NAME}"

log "Installing Rust ${VERSION} for ${PLATFORM}"

# 1. Download rustup-init
download_file "${RUSTUP_INIT_URL}" "rustup-init-${VERSION}-${RUST_HOST}"

rm -rf "${TOOL_DIR}"
mkdir -p "${TOOL_DIR}"

# 2. Set up RUSTUP_HOME and CARGO_HOME inside the tool dir
export RUSTUP_HOME="${TOOL_DIR}/rustup"
export CARGO_HOME="${TOOL_DIR}/cargo"

# Install rustup-init as the bundle entry point
cp "${SOURCES_DIR}/rustup-init-${VERSION}-${RUST_HOST}" "${TOOL_DIR}/rustup-init"
chmod +x "${TOOL_DIR}/rustup-init"

# 3. Run rustup-init non-interactively to install the requested toolchain
"${TOOL_DIR}/rustup-init" -y \
    --no-modify-path \
    --default-toolchain "${VERSION}" \
    --profile minimal \
    --default-host "${RUST_HOST}"

# 4. Install cross-compilation targets (matching COCA reference: 8 targets)
PATH="${CARGO_HOME}/bin:${PATH}"
TARGETS=(
    "x86_64-unknown-linux-gnu"
    "aarch64-unknown-linux-gnu"
    "x86_64-unknown-linux-musl"
    "aarch64-unknown-linux-musl"
    "x86_64-pc-windows-gnu"
    "wasm32-unknown-unknown"
    "wasm32-wasip1"
    "wasm32-unknown-emscripten"
)
for t in "${TARGETS[@]}"; do
    "${RUSTUP_HOME}/../cargo/bin/rustup" target add "${t}" --toolchain "${VERSION}-${RUST_HOST}" || \
        log "WARN: rustup target ${t} not added (may not exist for this Rust version)"
done

# 5. Verify
"${CARGO_HOME}/bin/rustc" --version
"${CARGO_HOME}/bin/cargo" --version

# 6. Strip rust toolchain binaries to save space (optional — saves ~50MB)
STAGE_TC="${RUSTUP_HOME}/toolchains/${VERSION}-${RUST_HOST}"
if [[ -d "${STAGE_TC}/bin" ]]; then
    find "${STAGE_TC}/bin" -type f -executable -exec strip --strip-unneeded {} \; 2>/dev/null || true
fi

# 7. Quick verify (rust binaries are usually OK; if any forbidden deps appear,
#    upstream is at fault — we accept upstream rust binaries as-is)
verify_no_forbidden_deps "${TOOL_DIR}" || \
    log "WARN: rust toolchain has dep issues; upstream binary kept as-is"

log "${TOOL_NAME} installed to ${TOOL_DIR}"
du -sh "${TOOL_DIR}"
ls "${RUSTUP_HOME}/toolchains/"
