#!/usr/bin/env bash
# =============================================================================
# Verify bundled tools (cmake/ninja/git/python/pwsh/...).
# Source verify-lib.sh before this file.
#
# Provides:
#   test_bundled_tools_exist
#   test_bundled_tools_run     — executes each tool's --version
#   test_bundled_tools_no_forbidden_deps  — ldd check on every ELF in tools/
# =============================================================================

# ── 1. Existence: every expected tool dir is present ────────────────────────
test_bundled_tools_exist() {
    log "--- Tools: existence ---"

    # Map tool name → expected entry point inside tools/<name>/
    declare -A EXPECTED_ENTRY=(
        [cmake]="bin/cmake"
        [ninja]="ninja"
        [git]="bin/git"
        [doxygen]="bin/doxygen"
        [graphviz]="bin/dot"
        [perl]="perl/bin/perl"
        [rsync]="bin/rsync"
        [python]="bin/python3"
        [wasmtime]="wasmtime"
        [jfrog]="jf"
        [glab]="glab"
        [pwsh]="pwsh"
        [rust]="cargo/bin/rustc"
        [emsdk]="emsdk.py"
        [conan]="bin/conan"
    )

    local fail=0
    for tool in "${!EXPECTED_ENTRY[@]}"; do
        local entry="${TOOLCHAIN_DIR}/tools/${tool}/${EXPECTED_ENTRY[${tool}]}"
        if [[ -e "${entry}" ]]; then
            check_pass "tool ${tool} exists at ${entry#${TOOLCHAIN_DIR}/}"
        else
            check_fail "tool ${tool} missing: ${entry}"
            fail=1
        fi
    done
    return ${fail}
}

# ── 2. Execution: each tool runs without error and reports a version ────────
test_bundled_tools_run() {
    log "--- Tools: execution / --version ---"

    local TOOL_DIR="${TOOLCHAIN_DIR}/tools"

    # Each tool is invoked with --version (or equivalent)
    [[ -x "${TOOL_DIR}/cmake/bin/cmake" ]] && \
        check_output "cmake --version" "${TOOL_DIR}/cmake/bin/cmake" --version

    [[ -x "${TOOL_DIR}/ninja/ninja" ]] && \
        check_output "ninja --version" "${TOOL_DIR}/ninja/ninja" --version

    [[ -x "${TOOL_DIR}/git/bin/git" ]] && \
        check_output "git --version" "${TOOL_DIR}/git/bin/git" --version

    [[ -x "${TOOL_DIR}/doxygen/bin/doxygen" ]] && \
        check_output "doxygen --version" "${TOOL_DIR}/doxygen/bin/doxygen" --version

    [[ -x "${TOOL_DIR}/graphviz/bin/dot" ]] && \
        check_output "graphviz dot -V" "${TOOL_DIR}/graphviz/bin/dot" -V 2>&1

    [[ -x "${TOOL_DIR}/perl/perl/bin/perl" ]] && \
        check_output "perl --version" "${TOOL_DIR}/perl/perl/bin/perl" --version

    [[ -x "${TOOL_DIR}/rsync/bin/rsync" ]] && \
        check_output "rsync --version" "${TOOL_DIR}/rsync/bin/rsync" --version

    [[ -x "${TOOL_DIR}/python/bin/python3" ]] && \
        check_output "python3 --version" "${TOOL_DIR}/python/bin/python3" --version

    [[ -x "${TOOL_DIR}/wasmtime/wasmtime" ]] && \
        check_output "wasmtime --version" "${TOOL_DIR}/wasmtime/wasmtime" --version

    [[ -x "${TOOL_DIR}/jfrog/jf" ]] && \
        check_output "jfrog --version" "${TOOL_DIR}/jfrog/jf" --version

    [[ -x "${TOOL_DIR}/glab/glab" ]] && \
        check_output "glab --version" "${TOOL_DIR}/glab/glab" --version

    [[ -x "${TOOL_DIR}/pwsh/pwsh" ]] && \
        check_output "pwsh --version" "${TOOL_DIR}/pwsh/pwsh" --version

    [[ -x "${TOOL_DIR}/rust/cargo/bin/rustc" ]] && \
        check_output "rustc --version" "${TOOL_DIR}/rust/cargo/bin/rustc" --version

    if [[ -x "${TOOL_DIR}/conan/bin/conan" ]]; then
        check_output "conan --version" "${TOOL_DIR}/conan/bin/conan" --version
    fi

    if [[ -d "${TOOL_DIR}/emsdk" && -f "${TOOL_DIR}/emsdk/emsdk.py" ]]; then
        if [[ -x "${TOOL_DIR}/python/bin/python3" ]]; then
            check_output "emsdk version" "${TOOL_DIR}/python/bin/python3" \
                "${TOOL_DIR}/emsdk/emsdk.py" list | grep -i 'INSTALLED' || true
        fi
    fi
}

# ── 3. Dependencies: no forbidden libs in any tool ──────────────────────────
# Allowed:
#   - glibc (libc, libm, libdl, libpthread, librt, libresolv, libnsl, libutil, ld-linux)
#   - libs in tools/<name>/lib/ (rpath = $ORIGIN/...)
# Forbidden globally:
#   - libstdc++, libgcc_s, libatomic from system
# Special exemption:
#   - tools/pwsh/lib/libstdc++.so.6 + libgcc_s.so.1 (bundled for .NET runtime)
test_bundled_tools_no_forbidden_deps() {
    log "--- Tools: no forbidden runtime deps ---"

    local TOOL_DIR="${TOOLCHAIN_DIR}/tools"
    local fail=0
    local checked=0
    local tool

    for tool_subdir in "${TOOL_DIR}"/*/; do
        tool="$(basename "${tool_subdir}")"
        # Skip non-binary tools (conan is python; emsdk is python; glab/jfrog are static go)
        # but still check for any ELF inside

        while IFS= read -r -d '' obj; do
            if ! file "${obj}" 2>/dev/null | grep -qE "ELF.*(executable|shared)"; then
                continue
            fi
            checked=$((checked + 1))

            local deps
            deps=$(ldd "${obj}" 2>/dev/null || true)

            # 1. Unresolved deps are ALWAYS a fail
            if echo "${deps}" | grep -q "not found"; then
                check_fail "tools/${tool}/$(realpath --relative-to="${tool_subdir}" "${obj}"): unresolved deps"
                echo "${deps}" | grep "not found" | sed 's/^/    /'
                fail=1
                continue
            fi

            # 2. Forbidden libs check (with pwsh exemption)
            local forbidden_pattern='libstdc\+\+\.so|libgcc_s\.so|libatomic\.so'
            local found_forbidden
            found_forbidden=$(echo "${deps}" | grep -E "${forbidden_pattern}" || true)

            if [[ -n "${found_forbidden}" ]]; then
                # Check if every forbidden dep resolves to inside tools/<tool>/
                local all_local=1
                while IFS= read -r line; do
                    local resolved
                    resolved=$(echo "${line}" | sed -E 's/.*=> ([^ ]+).*/\1/' | head -1)
                    if [[ -n "${resolved}" && "${resolved}" != "not" ]]; then
                        if [[ "${resolved}" != "${tool_subdir}"* ]]; then
                            all_local=0
                            break
                        fi
                    fi
                done <<< "${found_forbidden}"

                if (( all_local == 0 )); then
                    check_fail "tools/${tool}/$(realpath --relative-to="${tool_subdir}" "${obj}"): leaks forbidden lib to system"
                    echo "${found_forbidden}" | sed 's/^/    /'
                    fail=1
                fi
            fi
        done < <(find "${tool_subdir}" -type f -print0)
    done

    if (( fail == 0 )); then
        check_pass "tools dependency check: ${checked} ELF objects, all clean"
    fi
    return ${fail}
}

# ── 4. Test setup.py / scaffolding integrity ────────────────────────────────
test_toolchain_scaffolding() {
    log "--- Toolchain: scaffolding ---"

    if [[ ! -f "${TOOLCHAIN_DIR}/setup.py" ]]; then
        check_fail "setup.py missing"
        return 1
    fi
    check_pass "setup.py present"

    if [[ ! -f "${TOOLCHAIN_DIR}/toolchain.json" ]]; then
        check_fail "toolchain.json missing"
        return 1
    fi
    check_pass "toolchain.json present"

    if [[ ! -d "${TOOLCHAIN_DIR}/scripts" || ! -d "${TOOLCHAIN_DIR}/cmake" ]]; then
        check_fail "scripts/ or cmake/ subdirs missing"
        return 1
    fi
    check_pass "scripts/ and cmake/ present"

    # Try setup.py info via bundled Python
    if [[ -x "${TOOLCHAIN_DIR}/tools/python/bin/python3" ]]; then
        check_output "setup.py info" "${TOOLCHAIN_DIR}/tools/python/bin/python3" \
            "${TOOLCHAIN_DIR}/setup.py" info || true
    fi
}
