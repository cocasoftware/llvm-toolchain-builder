#!/usr/bin/env bash
# =============================================================================
# Post-build relocation: rpath fixup, strip, and dependency verification.
# Sourced by every build-tools/<tool>.sh after `make install`.
#
# Required commands: patchelf, file, ldd, strip (or llvm-strip).
# =============================================================================

# ── set_rpath_origin DIR ────────────────────────────────────────────────────
# For every ELF binary in DIR/bin/, set rpath to '$ORIGIN/../lib'.
# For every shared library in DIR/lib/, set rpath to '$ORIGIN'.
# Idempotent: safe to call multiple times.
set_rpath_origin() {
    local tool_dir="$1"
    if [[ ! -d "${tool_dir}" ]]; then
        echo "[relocate] skip: ${tool_dir} not a directory"
        return 0
    fi

    local count=0

    # Executables under bin/, sbin/, libexec/
    for sub in bin sbin libexec; do
        if [[ -d "${tool_dir}/${sub}" ]]; then
            while IFS= read -r -d '' exe; do
                if file "${exe}" 2>/dev/null | grep -q "ELF.*executable"; then
                    patchelf --force-rpath --set-rpath '$ORIGIN/../lib' "${exe}" 2>/dev/null || true
                    count=$((count + 1))
                fi
            done < <(find "${tool_dir}/${sub}" -type f -print0)
        fi
    done

    # Shared libraries under lib/, lib64/
    for sub in lib lib64; do
        if [[ -d "${tool_dir}/${sub}" ]]; then
            while IFS= read -r -d '' lib; do
                if file "${lib}" 2>/dev/null | grep -q "ELF.*shared"; then
                    patchelf --force-rpath --set-rpath '$ORIGIN' "${lib}" 2>/dev/null || true
                    count=$((count + 1))
                fi
            done < <(find "${tool_dir}/${sub}" -type f \( -name "*.so" -o -name "*.so.*" \) -print0)
        fi
    done

    echo "[relocate] patched rpath on ${count} ELF objects in ${tool_dir}"
}

# ── strip_binaries DIR [TOOL] ───────────────────────────────────────────────
# Strip debug + unneeded symbols from all ELF objects in DIR.
# TOOL defaults to llvm-strip from STAGE2_PREFIX or system strip.
strip_binaries() {
    local tool_dir="$1"
    local stripper="${2:-${STRIP:-strip}}"
    if [[ ! -x "${stripper}" ]]; then
        # Fallback to PATH lookup
        stripper="strip"
    fi

    local count=0
    while IFS= read -r -d '' obj; do
        if file "${obj}" 2>/dev/null | grep -qE "ELF.*(executable|shared)"; then
            "${stripper}" --strip-unneeded "${obj}" 2>/dev/null || true
            count=$((count + 1))
        fi
    done < <(find "${tool_dir}" -type f \( -perm -u+x -o -name "*.so*" \) -print0)

    echo "[relocate] stripped ${count} ELF objects in ${tool_dir}"
}

# ── verify_no_forbidden_deps DIR [EXTRA_ALLOWED_LIBS] ───────────────────────
# Walks every ELF object under DIR and checks ldd output.
# Forbidden: libstdc++, libgcc_s, libatomic, "not found".
# EXTRA_ALLOWED_LIBS: pipe-separated list of additional acceptable lib names
#   (used e.g. by pwsh which is permitted to bundle libstdc++ in tools/pwsh/lib/).
# Returns 0 on success, 1 on any violation.
verify_no_forbidden_deps() {
    local tool_dir="$1"
    local extra_allowed="${2:-}"
    local fail=0
    local count=0

    if [[ ! -d "${tool_dir}" ]]; then
        echo "[verify] skip: ${tool_dir} not a directory"
        return 0
    fi

    while IFS= read -r -d '' obj; do
        if ! file "${obj}" 2>/dev/null | grep -qE "ELF.*(executable|shared)"; then
            continue
        fi
        count=$((count + 1))

        local deps
        deps=$(ldd "${obj}" 2>/dev/null || true)

        # Check forbidden libs (with allow-list exemption)
        local forbidden_pattern='libstdc\+\+\.so|libgcc_s\.so|libatomic\.so'
        local found_forbidden
        found_forbidden=$(echo "${deps}" | grep -E "${forbidden_pattern}" || true)
        if [[ -n "${found_forbidden}" ]]; then
            # Check if dependency is satisfied by lib bundled INSIDE this tool's dir
            local resolves_locally=1
            while IFS= read -r line; do
                local resolved
                resolved=$(echo "${line}" | sed -E 's/.*=> ([^ ]+).*/\1/' | head -1)
                if [[ -n "${resolved}" && "${resolved}" != "not" ]]; then
                    if [[ "${resolved}" != "${tool_dir}"* ]]; then
                        resolves_locally=0
                        break
                    fi
                fi
            done <<< "${found_forbidden}"

            if (( resolves_locally == 0 )); then
                echo "[verify] FAIL: $(basename "${obj}") depends on system forbidden lib:"
                echo "${found_forbidden}" | sed 's/^/    /'
                fail=1
            fi
        fi

        # Check unresolved deps
        if echo "${deps}" | grep -q "not found"; then
            echo "[verify] FAIL: $(basename "${obj}") has unresolved dependencies:"
            echo "${deps}" | grep "not found" | sed 's/^/    /'
            fail=1
        fi
    done < <(find "${tool_dir}" -type f \( -perm -u+x -o -name "*.so*" \) -print0)

    if (( fail != 0 )); then
        echo "[verify] FATAL: ${tool_dir} has forbidden or unresolved deps"
        return 1
    fi
    echo "[verify] PASS: ${count} ELF objects in ${tool_dir} clean"
}

# ── relocate_and_verify DIR [EXTRA_ALLOWED_LIBS] ────────────────────────────
# Convenience: rpath + strip + verify in one call.
relocate_and_verify() {
    local tool_dir="$1"
    local extra_allowed="${2:-}"

    set_rpath_origin "${tool_dir}"
    strip_binaries "${tool_dir}"
    verify_no_forbidden_deps "${tool_dir}" "${extra_allowed}"
}
