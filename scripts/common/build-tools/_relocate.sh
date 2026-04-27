#!/usr/bin/env bash
# =============================================================================
# Post-build relocation: rpath fixup, strip, and dependency verification.
# Sourced by every build-tools/<tool>.sh after `make install`.
#
# Required commands: patchelf, file, ldd, strip (or llvm-strip).
# =============================================================================

# ── _patchelf_set_rpath OBJ RPATH ───────────────────────────────────────────
# Deterministic rpath setter with two-tier strategy.
#
# Tier 1: --set-rpath (DT_RUNPATH, modern, preferred — honored by every
#         glibc since 2.5; takes precedence over LD_LIBRARY_PATH).
# Tier 2: --force-rpath --set-rpath (DT_RPATH, legacy but rock-solid on
#         aarch64 binaries where DT_RUNPATH addition silently fails due
#         to insufficient PT_DYNAMIC slack space — a known patchelf 0.18
#         issue on certain Rust-emitted ELFs, including wasmtime aarch64).
#
# Both tiers use --remove-rpath first to ensure a clean dynamic section.
# Returns 0 if either tier persists; 1 with full readelf -d dump otherwise.
_patchelf_set_rpath() {
    local obj="$1"
    local rpath="$2"
    local before actual
    before=$(patchelf --print-rpath "${obj}" 2>/dev/null || true)

    # ── Tier 1: DT_RUNPATH ──────────────────────────────────────────────
    patchelf --remove-rpath "${obj}" 2>/dev/null || true
    if patchelf --set-rpath "${rpath}" "${obj}" 2>&1; then
        actual=$(patchelf --print-rpath "${obj}" 2>/dev/null)
        if [[ "${actual}" == "${rpath}" ]]; then
            return 0
        fi
    fi

    # ── Tier 2: DT_RPATH fallback ──────────────────────────────────────
    # Some aarch64 binaries refuse to accept DT_RUNPATH addition because
    # the dynamic section has no slack and patchelf cannot grow it. The
    # legacy DT_RPATH tag is still honored by every dynamic linker and
    # works on those binaries — at the cost of losing LD_LIBRARY_PATH
    # override semantics, which we don't need for self-contained tools.
    patchelf --remove-rpath "${obj}" 2>/dev/null || true
    if patchelf --force-rpath --set-rpath "${rpath}" "${obj}" 2>&1; then
        actual=$(patchelf --print-rpath "${obj}" 2>/dev/null)
        if [[ "${actual}" == "${rpath}" ]]; then
            echo "[relocate] used DT_RPATH fallback for ${obj}"
            return 0
        fi
    fi

    # Both tiers failed — the binary is unpatchable; caller must wrap.
    echo "[relocate] FATAL: ${obj}: rpath persistence failed (both DT_RUNPATH and DT_RPATH)" >&2
    echo "[relocate]        before='${before}' wanted='${rpath}' got='${actual:-<empty>}'" >&2
    echo "[relocate]        readelf -d output:" >&2
    readelf -d "${obj}" 2>&1 | sed 's/^/    /' >&2
    return 1
}

# ── set_rpath_origin DIR ────────────────────────────────────────────────────
# For every ELF object under DIR, set an $ORIGIN-relative rpath so the
# tool finds its own bundled libs in DIR/lib/ regardless of install prefix.
#
# Single-pass implementation: iterate ALL files under DIR, identify ELF
# binaries by file(1), and choose rpath based on:
#   • ELF executable in bin/sbin/libexec → $ORIGIN/<rel-to-lib>
#   • ELF shared library in lib/lib64/   → $ORIGIN (sibling lookup)
#   • ELF object in any other location   → $ORIGIN/<rel-to-lib>
# This avoids any -name pattern subtlety (e.g. libgcc_s.so.1 not matching
# *.so on some find versions) and handles non-standard layouts uniformly.
#
# Failures are NOT silenced: a patchelf error means the toolchain is not
# relocatable, which is a hard portability violation.
set_rpath_origin() {
    local tool_dir="$1"
    if [[ ! -d "${tool_dir}" ]]; then
        echo "[relocate] skip: ${tool_dir} not a directory"
        return 0
    fi
    local tool_dir_real
    tool_dir_real=$(readlink -f "${tool_dir}")
    local lib_dir="${tool_dir_real}/lib"

    local count=0 skipped=0
    while IFS= read -r -d '' obj; do
        local ftype
        ftype=$(file -b "${obj}" 2>/dev/null || echo '<unknown>')
        if [[ "${ftype}" != ELF* ]]; then
            continue
        fi
        if [[ "${ftype}" != *executable* && "${ftype}" != *shared* ]]; then
            continue
        fi

        local obj_dir rpath=""
        obj_dir=$(dirname "${obj}")
        case "${obj_dir}" in
            "${tool_dir_real}/bin"|"${tool_dir_real}/sbin"|"${tool_dir_real}/libexec")
                # Standard executable location → sibling lib dir.
                rpath='$ORIGIN/../lib'
                ;;
            "${tool_dir_real}/lib"|"${tool_dir_real}/lib64")
                # Top-level shared lib → siblings resolve each other.
                rpath='$ORIGIN'
                ;;
            "${tool_dir_real}/lib/"*|"${tool_dir_real}/lib64/"*)
                # Nested .so (e.g. Python's lib/python3.14/lib-dynload/*.so)
                # → climb back to tool's top-level lib dir.
                local rel
                rel=$(realpath --relative-to="${obj_dir}" "${lib_dir}" 2>/dev/null || echo "..")
                rpath="\$ORIGIN/${rel}"
                ;;
            *)
                # Non-standard nested layout (e.g. perl's tools/perl/perl/bin/
                # which has its own Configure-time rpath to perl/lib/CORE).
                # Leave untouched: matches legacy behavior.
                continue
                ;;
        esac

        if _patchelf_set_rpath "${obj}" "${rpath}"; then
            count=$((count + 1))
        else
            skipped=$((skipped + 1))
        fi
    done < <(find "${tool_dir}" -type f -print0)

    if (( skipped > 0 )); then
        echo "[relocate] WARN: ${skipped} ELF object(s) could not be patched in ${tool_dir}" >&2
    fi
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
# Walks every ELF object under DIR and verifies portability invariants.
#
# Strict portability rule (Apr 2026):
#   The final toolchain — INCLUDING every tool — must depend ONLY on:
#     1. glibc (system, ≥2.23 covering Ubuntu 16.04+ / 2016+ distros)
#     2. Stage 2 LLVM's own runtimes (libc++, libunwind, compiler-rt)
#     3. Libraries bundled INSIDE the tool's own dir (rpath=$ORIGIN/...)
#   Any GCC runtime (libstdc++/libgcc_s/libatomic) resolving from the host
#   system is FORBIDDEN. Upstream prebuilt tools that link these MUST bundle
#   them via bundle_gcc_runtime_into_tool() first.
#
# This function uses TWO complementary checks:
#
#   STATIC  (always run, never fails on build-env GLIBC mismatch):
#     For every DT_NEEDED entry that is a forbidden lib, verify there is a
#     corresponding file in ${tool_dir}/lib/<libname>. Combined with the
#     rpath patching (set_rpath_origin / add_rpath_to_lib_dir), this
#     guarantees the runtime linker resolves it locally.
#
#   RUNTIME (best-effort, ldd-based):
#     If the binary loads in the build env, walk ldd output and check that
#     no forbidden lib resolves outside ${tool_dir}. Skipped silently if the
#     binary requires a newer GLIBC than the build env supplies (common for
#     upstream Rust binaries built on RHEL 8: needs GLIBC 2.28).
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

    local tool_dir_real
    tool_dir_real=$(readlink -f "${tool_dir}")
    local forbidden_re='^(libstdc\+\+\.so|libgcc_s\.so|libatomic\.so)'

    while IFS= read -r -d '' obj; do
        if ! file "${obj}" 2>/dev/null | grep -qE "ELF.*(executable|shared)"; then
            continue
        fi
        count=$((count + 1))
        local obj_label
        obj_label="${obj#${tool_dir_real}/}"

        # ── STATIC check: DT_NEEDED forbidden libs MUST be bundled ────────
        local needed
        needed=$(patchelf --print-needed "${obj}" 2>/dev/null || true)
        while IFS= read -r dep; do
            [[ -z "${dep}" ]] && continue
            if echo "${dep}" | grep -qE "${forbidden_re}"; then
                # find file ${tool_dir}/lib/${dep} OR ${tool_dir}/lib/${dep}
                # (accounting for soversion in DT_NEEDED, e.g. libgcc_s.so.1)
                if [[ ! -e "${tool_dir}/lib/${dep}" ]]; then
                    echo "[verify] FAIL static: ${obj_label} DT_NEEDED '${dep}' but ${tool_dir}/lib/${dep} missing"
                    fail=1
                fi
            fi
        done <<< "${needed}"

        # ── RUNTIME check: ldd must resolve forbidden libs locally ────────
        # We run ldd with LD_LIBRARY_PATH prepended with tool_dir/lib so the
        # check simulates the runtime conditions the binary is exec'd under
        # (either via DT_RPATH/DT_RUNPATH OR via a launcher script that sets
        # LD_LIBRARY_PATH itself). This unifies both paths under one check
        # and verifies the BUNDLED lib has the right SONAME for resolution.
        local ldd_out
        ldd_out=$(LD_LIBRARY_PATH="${tool_dir_real}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" \
                  ldd "${obj}" 2>&1 || true)

        # Skip runtime check if build-env GLIBC is too old for this binary
        # (typical for upstream Rust binaries from RHEL 8 builders).
        if echo "${ldd_out}" | grep -q "version \`GLIBC_.*' not found"; then
            echo "[verify] skip runtime ${obj_label}: build-env GLIBC too old"
            continue
        fi
        # Skip if static binary or otherwise no dynamic deps
        if echo "${ldd_out}" | grep -q "not a dynamic executable\|statically linked"; then
            continue
        fi

        # Walk forbidden lines; each must resolve inside tool_dir or be missing
        # for a benign reason.
        local found_forbidden
        found_forbidden=$(echo "${ldd_out}" | grep -E "(libstdc\+\+|libgcc_s|libatomic)\.so" || true)
        if [[ -n "${found_forbidden}" ]]; then
            local has_violation=0
            while IFS= read -r line; do
                # Format: "  libname.so.X => /resolved/path (0xADDR)"
                #         or "  libname.so.X => not found"
                local resolved
                resolved=$(echo "${line}" | sed -nE 's/.*=> ([^ ]+).*/\1/p' | head -1)
                if [[ -z "${resolved}" || "${resolved}" == "not" ]]; then
                    # "not found" — fatal
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
                echo "[verify] FAIL runtime: ${obj_label} resolves forbidden lib from system:"
                echo "${found_forbidden}" | sed 's/^/    /'
                # Diagnostic dump: rpath/runpath, needed, lib dir contents
                echo "    [diag] DT_NEEDED:"
                patchelf --print-needed "${obj}" 2>/dev/null | sed 's/^/        /'
                echo "    [diag] DT_RPATH/RUNPATH: $(patchelf --print-rpath "${obj}" 2>/dev/null || echo '<unset>')"
                echo "    [diag] readelf -d (PATH-related):"
                readelf -d "${obj}" 2>/dev/null | grep -E 'RPATH|RUNPATH|NEEDED' | sed 's/^/        /'
                echo "    [diag] ${tool_dir}/lib/ contents:"
                ls -la "${tool_dir}/lib/" 2>/dev/null | sed 's/^/        /'
                fail=1
            fi
        fi

        # Unresolved (non-GLIBC) deps are always fatal
        if echo "${ldd_out}" | grep -E '=> not found' | grep -v "GLIBC_" >/dev/null; then
            echo "[verify] FAIL: ${obj_label} has unresolved dependencies:"
            echo "${ldd_out}" | grep "not found" | sed 's/^/    /'
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
        _patchelf_set_rpath "${obj}" "${new_rpath}"
        count=$((count + 1))
    done < <(find "${tool_dir}" -type f -print0)

    echo "[relocate] added rpath →${lib_dir} on ${count} ELF objects"
}

# ── wrap_with_launcher_script BIN_PATH ──────────────────────────────────────
# Final-tier fallback for ELF binaries that patchelf cannot patch (extremely
# rare — e.g. binaries with packed dynamic sections and no slack).
#
# Renames the original ELF to BIN_PATH.real and replaces BIN_PATH with a
# minimal /bin/sh launcher that prepends the bundled lib dir to
# LD_LIBRARY_PATH and execs the real binary. The launcher is POSIX shell
# (no bash dependency), ~150 bytes, with negligible startup overhead.
#
# Layout assumption: BIN_PATH is in <tool_dir>/{bin,sbin,libexec} and the
# bundled lib dir is at <tool_dir>/lib (sibling level).
wrap_with_launcher_script() {
    local bin_path="$1"
    if [[ ! -f "${bin_path}" ]]; then
        echo "[relocate] wrap_with_launcher_script: ${bin_path} not a file" >&2
        return 1
    fi
    local bin_dir bin_name real_path
    bin_dir=$(dirname "${bin_path}")
    bin_name=$(basename "${bin_path}")
    real_path="${bin_dir}/.${bin_name}.real"

    mv "${bin_path}" "${real_path}"
    cat > "${bin_path}" <<LAUNCHER_EOF
#!/bin/sh
# Auto-generated launcher: bundled-lib LD_LIBRARY_PATH wrapper.
DIR=\$(cd -- "\$(dirname -- "\$0")" && pwd)
LD_LIBRARY_PATH="\${DIR}/../lib\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}" \\
    exec "\${DIR}/.${bin_name}.real" "\$@"
LAUNCHER_EOF
    chmod +x "${bin_path}"
    echo "[relocate] wrapped ${bin_path} with launcher script (real: ${real_path})"
}

# ── relocate_and_verify DIR ─────────────────────────────────────────────────
# Convenience: rpath + strip + verify in one call.
relocate_and_verify() {
    local tool_dir="$1"

    set_rpath_origin "${tool_dir}"
    strip_binaries "${tool_dir}"
    verify_no_forbidden_deps "${tool_dir}"
}
