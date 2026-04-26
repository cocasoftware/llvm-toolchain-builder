#!/usr/bin/env bash
# =============================================================================
# Shared helpers for sysroot construction.
# Sourced by linux-gnu.sh / linux-musl.sh / mingw64.sh / wasi.sh.
# =============================================================================

: "${SYSROOTS_CACHE_DIR:=/opt/tools-cache/sysroots}"
: "${SYSROOTS_WORK_DIR:=/opt/tools-cache/work-sysroots}"

mkdir -p "${SYSROOTS_CACHE_DIR}" "${SYSROOTS_WORK_DIR}"

log() { echo "===> $(date '+%H:%M:%S') $*"; }

# ── extract_deb DEB_FILE DEST ───────────────────────────────────────────────
# Extract a Debian package into DEST using ar + tar (no dpkg required).
extract_deb() {
    local deb="$1"
    local dest="$2"
    local tmp
    tmp=$(mktemp -d)

    pushd "${tmp}" >/dev/null
    ar x "${deb}"
    if [[ -f data.tar.xz ]]; then
        tar -xJf data.tar.xz -C "${dest}"
    elif [[ -f data.tar.gz ]]; then
        tar -xzf data.tar.gz -C "${dest}"
    elif [[ -f data.tar.zst ]]; then
        tar --zstd -xf data.tar.zst -C "${dest}"
    elif [[ -f data.tar ]]; then
        tar -xf data.tar -C "${dest}"
    else
        echo "FATAL: no data.tar.* in ${deb}" >&2
        popd >/dev/null
        rm -rf "${tmp}"
        return 1
    fi
    popd >/dev/null
    rm -rf "${tmp}"
}

# ── extract_apk APK_FILE DEST ───────────────────────────────────────────────
# Extract an Alpine package (.apk = gzipped tar with metadata).
extract_apk() {
    local apk="$1"
    local dest="$2"
    tar -xzf "${apk}" -C "${dest}"
    # Alpine apk files contain extra metadata files (.PKGINFO, .post-install)
    # which are harmless but not needed in sysroot. Leave them.
}

# ── prune_sysroot DIR ───────────────────────────────────────────────────────
# Remove docs/man/info/locale data not needed for cross-compilation.
prune_sysroot() {
    local dir="$1"
    rm -rf "${dir}/usr/share/doc" \
           "${dir}/usr/share/man" \
           "${dir}/usr/share/info" \
           "${dir}/usr/share/locale" \
           "${dir}/usr/share/lintian" \
           "${dir}/var/cache" \
           "${dir}/var/log" \
           "${dir}/.PKGINFO" \
           "${dir}/.SIGN.RSA"* \
           2>/dev/null || true
}

# ── fix_absolute_symlinks DIR ───────────────────────────────────────────────
# Convert absolute symlinks within DIR (e.g. /usr/lib → ./usr/lib) to relative,
# so the sysroot is relocatable.
fix_absolute_symlinks() {
    local dir="$1"
    while IFS= read -r -d '' link; do
        local target
        target=$(readlink "${link}")
        if [[ "${target}" == /* ]]; then
            # Make relative: strip leading / and prepend correct ../ count
            local link_dir
            link_dir=$(dirname "${link}")
            local rel
            rel=$(realpath --relative-to="${link_dir}" "${dir}${target}" 2>/dev/null || echo "")
            if [[ -n "${rel}" ]]; then
                ln -sf "${rel}" "${link}"
            fi
        fi
    done < <(find "${dir}" -type l -print0)
}
