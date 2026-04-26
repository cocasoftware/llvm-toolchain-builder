#!/usr/bin/env bash
# =============================================================================
# Sandboxed build environment for tools/* compilation.
#
# Sourced by each build-tools/<tool>.sh. Establishes a minimal, deterministic
# environment where:
#   1. PATH contains ONLY: Stage 2 bin, bootstrap bin, system /usr/bin
#   2. Compilers are pinned to Stage 2 clang/lld
#   3. C++ uses libc++ (NEVER libstdc++)
#   4. Linker emits $ORIGIN-relative rpath
#   5. pkg-config points at bootstrap libs
#
# Required env (caller must set):
#   STAGE2_PREFIX  — where Stage 2 LLVM lives (bin/clang, lib/libc++.so)
# Optional env:
#   BOOTSTRAP_PREFIX  — bootstrap GCC + libs (default: /opt/bootstrap)
#   TOOLS_CACHE_DIR   — per-tool install cache (default: /opt/tools-cache)
# =============================================================================

if [[ -z "${STAGE2_PREFIX:-}" ]]; then
    echo "FATAL: _sandbox.sh requires STAGE2_PREFIX to be set" >&2
    return 1 2>/dev/null || exit 1
fi

if [[ ! -x "${STAGE2_PREFIX}/bin/clang" ]]; then
    echo "FATAL: ${STAGE2_PREFIX}/bin/clang not executable" >&2
    return 1 2>/dev/null || exit 1
fi

: "${BOOTSTRAP_PREFIX:=/opt/bootstrap}"
: "${TOOLS_CACHE_DIR:=/opt/tools-cache}"

# ── 1. Reset env to a known state ────────────────────────────────────────────
unset LIBRARY_PATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH CPATH OBJC_INCLUDE_PATH
unset LDFLAGS CFLAGS CXXFLAGS CPPFLAGS

# Minimal PATH — Stage 2 first, then bootstrap, then system
export PATH="${STAGE2_PREFIX}/bin:${BOOTSTRAP_PREFIX}/bin:/usr/local/bin:/usr/bin:/bin"

# ── 2. Pin all compiler/linker tools to Stage 2 LLVM ────────────────────────
export CC="${STAGE2_PREFIX}/bin/clang"
export CXX="${STAGE2_PREFIX}/bin/clang++"
export CPP="${STAGE2_PREFIX}/bin/clang -E"
export AR="${STAGE2_PREFIX}/bin/llvm-ar"
export RANLIB="${STAGE2_PREFIX}/bin/llvm-ranlib"
export NM="${STAGE2_PREFIX}/bin/llvm-nm"
export STRIP="${STAGE2_PREFIX}/bin/llvm-strip"
export OBJCOPY="${STAGE2_PREFIX}/bin/llvm-objcopy"
export OBJDUMP="${STAGE2_PREFIX}/bin/llvm-objdump"
export LD="${STAGE2_PREFIX}/bin/ld.lld"

# ── 3. Compilation flags ─────────────────────────────────────────────────────
# C tools: position-independent, optimized
export CFLAGS="-O2 -fPIC -ffunction-sections -fdata-sections"
export CPPFLAGS=""

# C++ tools: libc++ (NEVER libstdc++) — this is the critical invariant
export CXXFLAGS="-O2 -fPIC -ffunction-sections -fdata-sections -stdlib=libc++"

# Linker flags:
#   -fuse-ld=lld         use Stage 2 lld (faster, deterministic)
#   -Wl,-rpath,...       relative rpath chain so binaries find libc++ etc.
#   -L${STAGE2_PREFIX}/lib  find libc++.so / libunwind.so at link time
#   --gc-sections        strip unused sections
#
# rpath chain (every tool gets all three; the linker tries them in order):
#   $ORIGIN/../lib              tools/<name>/bin/<exe>  → tools/<name>/lib/   (own deps)
#   $ORIGIN/../../lib           tools/<name>/bin/<exe>  → tools/lib/          (rare)
#   $ORIGIN/../../../lib        tools/<name>/bin/<exe>  → <prefix>/lib/       (Stage 2 libc++/libunwind)
#
# NOTE: $ORIGIN must be a literal in the ELF; single-quote so shell doesn't
# expand it. The dynamic linker resolves $ORIGIN at runtime (per-binary).
export LDFLAGS='-fuse-ld=lld'
LDFLAGS="${LDFLAGS} -Wl,-rpath,\$ORIGIN/../lib"
LDFLAGS="${LDFLAGS} -Wl,-rpath,\$ORIGIN/../../lib"
LDFLAGS="${LDFLAGS} -Wl,-rpath,\$ORIGIN/../../../lib"
LDFLAGS="${LDFLAGS} -Wl,--gc-sections"
LDFLAGS="-L${STAGE2_PREFIX}/lib ${LDFLAGS}"
export LDFLAGS

# C++ link flags must include -stdlib=libc++ so clang++ links libc++ (not libstdc++)
# Build scripts that drive linking via clang++ get this automatically via CXXFLAGS.
# Build scripts that invoke ld directly (rare) must add it themselves.

# ── 4. pkg-config: only see bootstrap-provided libs ─────────────────────────
export PKG_CONFIG="${BOOTSTRAP_PREFIX}/bin/pkg-config"
export PKG_CONFIG_PATH="${BOOTSTRAP_PREFIX}/lib/pkgconfig:${BOOTSTRAP_PREFIX}/lib64/pkgconfig:${BOOTSTRAP_PREFIX}/share/pkgconfig"
unset PKG_CONFIG_SYSROOT_DIR
unset PKG_CONFIG_LIBDIR

# ── 5. Runtime library path (build-time only, not embedded) ─────────────────
# Stage 2 clang itself needs to find libc++.so to run.
# Bootstrap GCC libs needed for any auxiliary tools (e.g., bison, m4) at build time.
export LD_LIBRARY_PATH="${STAGE2_PREFIX}/lib:${BOOTSTRAP_PREFIX}/lib64:${BOOTSTRAP_PREFIX}/lib"

# ── 6. Helper: print sandbox state ──────────────────────────────────────────
sandbox_log() {
    echo "[sandbox] STAGE2_PREFIX  = ${STAGE2_PREFIX}"
    echo "[sandbox] BOOTSTRAP_PREFIX = ${BOOTSTRAP_PREFIX}"
    echo "[sandbox] CC           = ${CC}"
    echo "[sandbox] CXX          = ${CXX}"
    echo "[sandbox] CFLAGS       = ${CFLAGS}"
    echo "[sandbox] CXXFLAGS     = ${CXXFLAGS}"
    echo "[sandbox] LDFLAGS      = ${LDFLAGS}"
    echo "[sandbox] PKG_CONFIG_PATH = ${PKG_CONFIG_PATH}"
    "${CC}" --version | head -1
}

# ── 7. Helper: clean and prepare a tool's install dir under tools-cache ─────
prepare_tool_dir() {
    local tool_name="$1"
    local tool_dir="${TOOLS_CACHE_DIR}/built/${tool_name}"
    rm -rf "${tool_dir}"
    mkdir -p "${tool_dir}"
    echo "${tool_dir}"
}

# ── 8. Helper: get current source dir for a tool ────────────────────────────
get_source_dir() {
    local tool_name="$1"
    local version="$2"
    echo "${TOOLS_CACHE_DIR}/work/${tool_name}-${version}"
}

# ── 9. Logging ──────────────────────────────────────────────────────────────
log() { echo "===> $(date '+%H:%M:%S') $*"; }
err() { echo "ERROR: $*" >&2; }
