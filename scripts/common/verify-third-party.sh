#!/usr/bin/env bash
# =============================================================================
# Verify third-party — build popular OSS projects with the toolchain.
# Source verify-lib.sh before sourcing this file.
#
# Provides:
#   test_third_party_libs <tmpdir>
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

    # --- nlohmann/json (C++17, header-heavy) ---
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

    # --- GLFW (C, Vulkan/OpenGL windowing — headless build) ---
    if timeout 30 git clone --depth 1 https://github.com/glfw/glfw.git "${libdir}/glfw" 2>/dev/null; then
        cmake_build "glfw (headless)" "${libdir}/glfw" "${libdir}/glfw-build" "RelWithDebInfo" \
            -DGLFW_BUILD_EXAMPLES=OFF -DGLFW_BUILD_TESTS=OFF -DGLFW_BUILD_DOCS=OFF
    else
        skip "glfw — clone failed"
    fi

    # --- microsoft/proxy (C++20 concepts-heavy) ---
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
