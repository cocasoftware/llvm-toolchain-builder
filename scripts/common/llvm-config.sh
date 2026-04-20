#!/usr/bin/env bash
# =============================================================================
# LLVM CMake configuration generator.
#
# Produces an array of CMake arguments based on:
#   - VARIANT (main | p2996)
#   - STAGE (stage1 | stage2)
#   - PLATFORM (linux-x64 | linux-arm64)
#
# Usage:
#   source scripts/common/versions.sh
#   source scripts/common/llvm-config.sh
#   generate_cmake_args   # populates CMAKE_ARGS array
#
# Requires: versions.sh sourced, env vars set for prefixes/compilers.
# =============================================================================

: "${VARIANT:=main}"
: "${STAGE:=stage2}"
: "${PLATFORM:=linux-x64}"
: "${BOOTSTRAP_PREFIX:=/opt/bootstrap}"
: "${STAGE1_PREFIX:=/opt/stage1}"
: "${INSTALL_PREFIX:=/opt/coca-toolchain}"
: "${SOURCE_DIR:=/tmp/llvm-project}"
: "${BUILD_DIR:=/tmp/stage2-build}"

generate_cmake_args() {
    CMAKE_ARGS=()

    # Host triple for per-target runtime directory paths
    local LLVM_HOST_TRIPLE
    case "${PLATFORM}" in
        linux-x64)   LLVM_HOST_TRIPLE="x86_64-unknown-linux-gnu" ;;
        linux-arm64) LLVM_HOST_TRIPLE="aarch64-unknown-linux-gnu" ;;
        *)           LLVM_HOST_TRIPLE="x86_64-unknown-linux-gnu" ;;
    esac

    # ── Compiler selection ──────────────────────────────────────────────
    if [[ "${STAGE}" == "stage1" ]]; then
        CMAKE_ARGS+=(
            "-DCMAKE_C_COMPILER=${BOOTSTRAP_PREFIX}/bin/gcc"
            "-DCMAKE_CXX_COMPILER=${BOOTSTRAP_PREFIX}/bin/g++"
            "-DCMAKE_CXX_FLAGS=-w"
            "-DCMAKE_EXE_LINKER_FLAGS=-Wl,-rpath,${BOOTSTRAP_PREFIX}/lib64"
            "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-rpath,${BOOTSTRAP_PREFIX}/lib64"
        )
    else
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
            "-DCMAKE_EXE_LINKER_FLAGS=-stdlib=libc++ '-Wl,-rpath,\$ORIGIN/../lib' -Wl,-rpath,${STAGE1_PREFIX}/lib -Wl,-rpath,${STAGE1_PREFIX}/lib/${LLVM_HOST_TRIPLE} -Wl,-rpath,${BOOTSTRAP_PREFIX}/lib64 -Wl,-rpath,${BOOTSTRAP_PREFIX}/lib"
            "-DCMAKE_SHARED_LINKER_FLAGS=-stdlib=libc++ '-Wl,-rpath,\$ORIGIN/../lib' -Wl,-rpath,${STAGE1_PREFIX}/lib -Wl,-rpath,${STAGE1_PREFIX}/lib/${LLVM_HOST_TRIPLE} -Wl,-rpath,${BOOTSTRAP_PREFIX}/lib64 -Wl,-rpath,${BOOTSTRAP_PREFIX}/lib"
        )
    fi

    # ── Install prefix ──────────────────────────────────────────────────
    local prefix
    if [[ "${STAGE}" == "stage1" ]]; then
        prefix="${STAGE1_PREFIX}"
    else
        prefix="${INSTALL_PREFIX}"
    fi
    CMAKE_ARGS+=(
        "-DCMAKE_BUILD_TYPE=Release"
        "-DCMAKE_INSTALL_PREFIX=${prefix}"
    )

    # ── Projects and runtimes ───────────────────────────────────────────
    local projects runtimes targets

    if [[ "${STAGE}" == "stage1" ]]; then
        projects="clang;lld"
        runtimes="compiler-rt;libunwind;libcxxabi;libcxx"
        # Stage 1 only needs native target
        case "${PLATFORM}" in
            linux-x64)   targets="X86" ;;
            linux-arm64) targets="AArch64" ;;
            *)           targets="X86" ;;
        esac
    else
        # Stage 2: full build
        if [[ "${VARIANT}" == "main" ]]; then
            projects="${LLVM_PROJECTS_MAIN}"
            runtimes="${LLVM_RUNTIMES_MAIN}"
        else
            projects="${LLVM_PROJECTS_P2996}"
            runtimes="${LLVM_RUNTIMES_P2996}"
        fi
        targets="${LLVM_TARGETS_ALL}"

        # bolt is Linux-only (ELF binary optimizer)
        case "${PLATFORM}" in
            linux-*) projects="${projects};bolt" ;;
        esac
    fi

    CMAKE_ARGS+=(
        "-DLLVM_ENABLE_PROJECTS=${projects}"
        "-DLLVM_ENABLE_RUNTIMES=${runtimes}"
        "-DLLVM_TARGETS_TO_BUILD=${targets}"
    )

    # ── Common LLVM options ─────────────────────────────────────────────
    CMAKE_ARGS+=(
        "-DLLVM_ENABLE_ASSERTIONS=OFF"
        "-DLLVM_INCLUDE_TESTS=OFF"
        "-DLLVM_INCLUDE_BENCHMARKS=OFF"
        "-DLLVM_INCLUDE_EXAMPLES=OFF"
        "-DLLVM_INCLUDE_DOCS=OFF"
    )

    if [[ "${STAGE}" == "stage1" ]]; then
        CMAKE_ARGS+=(
            "-DLLVM_ENABLE_TERMINFO=OFF"
            "-DLLVM_ENABLE_ZLIB=OFF"
            "-DLLVM_ENABLE_ZSTD=OFF"
            "-DLLVM_ENABLE_LIBXML2=OFF"
        )
    else
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
    fi

    # ── Clang defaults ──────────────────────────────────────────────────
    CMAKE_ARGS+=(
        "-DCLANG_DEFAULT_RTLIB=compiler-rt"
        "-DCLANG_DEFAULT_UNWINDLIB=libunwind"
        "-DCLANG_DEFAULT_CXX_STDLIB=libc++"
        "-DCLANG_DEFAULT_LINKER=lld"
    )

    # ── compiler-rt options ─────────────────────────────────────────────
    if [[ "${STAGE}" == "stage1" ]]; then
        CMAKE_ARGS+=(
            "-DCOMPILER_RT_BUILD_SANITIZERS=OFF"
            "-DCOMPILER_RT_BUILD_XRAY=OFF"
            "-DCOMPILER_RT_BUILD_LIBFUZZER=OFF"
            "-DCOMPILER_RT_BUILD_PROFILE=OFF"
            "-DCOMPILER_RT_BUILD_MEMPROF=OFF"
            "-DCOMPILER_RT_BUILD_ORC=OFF"
        )
    else
        CMAKE_ARGS+=(
            "-DCOMPILER_RT_BUILD_SANITIZERS=ON"
            "-DCOMPILER_RT_BUILD_XRAY=ON"
            "-DCOMPILER_RT_BUILD_LIBFUZZER=ON"
            "-DCOMPILER_RT_BUILD_PROFILE=ON"
            "-DCOMPILER_RT_BUILD_MEMPROF=ON"
            "-DCOMPILER_RT_BUILD_ORC=ON"
        )
    fi

    # ── LLDB + Python (stage2 only) ─────────────────────────────────────
    if [[ "${STAGE}" == "stage2" ]]; then
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

        # MLIR Python bindings
        CMAKE_ARGS+=(
            "-DMLIR_ENABLE_BINDINGS_PYTHON=ON"
        )

        # libc++ modules
        CMAKE_ARGS+=(
            "-DLIBCXX_INSTALL_MODULES=ON"
        )
    fi
}
