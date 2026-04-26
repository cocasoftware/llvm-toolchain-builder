# =============================================================================
# COCA VTune — CMake module for Intel VTune Profiler integration
# =============================================================================
#
# Provides:
#   - Auto-detection of VTune (bundled in tools/vtune, or system install)
#   - COCA::ittnotify INTERFACE library for ITT API source annotations
#   - coca_vtune_profile() function to create profiling targets
#
# Usage in CMakeLists.txt:
#   include(<toolchain_root>/cmake/coca_vtune.cmake)
#
#   # Link ITT API annotations into your target
#   target_link_libraries(myapp PRIVATE COCA::ittnotify)
#
#   # Create a VTune profiling target
#   coca_vtune_profile(
#       TARGET myapp
#       ANALYSIS_TYPE hotspots
#       DURATION 10
#       RESULT_DIR ${CMAKE_BINARY_DIR}/vtune_results
#   )
#   # Then: cmake --build . --target vtune_myapp
#
# Supported ANALYSIS_TYPE values:
#   hotspots, memory-consumption, threading, hpc-performance,
#   io, uarch-exploration, memory-access, platform-profiler
#
# =============================================================================

# Guard against multiple inclusion
if(DEFINED _COCA_VTUNE_INCLUDED)
    return()
endif()
set(_COCA_VTUNE_INCLUDED TRUE)

# ---------------------------------------------------------------------------
# Resolve toolchain root if not already set
# ---------------------------------------------------------------------------
if(NOT DEFINED COCA_TOOLCHAIN_ROOT)
    get_filename_component(COCA_TOOLCHAIN_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
endif()

# ---------------------------------------------------------------------------
# 1. Detect VTune installation
# ---------------------------------------------------------------------------
# Search order:
#   1. COCA_VTUNE_ROOT (user override)
#   2. Bundled: <toolchain>/tools/vtune/
#   3. Environment: VTUNE_PROFILER_DIR or VTUNE_PROFILER_2025_DIR
#   4. Default oneAPI paths

function(_coca_vtune_find_root OUT_VAR)
    # User override
    if(DEFINED COCA_VTUNE_ROOT AND IS_DIRECTORY "${COCA_VTUNE_ROOT}")
        set(${OUT_VAR} "${COCA_VTUNE_ROOT}" PARENT_SCOPE)
        return()
    endif()

    # Bundled in toolchain
    set(_bundled "${COCA_TOOLCHAIN_ROOT}/tools/vtune")
    if(IS_DIRECTORY "${_bundled}/bin64")
        set(${OUT_VAR} "${_bundled}" PARENT_SCOPE)
        return()
    endif()

    # Environment variables
    foreach(_env VTUNE_PROFILER_DIR VTUNE_PROFILER_2025_DIR)
        if(DEFINED ENV{${_env}} AND IS_DIRECTORY "$ENV{${_env}}")
            set(${OUT_VAR} "$ENV{${_env}}" PARENT_SCOPE)
            return()
        endif()
    endforeach()

    # Default oneAPI paths
    set(_candidates
        "C:/Program Files (x86)/Intel/oneAPI/vtune/latest"
        "C:/Program Files (x86)/Intel/oneAPI/vtune/2025.0"
        "/opt/intel/oneapi/vtune/latest"
    )
    foreach(_p IN LISTS _candidates)
        if(IS_DIRECTORY "${_p}/bin64" OR IS_DIRECTORY "${_p}/bin")
            set(${OUT_VAR} "${_p}" PARENT_SCOPE)
            return()
        endif()
    endforeach()

    set(${OUT_VAR} "" PARENT_SCOPE)
endfunction()

_coca_vtune_find_root(_COCA_VTUNE_ROOT)

if(NOT _COCA_VTUNE_ROOT)
    message(WARNING
        "${_COCA_CLR_YELLOW}[COCA-VTune]${_COCA_CLR_RESET} VTune not found. "
        "Set COCA_VTUNE_ROOT or install VTune to enable profiling.")
    set(COCA_VTUNE_FOUND FALSE CACHE BOOL "VTune found" FORCE)
    return()
endif()

set(COCA_VTUNE_FOUND TRUE CACHE BOOL "VTune found" FORCE)
set(COCA_VTUNE_ROOT "${_COCA_VTUNE_ROOT}" CACHE PATH "VTune root directory" FORCE)

# Resolve vtune CLI executable
if(CMAKE_HOST_WIN32)
    set(COCA_VTUNE_EXE "${COCA_VTUNE_ROOT}/bin64/vtune.exe" CACHE FILEPATH "VTune CLI" FORCE)
    set(_COCA_VTUNE_ARCH "64")
else()
    set(COCA_VTUNE_EXE "${COCA_VTUNE_ROOT}/bin64/vtune" CACHE FILEPATH "VTune CLI" FORCE)
    set(_COCA_VTUNE_ARCH "64")
endif()

if(NOT EXISTS "${COCA_VTUNE_EXE}")
    message(WARNING
        "${_COCA_CLR_YELLOW}[COCA-VTune]${_COCA_CLR_RESET} VTune CLI not found at: ${COCA_VTUNE_EXE}")
    set(COCA_VTUNE_FOUND FALSE CACHE BOOL "VTune found" FORCE)
    return()
endif()

# Print status
if(NOT _COCA_VTUNE_MESSAGE_SHOWN)
    set(_COCA_VTUNE_MESSAGE_SHOWN TRUE CACHE INTERNAL "")
    message(STATUS
        "${_COCA_CLR_CYAN}[COCA-VTune]${_COCA_CLR_RESET} Found: ${_COCA_CLR_DIM}${COCA_VTUNE_ROOT}${_COCA_CLR_RESET}")
endif()

# ---------------------------------------------------------------------------
# 2. ITT API — COCA::ittnotify INTERFACE library
# ---------------------------------------------------------------------------
# The ITT (Instrumentation and Tracing Technology) API allows source-level
# annotations: __itt_domain_create, __itt_task_begin/end, __itt_frame, etc.
# When VTune is not attached, ITT calls are near-zero overhead (stub).

set(_COCA_VTUNE_INCLUDE "${COCA_VTUNE_ROOT}/include")
set(_COCA_VTUNE_LIB_DIR "${COCA_VTUNE_ROOT}/lib${_COCA_VTUNE_ARCH}")
set(_COCA_VTUNE_SDK_LIB_DIR "${COCA_VTUNE_ROOT}/sdk/lib${_COCA_VTUNE_ARCH}")

if(NOT TARGET COCA::ittnotify)
    add_library(coca_ittnotify INTERFACE)
    add_library(COCA::ittnotify ALIAS coca_ittnotify)

    # Include path
    if(IS_DIRECTORY "${_COCA_VTUNE_INCLUDE}")
        target_include_directories(coca_ittnotify INTERFACE "${_COCA_VTUNE_INCLUDE}")
    endif()

    # Link library — prefer lib64/libittnotify.lib, fallback to sdk/lib64/
    if(EXISTS "${_COCA_VTUNE_LIB_DIR}/libittnotify.lib")
        target_link_libraries(coca_ittnotify INTERFACE "${_COCA_VTUNE_LIB_DIR}/libittnotify.lib")
    elseif(EXISTS "${_COCA_VTUNE_SDK_LIB_DIR}/libittnotify.lib")
        target_link_libraries(coca_ittnotify INTERFACE "${_COCA_VTUNE_SDK_LIB_DIR}/libittnotify.lib")
    elseif(EXISTS "${_COCA_VTUNE_LIB_DIR}/libittnotify.a")
        target_link_libraries(coca_ittnotify INTERFACE "${_COCA_VTUNE_LIB_DIR}/libittnotify.a")
    endif()

    # INTEL_NO_ITTNOTIFY_API — define this to compile out all ITT calls
    # (useful for release builds that don't need profiling hooks)
    # Users can: target_compile_definitions(myapp PRIVATE INTEL_NO_ITTNOTIFY_API)
endif()

# ---------------------------------------------------------------------------
# 3. JIT Profiling API — COCA::jitprofiling INTERFACE library
# ---------------------------------------------------------------------------
# For JIT compilers: register dynamically generated code with VTune so it
# appears with symbols in the profiler.

if(NOT TARGET COCA::jitprofiling)
    add_library(coca_jitprofiling INTERFACE)
    add_library(COCA::jitprofiling ALIAS coca_jitprofiling)

    if(IS_DIRECTORY "${_COCA_VTUNE_INCLUDE}")
        target_include_directories(coca_jitprofiling INTERFACE "${_COCA_VTUNE_INCLUDE}")
    endif()

    if(EXISTS "${_COCA_VTUNE_LIB_DIR}/jitprofiling.lib")
        target_link_libraries(coca_jitprofiling INTERFACE "${_COCA_VTUNE_LIB_DIR}/jitprofiling.lib")
    elseif(EXISTS "${_COCA_VTUNE_SDK_LIB_DIR}/jitprofiling.lib")
        target_link_libraries(coca_jitprofiling INTERFACE "${_COCA_VTUNE_SDK_LIB_DIR}/jitprofiling.lib")
    elseif(EXISTS "${_COCA_VTUNE_LIB_DIR}/libjitprofiling.a")
        target_link_libraries(coca_jitprofiling INTERFACE "${_COCA_VTUNE_LIB_DIR}/libjitprofiling.a")
    endif()
endif()

# ---------------------------------------------------------------------------
# 4. coca_vtune_profile() — Create a VTune profiling custom target
# ---------------------------------------------------------------------------
#
# coca_vtune_profile(
#     TARGET <target>
#     [ANALYSIS_TYPE <type>]      # default: hotspots
#     [DURATION <seconds>]        # default: unlimited (until app exits)
#     [RESULT_DIR <dir>]          # default: ${CMAKE_BINARY_DIR}/vtune_results/<target>
#     [EXTRA_ARGS <args...>]      # additional vtune CLI arguments
#     [APP_ARGS <args...>]        # arguments passed to the profiled application
# )
#
# Creates target: vtune_<target>
# Usage: cmake --build <build_dir> --target vtune_<target>

function(coca_vtune_profile)
    cmake_parse_arguments(PARSE_ARGV 0 _VT
        ""
        "TARGET;ANALYSIS_TYPE;DURATION;RESULT_DIR"
        "EXTRA_ARGS;APP_ARGS"
    )

    if(NOT _VT_TARGET)
        message(FATAL_ERROR "[COCA-VTune] coca_vtune_profile: TARGET is required")
    endif()

    if(NOT COCA_VTUNE_FOUND)
        message(WARNING "[COCA-VTune] VTune not found — skipping vtune_${_VT_TARGET} target")
        return()
    endif()

    # Defaults
    if(NOT _VT_ANALYSIS_TYPE)
        set(_VT_ANALYSIS_TYPE "hotspots")
    endif()
    if(NOT _VT_RESULT_DIR)
        set(_VT_RESULT_DIR "${CMAKE_BINARY_DIR}/vtune_results/${_VT_TARGET}")
    endif()

    # Build vtune command
    set(_vtune_cmd
        "${COCA_VTUNE_EXE}"
        -collect "${_VT_ANALYSIS_TYPE}"
        -result-dir "${_VT_RESULT_DIR}"
        -quiet
    )

    if(_VT_DURATION)
        list(APPEND _vtune_cmd -duration "${_VT_DURATION}")
    endif()

    if(_VT_EXTRA_ARGS)
        list(APPEND _vtune_cmd ${_VT_EXTRA_ARGS})
    endif()

    # Application to profile
    list(APPEND _vtune_cmd -- "$<TARGET_FILE:${_VT_TARGET}>")

    if(_VT_APP_ARGS)
        list(APPEND _vtune_cmd ${_VT_APP_ARGS})
    endif()

    add_custom_target(vtune_${_VT_TARGET}
        COMMAND ${_vtune_cmd}
        DEPENDS ${_VT_TARGET}
        WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
        COMMENT "[COCA-VTune] Profiling ${_VT_TARGET} (${_VT_ANALYSIS_TYPE})..."
        VERBATIM
    )
endfunction()

# ---------------------------------------------------------------------------
# 5. coca_vtune_report() — Generate a text report from VTune results
# ---------------------------------------------------------------------------
#
# coca_vtune_report(
#     TARGET <target>
#     [RESULT_DIR <dir>]          # default: ${CMAKE_BINARY_DIR}/vtune_results/<target>
#     [REPORT_TYPE <type>]        # default: hotspots (summary, hotspots, hw-events, etc.)
#     [OUTPUT_FILE <file>]        # default: stdout (prints to build log)
# )
#
# Creates target: vtune_report_<target>

function(coca_vtune_report)
    cmake_parse_arguments(PARSE_ARGV 0 _VR
        ""
        "TARGET;RESULT_DIR;REPORT_TYPE;OUTPUT_FILE"
        ""
    )

    if(NOT _VR_TARGET)
        message(FATAL_ERROR "[COCA-VTune] coca_vtune_report: TARGET is required")
    endif()

    if(NOT COCA_VTUNE_FOUND)
        return()
    endif()

    if(NOT _VR_RESULT_DIR)
        set(_VR_RESULT_DIR "${CMAKE_BINARY_DIR}/vtune_results/${_VR_TARGET}")
    endif()
    if(NOT _VR_REPORT_TYPE)
        set(_VR_REPORT_TYPE "hotspots")
    endif()

    set(_report_cmd
        "${COCA_VTUNE_EXE}"
        -report "${_VR_REPORT_TYPE}"
        -result-dir "${_VR_RESULT_DIR}"
        -quiet
    )

    if(_VR_OUTPUT_FILE)
        list(APPEND _report_cmd -report-output "${_VR_OUTPUT_FILE}")
    endif()

    add_custom_target(vtune_report_${_VR_TARGET}
        COMMAND ${_report_cmd}
        WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
        COMMENT "[COCA-VTune] Generating ${_VR_REPORT_TYPE} report for ${_VR_TARGET}..."
        VERBATIM
    )
endfunction()
