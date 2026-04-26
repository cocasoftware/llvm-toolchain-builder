# =============================================================================
# COCA Bundle — CMake adapter for runtime dependency bundling
# =============================================================================
#
# Calls bundle.py to determine which runtime libraries must be shipped
# alongside executables built with the current COCA_TARGET_PROFILE.
#
# Usage in CMakeLists.txt:
#   include(<toolchain_root>/cmake/bundle.cmake)
#
#   # Bundle runtime libs next to an executable at install time
#   coca_bundle(TARGET myapp)
#
#   # Bundle into a custom directory
#   coca_bundle(TARGET myapp DESTINATION ${CMAKE_INSTALL_BINDIR})
#
#   # Bundle for a specific target with extra search dirs
#   coca_bundle(TARGET mylib
#       DESTINATION lib
#       EXTRA_DIRS "${MY_THIRD_PARTY}/bin")
#
#   # Just get the list of redist files (no install rules)
#   coca_bundle_list(OUTVAR _redist_files)
#
# =============================================================================

# Guard against multiple inclusion
if(DEFINED _COCA_BUNDLE_INCLUDED)
    return()
endif()
set(_COCA_BUNDLE_INCLUDED TRUE)

# ---------------------------------------------------------------------------
# Resolve toolchain root if not already set
# ---------------------------------------------------------------------------
if(NOT DEFINED COCA_TOOLCHAIN_ROOT)
    get_filename_component(COCA_TOOLCHAIN_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
endif()

# ---------------------------------------------------------------------------
# Locate Python — try toolchain-bundled first, then system
# ---------------------------------------------------------------------------
set(_COCA_BUNDLE_PY "${CMAKE_CURRENT_LIST_DIR}/bundle.py")

function(_coca_bundle_find_python OUT_VAR)
    # Toolchain-bundled Python (p2996 ships one)
    set(_candidates
        "${COCA_TOOLCHAIN_ROOT}/tools/python/python.exe"
        "${COCA_TOOLCHAIN_ROOT}/tools/python/python3"
        "${COCA_TOOLCHAIN_ROOT}/tools/python/python"
    )
    foreach(_p IN LISTS _candidates)
        if(EXISTS "${_p}")
            set(${OUT_VAR} "${_p}" PARENT_SCOPE)
            return()
        endif()
    endforeach()

    # System Python
    find_program(_sys_python NAMES python3 python)
    if(_sys_python)
        set(${OUT_VAR} "${_sys_python}" PARENT_SCOPE)
        return()
    endif()

    set(${OUT_VAR} "" PARENT_SCOPE)
endfunction()

# ---------------------------------------------------------------------------
# Internal: call bundle.py and parse the JSON output into a CMake list
# ---------------------------------------------------------------------------
function(_coca_bundle_query OUT_VAR)
    cmake_parse_arguments(PARSE_ARGV 1 _Q "" "" "CATEGORIES;EXTRA_DIRS")

    _coca_bundle_find_python(_python)
    if(NOT _python)
        message(WARNING "[COCA-Bundle] Python not found — cannot determine bundle files")
        set(${OUT_VAR} "" PARENT_SCOPE)
        return()
    endif()

    if(NOT DEFINED COCA_TARGET_PROFILE)
        message(WARNING "[COCA-Bundle] COCA_TARGET_PROFILE not set")
        set(${OUT_VAR} "" PARENT_SCOPE)
        return()
    endif()

    # Build command
    set(_cmd
        "${_python}" "${_COCA_BUNDLE_PY}"
        "--toolchain-root" "${COCA_TOOLCHAIN_ROOT}"
        "--profile" "${COCA_TARGET_PROFILE}"
    )

    # Categories
    if(_Q_CATEGORIES)
        list(APPEND _cmd "--categories" ${_Q_CATEGORIES})
    endif()

    # Extra dirs
    if(_Q_EXTRA_DIRS)
        list(APPEND _cmd "--extra-dirs" ${_Q_EXTRA_DIRS})
    endif()

    execute_process(
        COMMAND ${_cmd}
        OUTPUT_VARIABLE _json_output
        ERROR_VARIABLE  _err_output
        RESULT_VARIABLE _rc
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )

    if(NOT _rc EQUAL 0)
        message(WARNING "[COCA-Bundle] bundle.py failed (rc=${_rc}): ${_err_output}")
        set(${OUT_VAR} "" PARENT_SCOPE)
        return()
    endif()

    # Parse JSON array: strip brackets, quotes, commas → semicolon-separated CMake list
    # The output is a JSON array like: ["C:/path/a.dll", "C:/path/b.dll"]
    string(REPLACE "[" "" _json_output "${_json_output}")
    string(REPLACE "]" "" _json_output "${_json_output}")
    string(REPLACE "\"" "" _json_output "${_json_output}")
    string(REPLACE "," ";" _json_output "${_json_output}")
    string(STRIP "${_json_output}" _json_output)

    # Clean up each entry
    set(_files "")
    foreach(_entry IN LISTS _json_output)
        string(STRIP "${_entry}" _entry)
        if(_entry)
            list(APPEND _files "${_entry}")
        endif()
    endforeach()

    set(${OUT_VAR} "${_files}" PARENT_SCOPE)
endfunction()

# ---------------------------------------------------------------------------
# coca_bundle_list — populate a variable with all redist files for bundling
# ---------------------------------------------------------------------------
#
# coca_bundle_list(OUTVAR <variable>
#     [CATEGORIES <cat>...]     # Filter: vcruntime, ucrt, libc++, libunwind, etc.
#     [EXTRA_DIRS <dir>...]     # Additional directories to search
# )
#
function(coca_bundle_list)
    cmake_parse_arguments(PARSE_ARGV 0 _CBL "" "OUTVAR" "CATEGORIES;EXTRA_DIRS")

    if(NOT _CBL_OUTVAR)
        message(FATAL_ERROR "[COCA-Bundle] coca_bundle_list: OUTVAR is required")
    endif()

    _coca_bundle_query(_files
        CATEGORIES ${_CBL_CATEGORIES}
        EXTRA_DIRS ${_CBL_EXTRA_DIRS}
    )

    set(${_CBL_OUTVAR} "${_files}" PARENT_SCOPE)
endfunction()

# ---------------------------------------------------------------------------
# coca_bundle — install runtime libs alongside a target
# ---------------------------------------------------------------------------
#
# coca_bundle(TARGET <target>
#     [DESTINATION <dir>]       # Install destination (default: bin)
#     [CATEGORIES <cat>...]     # Filter categories
#     [EXTRA_DIRS <dir>...]     # Additional search directories
#     [COMPONENT <component>]   # Install component name
# )
#
function(coca_bundle)
    cmake_parse_arguments(PARSE_ARGV 0 _CB "" "TARGET;DESTINATION;COMPONENT" "CATEGORIES;EXTRA_DIRS")

    if(NOT _CB_TARGET)
        message(FATAL_ERROR "[COCA-Bundle] coca_bundle: TARGET is required")
    endif()

    if(NOT _CB_DESTINATION)
        set(_CB_DESTINATION "${CMAKE_INSTALL_BINDIR}")
        if(NOT _CB_DESTINATION)
            set(_CB_DESTINATION "bin")
        endif()
    endif()

    if(NOT _CB_COMPONENT)
        set(_CB_COMPONENT "runtime")
    endif()

    coca_bundle_list(
        OUTVAR _bundle_files
        CATEGORIES ${_CB_CATEGORIES}
        EXTRA_DIRS ${_CB_EXTRA_DIRS}
    )

    if(NOT _bundle_files)
        message(STATUS "[COCA-Bundle] No runtime libraries to bundle for ${COCA_TARGET_PROFILE}")
        return()
    endif()

    list(LENGTH _bundle_files _count)
    message(STATUS "[COCA-Bundle] Bundling ${_count} runtime libraries for ${_CB_TARGET}")

    install(FILES ${_bundle_files}
        DESTINATION "${_CB_DESTINATION}"
        COMPONENT "${_CB_COMPONENT}"
    )
endfunction()

# ---------------------------------------------------------------------------
# coca_bundle_copy — copy runtime libs to build output dir (for development)
# ---------------------------------------------------------------------------
#
# coca_bundle_copy(TARGET <target>
#     [CATEGORIES <cat>...]
#     [EXTRA_DIRS <dir>...]
# )
#
# Creates a post-build step that copies runtime libs next to the target binary.
#
function(coca_bundle_copy)
    cmake_parse_arguments(PARSE_ARGV 0 _CBC "" "TARGET" "CATEGORIES;EXTRA_DIRS")

    if(NOT _CBC_TARGET)
        message(FATAL_ERROR "[COCA-Bundle] coca_bundle_copy: TARGET is required")
    endif()

    coca_bundle_list(
        OUTVAR _bundle_files
        CATEGORIES ${_CBC_CATEGORIES}
        EXTRA_DIRS ${_CBC_EXTRA_DIRS}
    )

    if(NOT _bundle_files)
        return()
    endif()

    foreach(_file IN LISTS _bundle_files)
        get_filename_component(_fname "${_file}" NAME)
        add_custom_command(TARGET ${_CBC_TARGET} POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "${_file}"
                "$<TARGET_FILE_DIR:${_CBC_TARGET}>/${_fname}"
            COMMENT "[COCA-Bundle] Copying ${_fname}"
        )
    endforeach()
endfunction()
