#!/usr/bin/env bash
# =============================================================================
# Verify library — shared test framework functions.
# Source this file from any verify script. Provides counters, check helpers,
# cmake_build, and install_test_deps.
#
# Required env: TOOLCHAIN_DIR
# =============================================================================

: "${TOOLCHAIN_DIR:=/opt/coca-toolchain}"

PASS=0
FAIL=0
SKIP=0

CC="${TOOLCHAIN_DIR}/bin/clang"
CXX="${TOOLCHAIN_DIR}/bin/clang++"
CXX_FLAGS=(-stdlib=libc++ -Wl,-rpath,"${TOOLCHAIN_DIR}/lib")

log() { echo "===> $*"; }

check() {
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "  PASS: ${label}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${label}"
        FAIL=$((FAIL + 1))
    fi
}

check_output() {
    local label="$1"
    shift
    local output
    if output=$("$@" 2>&1); then
        echo "  PASS: ${label} → $(echo "${output}" | head -1)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${label} → $(echo "${output}" | head -3)"
        FAIL=$((FAIL + 1))
    fi
}

skip() {
    echo "  SKIP: $1"
    SKIP=$((SKIP + 1))
}

fail_msg() {
    local label="$1" detail="$2"
    echo "  FAIL: ${label}"
    echo "${detail}" | head -15 | sed 's/^/    /'
    FAIL=$((FAIL + 1))
}

try_compile_run() {
    local label="$1" compiler="$2" src="$3" out="$4"
    shift 4
    local compile_err
    if compile_err=$("${compiler}" "$@" -o "${out}" "${src}" 2>&1); then
        check "compile ${label}" true
        check "run ${label}" "${out}"
    else
        fail_msg "compile ${label}" "${compile_err}"
    fi
}

# Build a CMake project, returns 0 on success
cmake_build() {
    local label="$1" src_dir="$2" build_dir="$3" build_type="$4"
    shift 4
    local extra_args=("$@")

    echo "  Building ${label} (${build_type})..."
    local cmake_out
    if cmake_out=$(timeout 120 cmake \
        -G "Unix Makefiles" \
        -S "${src_dir}" -B "${build_dir}" \
        -DCMAKE_BUILD_TYPE="${build_type}" \
        -DCMAKE_C_COMPILER="${CC}" \
        -DCMAKE_CXX_COMPILER="${CXX}" \
        -DCMAKE_CXX_FLAGS="-stdlib=libc++" \
        -DCMAKE_EXE_LINKER_FLAGS="-Wl,-rpath,${TOOLCHAIN_DIR}/lib -L${TOOLCHAIN_DIR}/lib" \
        -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-rpath,${TOOLCHAIN_DIR}/lib -L${TOOLCHAIN_DIR}/lib" \
        ${extra_args[@]+"${extra_args[@]}"} 2>&1); then
        :
    else
        fail_msg "cmake configure ${label}" "${cmake_out}"
        return 1
    fi

    local nproc_val
    nproc_val=$(nproc 2>/dev/null || echo 2)
    if cmake_out=$(timeout 180 cmake --build "${build_dir}" -j"${nproc_val}" 2>&1); then
        echo "  PASS: build ${label} (${build_type})"
        PASS=$((PASS + 1))
        return 0
    else
        fail_msg "build ${label} (${build_type})" "${cmake_out}"
        return 1
    fi
}

# Install minimal build dependencies (apt-based distros)
install_test_deps() {
    if command -v apt-get &>/dev/null; then
        apt-get update -qq 2>/dev/null || true
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
            file libc6-dev ca-certificates git make wget 2>/dev/null || true
    fi

    # Ensure a modern cmake (>= 3.14) is available.
    local need_cmake=false
    if ! command -v cmake &>/dev/null; then
        need_cmake=true
    else
        local ver
        ver=$(cmake --version 2>/dev/null | head -1 | sed 's/[^0-9]*\([0-9]*\.[0-9]*\).*/\1/' || echo "0.0")
        local maj=${ver%%.*} min=${ver#*.}
        if [[ "${maj}" -lt 3 ]] || { [[ "${maj}" -eq 3 ]] && [[ "${min}" -lt 14 ]]; }; then
            need_cmake=true
        fi
    fi

    if ${need_cmake}; then
        log "System cmake too old or missing — downloading cmake 3.31.7"
        local arch
        arch=$(uname -m)
        local cmake_url="https://github.com/Kitware/CMake/releases/download/v3.31.7/cmake-3.31.7-linux-${arch}.tar.gz"
        local cmake_prefix="/tmp/cmake-dist"
        mkdir -p "${cmake_prefix}"
        local dl_ok=false
        if command -v wget &>/dev/null; then
            wget -q -O /tmp/cmake.tar.gz "${cmake_url}" 2>/dev/null && dl_ok=true
        elif command -v curl &>/dev/null; then
            curl -fsSL -o /tmp/cmake.tar.gz "${cmake_url}" 2>/dev/null && dl_ok=true
        fi
        if ${dl_ok}; then
            tar -xf /tmp/cmake.tar.gz -C "${cmake_prefix}" --strip-components=1 2>/dev/null || true
            export PATH="${cmake_prefix}/bin:${PATH}"
            rm -f /tmp/cmake.tar.gz
            log "cmake $(cmake --version 2>/dev/null | head -1) installed to ${cmake_prefix}/bin"
        else
            log "WARNING: failed to download cmake binary"
        fi
    fi
}

verify_summary() {
    log "============================="
    log "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
    log "============================="
    [[ ${FAIL} -eq 0 ]]
}
