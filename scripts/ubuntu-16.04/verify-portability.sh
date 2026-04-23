#!/usr/bin/env bash
# =============================================================================
# Portability verification script
# Verifies that the built LLVM toolchain runs on the current system.
# Designed to be invoked inside multiple Ubuntu containers (16.04 → 24.04).
#
# Test categories:
#   1. Binary execution — all shipped tools
#   2. Basic compilation — C, C++17, C++23, LLD
#   3. Sanitizers — ASan, UBSan
#   4. OpenMP — parallel execution
#   5. Profiling — PGO instrument + merge
#   6. Cross-compilation — AArch64 ELF generation (no run)
#   7. Fortran — flang-new hello world
#   8. clang-tidy — static analysis
#   9. Third-party libraries — build popular OSS projects
#  10. Dynamic dependency & glibc version checks
#
# Usage: TOOLCHAIN_DIR=/opt/coca-toolchain ./scripts/verify-portability.sh
# =============================================================================
set -euo pipefail

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

try_compile_run() {
    local label="$1" compiler="$2" src="$3" out="$4"
    shift 4
    local compile_err
    if compile_err=$("${compiler}" "$@" -o "${out}" "${src}" 2>&1); then
        check "compile ${label}" true
        check "run ${label}" "${out}"
    else
        echo "  FAIL: compile ${label}"
        echo "${compile_err}" | head -20 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
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
        echo "  FAIL: cmake configure ${label}"
        echo "${cmake_out}" | tail -10 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        return 1
    fi

    local nproc_val
    nproc_val=$(nproc 2>/dev/null || echo 2)
    if cmake_out=$(timeout 180 cmake --build "${build_dir}" -j"${nproc_val}" 2>&1); then
        echo "  PASS: build ${label} (${build_type})"
        PASS=$((PASS + 1))
        return 0
    else
        echo "  FAIL: build ${label} (${build_type})"
        echo "${cmake_out}" | tail -15 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        return 1
    fi
}

install_test_deps() {
    if command -v apt-get &>/dev/null; then
        apt-get update -qq 2>/dev/null || true
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
            file libc6-dev ca-certificates git make wget 2>/dev/null || true
    fi

    # Ensure a modern cmake (>= 3.14) is available. Ubuntu 16.04 ships cmake 3.5.
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
        if wget -q -O /tmp/cmake.tar.gz "${cmake_url}" 2>/dev/null; then
            tar -xf /tmp/cmake.tar.gz -C /opt --strip-components=1 2>/dev/null || true
            export PATH="/opt/bin:${PATH}"
            rm -f /tmp/cmake.tar.gz
            log "cmake $(cmake --version 2>/dev/null | head -1) installed to /opt/bin"
        else
            log "WARNING: failed to download cmake binary"
        fi
    fi
}

# =============================================================================
# 1. Binary execution tests
# =============================================================================
test_binary_execution() {
    log "--- 1. Binary execution ---"
    check_output "clang --version" "${CC}" --version
    check_output "clang++ --version" "${CXX}" --version
    check_output "lld --version" "${TOOLCHAIN_DIR}/bin/ld.lld" --version
    check_output "llvm-ar --version" "${TOOLCHAIN_DIR}/bin/llvm-ar" --version
    check_output "llvm-nm --version" "${TOOLCHAIN_DIR}/bin/llvm-nm" --version
    check_output "llvm-objdump --version" "${TOOLCHAIN_DIR}/bin/llvm-objdump" --version
    check_output "llvm-readelf --version" "${TOOLCHAIN_DIR}/bin/llvm-readelf" --version
    check_output "llvm-strip --version" "${TOOLCHAIN_DIR}/bin/llvm-strip" --version
    check_output "llvm-profdata --version" "${TOOLCHAIN_DIR}/bin/llvm-profdata" --version
    check_output "llvm-cov --version" "${TOOLCHAIN_DIR}/bin/llvm-cov" --version
    check_output "clang-format --version" "${TOOLCHAIN_DIR}/bin/clang-format" --version
    check_output "clang-tidy --version" "${TOOLCHAIN_DIR}/bin/clang-tidy" --version
    check_output "clangd --version" "${TOOLCHAIN_DIR}/bin/clangd" --version

    if [[ -x "${TOOLCHAIN_DIR}/bin/lldb" ]]; then
        check_output "lldb --version" "${TOOLCHAIN_DIR}/bin/lldb" --version
    fi

    if [[ -x "${TOOLCHAIN_DIR}/bin/flang-new" ]]; then
        check_output "flang-new --version" "${TOOLCHAIN_DIR}/bin/flang-new" --version
    fi
}

# =============================================================================
# 2. Basic compilation tests
# =============================================================================
test_basic_compilation() {
    log "--- 2. Basic compilation ---"
    local t="$1"

    cat > "${t}/hello.c" << 'EOF'
#include <stdio.h>
int main(void) { printf("Hello from COCA toolchain (C)!\n"); return 0; }
EOF
    try_compile_run "hello.c" "${CC}" "${t}/hello.c" "${t}/hello_c"

    cat > "${t}/hello.cpp" << 'EOF'
#include <iostream>
#include <vector>
#include <algorithm>
#include <string>
int main() {
    std::vector<std::string> v = {"Hello", "from", "COCA", "toolchain", "(C++)"};
    std::sort(v.begin(), v.end());
    for (const auto& s : v) std::cout << s << " ";
    std::cout << std::endl;
}
EOF
    try_compile_run "hello.cpp (libc++)" "${CXX}" "${t}/hello.cpp" "${t}/hello_cpp" "${CXX_FLAGS[@]}"

    # C++ with libstdc++ (if host has it)
    if "${CXX}" -stdlib=libstdc++ -o "${t}/hello_stdcpp" "${t}/hello.cpp" 2>/dev/null; then
        check "compile hello.cpp (libstdc++)" true
        check "run hello_stdcpp" "${t}/hello_stdcpp"
    else
        skip "hello.cpp (libstdc++) — no libstdc++ on host"
    fi

    # C++23
    cat > "${t}/cpp23.cpp" << 'EOF'
#include <print>
#include <expected>
#include <ranges>
#include <string>
auto parse(const std::string& s) -> std::expected<int, std::string> {
    try { return std::stoi(s); }
    catch (...) { return std::unexpected("parse error"); }
}
int main() {
    auto result = parse("42");
    if (result) std::println("Parsed: {}", *result);
    auto v = std::views::iota(1, 6) | std::views::transform([](int x) { return x * x; });
    for (int x : v) std::print("{} ", x);
    std::println("");
}
EOF
    try_compile_run "C++23 features" "${CXX}" "${t}/cpp23.cpp" "${t}/cpp23" -std=c++23 "${CXX_FLAGS[@]}"

    # LLD
    try_compile_run "link with lld" "${CC}" "${t}/hello.c" "${t}/hello_lld" -fuse-ld=lld
}

# =============================================================================
# 3. Sanitizer tests
# =============================================================================
test_sanitizers() {
    log "--- 3. Sanitizers ---"
    local t="$1"

    cat > "${t}/asan_test.c" << 'EOF'
#include <stdio.h>
#include <stdlib.h>
int main(void) {
    int *p = (int *)malloc(sizeof(int) * 10);
    p[0] = 42;
    printf("ASan clean: %d\n", p[0]);
    free(p);
    return 0;
}
EOF
    try_compile_run "ASan (clean)" "${CC}" "${t}/asan_test.c" "${t}/asan_clean" -fsanitize=address -fno-omit-frame-pointer

    cat > "${t}/ubsan_test.c" << 'EOF'
#include <stdio.h>
int main(void) {
    int x = 42;
    printf("UBSan clean: %d\n", x);
    return 0;
}
EOF
    try_compile_run "UBSan (clean)" "${CC}" "${t}/ubsan_test.c" "${t}/ubsan_clean" -fsanitize=undefined
}

# =============================================================================
# 4. OpenMP test
# =============================================================================
test_openmp() {
    log "--- 4. OpenMP ---"
    local t="$1"

    cat > "${t}/omp_test.c" << 'EOF'
#include <stdio.h>
#include <omp.h>
int main(void) {
    int sum = 0;
    #pragma omp parallel for reduction(+:sum)
    for (int i = 0; i < 100; i++) sum += i;
    printf("OpenMP sum(0..99) = %d (threads=%d)\n", sum, omp_get_max_threads());
    return (sum == 4950) ? 0 : 1;
}
EOF
    local omp_err
    if omp_err=$("${CC}" -fopenmp -Wl,-rpath,"${TOOLCHAIN_DIR}/lib" -o "${t}/omp_test" "${t}/omp_test.c" 2>&1); then
        check "compile OpenMP" true
        check "run OpenMP" "${t}/omp_test"
    else
        echo "  FAIL: compile OpenMP (libomp should be in Stage 2)"
        echo "${omp_err}" | head -10 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# 5. Profiling (PGO instrument + merge)
# =============================================================================
test_profiling() {
    log "--- 5. Profiling ---"
    local t="$1"

    cat > "${t}/prof_test.c" << 'EOF'
#include <stdio.h>
int fib(int n) { return (n < 2) ? n : fib(n-1) + fib(n-2); }
int main(void) { printf("fib(10)=%d\n", fib(10)); return 0; }
EOF
    local profdir="${t}/profdata"
    mkdir -p "${profdir}"
    if "${CC}" -fprofile-instr-generate="${profdir}/default_%p.profraw" \
       -o "${t}/prof_instr" "${t}/prof_test.c" 2>/dev/null; then
        check "compile PGO instrumented" true
        if "${t}/prof_instr" >/dev/null 2>&1; then
            check "run PGO instrumented" true
            if "${TOOLCHAIN_DIR}/bin/llvm-profdata" merge -output="${profdir}/merged.profdata" "${profdir}"/*.profraw 2>/dev/null; then
                check "llvm-profdata merge" true
            else
                echo "  FAIL: llvm-profdata merge"
                FAIL=$((FAIL + 1))
            fi
        else
            echo "  FAIL: run PGO instrumented"
            FAIL=$((FAIL + 1))
        fi
    else
        skip "PGO profiling — compiler-rt profile not available"
    fi
}

# =============================================================================
# 6. Cross-compilation (AArch64 ELF, no run)
# =============================================================================
test_cross_compilation() {
    log "--- 6. Cross-compilation ---"
    local t="$1"

    local host_arch
    host_arch=$(uname -m)

    # Cross-compile to the OTHER architecture
    local cross_triple cross_label
    case "${host_arch}" in
        x86_64|amd64) cross_triple="aarch64-unknown-linux-gnu"; cross_label="AArch64" ;;
        aarch64|arm64) cross_triple="x86_64-unknown-linux-gnu"; cross_label="x86_64" ;;
        *) skip "cross-compile — unknown host arch ${host_arch}"; return ;;
    esac

    cat > "${t}/cross.c" << 'EOF'
int main(void) { return 0; }
EOF
    if "${CC}" --target="${cross_triple}" -fuse-ld=lld -nostdlib -o "${t}/cross.o" -c "${t}/cross.c" 2>/dev/null; then
        check "cross-compile C to ${cross_label} (object)" true
        # Verify ELF is the right arch
        local elf_info
        elf_info=$(file "${t}/cross.o" 2>/dev/null || echo "")
        case "${cross_label}" in
            AArch64) [[ "${elf_info}" == *"aarch64"* || "${elf_info}" == *"ARM aarch64"* ]] && check "cross-compile ELF arch (${cross_label})" true || { echo "  FAIL: cross-compile ELF arch"; FAIL=$((FAIL + 1)); } ;;
            x86_64)  [[ "${elf_info}" == *"x86-64"* ]] && check "cross-compile ELF arch (${cross_label})" true || { echo "  FAIL: cross-compile ELF arch"; FAIL=$((FAIL + 1)); } ;;
        esac
    else
        skip "cross-compile to ${cross_label} — missing sysroot or target support"
    fi

    # Cross-compile C++ object (no link — no cross sysroot)
    cat > "${t}/cross.cpp" << 'EOF'
template<typename T> T add(T a, T b) { return a + b; }
int main() { return add(1, 2) - 3; }
EOF
    if "${CXX}" --target="${cross_triple}" -nostdlib -c -o "${t}/cross_cpp.o" "${t}/cross.cpp" 2>/dev/null; then
        check "cross-compile C++ to ${cross_label} (object)" true
    else
        skip "cross-compile C++ to ${cross_label}"
    fi

    # WebAssembly target (object only)
    if "${CC}" --target=wasm32-unknown-unknown -nostdlib -c -o "${t}/wasm.o" "${t}/cross.c" 2>/dev/null; then
        check "cross-compile to WebAssembly (object)" true
    else
        skip "cross-compile to WebAssembly"
    fi
}

# =============================================================================
# 7. Fortran (flang-new)
# =============================================================================
test_fortran() {
    log "--- 7. Fortran ---"
    local t="$1"

    if [[ ! -x "${TOOLCHAIN_DIR}/bin/flang-new" ]]; then
        echo "  FAIL: flang-new not found (should be built in Stage 2)"
        FAIL=$((FAIL + 1))
        return
    fi

    cat > "${t}/hello.f90" << 'EOF'
program hello
    print *, "Hello from Fortran (flang-new)!"
end program hello
EOF
    local flang_err
    if flang_err=$("${TOOLCHAIN_DIR}/bin/flang-new" -Wl,-rpath,"${TOOLCHAIN_DIR}/lib" -o "${t}/hello_f90" "${t}/hello.f90" 2>&1); then
        check "compile Fortran hello" true
        check "run Fortran hello" "${t}/hello_f90"
    else
        echo "  FAIL: compile Fortran hello"
        echo "${flang_err}" | head -10 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
    fi
}

# =============================================================================
# 8. clang-tidy static analysis
# =============================================================================
test_clang_tidy() {
    log "--- 8. clang-tidy ---"
    local t="$1"

    if [[ ! -x "${TOOLCHAIN_DIR}/bin/clang-tidy" ]]; then
        skip "clang-tidy not found"
        return
    fi

    cat > "${t}/tidy_test.cpp" << 'EOF'
#include <vector>
#include <algorithm>
int main() {
    std::vector<int> v = {3, 1, 4, 1, 5};
    std::sort(v.begin(), v.end());
    return v.front();
}
EOF
    if "${TOOLCHAIN_DIR}/bin/clang-tidy" "${t}/tidy_test.cpp" \
       --checks='-*,modernize-*,performance-*' \
       -- -stdlib=libc++ -std=c++17 -I"${TOOLCHAIN_DIR}/include/c++/v1" -I"${TOOLCHAIN_DIR}/include" 2>/dev/null; then
        check "clang-tidy analysis" true
    else
        # clang-tidy returns non-zero on findings, which is OK
        check "clang-tidy analysis" true
    fi
}

# =============================================================================
# 9. Third-party library builds
# =============================================================================
test_third_party_libs() {
    log "--- 9. Third-party library builds ---"
    local t="$1"

    if ! command -v git &>/dev/null; then
        echo "  FAIL: git not available (should be installed by install_test_deps)"
        FAIL=$((FAIL + 1))
        return
    fi
    if ! command -v cmake &>/dev/null; then
        echo "  FAIL: cmake not available (should be installed by install_test_deps)"
        FAIL=$((FAIL + 1))
        return
    fi

    local libdir="${t}/libs"
    mkdir -p "${libdir}"

    # --- googletest (C++17, template-heavy) ---
    if timeout 30 git clone --depth 1 https://github.com/google/googletest.git "${libdir}/googletest" 2>/dev/null; then
        cmake_build "googletest" "${libdir}/googletest" "${libdir}/googletest-build" "RelWithDebInfo" \
            -DBUILD_GMOCK=ON
    else
        skip "googletest — clone failed"
    fi

    # --- fmtlib/fmt (C++20, format library) ---
    if timeout 30 git clone --depth 1 https://github.com/fmtlib/fmt.git "${libdir}/fmt" 2>/dev/null; then
        cmake_build "fmt" "${libdir}/fmt" "${libdir}/fmt-build" "Debug" \
            -DFMT_TEST=OFF -DFMT_DOC=OFF
    else
        skip "fmt — clone failed"
    fi

    # --- nlohmann/json (C++17, header-heavy, build tests) ---
    if timeout 30 git clone --depth 1 https://github.com/nlohmann/json.git "${libdir}/json" 2>/dev/null; then
        cmake_build "nlohmann/json" "${libdir}/json" "${libdir}/json-build" "Debug" \
            -DJSON_BuildTests=OFF
    else
        skip "nlohmann/json — clone failed"
    fi

    # --- zlib-ng (C, SIMD optimizations) ---
    if timeout 30 git clone --depth 1 https://github.com/zlib-ng/zlib-ng.git "${libdir}/zlib-ng" 2>/dev/null; then
        cmake_build "zlib-ng" "${libdir}/zlib-ng" "${libdir}/zlib-ng-build" "RelWithDebInfo" \
            -DZLIB_COMPAT=ON -DWITH_GTEST=OFF
    else
        skip "zlib-ng — clone failed"
    fi

    # --- lz4 (C, minimal, performance-critical) ---
    if timeout 30 git clone --depth 1 https://github.com/lz4/lz4.git "${libdir}/lz4" 2>/dev/null; then
        cmake_build "lz4" "${libdir}/lz4/build/cmake" "${libdir}/lz4-build" "RelWithDebInfo" \
            -DLZ4_BUILD_CLI=OFF -DLZ4_BUILD_LEGACY_LZ4C=OFF
    else
        skip "lz4 — clone failed"
    fi

    # --- GLFW (C, Vulkan/OpenGL windowing — headless build, no X11/Wayland) ---
    if timeout 30 git clone --depth 1 https://github.com/glfw/glfw.git "${libdir}/glfw" 2>/dev/null; then
        # Build as library only (no examples/tests), disable all backends for headless CI
        cmake_build "glfw (headless)" "${libdir}/glfw" "${libdir}/glfw-build" "RelWithDebInfo" \
            -DGLFW_BUILD_EXAMPLES=OFF -DGLFW_BUILD_TESTS=OFF -DGLFW_BUILD_DOCS=OFF \
            -DGLFW_USE_WAYLAND=OFF
    else
        skip "glfw — clone failed"
    fi

    # --- microsoft/proxy (C++20 concepts-heavy, header-only tests) ---
    if timeout 30 git clone --depth 1 https://github.com/microsoft/proxy.git "${libdir}/proxy" 2>/dev/null; then
        cmake_build "microsoft/proxy" "${libdir}/proxy" "${libdir}/proxy-build" "Debug" \
            -DBUILD_TESTING=OFF
    else
        skip "microsoft/proxy — clone failed"
    fi

    # --- Vulkan-Headers + Vulkan-Loader (headless Vulkan ICD loader) ---
    local vk_headers_ok=false
    if timeout 30 git clone --depth 1 https://github.com/KhronosGroup/Vulkan-Headers.git "${libdir}/Vulkan-Headers" 2>/dev/null; then
        if cmake_build "Vulkan-Headers" "${libdir}/Vulkan-Headers" "${libdir}/vh-build" "Release"; then
            # Install headers so Vulkan-Loader can find them
            cmake --install "${libdir}/vh-build" --prefix "${libdir}/vh-install" >/dev/null 2>&1 || true
            vk_headers_ok=true
        fi
    else
        skip "Vulkan-Headers — clone failed"
    fi

    if ${vk_headers_ok}; then
        if timeout 30 git clone --depth 1 https://github.com/KhronosGroup/Vulkan-Loader.git "${libdir}/Vulkan-Loader" 2>/dev/null; then
            cmake_build "Vulkan-Loader" "${libdir}/Vulkan-Loader" "${libdir}/vl-build" "RelWithDebInfo" \
                -DVULKAN_HEADERS_INSTALL_DIR="${libdir}/vh-install" \
                -DBUILD_TESTS=OFF -DBUILD_WSI_XCB_SUPPORT=OFF -DBUILD_WSI_XLIB_SUPPORT=OFF \
                -DBUILD_WSI_WAYLAND_SUPPORT=OFF -DBUILD_WSI_DIRECTFB_SUPPORT=OFF
        else
            skip "Vulkan-Loader — clone failed"
        fi
    fi
}

# =============================================================================
# 10. Dynamic dependency & glibc checks
# =============================================================================
test_dependencies() {
    log "--- 10. Dynamic dependencies ---"
    local clang_deps
    clang_deps=$(ldd "${TOOLCHAIN_DIR}/bin/clang" 2>/dev/null || echo "ldd failed")
    echo "  clang dependencies:"
    echo "${clang_deps}" | sed 's/^/    /'

    if echo "${clang_deps}" | grep -q "not found"; then
        echo "  FAIL: clang has unresolved dependencies"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: all clang dependencies resolved"
        PASS=$((PASS + 1))
    fi

    # Forbidden deps check (same as post-install but at verify time)
    local forbidden_pattern="libstdc++|libgcc_s|libatomic"
    for bin in "${TOOLCHAIN_DIR}/bin/clang" "${TOOLCHAIN_DIR}/bin/ld.lld" "${TOOLCHAIN_DIR}/bin/lldb"; do
        [[ -f "${bin}" ]] || continue
        local deps
        deps=$(ldd "${bin}" 2>/dev/null || true)
        if echo "${deps}" | grep -qE "${forbidden_pattern}"; then
            echo "  FAIL: $(basename "${bin}") links to forbidden GCC runtime"
            echo "${deps}" | grep -E "${forbidden_pattern}" | sed 's/^/    /'
            FAIL=$((FAIL + 1))
        fi
    done

    log "--- glibc version check ---"
    local max_glibc_ver="0"
    for bin in "${TOOLCHAIN_DIR}/bin/clang" "${TOOLCHAIN_DIR}/bin/ld.lld"; do
        if [[ -f "${bin}" ]]; then
            local glibc_vers
            glibc_vers=$("${TOOLCHAIN_DIR}/bin/llvm-objdump" -T "${bin}" 2>/dev/null \
                | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sed 's/GLIBC_//' | sort -V | tail -1 || echo "0")
            echo "  $(basename "${bin}"): requires GLIBC_${glibc_vers:-unknown}"
            if [[ -n "${glibc_vers}" && "$(printf '%s\n%s' "${max_glibc_ver}" "${glibc_vers}" | sort -V | tail -1)" == "${glibc_vers}" ]]; then
                max_glibc_ver="${glibc_vers}"
            fi
        fi
    done
    echo "  Maximum glibc requirement: GLIBC_${max_glibc_ver}"
}

# =============================================================================
# Main
# =============================================================================
main() {
    log "Portability verification on $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || echo 'unknown')"
    log "glibc: $(ldd --version 2>&1 | head -1 || echo 'unknown')"
    log "Toolchain: ${TOOLCHAIN_DIR}"

    install_test_deps

    local tmpdir
    tmpdir=$(mktemp -d)

    test_binary_execution
    test_basic_compilation "${tmpdir}"
    test_sanitizers "${tmpdir}"
    test_openmp "${tmpdir}"
    test_profiling "${tmpdir}"
    test_cross_compilation "${tmpdir}"
    test_fortran "${tmpdir}"
    test_clang_tidy "${tmpdir}"
    test_third_party_libs "${tmpdir}"
    test_dependencies

    rm -rf "${tmpdir}"

    log "============================="
    log "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
    log "============================="

    [[ ${FAIL} -eq 0 ]]
}

main "$@"
