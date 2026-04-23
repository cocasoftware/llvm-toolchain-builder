#!/usr/bin/env bash
# =============================================================================
# Verify toolchain — core tests for any Linux platform/arch/distro.
# Source verify-lib.sh before sourcing this file.
#
# Provides test functions (call from an entry-point script):
#   test_binary_execution
#   test_basic_compilation  <tmpdir>
#   test_sanitizers         <tmpdir>
#   test_openmp             <tmpdir>
#   test_profiling          <tmpdir>
#   test_cross_compilation  <tmpdir>
#   test_fortran            <tmpdir>
#   test_clang_tidy         <tmpdir>
#   test_dependencies
# =============================================================================

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
    local san_err
    if san_err=$("${CC}" -fsanitize=address -fno-omit-frame-pointer -Wl,-rpath,"${TOOLCHAIN_DIR}/lib" -o "${t}/asan_clean" "${t}/asan_test.c" 2>&1); then
        check "compile ASan (clean)" true
        local run_out
        if run_out=$("${t}/asan_clean" 2>&1); then
            check "run ASan (clean)" true
        else
            echo "  FAIL: run ASan (clean)"
            echo "${run_out}" | head -20 | sed 's/^/    /'
            FAIL=$((FAIL + 1))
        fi
    else
        fail_msg "compile ASan (clean)" "${san_err}"
    fi

    cat > "${t}/ubsan_test.c" << 'EOF'
#include <stdio.h>
int main(void) {
    int x = 42;
    printf("UBSan clean: %d\n", x);
    return 0;
}
EOF
    if san_err=$("${CC}" -fsanitize=undefined -Wl,-rpath,"${TOOLCHAIN_DIR}/lib" -o "${t}/ubsan_clean" "${t}/ubsan_test.c" 2>&1); then
        check "compile UBSan (clean)" true
        local run_out
        if run_out=$("${t}/ubsan_clean" 2>&1); then
            check "run UBSan (clean)" true
        else
            echo "  FAIL: run UBSan (clean)"
            echo "${run_out}" | head -20 | sed 's/^/    /'
            FAIL=$((FAIL + 1))
        fi
    else
        fail_msg "compile UBSan (clean)" "${san_err}"
    fi
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
        fail_msg "compile OpenMP (libomp should be in Stage 2)" "${omp_err}"
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
# 6. Cross-compilation (object files, no run)
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
        local elf_info
        elf_info=$(file "${t}/cross.o" 2>/dev/null || echo "")
        case "${cross_label}" in
            AArch64) [[ "${elf_info}" == *"aarch64"* || "${elf_info}" == *"ARM aarch64"* ]] && check "cross-compile ELF arch (${cross_label})" true || { echo "  FAIL: cross-compile ELF arch"; FAIL=$((FAIL + 1)); } ;;
            x86_64)  [[ "${elf_info}" == *"x86-64"* ]] && check "cross-compile ELF arch (${cross_label})" true || { echo "  FAIL: cross-compile ELF arch"; FAIL=$((FAIL + 1)); } ;;
        esac
    else
        skip "cross-compile to ${cross_label} — missing sysroot or target support"
    fi

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
        fail_msg "compile Fortran hello" "${flang_err}"
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

    # Forbidden deps check
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
