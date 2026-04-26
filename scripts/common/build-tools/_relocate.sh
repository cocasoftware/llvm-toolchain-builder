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

# ── verify_no_forbidden_deps DIR ────────────────────────────────────────────
# Walks every ELF object under DIR and checks ldd output.
# Forbidden: libstdc++, libgcc_s, libatomic — UNLESS they resolve to a path
# INSIDE ${tool_dir} (i.e. bundled locally with proper rpath).
#
# Strict portability rule (Apr 2026):
#   The final toolchain — INCLUDING every tool — must depend ONLY on:
#     1. glibc (system, ≥2.19 covering 2015+ distros)
#     2. Stage 2 LLVM's own runtimes (libc++, libunwind, compiler-rt)
#     3. Libraries bundled INSIDE the tool's own dir (rpath=$ORIGIN/...)
#   Any GCC runtime (libstdc++/libgcc_s/libatomic) resolving from the host
#   system is FORBIDDEN. Upstream prebuilt tools that link these MUST bundle
#   them via bundle_gcc_runtime_into_tool() before calling this function.
#
# Returns 0 on success, 1 on any violation.
verify_no_forbidden_deps() {
    local tool_dir="$1"
    local fail=0
    local count=0

    if [[ ! -d "${tool_dir}" ]]; then
        echo "[verify] skip: ${tool_dir} not a directory"
        return 0
    fi

    # Realpath of tool_dir for prefix comparison (handles symlinks)
    local tool_dir_real
    tool_dir_real=$(readlink -f "${tool_dir}")

    while IFS= read -r -d '' obj; do
        if ! file "${obj}" 2>/dev/null | grep -qE "ELF.*(executable|shared)"; then
            continue
        fi
        count=$((count + 1))

        local deps
        deps=$(ldd "${obj}" 2>/dev/null || true)

        # Forbidden GCC-runtime libs
        local forbidden_pattern='libstdc\+\+\.so|libgcc_s\.so|libatomic\.so'
        local found_forbidden
        found_forbidden=$(echo "${deps}" | grep -E "${forbidden_pattern}" || true)
        if [[ -n "${found_forbidden}" ]]; then
            local has_violation=0
            while IFS= read -r line; do
                local resolved
                resolved=$(echo "${line}" | sed -E 's/.*=> ([^ ]+).*/\1/' | head -1)
                # Resolved path must be inside tool_dir to count as bundled
                if [[ -z "${resolved}" || "${resolved}" == "not" ]]; then
                    has_violation=1
                    continue
                fi
                local resolved_real
                resolved_real=$(readlink -f "${resolved}" 2>/dev/null || echo "${resolved}")
                if [[ "${resolved_real}" != "${tool_dir_real}"* ]]; then
                    has_violation=1
                fi
            done <<< "${found_forbidden}"

            if (( has_violation == 1 )); then
                echo "[verify] FAIL: $(basename "${obj}") depends on system forbidden lib:"
                echo "${found_forbidden}" | sed 's/^/    /'
                fail=1
            fi
        fi

        # Unresolved deps are always fatal
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

# ── bundle_gcc_runtime_into_tool TOOL_DIR [LIBS...] ─────────────────────────
# Copies the requested GCC runtime libs from BOOTSTRAP_PREFIX into
# ${TOOL_DIR}/lib/, dereferencing the symlinks (so the tool dir is fully
# self-contained). The caller is responsible for setting an rpath that
# points to ${TOOL_DIR}/lib/ (typically $ORIGIN/lib or $ORIGIN/../lib).
#
# Default LIBS: libgcc_s libstdc++
# Each LIB name is matched against ${BOOTSTRAP_PREFIX}/{lib64,lib}/<name>.so*
# and ALL versioned symlinks/files for that lib are copied so that DT_NEEDED
# entries like "libgcc_s.so.1" resolve correctly.
#
# Returns 0 if all requested libs were copied, 1 if any was missing.
bundle_gcc_runtime_into_tool() {
    local tool_dir="$1"
    shift
    local libs=("$@")
    if (( ${#libs[@]} == 0 )); then
        libs=(libgcc_s libstdc++)
    fi
    local bp="${BOOTSTRAP_PREFIX:-/opt/bootstrap}"
    if [[ ! -d "${bp}" ]]; then
        echo "[bundle] FATAL: BOOTSTRAP_PREFIX=${bp} does not exist" >&2
        return 1
    fi
    mkdir -p "${tool_dir}/lib"

    local missing=0
    for libname in "${libs[@]}"; do
        local copied=0
        for d in "${bp}/lib64" "${bp}/lib"; do
            [[ -d "${d}" ]] || continue
            # Match libgcc_s.so, libgcc_s.so.1, libgcc_s.so.1.0.0 etc.
            for f in "${d}/${libname}".so "${d}/${libname}".so.[0-9]*; do
                [[ -e "${f}" ]] || continue
                # cp -aL: dereference symlinks, preserve mode/timestamps
                cp -aL "${f}" "${tool_dir}/lib/$(basename "${f}")"
                copied=1
            done
            (( copied == 1 )) && break
        done
        if (( copied == 0 )); then
            echo "[bundle] FATAL: cannot find ${libname}.so* under ${bp}/{lib64,lib}" >&2
            missing=1
        else
            echo "[bundle] copied ${libname} runtime to ${tool_dir}/lib/"
        fi
    done

    return ${missing}
}

# ── add_rpath_to_lib_dir TOOL_DIR LIB_DIR ───────────────────────────────────
# For every ELF under TOOL_DIR, compute the relative path from its directory
# to LIB_DIR and ADD '$ORIGIN/<relpath>' to its rpath (preserving any
# existing rpath entries — important for tools like Rust that already have
# internal rpath like '$ORIGIN/../lib' for their own .so modules).
#
# Use this for tools with non-standard layouts (Rust: cargo/bin, rustup/...)
# where set_rpath_origin's bin/sbin/libexec heuristic isn't enough.
add_rpath_to_lib_dir() {
    local tool_dir="$1"
    local lib_dir="$2"
    if [[ ! -d "${tool_dir}" || ! -d "${lib_dir}" ]]; then
        echo "[relocate] skip add_rpath: ${tool_dir} or ${lib_dir} not a directory"
        return 0
    fi
    local lib_real
    lib_real=$(readlink -f "${lib_dir}")

    local count=0
    while IFS= read -r -d '' obj; do
        if ! file "${obj}" 2>/dev/null | grep -qE "ELF.*(executable|shared)"; then
            continue
        fi
        local obj_dir
        obj_dir=$(dirname "${obj}")
        local rel
        rel=$(realpath --relative-to="${obj_dir}" "${lib_real}" 2>/dev/null) || continue

        # Get existing rpath (may be empty)
        local existing_rpath
        existing_rpath=$(patchelf --print-rpath "${obj}" 2>/dev/null || true)
        local new_rpath="\$ORIGIN/${rel}"
        if [[ -n "${existing_rpath}" ]]; then
            new_rpath="${new_rpath}:${existing_rpath}"
        fi
        patchelf --force-rpath --set-rpath "${new_rpath}" "${obj}" 2>/dev/null || true
        count=$((count + 1))
    done < <(find "${tool_dir}" -type f -print0)

    echo "[relocate] added rpath →${lib_dir} on ${count} ELF objects"
}

# ── relocate_and_verify DIR ─────────────────────────────────────────────────
# Convenience: rpath + strip + verify in one call.
relocate_and_verify() {
    local tool_dir="$1"

    set_rpath_origin "${tool_dir}"
    strip_binaries "${tool_dir}"
    verify_no_forbidden_deps "${tool_dir}"
}
