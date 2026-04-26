#!/usr/bin/env bash
# =============================================================================
# Centralized version registry for all bundled tools.
# Sourced by every build-tools/<tool>.sh script and by workflow cache key
# computation. Bumping a version here invalidates ONLY that tool's cache.
# =============================================================================

# ── Build tools (compiled from source with Stage 2 LLVM) ────────────────────
export TOOL_CMAKE_VERSION="${TOOL_CMAKE_VERSION:-4.2.3}"
export TOOL_NINJA_VERSION="${TOOL_NINJA_VERSION:-1.13.1}"
export TOOL_GIT_VERSION="${TOOL_GIT_VERSION:-2.53.0}"
export TOOL_DOXYGEN_VERSION="${TOOL_DOXYGEN_VERSION:-1.16.1}"
export TOOL_GRAPHVIZ_VERSION="${TOOL_GRAPHVIZ_VERSION:-14.1.2}"
export TOOL_PERL_VERSION="${TOOL_PERL_VERSION:-5.42.0}"
export TOOL_RSYNC_VERSION="${TOOL_RSYNC_VERSION:-3.4.1}"
export TOOL_PYTHON_VERSION="${TOOL_PYTHON_VERSION:-3.14.4}"

# ── Python build dependencies (compiled from source) ────────────────────────
export TOOL_BZIP2_VERSION="${TOOL_BZIP2_VERSION:-1.0.8}"
export TOOL_SQLITE_VERSION="${TOOL_SQLITE_VERSION:-3.51.0}"
export TOOL_SQLITE_YEAR="${TOOL_SQLITE_YEAR:-2025}"
export TOOL_EXPAT_VERSION="${TOOL_EXPAT_VERSION:-2.7.1}"

# ── PowerShell dependencies (compiled from source, bundled into pwsh dir) ───
export TOOL_OPENSSL11_VERSION="${TOOL_OPENSSL11_VERSION:-1.1.1w}"
export TOOL_ICU_VERSION="${TOOL_ICU_VERSION:-77.1}"
export TOOL_KRB5_VERSION="${TOOL_KRB5_VERSION:-1.21.3}"

# ── Pre-built downloads (statically-linked or self-contained) ───────────────
export TOOL_WASMTIME_VERSION="${TOOL_WASMTIME_VERSION:-41.0.3}"
export TOOL_JFROG_VERSION="${TOOL_JFROG_VERSION:-2.72.2}"
export TOOL_GLAB_VERSION="${TOOL_GLAB_VERSION:-1.74.0}"
export TOOL_PWSH_VERSION="${TOOL_PWSH_VERSION:-7.5.5}"

# ── Special install methods ─────────────────────────────────────────────────
export TOOL_RUST_VERSION="${TOOL_RUST_VERSION:-1.93.1}"
export TOOL_EMSDK_VERSION="${TOOL_EMSDK_VERSION:-5.0.0}"
export TOOL_CONAN_VERSION="${TOOL_CONAN_VERSION:-2.25.2}"

# ── Sysroot sources ─────────────────────────────────────────────────────────
export SYSROOT_UBUNTU_VERSION="${SYSROOT_UBUNTU_VERSION:-16.04}"
export SYSROOT_ALPINE_VERSION="${SYSROOT_ALPINE_VERSION:-3.20}"
export SYSROOT_MUSL_VERSION="${SYSROOT_MUSL_VERSION:-1.2.5}"
export SYSROOT_MINGW_VERSION="${SYSROOT_MINGW_VERSION:-12.0.0}"
export SYSROOT_WASI_SDK_VERSION="${SYSROOT_WASI_SDK_VERSION:-30.0}"

# ── Helper: print all versions (for cache key debug / info dump) ────────────
print_tool_versions() {
    set | grep -E '^TOOL_|^SYSROOT_' | sort
}
