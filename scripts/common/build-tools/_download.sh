#!/usr/bin/env bash
# =============================================================================
# Source/binary tarball download with SHA-256 verification.
# Sourced by build-tools/<tool>.sh.
#
# Required env: TOOLS_CACHE_DIR  (default: /opt/tools-cache)
# =============================================================================

: "${TOOLS_CACHE_DIR:=/opt/tools-cache}"
: "${SOURCES_DIR:=${TOOLS_CACHE_DIR}/sources}"
: "${WORK_DIR:=${TOOLS_CACHE_DIR}/work}"

mkdir -p "${SOURCES_DIR}" "${WORK_DIR}"

# ── download_file URL DEST_NAME [SHA256] ────────────────────────────────────
# Cached download with integrity check.
# If DEST exists with matching SHA-256, skip download (cache hit).
# If SHA-256 omitted, only existence is verified (less safe but acceptable for
# fast-moving tools where pinning is impractical).
download_file() {
    local url="$1"
    local dest_name="$2"
    local expected_sha256="${3:-}"
    local dest="${SOURCES_DIR}/${dest_name}"

    # ── Cache hit? ──────────────────────────────────────────────────────────
    if [[ -f "${dest}" ]]; then
        if [[ -n "${expected_sha256}" ]]; then
            local actual_sha256
            actual_sha256=$(sha256sum "${dest}" | cut -d' ' -f1)
            if [[ "${actual_sha256}" == "${expected_sha256}" ]]; then
                echo "[download] cache hit: ${dest_name}"
                return 0
            else
                echo "[download] checksum mismatch, re-downloading: ${dest_name}"
                rm -f "${dest}"
            fi
        else
            echo "[download] cache hit (unverified): ${dest_name}"
            return 0
        fi
    fi

    # ── Fetch ───────────────────────────────────────────────────────────────
    echo "[download] fetching ${url}"
    local tries=3
    local i=0
    while (( i < tries )); do
        if curl --fail --location --silent --show-error \
                --retry 3 --retry-delay 5 \
                --connect-timeout 30 --max-time 1800 \
                --output "${dest}.partial" "${url}"; then
            mv "${dest}.partial" "${dest}"
            break
        fi
        i=$((i + 1))
        echo "[download] attempt ${i}/${tries} failed; retrying in 10s..."
        sleep 10
        rm -f "${dest}.partial"
    done

    if [[ ! -f "${dest}" ]]; then
        echo "[download] FATAL: failed to download ${url} after ${tries} attempts" >&2
        return 1
    fi

    # ── Verify ──────────────────────────────────────────────────────────────
    if [[ -n "${expected_sha256}" ]]; then
        local actual_sha256
        actual_sha256=$(sha256sum "${dest}" | cut -d' ' -f1)
        if [[ "${actual_sha256}" != "${expected_sha256}" ]]; then
            echo "[download] FATAL: SHA-256 mismatch for ${dest_name}" >&2
            echo "  expected: ${expected_sha256}" >&2
            echo "  actual:   ${actual_sha256}" >&2
            rm -f "${dest}"
            return 1
        fi
        echo "[download] verified ${dest_name}"
    fi
}

# ── extract_archive ARCHIVE DEST [STRIP_COMPONENTS] ─────────────────────────
# Auto-detect tar format and extract.
# Returns 0 on success.
extract_archive() {
    local archive="$1"
    local dest="$2"
    local strip="${3:-1}"

    mkdir -p "${dest}"

    case "${archive}" in
        *.tar.gz|*.tgz)    tar -xzf "${archive}" -C "${dest}" --strip-components="${strip}" ;;
        *.tar.xz)          tar -xJf "${archive}" -C "${dest}" --strip-components="${strip}" ;;
        *.tar.zst|*.tzst)  tar --zstd -xf "${archive}" -C "${dest}" --strip-components="${strip}" ;;
        *.tar.bz2|*.tbz2)  tar -xjf "${archive}" -C "${dest}" --strip-components="${strip}" ;;
        *.tar)             tar -xf "${archive}" -C "${dest}" --strip-components="${strip}" ;;
        *.zip)             unzip -q -d "${dest}" "${archive}" ;;
        *)
            echo "[extract] FATAL: unsupported archive format: ${archive}" >&2
            return 1
            ;;
    esac
}

# ── fetch_and_extract URL DEST [SHA256] ─────────────────────────────────────
# Combined download + extract. Returns extracted dir path via stdout.
fetch_and_extract() {
    local url="$1"
    local dest="$2"
    local expected_sha256="${3:-}"
    local dest_name
    dest_name=$(basename "${url}")

    download_file "${url}" "${dest_name}" "${expected_sha256}" || return 1
    rm -rf "${dest}"
    mkdir -p "${dest}"
    extract_archive "${SOURCES_DIR}/${dest_name}" "${dest}" 1 || return 1
}
