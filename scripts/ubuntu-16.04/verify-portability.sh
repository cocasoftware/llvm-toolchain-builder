#!/usr/bin/env bash
# =============================================================================
# Portability verification script
# Verifies that the built LLVM toolchain runs on the current system.
# Designed to be invoked inside multiple Ubuntu containers (16.04 → 24.04).
#
# Usage: TOOLCHAIN_DIR=/opt/coca-toolchain ./scripts/verify-portability.sh
# =============================================================================
set -euo pipefail

: "${TOOLCHAIN_DIR:=/opt/coca-toolchain}"

PASS=0
FAIL=0

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
        echo "  PASS: ${label} → ${output}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${label} → ${output}"
        FAIL=$((FAIL + 1))
    fi
}

# Install minimal build dependencies for test compilation
install_test_deps() {
    if command -v apt-get &>/dev/null; then
        apt-get update -qq 2>/dev/null || true
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
            file libc6-dev 2>/dev/null || true
    fi
}

# -----------------------------------------------------------------------------
# Tests
# -----------------------------------------------------------------------------
main() {
    log "Portability verification on $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || echo 'unknown')"
    log "glibc: $(ldd --version 2>&1 | head -1 || echo 'unknown')"
    log "Toolchain: ${TOOLCHAIN_DIR}"

    install_test_deps

    # 1. Binary execution tests
    log "--- Binary execution ---"
    check_output "clang --version" "${TOOLCHAIN_DIR}/bin/clang" --version
    check_output "clang++ --version" "${TOOLCHAIN_DIR}/bin/clang++" --version
    check_output "lld --version" "${TOOLCHAIN_DIR}/bin/ld.lld" --version
    check_output "llvm-ar --version" "${TOOLCHAIN_DIR}/bin/llvm-ar" --version
    check_output "llvm-nm --version" "${TOOLCHAIN_DIR}/bin/llvm-nm" --version
    check_output "llvm-objdump --version" "${TOOLCHAIN_DIR}/bin/llvm-objdump" --version
    check_output "llvm-readelf --version" "${TOOLCHAIN_DIR}/bin/llvm-readelf" --version
    check_output "llvm-strip --version" "${TOOLCHAIN_DIR}/bin/llvm-strip" --version
    check_output "llvm-profdata --version" "${TOOLCHAIN_DIR}/bin/llvm-profdata" --version || true
    check_output "llvm-cov --version" "${TOOLCHAIN_DIR}/bin/llvm-cov" --version || true
    check_output "clang-format --version" "${TOOLCHAIN_DIR}/bin/clang-format" --version || true
    check_output "clang-tidy --version" "${TOOLCHAIN_DIR}/bin/clang-tidy" --version || true
    check_output "clangd --version" "${TOOLCHAIN_DIR}/bin/clangd" --version || true

    # LLDB (may fail on very old systems due to kernel ptrace)
    if [[ -x "${TOOLCHAIN_DIR}/bin/lldb" ]]; then
        check_output "lldb --version" "${TOOLCHAIN_DIR}/bin/lldb" --version
    fi

    # 2. Compilation tests
    log "--- Compilation tests ---"

    # Diagnostic: show config file status
    local cfg="${TOOLCHAIN_DIR}/bin/clang.cfg"
    if [[ -f "${cfg}" ]]; then
        echo "  clang.cfg exists: $(cat "${cfg}" | grep -v '^#' | tr '\n' ' ')"
    else
        echo "  WARNING: clang.cfg not found at ${cfg}"
    fi
    echo "  clang -v dump:"
    "${TOOLCHAIN_DIR}/bin/clang" -### /dev/null 2>&1 | grep -iE 'config|"-L' | head -5 | sed 's/^/    /' || true

    local tmpdir
    tmpdir=$(mktemp -d)

    # C compilation
    cat > "${tmpdir}/hello.c" << 'EOF'
#include <stdio.h>
int main(void) {
    printf("Hello from COCA toolchain (C)!\n");
    return 0;
}
EOF
    local compile_err
    if compile_err=$("${TOOLCHAIN_DIR}/bin/clang" -o "${tmpdir}/hello_c" "${tmpdir}/hello.c" 2>&1); then
        check "compile hello.c" true
        check "run hello_c" "${tmpdir}/hello_c"
    else
        echo "  FAIL: compile hello.c"
        echo "${compile_err}" | head -20 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
    fi

    # C++ compilation with libc++
    cat > "${tmpdir}/hello.cpp" << 'EOF'
#include <iostream>
#include <vector>
#include <algorithm>
#include <string>
int main() {
    std::vector<std::string> v = {"Hello", "from", "COCA", "toolchain", "(C++)"};
    std::sort(v.begin(), v.end());
    for (const auto& s : v) std::cout << s << " ";
    std::cout << std::endl;
    return 0;
}
EOF
    if compile_err=$("${TOOLCHAIN_DIR}/bin/clang++" -stdlib=libc++ -Wl,-rpath,"${TOOLCHAIN_DIR}/lib" -o "${tmpdir}/hello_cpp" "${tmpdir}/hello.cpp" 2>&1); then
        check "compile hello.cpp (libc++)" true
        check "run hello_cpp" "${tmpdir}/hello_cpp"
    else
        echo "  FAIL: compile hello.cpp (libc++)"
        echo "${compile_err}" | head -20 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
    fi

    # C++ compilation with libstdc++ (if available on host)
    if "${TOOLCHAIN_DIR}/bin/clang++" -stdlib=libstdc++ -Wl,-rpath,"${TOOLCHAIN_DIR}/lib" -o "${tmpdir}/hello_stdcpp" "${tmpdir}/hello.cpp" 2>/dev/null; then
        check "compile hello.cpp (libstdc++)" true
        check "run hello_stdcpp" "${tmpdir}/hello_stdcpp"
    else
        echo "  SKIP: compile hello.cpp (libstdc++) — no libstdc++ on host"
    fi

    # C++23 features
    cat > "${tmpdir}/cpp23.cpp" << 'EOF'
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
    auto v = std::views::iota(1, 6)
           | std::views::transform([](int x) { return x * x; });
    for (int x : v) std::print("{} ", x);
    std::println("");
    return 0;
}
EOF
    if "${TOOLCHAIN_DIR}/bin/clang++" -std=c++23 -stdlib=libc++ -Wl,-rpath,"${TOOLCHAIN_DIR}/lib" -o "${tmpdir}/cpp23" "${tmpdir}/cpp23.cpp" 2>/dev/null; then
        check "compile C++23 features" true
        check "run C++23 binary" "${tmpdir}/cpp23"
    else
        echo "  SKIP: C++23 features (may need newer libc++ headers)"
    fi

    # LLD linking test
    if compile_err=$("${TOOLCHAIN_DIR}/bin/clang" -fuse-ld=lld -o "${tmpdir}/hello_lld" "${tmpdir}/hello.c" 2>&1); then
        check "link with lld" true
        check "run lld-linked binary" "${tmpdir}/hello_lld"
    else
        echo "  FAIL: link with lld"
        echo "${compile_err}" | head -20 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
    fi

    # 3. Dynamic dependency check
    log "--- Dynamic dependencies ---"
    local clang_deps
    clang_deps=$(ldd "${TOOLCHAIN_DIR}/bin/clang" 2>/dev/null || echo "ldd failed")
    echo "  clang dependencies:"
    echo "${clang_deps}" | sed 's/^/    /'

    # Check that no "not found" in ldd output
    if echo "${clang_deps}" | grep -q "not found"; then
        echo "  FAIL: clang has unresolved dependencies"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: all clang dependencies resolved"
        PASS=$((PASS + 1))
    fi

    # Check max glibc version required
    log "--- glibc version check ---"
    local max_glibc_ver="0"
    for bin in "${TOOLCHAIN_DIR}/bin/clang" "${TOOLCHAIN_DIR}/bin/ld.lld"; do
        if [[ -f "${bin}" ]]; then
            local glibc_vers
            glibc_vers=$("${TOOLCHAIN_DIR}/bin/llvm-objdump" -T "${bin}" 2>/dev/null | grep -oP 'GLIBC_\K[0-9]+\.[0-9]+' | sort -V | tail -1 || echo "0")
            echo "  $(basename "${bin}"): requires GLIBC_${glibc_vers:-unknown}"
            if [[ -n "${glibc_vers}" && "$(printf '%s\n%s' "${max_glibc_ver}" "${glibc_vers}" | sort -V | tail -1)" == "${glibc_vers}" ]]; then
                max_glibc_ver="${glibc_vers}"
            fi
        fi
    done
    echo "  Maximum glibc requirement: GLIBC_${max_glibc_ver}"

    # Cleanup
    rm -rf "${tmpdir}"

    # Summary
    log "============================="
    log "Results: ${PASS} passed, ${FAIL} failed"
    log "============================="

    [[ ${FAIL} -eq 0 ]]
}

main "$@"
