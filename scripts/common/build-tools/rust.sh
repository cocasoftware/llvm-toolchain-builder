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

# 5. Smoke test BEFORE relocation (ensures install completed correctly with
#    system libgcc_s; we'll then bundle it locally and re-verify)
"${CARGO_HOME}/bin/rustc" --version
"${CARGO_HOME}/bin/cargo" --version

# 6. Bundle libgcc_s + libstdc++ from bootstrap GCC into tools/rust/lib/.
#    Rust's rustc/cargo (and various .so plugins under rustup/toolchains/...)
#    link against these. Bundling makes tools/rust/ self-contained on any
#    2015+ glibc system without requiring system GCC runtime.
bundle_gcc_runtime_into_tool "${TOOL_DIR}" libgcc_s libstdc++

# 7. Patch rpath on EVERY ELF under tools/rust/. Each binary gets a per-file
#    relative path to tools/rust/lib/ prepended (existing internal rpaths
#    like '$ORIGIN/../lib' for libstd.so are preserved).
add_rpath_to_lib_dir "${TOOL_DIR}" "${TOOL_DIR}/lib"

# 8. Strip toolchain binaries to save space (~50MB saved)
strip_binaries "${TOOL_DIR}"

# 9. Final verify: must have NO forbidden deps from the system, NO unresolved
verify_no_forbidden_deps "${TOOL_DIR}"

# 10. Re-test post-relocation
"${CARGO_HOME}/bin/rustc" --version
"${CARGO_HOME}/bin/cargo" --version

log "${TOOL_NAME} installed to ${TOOL_DIR}"
du -sh "${TOOL_DIR}"
ls "${RUSTUP_HOME}/toolchains/"
