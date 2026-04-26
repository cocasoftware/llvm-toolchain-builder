# =============================================================================
# COCA PGO — CMake module for Profile-Guided Optimization workflow
# =============================================================================
#
# Provides a complete 3-stage PGO workflow using clang's instrumentation-based
# PGO, with optional VTune integration for workload analysis.
#
# Stages:
#   1. Instrument — build with -fprofile-generate (produces .profraw at runtime)
#   2. Collect    — run instrumented binary, merge .profraw → .profdata
#   3. Optimize   — rebuild with -fprofile-use=<merged.profdata>
#
# Usage in CMakeLists.txt:
#   include(<toolchain_root>/cmake/coca_pgo.cmake)
#
#   # === Per-target approach (fine-grained control) ===
#
#   # Stage 1: Add instrumentation flags to a target
#   coca_pgo_instrument(TARGET myapp)
#
#   # Stage 2: Create a collection target that runs the app and merges profiles
#   coca_pgo_collect(
#       TARGET myapp
#       COMMAND $<TARGET_FILE:myapp> --benchmark-mode
#       PROFRAW_DIR ${CMAKE_BINARY_DIR}/pgo_profiles/myapp
#   )
#   # Run: cmake --build . --target pgo_collect_myapp
#
#   # Stage 3: Create an optimized build target
#   coca_pgo_optimize(TARGET myapp)
#
#   # === Convenience: all-in-one ===
#   coca_pgo(
#       TARGET myapp
#       TRAINING_COMMAND $<TARGET_FILE:myapp> --benchmark-mode
#   )
#
# Supported profiles: win-x64, linux-x64, linux-arm64
# Not supported: wasm-*, musl (no profiling runtime), mingw (untested)
#
# =============================================================================

# Guard against multiple inclusion
if(DEFINED _COCA_PGO_INCLUDED)
    return()
endif()
set(_COCA_PGO_INCLUDED TRUE)

# ---------------------------------------------------------------------------
# Resolve toolchain root if not already set
# ---------------------------------------------------------------------------
if(NOT DEFINED COCA_TOOLCHAIN_ROOT)
    get_filename_component(COCA_TOOLCHAIN_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
endif()

# ---------------------------------------------------------------------------
# 1. Detect llvm-profdata (required for merging .profraw files)
# ---------------------------------------------------------------------------
set(_COCA_BIN_PGO "${COCA_TOOLCHAIN_ROOT}/bin")
if(CMAKE_HOST_WIN32)
    set(_COCA_PROFDATA "${_COCA_BIN_PGO}/llvm-profdata.exe")
else()
    set(_COCA_PROFDATA "${_COCA_BIN_PGO}/llvm-profdata")
endif()

if(NOT EXISTS "${_COCA_PROFDATA}")
    message(WARNING
        "${_COCA_CLR_YELLOW}[COCA-PGO]${_COCA_CLR_RESET} llvm-profdata not found at: ${_COCA_PROFDATA}")
    set(COCA_PGO_AVAILABLE FALSE CACHE BOOL "PGO available" FORCE)
    return()
endif()

set(COCA_PGO_AVAILABLE TRUE CACHE BOOL "PGO available" FORCE)
set(COCA_PROFDATA_EXE "${_COCA_PROFDATA}" CACHE FILEPATH "llvm-profdata" FORCE)

# Determine if we're using clang-cl (MSVC driver) or clang (GNU driver)
# This affects how PGO flags are passed
if(DEFINED COCA_TARGET_PROFILE)
    if(COCA_TARGET_PROFILE STREQUAL "win-x64")
        set(_COCA_PGO_DRIVER "clang-cl")
    else()
        set(_COCA_PGO_DRIVER "clang")
    endif()
else()
    # Fallback: detect from compiler
    get_filename_component(_compiler_name "${CMAKE_CXX_COMPILER}" NAME)
    if(_compiler_name MATCHES "clang-cl")
        set(_COCA_PGO_DRIVER "clang-cl")
    else()
        set(_COCA_PGO_DRIVER "clang")
    endif()
endif()

# Print status
if(NOT _COCA_PGO_MESSAGE_SHOWN)
    set(_COCA_PGO_MESSAGE_SHOWN TRUE CACHE INTERNAL "")
    message(STATUS
        "${_COCA_CLR_CYAN}[COCA-PGO]${_COCA_CLR_RESET} Available — driver: ${_COCA_CLR_BOLD}${_COCA_PGO_DRIVER}${_COCA_CLR_RESET}, profdata: ${_COCA_CLR_DIM}${COCA_PROFDATA_EXE}${_COCA_CLR_RESET}")
endif()

# ---------------------------------------------------------------------------
# Helper: get the correct compiler/linker flags for PGO stages
# ---------------------------------------------------------------------------
# clang-cl requires /clang: prefix for clang-specific flags
# clang uses flags directly

function(_coca_pgo_generate_flags OUT_COMPILE OUT_LINK PROFRAW_DIR)
    if(_COCA_PGO_DRIVER STREQUAL "clang-cl")
        set(${OUT_COMPILE} "/clang:-fprofile-generate=\"${PROFRAW_DIR}\"" PARENT_SCOPE)
        set(${OUT_LINK}    "/clang:-fprofile-generate=\"${PROFRAW_DIR}\"" PARENT_SCOPE)
    else()
        set(${OUT_COMPILE} "-fprofile-generate=${PROFRAW_DIR}" PARENT_SCOPE)
        set(${OUT_LINK}    "-fprofile-generate=${PROFRAW_DIR}" PARENT_SCOPE)
    endif()
endfunction()

function(_coca_pgo_use_flags OUT_COMPILE OUT_LINK PROFDATA_FILE)
    if(_COCA_PGO_DRIVER STREQUAL "clang-cl")
        set(${OUT_COMPILE} "/clang:-fprofile-use=\"${PROFDATA_FILE}\"" PARENT_SCOPE)
        set(${OUT_LINK}    "/clang:-fprofile-use=\"${PROFDATA_FILE}\"" PARENT_SCOPE)
    else()
        set(${OUT_COMPILE} "-fprofile-use=${PROFDATA_FILE}" PARENT_SCOPE)
        set(${OUT_LINK}    "-fprofile-use=${PROFDATA_FILE}" PARENT_SCOPE)
    endif()
endfunction()

# ---------------------------------------------------------------------------
# 2. coca_pgo_instrument() — Add instrumentation flags to a target
# ---------------------------------------------------------------------------
#
# coca_pgo_instrument(
#     TARGET <target>
#     [PROFRAW_DIR <dir>]    # default: ${CMAKE_BINARY_DIR}/pgo_profiles/<target>
# )
#
# Adds -fprofile-generate compile and link flags to the target.
# When the instrumented binary runs, it writes .profraw files to PROFRAW_DIR.

function(coca_pgo_instrument)
    cmake_parse_arguments(PARSE_ARGV 0 _PI "" "TARGET;PROFRAW_DIR" "")

    if(NOT _PI_TARGET)
        message(FATAL_ERROR "[COCA-PGO] coca_pgo_instrument: TARGET is required")
    endif()

    if(NOT COCA_PGO_AVAILABLE)
        message(WARNING "[COCA-PGO] PGO not available — skipping instrumentation for ${_PI_TARGET}")
        return()
    endif()

    if(NOT _PI_PROFRAW_DIR)
        set(_PI_PROFRAW_DIR "${CMAKE_BINARY_DIR}/pgo_profiles/${_PI_TARGET}")
    endif()

    # Store profraw dir as a target property for later stages
    set_target_properties(${_PI_TARGET} PROPERTIES
        COCA_PGO_PROFRAW_DIR "${_PI_PROFRAW_DIR}"
    )

    _coca_pgo_generate_flags(_compile_flag _link_flag "${_PI_PROFRAW_DIR}")

    target_compile_options(${_PI_TARGET} PRIVATE "${_compile_flag}")
    target_link_options(${_PI_TARGET} PRIVATE "${_link_flag}")

    # Ensure profraw directory exists at build time
    add_custom_command(TARGET ${_PI_TARGET} PRE_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory "${_PI_PROFRAW_DIR}"
        COMMENT "[COCA-PGO] Ensuring profile directory: ${_PI_PROFRAW_DIR}"
        VERBATIM
    )
endfunction()

# ---------------------------------------------------------------------------
# 3. coca_pgo_collect() — Run instrumented binary and merge profiles
# ---------------------------------------------------------------------------
#
# coca_pgo_collect(
#     TARGET <target>
#     [COMMAND <cmd> [args...]]   # training workload command
#     [PROFRAW_DIR <dir>]         # default: from target property or build dir
#     [PROFDATA_FILE <file>]      # default: ${CMAKE_BINARY_DIR}/pgo_profiles/<target>.profdata
# )
#
# Creates target: pgo_collect_<target>
# This target:
#   1. Cleans old .profraw files
#   2. Runs the training workload
#   3. Merges all .profraw → single .profdata using llvm-profdata merge

function(coca_pgo_collect)
    cmake_parse_arguments(PARSE_ARGV 0 _PC
        ""
        "TARGET;PROFRAW_DIR;PROFDATA_FILE"
        "COMMAND"
    )

    if(NOT _PC_TARGET)
        message(FATAL_ERROR "[COCA-PGO] coca_pgo_collect: TARGET is required")
    endif()

    if(NOT COCA_PGO_AVAILABLE)
        message(WARNING "[COCA-PGO] PGO not available — skipping collection for ${_PC_TARGET}")
        return()
    endif()

    # Resolve profraw dir
    if(NOT _PC_PROFRAW_DIR)
        get_target_property(_PC_PROFRAW_DIR ${_PC_TARGET} COCA_PGO_PROFRAW_DIR)
        if(NOT _PC_PROFRAW_DIR)
            set(_PC_PROFRAW_DIR "${CMAKE_BINARY_DIR}/pgo_profiles/${_PC_TARGET}")
        endif()
    endif()

    # Resolve profdata output
    if(NOT _PC_PROFDATA_FILE)
        set(_PC_PROFDATA_FILE "${CMAKE_BINARY_DIR}/pgo_profiles/${_PC_TARGET}.profdata")
    endif()

    # Store profdata path as target property
    set_target_properties(${_PC_TARGET} PROPERTIES
        COCA_PGO_PROFDATA_FILE "${_PC_PROFDATA_FILE}"
    )

    # Default training command: just run the target
    if(NOT _PC_COMMAND)
        set(_PC_COMMAND "$<TARGET_FILE:${_PC_TARGET}>")
    endif()

    # Create the collection target
    # Step 1: Clean old profraw files
    # Step 2: Run training workload
    # Step 3: Merge profraw → profdata
    add_custom_target(pgo_collect_${_PC_TARGET}
        # Clean old profiles
        COMMAND ${CMAKE_COMMAND} -E rm -rf "${_PC_PROFRAW_DIR}"
        COMMAND ${CMAKE_COMMAND} -E make_directory "${_PC_PROFRAW_DIR}"
        # Run training workload
        COMMAND ${_PC_COMMAND}
        # Merge profiles
        COMMAND "${COCA_PROFDATA_EXE}" merge
            -output="${_PC_PROFDATA_FILE}"
            "${_PC_PROFRAW_DIR}"
        DEPENDS ${_PC_TARGET}
        WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
        COMMENT "[COCA-PGO] Collecting profiles for ${_PC_TARGET}..."
        VERBATIM
    )
endfunction()

# ---------------------------------------------------------------------------
# 4. coca_pgo_optimize() — Add profile-use flags to a target
# ---------------------------------------------------------------------------
#
# coca_pgo_optimize(
#     TARGET <target>
#     [PROFDATA_FILE <file>]    # default: from target property or standard path
# )
#
# Adds -fprofile-use compile and link flags to the target.
# The profdata file must exist before building (run pgo_collect first).

function(coca_pgo_optimize)
    cmake_parse_arguments(PARSE_ARGV 0 _PO "" "TARGET;PROFDATA_FILE" "")

    if(NOT _PO_TARGET)
        message(FATAL_ERROR "[COCA-PGO] coca_pgo_optimize: TARGET is required")
    endif()

    if(NOT COCA_PGO_AVAILABLE)
        message(WARNING "[COCA-PGO] PGO not available — skipping optimization for ${_PO_TARGET}")
        return()
    endif()

    # Resolve profdata file
    if(NOT _PO_PROFDATA_FILE)
        get_target_property(_PO_PROFDATA_FILE ${_PO_TARGET} COCA_PGO_PROFDATA_FILE)
        if(NOT _PO_PROFDATA_FILE)
            set(_PO_PROFDATA_FILE "${CMAKE_BINARY_DIR}/pgo_profiles/${_PO_TARGET}.profdata")
        endif()
    endif()

    _coca_pgo_use_flags(_compile_flag _link_flag "${_PO_PROFDATA_FILE}")

    target_compile_options(${_PO_TARGET} PRIVATE "${_compile_flag}")
    target_link_options(${_PO_TARGET} PRIVATE "${_link_flag}")
endfunction()

# ---------------------------------------------------------------------------
# 5. coca_pgo() — All-in-one convenience wrapper
# ---------------------------------------------------------------------------
#
# coca_pgo(
#     TARGET <target>
#     [TRAINING_COMMAND <cmd> [args...]]  # workload for profile collection
#     [PROFRAW_DIR <dir>]
#     [PROFDATA_FILE <file>]
#     [MODE instrument|optimize]          # default: instrument
# )
#
# MODE=instrument (default):
#   - Adds instrumentation flags to the target
#   - Creates pgo_collect_<target> custom target
#
# MODE=optimize:
#   - Adds profile-use flags to the target
#   - Expects profdata file to exist (from a previous instrument+collect cycle)
#
# Typical workflow:
#   1. Configure with MODE=instrument (or default)
#   2. Build the target
#   3. Run: cmake --build . --target pgo_collect_<target>
#   4. Reconfigure with MODE=optimize
#   5. Rebuild the target — now PGO-optimized

function(coca_pgo)
    cmake_parse_arguments(PARSE_ARGV 0 _P
        ""
        "TARGET;PROFRAW_DIR;PROFDATA_FILE;MODE"
        "TRAINING_COMMAND"
    )

    if(NOT _P_TARGET)
        message(FATAL_ERROR "[COCA-PGO] coca_pgo: TARGET is required")
    endif()

    if(NOT _P_MODE)
        set(_P_MODE "instrument")
    endif()

    if(_P_MODE STREQUAL "instrument")
        # Stage 1: Instrument
        coca_pgo_instrument(
            TARGET ${_P_TARGET}
            PROFRAW_DIR "${_P_PROFRAW_DIR}"
        )

        # Stage 2: Create collection target
        set(_collect_args TARGET ${_P_TARGET})
        if(_P_TRAINING_COMMAND)
            list(APPEND _collect_args COMMAND ${_P_TRAINING_COMMAND})
        endif()
        if(_P_PROFRAW_DIR)
            list(APPEND _collect_args PROFRAW_DIR "${_P_PROFRAW_DIR}")
        endif()
        if(_P_PROFDATA_FILE)
            list(APPEND _collect_args PROFDATA_FILE "${_P_PROFDATA_FILE}")
        endif()
        coca_pgo_collect(${_collect_args})

    elseif(_P_MODE STREQUAL "optimize")
        # Stage 3: Optimize
        coca_pgo_optimize(
            TARGET ${_P_TARGET}
            PROFDATA_FILE "${_P_PROFDATA_FILE}"
        )

    else()
        message(FATAL_ERROR
            "[COCA-PGO] Unknown MODE: ${_P_MODE}. Use 'instrument' or 'optimize'.")
    endif()
endfunction()

# ---------------------------------------------------------------------------
# 6. coca_pgo_vtune_analyze() — VTune analysis of PGO-optimized binary
# ---------------------------------------------------------------------------
# Optional: requires coca_vtune.cmake to be included first.
# Runs VTune hotspots analysis on the optimized binary to verify PGO gains.
#
# coca_pgo_vtune_analyze(
#     TARGET <target>
#     [ANALYSIS_TYPE <type>]    # default: hotspots
#     [DURATION <seconds>]
#     [APP_ARGS <args...>]
# )
#
# Creates target: pgo_vtune_<target>

function(coca_pgo_vtune_analyze)
    cmake_parse_arguments(PARSE_ARGV 0 _PV
        ""
        "TARGET;ANALYSIS_TYPE;DURATION"
        "APP_ARGS"
    )

    if(NOT _PV_TARGET)
        message(FATAL_ERROR "[COCA-PGO] coca_pgo_vtune_analyze: TARGET is required")
    endif()

    # Check if VTune module is loaded
    if(NOT COCA_VTUNE_FOUND)
        message(WARNING
            "[COCA-PGO] VTune not found — skipping pgo_vtune_${_PV_TARGET}. "
            "Include coca_vtune.cmake first.")
        return()
    endif()

    if(NOT _PV_ANALYSIS_TYPE)
        set(_PV_ANALYSIS_TYPE "hotspots")
    endif()

    set(_result_dir "${CMAKE_BINARY_DIR}/vtune_results/pgo_${_PV_TARGET}")

    set(_vtune_args
        TARGET ${_PV_TARGET}
        ANALYSIS_TYPE "${_PV_ANALYSIS_TYPE}"
        RESULT_DIR "${_result_dir}"
    )
    if(_PV_DURATION)
        list(APPEND _vtune_args DURATION "${_PV_DURATION}")
    endif()
    if(_PV_APP_ARGS)
        list(APPEND _vtune_args APP_ARGS ${_PV_APP_ARGS})
    endif()

    coca_vtune_profile(${_vtune_args})

    # Rename the generated target from vtune_<target> to pgo_vtune_<target>
    # (coca_vtune_profile already created vtune_<target>, so we create an alias)
    add_custom_target(pgo_vtune_${_PV_TARGET}
        DEPENDS vtune_${_PV_TARGET}
        COMMENT "[COCA-PGO] VTune analysis of PGO-optimized ${_PV_TARGET}"
    )
endfunction()
