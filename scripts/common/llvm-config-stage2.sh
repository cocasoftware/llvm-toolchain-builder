#!/usr/bin/env bash
# =============================================================================
# LLVM CMake configuration — Stage 2 (full toolchain using Stage 1 clang).
#
# Changes to this file do NOT invalidate Stage 1 cache.
# =============================================================================

SCRIPT_DIR_CONFIG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR_CONFIG}/llvm-config-common.sh"

generate_cmake_args() {
    CMAKE_ARGS=()

    # ── Host triple (for per-target lib path fallbacks in rpath) ────────
    local LLVM_HOST_TRIPLE
    case "${PLATFORM}" in
        linux-x64)   LLVM_HOST_TRIPLE="x86_64-unknown-linux-gnu" ;;
        linux-arm64) LLVM_HOST_TRIPLE="aarch64-unknown-linux-gnu" ;;
        *)           LLVM_HOST_TRIPLE="x86_64-unknown-linux-gnu" ;;
    esac

    # ── Compiler: Stage 1 clang ─────────────────────────────────────────
    CMAKE_ARGS+=(
        "-DCMAKE_C_COMPILER=${STAGE1_PREFIX}/bin/clang"
        "-DCMAKE_CXX_COMPILER=${STAGE1_PREFIX}/bin/clang++"
        "-DCMAKE_ASM_COMPILER=${STAGE1_PREFIX}/bin/clang"
        "-DCMAKE_AR=${STAGE1_PREFIX}/bin/llvm-ar"
        "-DCMAKE_RANLIB=${STAGE1_PREFIX}/bin/llvm-ranlib"
        "-DCMAKE_NM=${STAGE1_PREFIX}/bin/llvm-nm"
        "-DCMAKE_STRIP=${STAGE1_PREFIX}/bin/llvm-strip"
        "-DCMAKE_OBJCOPY=${STAGE1_PREFIX}/bin/llvm-objcopy"
        "-DCMAKE_OBJDUMP=${STAGE1_PREFIX}/bin/llvm-objdump"
        "-DCMAKE_C_FLAGS=-w"
        "-DCMAKE_CXX_FLAGS=-stdlib=libc++ -w"
        "-DCMAKE_EXE_LINKER_FLAGS=-L${STAGE1_PREFIX}/lib -L${BOOTSTRAP_PREFIX}/lib64 -L${BOOTSTRAP_PREFIX}/lib '-Wl,-rpath,\$ORIGIN/../lib' -Wl,-rpath,${STAGE1_PREFIX}/lib -Wl,-rpath,${BOOTSTRAP_PREFIX}/lib64 -Wl,-rpath,${BOOTSTRAP_PREFIX}/lib"
        "-DCMAKE_SHARED_LINKER_FLAGS=-L${STAGE1_PREFIX}/lib -L${BOOTSTRAP_PREFIX}/lib64 -L${BOOTSTRAP_PREFIX}/lib '-Wl,-rpath,\$ORIGIN/../lib' -Wl,-rpath,${STAGE1_PREFIX}/lib -Wl,-rpath,${BOOTSTRAP_PREFIX}/lib64 -Wl,-rpath,${BOOTSTRAP_PREFIX}/lib"
    )

    # ── Projects and runtimes: full build ───────────────────────────────
    local projects runtimes
    if [[ "${VARIANT}" == "main" ]]; then
        projects="${LLVM_PROJECTS_MAIN}"
        runtimes="${LLVM_RUNTIMES_MAIN}"
    else
        projects="${LLVM_PROJECTS_P2996}"
        runtimes="${LLVM_RUNTIMES_P2996}"
    fi

    # bolt is Linux-only (ELF binary optimizer)
    case "${PLATFORM}" in
        linux-*) projects="${projects};bolt" ;;
    esac

    CMAKE_ARGS+=(
        "-DLLVM_ENABLE_PROJECTS=${projects}"
        "-DLLVM_ENABLE_RUNTIMES=${runtimes}"
        "-DLLVM_TARGETS_TO_BUILD=${LLVM_TARGETS_ALL}"
    )

    # ── Common options ──────────────────────────────────────────────────
    _append_common_cmake_args

    # ── Stage 2 specific: dylib, optional deps ──────────────────────────
    CMAKE_ARGS+=(
        "-DLLVM_BUILD_LLVM_DYLIB=ON"
        "-DLLVM_LINK_LLVM_DYLIB=ON"
        "-DLLVM_ENABLE_TERMINFO=ON"
        "-DLLVM_ENABLE_ZLIB=ON"
        "-DLLVM_ENABLE_ZSTD=ON"
        "-DLLVM_ENABLE_LLD=ON"
        "-DLLVM_INSTALL_UTILS=ON"
        "-DLLVM_ENABLE_BINDINGS=ON"
        "-DLLVM_INSTALL_TOOLCHAIN_ONLY=OFF"
        "-DLLVM_ENABLE_LIBXML2=ON"
        "-DLLVM_ENABLE_LIBEDIT=ON"
    )

    # ── compiler-rt: full ───────────────────────────────────────────────
    CMAKE_ARGS+=(
        "-DCOMPILER_RT_BUILD_SANITIZERS=ON"
        "-DCOMPILER_RT_BUILD_XRAY=ON"
        "-DCOMPILER_RT_BUILD_LIBFUZZER=ON"
        "-DCOMPILER_RT_BUILD_PROFILE=ON"
        "-DCOMPILER_RT_BUILD_MEMPROF=ON"
        "-DCOMPILER_RT_BUILD_ORC=ON"
        "-DCOMPILER_RT_USE_LLVM_UNWINDER=ON"
        "-DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON"
    )

    # ── LLDB + Python ───────────────────────────────────────────────────
    local python_exe="${BOOTSTRAP_PREFIX}/bin/python3"
    local python_version
    python_version=$("${python_exe}" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    local python_include
    python_include=$("${python_exe}" -c 'import sysconfig; print(sysconfig.get_path("include"))')
    local python_lib
    python_lib=$("${python_exe}" -c 'import sysconfig; print(sysconfig.get_config_var("LIBDIR"))')

    CMAKE_ARGS+=(
        "-DLLDB_ENABLE_PYTHON=ON"
        "-DLLDB_ENABLE_LIBEDIT=ON"
        "-DLLDB_ENABLE_CURSES=ON"
        "-DLLDB_ENABLE_LZMA=ON"
        "-DLLDB_ENABLE_LIBXML2=ON"
        "-DPython3_EXECUTABLE=${python_exe}"
        "-DPython3_INCLUDE_DIR=${python_include}"
        "-DPython3_LIBRARY=${python_lib}/libpython${python_version}.so"
        "-DSWIG_EXECUTABLE=${BOOTSTRAP_PREFIX}/bin/swig"
    )

    # ── MLIR Python bindings ────────────────────────────────────────────
    CMAKE_ARGS+=(
        "-DMLIR_ENABLE_BINDINGS_PYTHON=ON"
    )

    # ── libc++ modules ──────────────────────────────────────────────────
    CMAKE_ARGS+=(
        "-DLIBCXX_INSTALL_MODULES=ON"
    )
}
