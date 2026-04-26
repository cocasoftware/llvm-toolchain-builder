# =============================================================================
# COCA Rust — CMake module for Rust integration
# =============================================================================
#
# Provides:
#   - Auto-detection of bundled Rust toolchain (tools/rust/)
#   - Profile-aware Rust target triple mapping
#   - Linker configuration so Rust uses COCA's lld and sysroots
#   - coca_rust_staticlib()  — build a Rust crate as a C-compatible static lib
#   - coca_rust_cdylib()     — build a Rust crate as a C-compatible shared lib
#   - coca_rust_bin()        — build a Rust binary crate
#
# Usage in CMakeLists.txt:
#   include(<toolchain_root>/cmake/coca_rust.cmake)
#
#   # Build a Rust staticlib and link it into a C/C++ target
#   coca_rust_staticlib(
#       NAME mylib_rs
#       CRATE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/mylib-rs
#       FEATURES "feature1;feature2"          # optional
#   )
#   target_link_libraries(myapp PRIVATE mylib_rs)
#
#   # Build a Rust binary
#   coca_rust_bin(
#       NAME mytool
#       CRATE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/mytool-rs
#   )
#
# Environment:
#   The module sets RUSTUP_HOME, CARGO_HOME, and CARGO_TARGET_*_LINKER
#   so that cargo uses COCA's bundled Rust and LLVM linkers.
#
# =============================================================================

# Guard against multiple inclusion
if(DEFINED _COCA_RUST_INCLUDED)
    return()
endif()
set(_COCA_RUST_INCLUDED TRUE)

# ---------------------------------------------------------------------------
# Resolve toolchain root if not already set
# ---------------------------------------------------------------------------
if(NOT DEFINED COCA_TOOLCHAIN_ROOT)
    get_filename_component(COCA_TOOLCHAIN_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
endif()

# ---------------------------------------------------------------------------
# 1. Detect Rust toolchain
# ---------------------------------------------------------------------------
set(_COCA_RUST_DIR "${COCA_TOOLCHAIN_ROOT}/tools/rust")
set(_COCA_RUSTUP_HOME "${_COCA_RUST_DIR}/rustup")
set(_COCA_CARGO_HOME  "${_COCA_RUST_DIR}/cargo")

if(CMAKE_HOST_WIN32)
    set(_COCA_RUSTC  "${_COCA_CARGO_HOME}/bin/rustc.exe")
    set(_COCA_CARGO  "${_COCA_CARGO_HOME}/bin/cargo.exe")
    set(_COCA_RUSTUP "${_COCA_CARGO_HOME}/bin/rustup.exe")
else()
    set(_COCA_RUSTC  "${_COCA_CARGO_HOME}/bin/rustc")
    set(_COCA_CARGO  "${_COCA_CARGO_HOME}/bin/cargo")
    set(_COCA_RUSTUP "${_COCA_CARGO_HOME}/bin/rustup")
endif()

if(NOT EXISTS "${_COCA_RUSTC}")
    message(FATAL_ERROR
        "[COCA Rust] Bundled Rust not found at ${_COCA_RUST_DIR}\n"
        "  Run: python tools/rust/setup_rust_toolchain.py")
endif()

# Export for use by consumers
set(COCA_RUSTC  "${_COCA_RUSTC}"  CACHE FILEPATH "COCA Rust compiler"  FORCE)
set(COCA_CARGO  "${_COCA_CARGO}"  CACHE FILEPATH "COCA Cargo"          FORCE)
set(COCA_RUSTUP "${_COCA_RUSTUP}" CACHE FILEPATH "COCA rustup"         FORCE)
set(COCA_RUSTUP_HOME "${_COCA_RUSTUP_HOME}" CACHE PATH "COCA RUSTUP_HOME" FORCE)
set(COCA_CARGO_HOME  "${_COCA_CARGO_HOME}"  CACHE PATH "COCA CARGO_HOME"  FORCE)

# ---------------------------------------------------------------------------
# 2. Map COCA_TARGET_PROFILE → Rust target triple
# ---------------------------------------------------------------------------
set(_COCA_RUST_TARGET_MAP_win-x64              "x86_64-pc-windows-msvc")
set(_COCA_RUST_TARGET_MAP_win-x64-clang        "x86_64-pc-windows-msvc")
set(_COCA_RUST_TARGET_MAP_linux-x64            "x86_64-unknown-linux-gnu")
set(_COCA_RUST_TARGET_MAP_linux-arm64          "aarch64-unknown-linux-gnu")
set(_COCA_RUST_TARGET_MAP_linux-x64-kylin      "x86_64-unknown-linux-gnu")
set(_COCA_RUST_TARGET_MAP_linux-arm64-kylin    "aarch64-unknown-linux-gnu")
set(_COCA_RUST_TARGET_MAP_linux-x64-musl       "x86_64-unknown-linux-musl")
set(_COCA_RUST_TARGET_MAP_linux-arm64-musl     "aarch64-unknown-linux-musl")
set(_COCA_RUST_TARGET_MAP_win-x64-mingw-ucrt   "x86_64-pc-windows-gnu")
set(_COCA_RUST_TARGET_MAP_win-x64-mingw-msvcrt "x86_64-pc-windows-gnu")
set(_COCA_RUST_TARGET_MAP_wasm-wasi            "wasm32-wasip1")
set(_COCA_RUST_TARGET_MAP_wasm-emscripten      "wasm32-unknown-emscripten")

if(DEFINED COCA_TARGET_PROFILE)
    set(_coca_rust_target "${_COCA_RUST_TARGET_MAP_${COCA_TARGET_PROFILE}}")
    if(NOT _coca_rust_target)
        message(WARNING "[COCA Rust] No Rust target mapping for profile '${COCA_TARGET_PROFILE}'")
    endif()
else()
    # Fallback: host target
    if(CMAKE_HOST_WIN32)
        set(_coca_rust_target "x86_64-pc-windows-msvc")
    else()
        set(_coca_rust_target "x86_64-unknown-linux-gnu")
    endif()
endif()

set(COCA_RUST_TARGET "${_coca_rust_target}" CACHE STRING "Rust target triple for COCA profile" FORCE)

# ---------------------------------------------------------------------------
# 3. Determine linker for Rust based on profile
# ---------------------------------------------------------------------------
set(_COCA_BIN "${COCA_TOOLCHAIN_ROOT}/bin")
if(CMAKE_HOST_WIN32)
    set(_coca_exe ".exe")
else()
    set(_coca_exe "")
endif()

# Map Rust target → COCA linker
# Windows MSVC → lld-link
# Linux (gnu/musl) → ld.lld via clang (Rust needs a cc-like linker wrapper)
# MinGW → ld.lld via clang
# WASM → we let Rust use its built-in linker (rust-lld)
set(_coca_rust_linker "")
set(_coca_rust_linker_args "")

if(COCA_RUST_TARGET MATCHES "windows-msvc")
    set(_coca_rust_linker "${_COCA_BIN}/lld-link${_coca_exe}")
elseif(COCA_RUST_TARGET MATCHES "linux-gnu|linux-musl")
    # Rust for Linux cross-compilation needs a cc-like linker driver.
    # We use clang as the linker driver, which internally invokes ld.lld.
    set(_coca_rust_linker "${_COCA_BIN}/clang${_coca_exe}")
    # Determine sysroot for cross-linking
    if(COCA_RUST_TARGET MATCHES "x86_64.*linux-gnu")
        set(_coca_rust_sysroot "${COCA_TOOLCHAIN_ROOT}/sysroots/x86_64-linux-gnu")
    elseif(COCA_RUST_TARGET MATCHES "aarch64.*linux-gnu")
        set(_coca_rust_sysroot "${COCA_TOOLCHAIN_ROOT}/sysroots/aarch64-linux-gnu")
    elseif(COCA_RUST_TARGET MATCHES "x86_64.*linux-musl")
        set(_coca_rust_sysroot "${COCA_TOOLCHAIN_ROOT}/sysroots/x86_64-linux-musl")
    elseif(COCA_RUST_TARGET MATCHES "aarch64.*linux-musl")
        set(_coca_rust_sysroot "${COCA_TOOLCHAIN_ROOT}/sysroots/aarch64-linux-musl")
    endif()
elseif(COCA_RUST_TARGET MATCHES "windows-gnu")
    set(_coca_rust_linker "${_COCA_BIN}/ld.lld${_coca_exe}")
endif()
# wasm targets: Rust uses its bundled rust-lld, no override needed

set(COCA_RUST_LINKER "${_coca_rust_linker}" CACHE FILEPATH "Linker for Rust builds" FORCE)

# ---------------------------------------------------------------------------
# 4. Build the cargo environment
# ---------------------------------------------------------------------------
# Cargo environment variable names use upper-case target triple with
# hyphens replaced by underscores, e.g.:
#   CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER
function(_coca_rust_target_env_prefix TRIPLE OUT_VAR)
    string(TOUPPER "${TRIPLE}" _upper)
    string(REPLACE "-" "_" _env "${_upper}")
    set(${OUT_VAR} "CARGO_TARGET_${_env}" PARENT_SCOPE)
endfunction()

_coca_rust_target_env_prefix("${COCA_RUST_TARGET}" _coca_cargo_target_prefix)

# Collect all environment variables needed for cargo invocations
set(COCA_RUST_ENV
    "RUSTUP_HOME=${COCA_RUSTUP_HOME}"
    "CARGO_HOME=${COCA_CARGO_HOME}"
)

if(COCA_RUST_LINKER)
    list(APPEND COCA_RUST_ENV
        "${_coca_cargo_target_prefix}_LINKER=${COCA_RUST_LINKER}")
endif()

# For Linux cross-compilation, set CC and RUSTFLAGS for sysroot
if(DEFINED _coca_rust_sysroot)
    # Rust target triple for --target flag
    set(_coca_rust_triple_flag "${COCA_RUST_TARGET}")
    # clang as linker driver needs --target and --sysroot
    list(APPEND COCA_RUST_ENV
        "CC_${COCA_RUST_TARGET}=${_COCA_BIN}/clang${_coca_exe}"
        "AR_${COCA_RUST_TARGET}=${_COCA_BIN}/llvm-ar${_coca_exe}"
    )
    # RUSTFLAGS for linker args: sysroot, target, fuse-ld=lld
    set(_coca_rustflags
        "-C linker=${_COCA_BIN}/clang${_coca_exe}"
        "-C link-arg=--target=${COCA_RUST_TARGET}"
        "-C link-arg=--sysroot=${_coca_rust_sysroot}"
        "-C link-arg=-fuse-ld=lld"
    )
    if(COCA_RUST_TARGET MATCHES "musl")
        list(APPEND _coca_rustflags "-C link-arg=-static")
        list(APPEND _coca_rustflags "-C target-feature=+crt-static")
    endif()
    string(JOIN " " _coca_rustflags_str ${_coca_rustflags})
    list(APPEND COCA_RUST_ENV
        "${_coca_cargo_target_prefix}_RUSTFLAGS=${_coca_rustflags_str}")
endif()

# ---------------------------------------------------------------------------
# 5. Helper: Rust output directory and library naming
# ---------------------------------------------------------------------------
function(_coca_rust_output_dir BUILD_TYPE OUT_VAR)
    if(BUILD_TYPE STREQUAL "Debug" OR BUILD_TYPE STREQUAL "DEBUG")
        set(_profile "debug")
    else()
        set(_profile "release")
    endif()
    set(${OUT_VAR} "target/${COCA_RUST_TARGET}/${_profile}" PARENT_SCOPE)
endfunction()

function(_coca_rust_lib_filename NAME KIND OUT_VAR)
    # Cargo converts hyphens to underscores in output filenames
    string(REPLACE "-" "_" NAME "${NAME}")
    # KIND: staticlib or cdylib
    if(CMAKE_HOST_WIN32 AND COCA_RUST_TARGET MATCHES "windows-msvc")
        if(KIND STREQUAL "staticlib")
            set(${OUT_VAR} "${NAME}.lib" PARENT_SCOPE)
        else()
            set(${OUT_VAR} "${NAME}.dll" PARENT_SCOPE)
        endif()
    elseif(COCA_RUST_TARGET MATCHES "windows-gnu")
        if(KIND STREQUAL "staticlib")
            set(${OUT_VAR} "lib${NAME}.a" PARENT_SCOPE)
        else()
            set(${OUT_VAR} "${NAME}.dll" PARENT_SCOPE)
        endif()
    else()
        # Linux / WASM
        if(KIND STREQUAL "staticlib")
            set(${OUT_VAR} "lib${NAME}.a" PARENT_SCOPE)
        else()
            set(${OUT_VAR} "lib${NAME}.so" PARENT_SCOPE)
        endif()
    endif()
endfunction()

# ---------------------------------------------------------------------------
# 6. coca_rust_staticlib() — Build a Rust crate as a static library
# ---------------------------------------------------------------------------
#
# coca_rust_staticlib(
#     NAME <import_name>          # CMake target name (also used for linking)
#     CRATE_DIR <path>            # Path to the Rust crate (contains Cargo.toml)
#     [CRATE_NAME <name>]         # Cargo package name if different from NAME
#     [FEATURES <feat1;feat2>]    # Cargo features to enable
#     [ALL_FEATURES]              # Enable all features
#     [NO_DEFAULT_FEATURES]       # Disable default features
# )
#
# Creates an IMPORTED STATIC library target that can be linked with
# target_link_libraries().
#
function(coca_rust_staticlib)
    cmake_parse_arguments(RS
        "ALL_FEATURES;NO_DEFAULT_FEATURES"
        "NAME;CRATE_DIR;CRATE_NAME"
        "FEATURES"
        ${ARGN}
    )

    if(NOT RS_NAME)
        message(FATAL_ERROR "coca_rust_staticlib: NAME is required")
    endif()
    if(NOT RS_CRATE_DIR)
        message(FATAL_ERROR "coca_rust_staticlib: CRATE_DIR is required")
    endif()
    if(NOT RS_CRATE_NAME)
        set(RS_CRATE_NAME "${RS_NAME}")
    endif()

    _coca_rust_build_crate(
        NAME "${RS_NAME}"
        CRATE_DIR "${RS_CRATE_DIR}"
        CRATE_NAME "${RS_CRATE_NAME}"
        KIND "staticlib"
        FEATURES "${RS_FEATURES}"
        ALL_FEATURES "${RS_ALL_FEATURES}"
        NO_DEFAULT_FEATURES "${RS_NO_DEFAULT_FEATURES}"
    )
endfunction()

# ---------------------------------------------------------------------------
# 7. coca_rust_cdylib() — Build a Rust crate as a shared library
# ---------------------------------------------------------------------------
function(coca_rust_cdylib)
    cmake_parse_arguments(RS
        "ALL_FEATURES;NO_DEFAULT_FEATURES"
        "NAME;CRATE_DIR;CRATE_NAME"
        "FEATURES"
        ${ARGN}
    )

    if(NOT RS_NAME)
        message(FATAL_ERROR "coca_rust_cdylib: NAME is required")
    endif()
    if(NOT RS_CRATE_DIR)
        message(FATAL_ERROR "coca_rust_cdylib: CRATE_DIR is required")
    endif()
    if(NOT RS_CRATE_NAME)
        set(RS_CRATE_NAME "${RS_NAME}")
    endif()

    _coca_rust_build_crate(
        NAME "${RS_NAME}"
        CRATE_DIR "${RS_CRATE_DIR}"
        CRATE_NAME "${RS_CRATE_NAME}"
        KIND "cdylib"
        FEATURES "${RS_FEATURES}"
        ALL_FEATURES "${RS_ALL_FEATURES}"
        NO_DEFAULT_FEATURES "${RS_NO_DEFAULT_FEATURES}"
    )
endfunction()

# ---------------------------------------------------------------------------
# 8. coca_rust_bin() — Build a Rust binary crate
# ---------------------------------------------------------------------------
function(coca_rust_bin)
    cmake_parse_arguments(RS
        "ALL_FEATURES;NO_DEFAULT_FEATURES"
        "NAME;CRATE_DIR;CRATE_NAME"
        "FEATURES"
        ${ARGN}
    )

    if(NOT RS_NAME)
        message(FATAL_ERROR "coca_rust_bin: NAME is required")
    endif()
    if(NOT RS_CRATE_DIR)
        message(FATAL_ERROR "coca_rust_bin: CRATE_DIR is required")
    endif()
    if(NOT RS_CRATE_NAME)
        set(RS_CRATE_NAME "${RS_NAME}")
    endif()

    _coca_rust_build_crate(
        NAME "${RS_NAME}"
        CRATE_DIR "${RS_CRATE_DIR}"
        CRATE_NAME "${RS_CRATE_NAME}"
        KIND "bin"
        FEATURES "${RS_FEATURES}"
        ALL_FEATURES "${RS_ALL_FEATURES}"
        NO_DEFAULT_FEATURES "${RS_NO_DEFAULT_FEATURES}"
    )
endfunction()

# ---------------------------------------------------------------------------
# 9. Internal: _coca_rust_build_crate() — core cargo build logic
# ---------------------------------------------------------------------------
function(_coca_rust_build_crate)
    cmake_parse_arguments(RS
        "ALL_FEATURES;NO_DEFAULT_FEATURES"
        "NAME;CRATE_DIR;CRATE_NAME;KIND"
        "FEATURES"
        ${ARGN}
    )

    # Determine cargo build type
    if(CMAKE_BUILD_TYPE MATCHES "^[Dd]ebug$" OR NOT CMAKE_BUILD_TYPE)
        set(_cargo_profile "dev")
        set(_cargo_subdir "debug")
        set(_cargo_release_flag "")
    else()
        set(_cargo_profile "release")
        set(_cargo_subdir "release")
        set(_cargo_release_flag "--release")
    endif()

    # Build the cargo command
    set(_cargo_cmd
        "${CMAKE_COMMAND}" -E env ${COCA_RUST_ENV}
        "${COCA_CARGO}" build
        --manifest-path "${RS_CRATE_DIR}/Cargo.toml"
        --target "${COCA_RUST_TARGET}"
        --target-dir "${CMAKE_CURRENT_BINARY_DIR}/rust-target"
    )
    if(_cargo_release_flag)
        list(APPEND _cargo_cmd "${_cargo_release_flag}")
    endif()
    if(RS_FEATURES)
        string(REPLACE ";" "," _feat_csv "${RS_FEATURES}")
        list(APPEND _cargo_cmd --features "${_feat_csv}")
    endif()
    if(RS_ALL_FEATURES)
        list(APPEND _cargo_cmd --all-features)
    endif()
    if(RS_NO_DEFAULT_FEATURES)
        list(APPEND _cargo_cmd --no-default-features)
    endif()

    # Output path
    set(_rust_out_dir "${CMAKE_CURRENT_BINARY_DIR}/rust-target/${COCA_RUST_TARGET}/${_cargo_subdir}")

    # Cargo converts hyphens to underscores in output filenames
    string(REPLACE "-" "_" _rs_out_name "${RS_CRATE_NAME}")

    if(RS_KIND STREQUAL "bin")
        # Binary output
        if(COCA_RUST_TARGET MATCHES "windows")
            set(_bin_name "${_rs_out_name}.exe")
        elseif(COCA_RUST_TARGET MATCHES "wasm")
            set(_bin_name "${_rs_out_name}.wasm")
        else()
            set(_bin_name "${_rs_out_name}")
        endif()
        set(_output_file "${_rust_out_dir}/${_bin_name}")

        add_custom_command(
            OUTPUT "${_output_file}"
            COMMAND ${_cargo_cmd}
            WORKING_DIRECTORY "${RS_CRATE_DIR}"
            COMMENT "[COCA Rust] Building bin '${RS_NAME}' for ${COCA_RUST_TARGET} (${_cargo_profile})"
            USES_TERMINAL
        )
        add_custom_target(${RS_NAME} ALL DEPENDS "${_output_file}")
        set_target_properties(${RS_NAME} PROPERTIES
            COCA_RUST_OUTPUT "${_output_file}"
            COCA_RUST_KIND "bin"
        )

    elseif(RS_KIND STREQUAL "staticlib")
        _coca_rust_lib_filename("${RS_CRATE_NAME}" "staticlib" _lib_name)
        set(_output_file "${_rust_out_dir}/${_lib_name}")

        add_custom_command(
            OUTPUT "${_output_file}"
            COMMAND ${_cargo_cmd}
            WORKING_DIRECTORY "${RS_CRATE_DIR}"
            COMMENT "[COCA Rust] Building staticlib '${RS_NAME}' for ${COCA_RUST_TARGET} (${_cargo_profile})"
            USES_TERMINAL
        )
        # Create an IMPORTED static library so C/C++ targets can link it
        add_library(${RS_NAME} STATIC IMPORTED GLOBAL)
        set_target_properties(${RS_NAME} PROPERTIES
            IMPORTED_LOCATION "${_output_file}"
            COCA_RUST_KIND "staticlib"
        )
        # Custom target to trigger the build
        add_custom_target(${RS_NAME}_build ALL DEPENDS "${_output_file}")
        add_dependencies(${RS_NAME} ${RS_NAME}_build)

        # Rust staticlibs on Windows MSVC need these system libs
        if(COCA_RUST_TARGET MATCHES "windows-msvc")
            set_target_properties(${RS_NAME} PROPERTIES
                INTERFACE_LINK_LIBRARIES "ws2_32;userenv;bcrypt;ntdll;advapi32"
            )
        elseif(COCA_RUST_TARGET MATCHES "linux")
            set_target_properties(${RS_NAME} PROPERTIES
                INTERFACE_LINK_LIBRARIES "dl;pthread;m"
            )
        endif()

    elseif(RS_KIND STREQUAL "cdylib")
        _coca_rust_lib_filename("${RS_CRATE_NAME}" "cdylib" _lib_name)
        set(_output_file "${_rust_out_dir}/${_lib_name}")

        add_custom_command(
            OUTPUT "${_output_file}"
            COMMAND ${_cargo_cmd}
            WORKING_DIRECTORY "${RS_CRATE_DIR}"
            COMMENT "[COCA Rust] Building cdylib '${RS_NAME}' for ${COCA_RUST_TARGET} (${_cargo_profile})"
            USES_TERMINAL
        )
        add_library(${RS_NAME} SHARED IMPORTED GLOBAL)
        if(COCA_RUST_TARGET MATCHES "windows")
            # On Windows, .dll goes to IMPORTED_LOCATION and .dll.lib to IMPORTED_IMPLIB
            set(_implib_file "${_rust_out_dir}/${_rs_out_name}.dll.lib")
            set_target_properties(${RS_NAME} PROPERTIES
                IMPORTED_LOCATION "${_output_file}"
                IMPORTED_IMPLIB   "${_implib_file}"
            )
        else()
            set_target_properties(${RS_NAME} PROPERTIES
                IMPORTED_LOCATION "${_output_file}"
            )
        endif()
        set_target_properties(${RS_NAME} PROPERTIES COCA_RUST_KIND "cdylib")
        add_custom_target(${RS_NAME}_build ALL DEPENDS "${_output_file}")
        add_dependencies(${RS_NAME} ${RS_NAME}_build)
    endif()

endfunction()

# ---------------------------------------------------------------------------
# 10. Status message
# ---------------------------------------------------------------------------
if(NOT _COCA_RUST_MESSAGE_SHOWN)
    set(_COCA_RUST_MESSAGE_SHOWN TRUE CACHE INTERNAL "")
    execute_process(
        COMMAND "${COCA_RUSTC}" --version
        OUTPUT_VARIABLE _coca_rustc_ver
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
        RESULT_VARIABLE _coca_rustc_rc
    )
    if(_coca_rustc_rc EQUAL 0)
        message(STATUS "[COCA Rust] ${_coca_rustc_ver}")
    endif()
    message(STATUS "[COCA Rust] Target: ${COCA_RUST_TARGET}")
    if(COCA_RUST_LINKER)
        message(STATUS "[COCA Rust] Linker: ${COCA_RUST_LINKER}")
    endif()
endif()
