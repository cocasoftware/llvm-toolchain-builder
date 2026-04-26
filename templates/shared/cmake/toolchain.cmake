# =============================================================================
# COCA Toolchain — Unified CMake Toolchain File
# =============================================================================
#
# Usage:
#   cmake -G Ninja -B build \
#       -DCMAKE_TOOLCHAIN_FILE=<toolchain_root>/cmake/toolchain.cmake \
#       -DCOCA_TARGET_PROFILE=<profile>
#
# Supported profiles:
#   win-x64           — Windows x64 (MSVC ABI, clang-cl driver)
#   win-x64-clang     — Windows x64 (MSVC ABI, clang/clang++ GNU driver)
#   linux-x64         — Linux x86_64 cross-compile (glibc)
#   linux-arm64       — Linux AArch64 cross-compile (glibc)
#   linux-x64-kylin   — Kylin OS x86_64 (shares linux-x64 sysroot)
#   linux-arm64-kylin — Kylin OS AArch64 (shares linux-arm64 sysroot)
#   linux-x64-musl    — Linux x86_64 fully-static (musl libc)
#   linux-arm64-musl  — Linux AArch64 fully-static (musl libc)
#   wasm-wasi         — WebAssembly WASI (standalone .wasm)
#   wasm-emscripten   — WebAssembly Emscripten (browser, delegates to emsdk)
#
# Optional variables:
#   COCA_TOOLCHAIN_ROOT        — Override auto-detected toolchain root
#   COCA_CXX_STANDARD          — C++ standard (default: 23)
#   COCA_C_STANDARD            — C standard (default: 23)
#   COCA_ENABLE_LTO            — Enable LTO (default: OFF)
#   COCA_ALLOW_AUTO_DETECTION  — Allow CMake to search host system (default: OFF)
#   COCA_FORTRAN_COMPILER      — Fortran compiler: ifort, flang, none, auto (default: auto)
#   COCA_ENABLE_VTUNE          — Enable VTune integration (default: OFF)
#   COCA_ENABLE_PGO            — Enable PGO workflow (default: OFF)
#   COCA_ENABLE_RUST           — Enable Rust integration (default: OFF)
#   COCA_VTUNE_ROOT            — Override VTune installation path
# =============================================================================

cmake_minimum_required(VERSION 3.21)

# ---------------------------------------------------------------------------
# 1. Resolve toolchain root
# ---------------------------------------------------------------------------
if(NOT DEFINED COCA_TOOLCHAIN_ROOT)
    get_filename_component(COCA_TOOLCHAIN_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
endif()
cmake_path(NORMAL_PATH COCA_TOOLCHAIN_ROOT)
set(COCA_TOOLCHAIN_ROOT "${COCA_TOOLCHAIN_ROOT}" CACHE PATH "COCA toolchain root" FORCE)

# ---------------------------------------------------------------------------
# ANSI color helpers (enabled when CMAKE_COLOR_DIAGNOSTICS is ON)
# ---------------------------------------------------------------------------
if(CMAKE_COLOR_DIAGNOSTICS)
    string(ASCII 27 _esc)
    set(_COCA_CLR_RESET   "${_esc}[0m")
    set(_COCA_CLR_BOLD    "${_esc}[1m")
    set(_COCA_CLR_DIM     "${_esc}[2m")
    set(_COCA_CLR_RED     "${_esc}[1;31m")
    set(_COCA_CLR_GREEN   "${_esc}[1;32m")
    set(_COCA_CLR_YELLOW  "${_esc}[1;33m")
    set(_COCA_CLR_CYAN    "${_esc}[1;36m")
    set(_COCA_CLR_WHITE   "${_esc}[1;37m")
else()
    set(_COCA_CLR_RESET   "")
    set(_COCA_CLR_BOLD    "")
    set(_COCA_CLR_DIM     "")
    set(_COCA_CLR_RED     "")
    set(_COCA_CLR_GREEN   "")
    set(_COCA_CLR_YELLOW  "")
    set(_COCA_CLR_CYAN    "")
    set(_COCA_CLR_WHITE   "")
endif()

# ---------------------------------------------------------------------------
# Disable C++20 module dependency scanning (clang-scan-deps).
# The scanner chokes on third-party headers (stdexec __has_builtin,
# googletest cxxabi.h) during cross-compilation.  No COCA projects use
# C++20 modules yet; re-enable when module support is needed.
# ---------------------------------------------------------------------------
set(CMAKE_CXX_SCAN_FOR_MODULES OFF)

# ---------------------------------------------------------------------------
# 2. Validate profile selection
# ---------------------------------------------------------------------------
if(NOT DEFINED COCA_TARGET_PROFILE)
    message(FATAL_ERROR
        "${_COCA_CLR_RED}>${_COCA_CLR_RESET} COCA_TARGET_PROFILE is not set.\n"
        "  Supported profiles: win-x64, win-x64-clang, linux-x64, linux-arm64,\n"
        "    linux-x64-kylin, linux-arm64-kylin,\n"
        "    linux-x64-musl, linux-arm64-musl,\n"
        "    win-x64-mingw-ucrt, win-x64-mingw-msvcrt,\n"
        "    wasm-wasi, wasm-emscripten")
endif()
set(COCA_TARGET_PROFILE "${COCA_TARGET_PROFILE}" CACHE STRING "COCA target profile" FORCE)

# Forward COCA variables to try_compile sub-projects
list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES
    COCA_TOOLCHAIN_ROOT
    COCA_TARGET_PROFILE
    COCA_CXX_STANDARD
    COCA_C_STANDARD
    COCA_ENABLE_LTO
    COCA_ALLOW_AUTO_DETECTION
    COCA_FORTRAN_COMPILER
    COCA_ENABLE_VTUNE
    COCA_ENABLE_PGO
    COCA_ENABLE_RUST
)

# (Messages deferred to after sandbox section so all print together)

# ---------------------------------------------------------------------------
# 3. Defaults for optional variables
# ---------------------------------------------------------------------------
if(NOT DEFINED COCA_CXX_STANDARD)
    set(COCA_CXX_STANDARD 23)
endif()
if(NOT DEFINED COCA_C_STANDARD)
    set(COCA_C_STANDARD 23)
endif()
if(NOT DEFINED COCA_ENABLE_LTO)
    set(COCA_ENABLE_LTO OFF)
endif()
if(NOT DEFINED COCA_FORTRAN_COMPILER)
    set(COCA_FORTRAN_COMPILER "auto")
endif()
if(NOT DEFINED COCA_ENABLE_VTUNE)
    set(COCA_ENABLE_VTUNE OFF)
endif()
if(NOT DEFINED COCA_ENABLE_PGO)
    set(COCA_ENABLE_PGO OFF)
endif()
if(NOT DEFINED COCA_ENABLE_RUST)
    set(COCA_ENABLE_RUST OFF)
endif()

# ---------------------------------------------------------------------------
# 4. Sandbox enforcement — use ONLY toolchain executables and sysroots
#    Set COCA_ALLOW_AUTO_DETECTION=ON to disable these restrictions.
# ---------------------------------------------------------------------------
if(NOT DEFINED COCA_ALLOW_AUTO_DETECTION)
    set(COCA_ALLOW_AUTO_DETECTION OFF)
endif()

if(NOT COCA_ALLOW_AUTO_DETECTION)
    # 4a. Force bundled Ninja as the build program
    set(_COCA_TOOLS "${COCA_TOOLCHAIN_ROOT}/tools")
    if(CMAKE_HOST_WIN32)
        set(_COCA_NINJA_CANDIDATE "${_COCA_TOOLS}/ninja/ninja.exe")
    else()
        set(_COCA_NINJA_CANDIDATE "${_COCA_TOOLS}/ninja/ninja")
    endif()
    if(EXISTS "${_COCA_NINJA_CANDIDATE}")
        set(CMAKE_MAKE_PROGRAM "${_COCA_NINJA_CANDIDATE}" CACHE FILEPATH "" FORCE)
    endif()

    # 4b. Disable CMake's implicit host-system search paths
    set(CMAKE_FIND_USE_SYSTEM_ENVIRONMENT_PATH OFF CACHE BOOL "" FORCE)
    set(CMAKE_FIND_USE_CMAKE_ENVIRONMENT_PATH  OFF CACHE BOOL "" FORCE)
    set(CMAKE_FIND_USE_CMAKE_SYSTEM_PATH       OFF CACHE BOOL "" FORCE)
    set(CMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY OFF CACHE BOOL "" FORCE)
    set(CMAKE_FIND_USE_PACKAGE_REGISTRY        OFF CACHE BOOL "" FORCE)
    set(CMAKE_FIND_USE_PACKAGE_ROOT_PATH       ON  CACHE BOOL "" FORCE)
    set(CMAKE_FIND_USE_CMAKE_PATH              ON  CACHE BOOL "" FORCE)

    # 4c. Restrict program search to toolchain directories only
    #     (sysroot-based find_library/find_path handled per-profile via
    #      CMAKE_FIND_ROOT_PATH + CMAKE_FIND_ROOT_PATH_MODE_*)
    set(CMAKE_PROGRAM_PATH
        "${COCA_TOOLCHAIN_ROOT}/bin"
        "${_COCA_TOOLS}/ninja"
        CACHE STRING "" FORCE
    )
    # Discover cmake tool dirs (cmake-*/bin) for ctest, cpack, etc.
    if(IS_DIRECTORY "${_COCA_TOOLS}")
        file(GLOB _coca_cmake_dirs "${_COCA_TOOLS}/cmake*/bin")
        foreach(_d IN LISTS _coca_cmake_dirs)
            list(APPEND CMAKE_PROGRAM_PATH "${_d}")
        endforeach()
        unset(_coca_cmake_dirs)
        unset(_d)
    endif()

    # Register all bundled tool directories so find_program() can
    # locate git, python, graphviz (dot), coca, jfrog, cargo, perl, etc.
    # Each entry is guarded by IS_DIRECTORY so the toolchain file
    # works even when some optional tools are not installed.
    set(_COCA_TOOL_SEARCH_DIRS
        "${_COCA_TOOLS}/git/cmd"            # git.exe
        "${_COCA_TOOLS}/python"             # python.exe
        "${_COCA_TOOLS}/graphviz/bin"       # dot.exe
        "${_COCA_TOOLS}/coca"               # coca.exe, coca-tie-gen.exe
        "${_COCA_TOOLS}/jfrog"              # jf.exe
        "${_COCA_TOOLS}/rust/cargo/bin"     # cargo.exe, rustc.exe
        "${_COCA_TOOLS}/perl/perl/bin"      # perl.exe
        "${_COCA_TOOLS}/conan"              # conan.cmd
    )
    foreach(_d IN LISTS _COCA_TOOL_SEARCH_DIRS)
        if(IS_DIRECTORY "${_d}")
            list(APPEND CMAKE_PROGRAM_PATH "${_d}")
        endif()
    endforeach()
    unset(_COCA_TOOL_SEARCH_DIRS)
    unset(_d)

endif()

# 4d. Discover optional compilers (Fortran, ASM_MASM).
#     These are only *used* when the project calls enable_language() on them.
#     Setting them here just tells CMake where to find them if needed.
#     Without this, CMake may pick up stale system compilers from presets or
#     PATH that hang during compiler ID detection.
#
#     COCA_FORTRAN_COMPILER selects the Fortran compiler:
#       auto  — prefer ifort if available, else flang if available, else none
#       ifort — use bundled Intel Fortran (tools/ifort/)
#       flang — use LLVM Flang (bin/flang)
#       none  — disable Fortran
if(NOT COCA_ALLOW_AUTO_DETECTION)

    # --- Resolve which Fortran compiler to use ---
    set(_COCA_IFORT_DIR "${COCA_TOOLCHAIN_ROOT}/tools/ifort")
    if(CMAKE_HOST_WIN32)
        set(_COCA_IFORT_EXE "${_COCA_IFORT_DIR}/bin/ifort-wrapper.cmd")
        if(NOT EXISTS "${_COCA_IFORT_EXE}")
            set(_COCA_IFORT_EXE "${_COCA_IFORT_DIR}/bin/ifort.exe")
        endif()
        set(_COCA_FLANG_EXE "${COCA_TOOLCHAIN_ROOT}/bin/flang.exe")
    else()
        set(_COCA_IFORT_EXE "${_COCA_IFORT_DIR}/bin/ifort")
        set(_COCA_FLANG_EXE "${COCA_TOOLCHAIN_ROOT}/bin/flang")
    endif()
    set(_COCA_HAVE_IFORT FALSE)
    set(_COCA_HAVE_FLANG FALSE)
    if(EXISTS "${_COCA_IFORT_EXE}")
        set(_COCA_HAVE_IFORT TRUE)
    endif()
    if(EXISTS "${_COCA_FLANG_EXE}")
        set(_COCA_HAVE_FLANG TRUE)
    endif()

    # Resolve "auto" to a concrete choice
    set(_COCA_FORTRAN_CHOICE "${COCA_FORTRAN_COMPILER}")
    if(_COCA_FORTRAN_CHOICE STREQUAL "auto")
        if(_COCA_HAVE_IFORT)
            set(_COCA_FORTRAN_CHOICE "ifort")
        elseif(_COCA_HAVE_FLANG)
            set(_COCA_FORTRAN_CHOICE "flang")
        else()
            set(_COCA_FORTRAN_CHOICE "none")
        endif()
    endif()

    # --- ifort configuration ---
    if(_COCA_FORTRAN_CHOICE STREQUAL "ifort")
        if(NOT _COCA_HAVE_IFORT)
            message(WARNING "> COCA_FORTRAN_COMPILER=ifort but ifort not found at ${_COCA_IFORT_EXE}")
            set(CMAKE_Fortran_COMPILER "CMAKE_Fortran_COMPILER-NOTFOUND" CACHE FILEPATH "" FORCE)
        else()
            set(CMAKE_Fortran_COMPILER "${_COCA_IFORT_EXE}" CACHE FILEPATH "" FORCE)
            # Skip compiler ID detection — fortcom.exe from ComposerXE-2011 has a
            # memory leak bug that consumes all system memory during try_compile.
            # Setting ID_RUN + ID tells CMake the compiler identity without
            # invoking fortcom.  CMake will still load Compiler/Intel-Fortran.cmake
            # to get the correct preprocessing/module flags for Ninja dep scanning.
            set(CMAKE_Fortran_COMPILER_ID_RUN TRUE)
            set(CMAKE_Fortran_COMPILER_ID Intel)
            set(CMAKE_Fortran_COMPILER_FORCED TRUE)
            # Since FORCED skips loading Compiler/Intel-Fortran.cmake, we must
            # replicate its settings here.  The Ninja generator needs these for
            # Fortran dependency scanning (preprocessing + module detection).
            set(CMAKE_Fortran_COMPILE_WITH_DEFINES 1)
            set(CMAKE_Fortran_MODDIR_FLAG "-module:")
            set(CMAKE_Fortran_FORMAT_FIXED_FLAG "-fixed")
            set(CMAKE_Fortran_FORMAT_FREE_FLAG "-free")
            set(CMAKE_Fortran_COMPILE_OPTIONS_PREPROCESS_ON "-fpp")
            set(CMAKE_Fortran_COMPILE_OPTIONS_PREPROCESS_OFF "-nofpp")
            set(CMAKE_Fortran_SUBMODULE_SEP "@")
            set(CMAKE_Fortran_SUBMODULE_EXT ".smod")
            # Intel Fortran compile flags (from old-fortran reference).
            # /iface:nomixed_str_len_arg — string length not mixed with args
            # /iface:cref               — C-style calling convention
            # -Qvc8                     — MSVC 8 compatibility
            # -efi2                     — end-of-file handling
            # /assume:noprotect_constants — allow constants in CALL args
            # /MD                       — link with MSVCRT (dynamic CRT)
            # /LD                       — create DLL
            # /Qsave                    — save local variables (SAVE semantics)
            set(CMAKE_Fortran_FLAGS_INIT
                "/nologo /iface:nomixed_str_len_arg /iface:cref -Qvc8 -efi2 /assume:noprotect_constants /MD /LD /Qsave")
            set(CMAKE_Fortran_FLAGS_DEBUG_INIT   "/Od /Zi")
            set(CMAKE_Fortran_FLAGS_RELEASE_INIT "/O2")
            set(CMAKE_Fortran_FLAGS_RELWITHDEBINFO_INIT "/O2 /Zi")
            set(CMAKE_Fortran_FLAGS_MINSIZEREL_INIT "/O1")
            # Old ifort 2011 doesn't support -Fi<file>.  Use /E to preprocess
            # to stdout and redirect via the shell.
            set(CMAKE_Fortran_PREPROCESS_SOURCE
                "<CMAKE_Fortran_COMPILER> -fpp <DEFINES> <INCLUDES> <FLAGS> /E <SOURCE> > <PREPROCESSED_SOURCE>")
            set(CMAKE_Fortran_CREATE_PREPROCESSED_SOURCE
                "<CMAKE_Fortran_COMPILER> <DEFINES> <INCLUDES> <FLAGS> /E <SOURCE> > <PREPROCESSED_SOURCE>")
            set(CMAKE_Fortran_CREATE_ASSEMBLY_SOURCE
                "<CMAKE_Fortran_COMPILER> <DEFINES> <INCLUDES> <FLAGS> -S <SOURCE> -o <ASSEMBLY_SOURCE>")
        endif()

    # --- flang configuration ---
    elseif(_COCA_FORTRAN_CHOICE STREQUAL "flang")
        if(NOT _COCA_HAVE_FLANG)
            message(WARNING "> COCA_FORTRAN_COMPILER=flang but flang not found at ${_COCA_FLANG_EXE}")
            set(CMAKE_Fortran_COMPILER "CMAKE_Fortran_COMPILER-NOTFOUND" CACHE FILEPATH "" FORCE)
        else()
            set(CMAKE_Fortran_COMPILER "${_COCA_FLANG_EXE}" CACHE FILEPATH "" FORCE)
            # CMake ≥ 3.21 natively supports LLVMFlang — no forced ID needed.
            # flang uses clang-like flags (-O2, -g, -J <moddir>, etc.)
        endif()

    # --- none: disable Fortran ---
    elseif(_COCA_FORTRAN_CHOICE STREQUAL "none")
        set(CMAKE_Fortran_COMPILER "CMAKE_Fortran_COMPILER-NOTFOUND" CACHE FILEPATH "" FORCE)

    else()
        message(FATAL_ERROR
            "> Unknown COCA_FORTRAN_COMPILER value: '${COCA_FORTRAN_COMPILER}'\n"
            "       Valid values: auto, ifort, flang, none")
    endif()

    unset(_COCA_FORTRAN_CHOICE)
    unset(_COCA_HAVE_IFORT)
    unset(_COCA_HAVE_FLANG)
    unset(_COCA_IFORT_EXE)
    unset(_COCA_IFORT_DIR)
    unset(_COCA_FLANG_EXE)

    # ASM_MASM: use bundled ml64.exe (tools/ml64/) if available
    set(_COCA_ML64_DIR "${COCA_TOOLCHAIN_ROOT}/tools/ml64")
    if(CMAKE_HOST_WIN32)
        set(_COCA_ML64_EXE "${_COCA_ML64_DIR}/ml64.exe")
    else()
        set(_COCA_ML64_EXE "")
    endif()
    if(_COCA_ML64_EXE AND EXISTS "${_COCA_ML64_EXE}")
        set(CMAKE_ASM_MASM_COMPILER "${_COCA_ML64_EXE}" CACHE FILEPATH "" FORCE)
    else()
        set(CMAKE_ASM_MASM_COMPILER "CMAKE_ASM_MASM_COMPILER-NOTFOUND" CACHE FILEPATH "" FORCE)
    endif()
    unset(_COCA_ML64_EXE)
    unset(_COCA_ML64_DIR)
endif()

# 4e. Ensure toolchain bin/ and bundled tool directories are on the
#     process PATH so that compilers can find sibling tools (lld-link,
#     llvm-lib, etc.) and external commands (git, python, dot, etc.)
#     during compiler ID detection, try_compile, and FetchContent.
#     CMAKE_FIND_USE_* / CMAKE_PROGRAM_PATH only affect CMake's
#     find_*() commands — they do NOT affect execute_process() or the
#     compiler's own subprocess spawning.
if(CMAKE_HOST_WIN32)
    set(_COCA_PATH_SEP ";")
else()
    set(_COCA_PATH_SEP ":")
endif()
set(_COCA_EXTRA_PATH_DIRS
    "${COCA_TOOLCHAIN_ROOT}/bin"
    "${COCA_TOOLCHAIN_ROOT}/tools/git/cmd"
    "${COCA_TOOLCHAIN_ROOT}/tools/python"
    "${COCA_TOOLCHAIN_ROOT}/tools/graphviz/bin"
    "${COCA_TOOLCHAIN_ROOT}/tools/coca"
    "${COCA_TOOLCHAIN_ROOT}/tools/jfrog"
    "${COCA_TOOLCHAIN_ROOT}/tools/rust/cargo/bin"
    "${COCA_TOOLCHAIN_ROOT}/tools/perl/perl/bin"
    "${COCA_TOOLCHAIN_ROOT}/tools/conan"
)
foreach(_d IN LISTS _COCA_EXTRA_PATH_DIRS)
    if(IS_DIRECTORY "${_d}")
        string(FIND "$ENV{PATH}" "${_d}" _coca_d_in_path)
        if(_coca_d_in_path EQUAL -1)
            set(ENV{PATH} "${_d}${_COCA_PATH_SEP}$ENV{PATH}")
        endif()
        unset(_coca_d_in_path)
    endif()
endforeach()
unset(_COCA_EXTRA_PATH_DIRS)
unset(_d)
# Set up Intel Fortran environment only when ifort is selected.
# Without INCLUDE/LIB, fortcom.exe hangs or leaks memory because it
# cannot find its intrinsic modules and runtime libraries.
if(CMAKE_Fortran_COMPILER AND CMAKE_Fortran_COMPILER MATCHES "ifort")
    set(_COCA_IFORT_ROOT "${COCA_TOOLCHAIN_ROOT}/tools/ifort")
    if(IS_DIRECTORY "${_COCA_IFORT_ROOT}/bin")
        # PATH: ifort bin + redist DLLs (libifcoremd.dll, libmmd.dll, etc.)
        string(FIND "$ENV{PATH}" "${_COCA_IFORT_ROOT}/bin" _coca_ifort_in_path)
        if(_coca_ifort_in_path EQUAL -1)
            set(ENV{PATH} "${_COCA_IFORT_ROOT}/bin${_COCA_PATH_SEP}$ENV{PATH}")
        endif()
        unset(_coca_ifort_in_path)
        if(IS_DIRECTORY "${_COCA_IFORT_ROOT}/redist")
            string(FIND "$ENV{PATH}" "${_COCA_IFORT_ROOT}/redist" _coca_ifort_redist_in_path)
            if(_coca_ifort_redist_in_path EQUAL -1)
                set(ENV{PATH} "${_COCA_IFORT_ROOT}/redist${_COCA_PATH_SEP}$ENV{PATH}")
            endif()
            unset(_coca_ifort_redist_in_path)
        endif()
        # INCLUDE: Fortran intrinsic modules (.f90 interfaces, .h headers)
        if(IS_DIRECTORY "${_COCA_IFORT_ROOT}/include")
            set(ENV{INCLUDE} "${_COCA_IFORT_ROOT}/include${_COCA_PATH_SEP}${_COCA_IFORT_ROOT}/include/intel64${_COCA_PATH_SEP}$ENV{INCLUDE}")
        endif()
        # LIB: Fortran runtime libraries (libifcore*.lib, etc.)
        if(IS_DIRECTORY "${_COCA_IFORT_ROOT}/lib")
            set(ENV{LIB} "${_COCA_IFORT_ROOT}/lib${_COCA_PATH_SEP}$ENV{LIB}")
        endif()
    endif()
    unset(_COCA_IFORT_ROOT)
endif()

# Print all status messages once (toolchain files are loaded twice by CMake)
if(NOT _COCA_TOOLCHAIN_MESSAGE_SHOWN)
    set(_COCA_TOOLCHAIN_MESSAGE_SHOWN TRUE CACHE INTERNAL "")
    message(STATUS "${_COCA_CLR_CYAN}>${_COCA_CLR_RESET} Toolchain root: ${_COCA_CLR_BOLD}${COCA_TOOLCHAIN_ROOT}${_COCA_CLR_RESET}")
    message(STATUS "${_COCA_CLR_CYAN}>${_COCA_CLR_RESET} Target profile: ${_COCA_CLR_BOLD}${COCA_TARGET_PROFILE}${_COCA_CLR_RESET}")
    if(NOT COCA_ALLOW_AUTO_DETECTION)
        message(STATUS "${_COCA_CLR_CYAN}>${_COCA_CLR_RESET} Sandbox mode: ${_COCA_CLR_GREEN}ON${_COCA_CLR_RESET} ${_COCA_CLR_DIM}(host system search disabled)${_COCA_CLR_RESET}")
    else()
        message(STATUS "${_COCA_CLR_CYAN}>${_COCA_CLR_RESET} Sandbox mode: ${_COCA_CLR_YELLOW}OFF${_COCA_CLR_RESET} ${_COCA_CLR_DIM}(COCA_ALLOW_AUTO_DETECTION=ON)${_COCA_CLR_RESET}")
    endif()
    if(CMAKE_Fortran_COMPILER AND NOT CMAKE_Fortran_COMPILER MATCHES "NOTFOUND")
        if(CMAKE_Fortran_COMPILER MATCHES "ifort")
            set(_coca_fc_label "ifort")
        elseif(CMAKE_Fortran_COMPILER MATCHES "flang")
            set(_coca_fc_label "flang")
        else()
            set(_coca_fc_label "unknown")
        endif()
        message(STATUS "${_COCA_CLR_CYAN}>${_COCA_CLR_RESET} Fortran compiler: ${_COCA_CLR_BOLD}${_coca_fc_label}${_COCA_CLR_RESET} ${_COCA_CLR_DIM}(${CMAKE_Fortran_COMPILER})${_COCA_CLR_RESET}")
        unset(_coca_fc_label)
    endif()
    if(CMAKE_ASM_MASM_COMPILER AND NOT CMAKE_ASM_MASM_COMPILER MATCHES "NOTFOUND")
        message(STATUS "${_COCA_CLR_CYAN}>${_COCA_CLR_RESET} ASM_MASM compiler: ${_COCA_CLR_DIM}${CMAKE_ASM_MASM_COMPILER}${_COCA_CLR_RESET}")
    endif()
    if(COCA_ENABLE_VTUNE)
        message(STATUS "${_COCA_CLR_CYAN}>${_COCA_CLR_RESET} VTune integration: ${_COCA_CLR_GREEN}ON${_COCA_CLR_RESET}")
    endif()
    if(COCA_ENABLE_PGO)
        message(STATUS "${_COCA_CLR_CYAN}>${_COCA_CLR_RESET} PGO workflow: ${_COCA_CLR_GREEN}ON${_COCA_CLR_RESET}")
    endif()
    if(COCA_ENABLE_RUST)
        message(STATUS "${_COCA_CLR_CYAN}>${_COCA_CLR_RESET} Rust integration: ${_COCA_CLR_GREEN}ON${_COCA_CLR_RESET}")
    endif()
endif()

# ---------------------------------------------------------------------------
# 4f. Include optional CMake modules when enabled
# ---------------------------------------------------------------------------
if(COCA_ENABLE_VTUNE)
    include("${COCA_TOOLCHAIN_ROOT}/cmake/coca_vtune.cmake")
endif()
if(COCA_ENABLE_PGO)
    include("${COCA_TOOLCHAIN_ROOT}/cmake/coca_pgo.cmake")
endif()
if(COCA_ENABLE_RUST)
    include("${COCA_TOOLCHAIN_ROOT}/cmake/coca_rust.cmake")
endif()

# ---------------------------------------------------------------------------
# 5. Host executable suffix
# ---------------------------------------------------------------------------
if(CMAKE_HOST_WIN32)
    set(_COCA_EXE_SUFFIX ".exe")
else()
    set(_COCA_EXE_SUFFIX "")
endif()

# ---------------------------------------------------------------------------
# 6. Common compiler paths
# ---------------------------------------------------------------------------
set(_COCA_BIN "${COCA_TOOLCHAIN_ROOT}/bin")
set(_COCA_CLANG    "${_COCA_BIN}/clang${_COCA_EXE_SUFFIX}")
set(_COCA_CLANGXX  "${_COCA_BIN}/clang++${_COCA_EXE_SUFFIX}")
set(_COCA_CLANG_CL "${_COCA_BIN}/clang-cl${_COCA_EXE_SUFFIX}")
set(_COCA_LLD_LINK "${_COCA_BIN}/lld-link${_COCA_EXE_SUFFIX}")
set(_COCA_LD_LLD   "${_COCA_BIN}/ld.lld${_COCA_EXE_SUFFIX}")
set(_COCA_WASM_LD  "${_COCA_BIN}/wasm-ld${_COCA_EXE_SUFFIX}")
set(_COCA_AR       "${_COCA_BIN}/llvm-ar${_COCA_EXE_SUFFIX}")
set(_COCA_RANLIB   "${_COCA_BIN}/llvm-ranlib${_COCA_EXE_SUFFIX}")
set(_COCA_NM       "${_COCA_BIN}/llvm-nm${_COCA_EXE_SUFFIX}")
set(_COCA_OBJCOPY  "${_COCA_BIN}/llvm-objcopy${_COCA_EXE_SUFFIX}")
set(_COCA_OBJDUMP  "${_COCA_BIN}/llvm-objdump${_COCA_EXE_SUFFIX}")
set(_COCA_STRIP    "${_COCA_BIN}/llvm-strip${_COCA_EXE_SUFFIX}")
set(_COCA_RC       "${_COCA_BIN}/llvm-rc${_COCA_EXE_SUFFIX}")

# Common tool settings
set(CMAKE_AR       "${_COCA_AR}"      CACHE FILEPATH "" FORCE)
set(CMAKE_RANLIB   "${_COCA_RANLIB}"  CACHE FILEPATH "" FORCE)
set(CMAKE_NM       "${_COCA_NM}"      CACHE FILEPATH "" FORCE)
set(CMAKE_OBJCOPY  "${_COCA_OBJCOPY}" CACHE FILEPATH "" FORCE)
set(CMAKE_OBJDUMP  "${_COCA_OBJDUMP}" CACHE FILEPATH "" FORCE)
set(CMAKE_STRIP    "${_COCA_STRIP}"   CACHE FILEPATH "" FORCE)

# Language standards
set(CMAKE_CXX_STANDARD          ${COCA_CXX_STANDARD} CACHE STRING "" FORCE)
set(CMAKE_CXX_STANDARD_REQUIRED ON  CACHE BOOL "" FORCE)
set(CMAKE_C_STANDARD            ${COCA_C_STANDARD}   CACHE STRING "" FORCE)
set(CMAKE_C_STANDARD_REQUIRED   ON  CACHE BOOL "" FORCE)

# LTO
if(COCA_ENABLE_LTO)
    set(CMAKE_INTERPROCEDURAL_OPTIMIZATION ON CACHE BOOL "" FORCE)
endif()

# ---------------------------------------------------------------------------
# 6a. Binary identity injection (COCA_TOOLCHAIN_IDENT)
# ---------------------------------------------------------------------------
include("${COCA_TOOLCHAIN_ROOT}/cmake/coca_ident.cmake")

# =============================================================================
#  PROFILE: wasm-emscripten
#  Delegates to Emscripten's own toolchain file.
# =============================================================================
if(COCA_TARGET_PROFILE STREQUAL "wasm-emscripten")
    set(_COCA_EMSDK "${COCA_TOOLCHAIN_ROOT}/tools/emsdk")
    set(_COCA_EM_TOOLCHAIN
        "${_COCA_EMSDK}/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake")

    if(NOT EXISTS "${_COCA_EM_TOOLCHAIN}")
        message(FATAL_ERROR
            "${_COCA_CLR_RED}>${_COCA_CLR_RESET} Emscripten toolchain file not found at:\n"
            "  ${_COCA_EM_TOOLCHAIN}\n"
            "  Run: emsdk install latest && emsdk activate latest")
    endif()

    # Set Emscripten environment variables so emcc can find its SDK
    set(ENV{EMSDK} "${_COCA_EMSDK}")
    set(ENV{EM_CONFIG} "${_COCA_EMSDK}/.emscripten")

    message(STATUS "${_COCA_CLR_CYAN}>${_COCA_CLR_RESET} Delegating to Emscripten toolchain: ${_COCA_CLR_DIM}${_COCA_EM_TOOLCHAIN}${_COCA_CLR_RESET}")
    include("${_COCA_EM_TOOLCHAIN}")

    # Override standards after Emscripten include
    set(CMAKE_CXX_STANDARD          ${COCA_CXX_STANDARD} CACHE STRING "" FORCE)
    set(CMAKE_CXX_STANDARD_REQUIRED ON  CACHE BOOL "" FORCE)
    set(CMAKE_C_STANDARD            ${COCA_C_STANDARD}   CACHE STRING "" FORCE)
    set(CMAKE_C_STANDARD_REQUIRED   ON  CACHE BOOL "" FORCE)

    # Inject toolchain ident into Emscripten builds
    set(CMAKE_C_FLAGS_INIT   "${COCA_IDENT_C_FLAGS}" CACHE STRING "" FORCE)
    set(CMAKE_CXX_FLAGS_INIT "${COCA_IDENT_CXX_FLAGS}" CACHE STRING "" FORCE)
    return()
endif()

# =============================================================================
#  PROFILE: win-x64
# =============================================================================
if(COCA_TARGET_PROFILE STREQUAL "win-x64")
    set(CMAKE_SYSTEM_NAME Windows)
    set(CMAKE_SYSTEM_PROCESSOR AMD64)

    # Use clang-cl as the compiler driver (MSVC-compatible)
    set(CMAKE_C_COMPILER   "${_COCA_CLANG_CL}" CACHE FILEPATH "" FORCE)
    set(CMAKE_CXX_COMPILER "${_COCA_CLANG_CL}" CACHE FILEPATH "" FORCE)
    set(CMAKE_LINKER       "${_COCA_LLD_LINK}"  CACHE FILEPATH "" FORCE)
    set(CMAKE_RC_COMPILER  "${_COCA_RC}"        CACHE FILEPATH "" FORCE)

    # llvm-lib understands MSVC-style flags (/nologo /machine:x64) that CMake
    # passes when it detects clang-cl; llvm-ar does not.
    set(CMAKE_AR "${_COCA_BIN}/llvm-lib${_COCA_EXE_SUFFIX}" CACHE FILEPATH "" FORCE)

    # Sysroot paths
    set(_COCA_SYSROOT "${COCA_TOOLCHAIN_ROOT}/sysroots/x86_64-windows-msvc")
    set(_COCA_MSVC_INC "${_COCA_SYSROOT}/msvc/include")
    set(_COCA_SDK_INC  "${_COCA_SYSROOT}/sdk/Include/10.0.26100.0")
    set(_COCA_MSVC_LIB "${_COCA_SYSROOT}/msvc/lib/x64")
    set(_COCA_SDK_UCRT_LIB "${_COCA_SYSROOT}/sdk/Lib/10.0.26100.0/ucrt/x64")
    set(_COCA_SDK_UM_LIB   "${_COCA_SYSROOT}/sdk/Lib/10.0.26100.0/um/x64")

    # Include paths (clang-cl uses /imsvc for system includes)
    set(_COCA_WIN_COMPILE_FLAGS
        "/imsvc\"${_COCA_MSVC_INC}\""
        "/imsvc\"${_COCA_SDK_INC}/ucrt\""
        "/imsvc\"${_COCA_SDK_INC}/um\""
        "/imsvc\"${_COCA_SDK_INC}/shared\""
        "/imsvc\"${_COCA_SDK_INC}/winrt\""
    )
    string(JOIN " " _COCA_WIN_COMPILE_FLAGS_STR ${_COCA_WIN_COMPILE_FLAGS})

    set(CMAKE_C_FLAGS_INIT   "${_COCA_WIN_COMPILE_FLAGS_STR} ${COCA_IDENT_C_FLAGS}" CACHE STRING "" FORCE)
    set(CMAKE_CXX_FLAGS_INIT "${_COCA_WIN_COMPILE_FLAGS_STR} ${COCA_IDENT_CXX_FLAGS}" CACHE STRING "" FORCE)

    # Library paths
    set(_COCA_WIN_LINK_FLAGS
        "/LIBPATH:\"${_COCA_MSVC_LIB}\""
        "/LIBPATH:\"${_COCA_SDK_UCRT_LIB}\""
        "/LIBPATH:\"${_COCA_SDK_UM_LIB}\""
    )
    string(JOIN " " _COCA_WIN_LINK_FLAGS_STR ${_COCA_WIN_LINK_FLAGS})

    set(CMAKE_EXE_LINKER_FLAGS_INIT    "${_COCA_WIN_LINK_FLAGS_STR}" CACHE STRING "" FORCE)
    set(CMAKE_SHARED_LINKER_FLAGS_INIT "${_COCA_WIN_LINK_FLAGS_STR}" CACHE STRING "" FORCE)
    set(CMAKE_MODULE_LINKER_FLAGS_INIT "${_COCA_WIN_LINK_FLAGS_STR}" CACHE STRING "" FORCE)

    # Prevent CMake from searching host system paths
    set(CMAKE_FIND_ROOT_PATH "${_COCA_SYSROOT}")
    set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
    set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

    return()
endif()

# =============================================================================
#  PROFILE: win-x64-clang
#  Windows x64 using clang/clang++ GNU-like driver (MSVC ABI).
#  Same sysroot and CRT as win-x64, but uses -isystem / -L flags instead of
#  clang-cl's /imsvc / /LIBPATH.  Suitable for projects that expect GCC-style
#  command-line flags.
# =============================================================================
if(COCA_TARGET_PROFILE STREQUAL "win-x64-clang")
    set(CMAKE_SYSTEM_NAME Windows)
    set(CMAKE_SYSTEM_PROCESSOR AMD64)

    set(_COCA_TARGET_TRIPLE "x86_64-pc-windows-msvc")

    # Use clang/clang++ (GNU driver) with MSVC ABI target
    set(CMAKE_C_COMPILER   "${_COCA_CLANG}"   CACHE FILEPATH "" FORCE)
    set(CMAKE_CXX_COMPILER "${_COCA_CLANGXX}" CACHE FILEPATH "" FORCE)
    set(CMAKE_LINKER       "${_COCA_LLD_LINK}" CACHE FILEPATH "" FORCE)
    set(CMAKE_RC_COMPILER  "${_COCA_RC}"       CACHE FILEPATH "" FORCE)

    # llvm-ar for COFF archives — CMake generates GNU ar-style commands (qc)
    # for GNU-like compilers; llvm-lib only accepts MSVC syntax (/out:).
    set(CMAKE_AR     "${_COCA_BIN}/llvm-ar${_COCA_EXE_SUFFIX}"     CACHE FILEPATH "" FORCE)
    set(CMAKE_RANLIB "${_COCA_BIN}/llvm-ranlib${_COCA_EXE_SUFFIX}" CACHE FILEPATH "" FORCE)

    # Target triple
    set(CMAKE_C_COMPILER_TARGET   "${_COCA_TARGET_TRIPLE}" CACHE STRING "" FORCE)
    set(CMAKE_CXX_COMPILER_TARGET "${_COCA_TARGET_TRIPLE}" CACHE STRING "" FORCE)

    # Sysroot paths (same as win-x64)
    set(_COCA_SYSROOT "${COCA_TOOLCHAIN_ROOT}/sysroots/x86_64-windows-msvc")
    set(_COCA_MSVC_INC "${_COCA_SYSROOT}/msvc/include")
    set(_COCA_SDK_INC  "${_COCA_SYSROOT}/sdk/Include/10.0.26100.0")
    set(_COCA_MSVC_LIB "${_COCA_SYSROOT}/msvc/lib/x64")
    set(_COCA_SDK_UCRT_LIB "${_COCA_SYSROOT}/sdk/Lib/10.0.26100.0/ucrt/x64")
    set(_COCA_SDK_UM_LIB   "${_COCA_SYSROOT}/sdk/Lib/10.0.26100.0/um/x64")

    # libc++ paths (vcruntime ABI, built from LLVM 21.1.1)
    set(_COCA_LIBCXX_INC "${COCA_TOOLCHAIN_ROOT}/include/c++/v1")
    set(_COCA_LIBCXX_LIB "${COCA_TOOLCHAIN_ROOT}/lib")

    # Clang resource dir (provides <stddef.h> with max_align_t, intrinsics, etc.)
    set(_COCA_CLANG_RESOURCE_INC "${COCA_TOOLCHAIN_ROOT}/lib/clang/21/include")

    # Suppress auto-detected host MSVC/SDK includes so we use only our sysroot.
    # -nostdinc++   — suppress auto-detected C++ STL includes
    # -nostdlibinc  — suppress auto-detected C library includes (host MSVC SDK)
    # Then re-add: libc++ → clang resource dir → sysroot MSVC → sysroot SDK
    set(_COCA_WIN_CLANG_COMPILE_FLAGS
        "-nostdinc++"
        "-nostdlibinc"
        "-isystem \"${_COCA_LIBCXX_INC}\""
        "-isystem \"${_COCA_CLANG_RESOURCE_INC}\""
        "-isystem \"${_COCA_MSVC_INC}\""
        "-isystem \"${_COCA_SDK_INC}/ucrt\""
        "-isystem \"${_COCA_SDK_INC}/um\""
        "-isystem \"${_COCA_SDK_INC}/shared\""
        "-D_CRT_SECURE_NO_WARNINGS"
    )
    string(JOIN " " _COCA_WIN_CLANG_COMPILE_FLAGS_STR ${_COCA_WIN_CLANG_COMPILE_FLAGS})

    set(CMAKE_C_FLAGS_INIT   "${_COCA_WIN_CLANG_COMPILE_FLAGS_STR} ${COCA_IDENT_C_FLAGS}" CACHE STRING "" FORCE)
    set(CMAKE_CXX_FLAGS_INIT "${_COCA_WIN_CLANG_COMPILE_FLAGS_STR} ${COCA_IDENT_CXX_FLAGS}" CACHE STRING "" FORCE)

    # Library paths: libc++ + MSVC + SDK
    # lld-link is invoked internally by clang driver via -fuse-ld=lld;
    # -L flags are translated to /LIBPATH for lld-link.
    set(_COCA_WIN_CLANG_LINK_FLAGS
        "-fuse-ld=lld"
        "-L\"${_COCA_LIBCXX_LIB}\""
        "-L\"${_COCA_MSVC_LIB}\""
        "-L\"${_COCA_SDK_UCRT_LIB}\""
        "-L\"${_COCA_SDK_UM_LIB}\""
    )
    string(JOIN " " _COCA_WIN_CLANG_LINK_FLAGS_STR ${_COCA_WIN_CLANG_LINK_FLAGS})

    set(CMAKE_EXE_LINKER_FLAGS_INIT    "${_COCA_WIN_CLANG_LINK_FLAGS_STR}" CACHE STRING "" FORCE)
    set(CMAKE_SHARED_LINKER_FLAGS_INIT "${_COCA_WIN_CLANG_LINK_FLAGS_STR}" CACHE STRING "" FORCE)
    set(CMAKE_MODULE_LINKER_FLAGS_INIT "${_COCA_WIN_CLANG_LINK_FLAGS_STR}" CACHE STRING "" FORCE)

    # Prevent CMake from searching host system paths
    set(CMAKE_FIND_ROOT_PATH "${_COCA_SYSROOT}")
    set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
    set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

    return()
endif()

# =============================================================================
#  PROFILE: linux-x64, linux-arm64, linux-x64-kylin, linux-arm64-kylin
# =============================================================================
set(_COCA_LINUX_PROFILES "linux-x64;linux-arm64;linux-x64-kylin;linux-arm64-kylin")
if(COCA_TARGET_PROFILE IN_LIST _COCA_LINUX_PROFILES)
    set(CMAKE_SYSTEM_NAME Linux)

    # Determine target triple and sysroot based on profile
    if(COCA_TARGET_PROFILE MATCHES "arm64")
        set(_COCA_TARGET_TRIPLE "aarch64-unknown-linux-gnu")
        set(_COCA_SYSROOT "${COCA_TOOLCHAIN_ROOT}/sysroots/aarch64-linux-gnu")
        set(CMAKE_SYSTEM_PROCESSOR aarch64)
    else()
        set(_COCA_TARGET_TRIPLE "x86_64-unknown-linux-gnu")
        set(_COCA_SYSROOT "${COCA_TOOLCHAIN_ROOT}/sysroots/x86_64-linux-gnu")
        set(CMAKE_SYSTEM_PROCESSOR x86_64)
    endif()

    # Compiler
    set(CMAKE_C_COMPILER   "${_COCA_CLANG}"   CACHE FILEPATH "" FORCE)
    set(CMAKE_CXX_COMPILER "${_COCA_CLANGXX}" CACHE FILEPATH "" FORCE)
    set(CMAKE_LINKER       "${_COCA_LD_LLD}"  CACHE FILEPATH "" FORCE)

    # Target triple
    set(CMAKE_C_COMPILER_TARGET   "${_COCA_TARGET_TRIPLE}" CACHE STRING "" FORCE)
    set(CMAKE_CXX_COMPILER_TARGET "${_COCA_TARGET_TRIPLE}" CACHE STRING "" FORCE)

    # Sysroot
    set(CMAKE_SYSROOT "${_COCA_SYSROOT}" CACHE PATH "" FORCE)

    # LLVM runtime stack: libc++ / compiler-rt / libunwind
    # Use -nostdinc++ to suppress the toolchain's Windows libc++ headers
    # (include/c++/v1/) and explicitly point to the sysroot's Linux libc++
    # headers instead.  Without this, clang picks up the Windows MSVC-ABI
    # headers which are missing cxxabi.h and have ABI differences.
    set(_COCA_LINUX_COMPILE_FLAGS
        "-stdlib=libc++"
        "-nostdinc++"
        "-isystem" "${_COCA_SYSROOT}/usr/include/c++/v1"
    )
    set(_COCA_LINUX_LINK_FLAGS
        "-fuse-ld=lld"
        "-stdlib=libc++"
        "-rtlib=compiler-rt"
        "-unwindlib=libunwind"
    )
    string(JOIN " " _COCA_LINUX_COMPILE_FLAGS_STR ${_COCA_LINUX_COMPILE_FLAGS})
    string(JOIN " " _COCA_LINUX_LINK_FLAGS_STR    ${_COCA_LINUX_LINK_FLAGS})

    set(CMAKE_C_FLAGS_INIT   "${COCA_IDENT_C_FLAGS}" CACHE STRING "" FORCE)
    set(CMAKE_CXX_FLAGS_INIT "${_COCA_LINUX_COMPILE_FLAGS_STR} ${COCA_IDENT_CXX_FLAGS}" CACHE STRING "" FORCE)

    set(CMAKE_EXE_LINKER_FLAGS_INIT    "${_COCA_LINUX_LINK_FLAGS_STR}" CACHE STRING "" FORCE)
    set(CMAKE_SHARED_LINKER_FLAGS_INIT "${_COCA_LINUX_LINK_FLAGS_STR}" CACHE STRING "" FORCE)
    set(CMAKE_MODULE_LINKER_FLAGS_INIT "${_COCA_LINUX_LINK_FLAGS_STR}" CACHE STRING "" FORCE)

    # Restrict find_* to sysroot
    set(CMAKE_FIND_ROOT_PATH "${_COCA_SYSROOT}")
    set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
    set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

    return()
endif()

# =============================================================================
#  PROFILE: linux-x64-musl, linux-arm64-musl
#  Fully-static musl-based Linux targets for maximum portability.
# =============================================================================
set(_COCA_MUSL_PROFILES "linux-x64-musl;linux-arm64-musl")
if(COCA_TARGET_PROFILE IN_LIST _COCA_MUSL_PROFILES)
    set(CMAKE_SYSTEM_NAME Linux)

    if(COCA_TARGET_PROFILE MATCHES "arm64")
        set(_COCA_TARGET_TRIPLE "aarch64-unknown-linux-musl")
        set(_COCA_SYSROOT "${COCA_TOOLCHAIN_ROOT}/sysroots/aarch64-linux-musl")
        set(CMAKE_SYSTEM_PROCESSOR aarch64)
    else()
        set(_COCA_TARGET_TRIPLE "x86_64-unknown-linux-musl")
        set(_COCA_SYSROOT "${COCA_TOOLCHAIN_ROOT}/sysroots/x86_64-linux-musl")
        set(CMAKE_SYSTEM_PROCESSOR x86_64)
    endif()

    # Compiler
    set(CMAKE_C_COMPILER   "${_COCA_CLANG}"   CACHE FILEPATH "" FORCE)
    set(CMAKE_CXX_COMPILER "${_COCA_CLANGXX}" CACHE FILEPATH "" FORCE)
    set(CMAKE_LINKER       "${_COCA_LD_LLD}"  CACHE FILEPATH "" FORCE)

    # Target triple
    set(CMAKE_C_COMPILER_TARGET   "${_COCA_TARGET_TRIPLE}" CACHE STRING "" FORCE)
    set(CMAKE_CXX_COMPILER_TARGET "${_COCA_TARGET_TRIPLE}" CACHE STRING "" FORCE)

    # Sysroot
    set(CMAKE_SYSROOT "${_COCA_SYSROOT}" CACHE PATH "" FORCE)

    # LLVM runtime stack: libc++ / compiler-rt / libunwind, fully static
    # We add -L<sysroot>/usr/lib explicitly because clang's default library
    # search for musl targets may not include it.
    # Use -nostdinc++ to suppress toolchain's Windows libc++ headers and
    # use the sysroot's Linux libc++ headers instead (same as glibc profiles).
    set(_COCA_MUSL_COMPILE_FLAGS
        "-stdlib=libc++"
        "-nostdinc++"
        "-isystem" "${_COCA_SYSROOT}/usr/include/c++/v1"
    )
    set(_COCA_MUSL_LINK_FLAGS
        "-static"
        "-fuse-ld=lld"
        "-stdlib=libc++"
        "-lc++abi"
        "-rtlib=compiler-rt"
        "-unwindlib=libunwind"
        "-L${_COCA_SYSROOT}/usr/lib"
        "-L${_COCA_SYSROOT}/lib"
    )
    string(JOIN " " _COCA_MUSL_COMPILE_FLAGS_STR ${_COCA_MUSL_COMPILE_FLAGS})
    string(JOIN " " _COCA_MUSL_LINK_FLAGS_STR    ${_COCA_MUSL_LINK_FLAGS})

    set(CMAKE_C_FLAGS_INIT   "${COCA_IDENT_C_FLAGS}" CACHE STRING "" FORCE)
    set(CMAKE_CXX_FLAGS_INIT "${_COCA_MUSL_COMPILE_FLAGS_STR} ${COCA_IDENT_CXX_FLAGS}" CACHE STRING "" FORCE)

    set(CMAKE_EXE_LINKER_FLAGS_INIT    "${_COCA_MUSL_LINK_FLAGS_STR}" CACHE STRING "" FORCE)
    set(CMAKE_SHARED_LINKER_FLAGS_INIT "${_COCA_MUSL_LINK_FLAGS_STR}" CACHE STRING "" FORCE)
    set(CMAKE_MODULE_LINKER_FLAGS_INIT "${_COCA_MUSL_LINK_FLAGS_STR}" CACHE STRING "" FORCE)

    # Static-only: no shared libraries
    set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

    # Restrict find_* to sysroot
    set(CMAKE_FIND_ROOT_PATH "${_COCA_SYSROOT}")
    set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
    set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

    return()
endif()

# =============================================================================
#  PROFILE: win-x64-mingw-ucrt, win-x64-mingw-msvcrt
#  MinGW-w64 targets using llvm-mingw sysroot (libc++ from sysroot).
# =============================================================================
set(_COCA_MINGW_PROFILES "win-x64-mingw-ucrt;win-x64-mingw-msvcrt")
if(COCA_TARGET_PROFILE IN_LIST _COCA_MINGW_PROFILES)
    set(CMAKE_SYSTEM_NAME Windows)
    set(CMAKE_SYSTEM_PROCESSOR AMD64)

    set(_COCA_TARGET_TRIPLE "x86_64-w64-mingw32")

    # Select sysroot based on CRT variant
    if(COCA_TARGET_PROFILE STREQUAL "win-x64-mingw-ucrt")
        set(_COCA_SYSROOT "${COCA_TOOLCHAIN_ROOT}/sysroots/x86_64-w64-mingw32-ucrt")
    else()
        set(_COCA_SYSROOT "${COCA_TOOLCHAIN_ROOT}/sysroots/x86_64-w64-mingw32-msvcrt")
    endif()

    # Use clang/clang++ (GNU driver, not clang-cl)
    set(CMAKE_C_COMPILER   "${_COCA_CLANG}"   CACHE FILEPATH "" FORCE)
    set(CMAKE_CXX_COMPILER "${_COCA_CLANGXX}" CACHE FILEPATH "" FORCE)
    set(CMAKE_LINKER       "${_COCA_LD_LLD}"  CACHE FILEPATH "" FORCE)
    set(CMAKE_RC_COMPILER  "${_COCA_RC}"      CACHE FILEPATH "" FORCE)

    # Target triple
    set(CMAKE_C_COMPILER_TARGET   "${_COCA_TARGET_TRIPLE}" CACHE STRING "" FORCE)
    set(CMAKE_CXX_COMPILER_TARGET "${_COCA_TARGET_TRIPLE}" CACHE STRING "" FORCE)

    # Sysroot
    set(CMAKE_SYSROOT "${_COCA_SYSROOT}" CACHE PATH "" FORCE)

    # Compile flags: use libc++ from the sysroot (dynamic linking)
    set(_COCA_MINGW_COMPILE_FLAGS
        "-stdlib=libc++"
    )
    set(_COCA_MINGW_LINK_FLAGS
        "-fuse-ld=lld"
        "-stdlib=libc++"
        "-rtlib=compiler-rt"
        "-unwindlib=libunwind"
        "-L${_COCA_SYSROOT}/lib"
    )
    string(JOIN " " _COCA_MINGW_COMPILE_FLAGS_STR ${_COCA_MINGW_COMPILE_FLAGS})
    string(JOIN " " _COCA_MINGW_LINK_FLAGS_STR    ${_COCA_MINGW_LINK_FLAGS})

    set(CMAKE_C_FLAGS_INIT   "${COCA_IDENT_C_FLAGS}" CACHE STRING "" FORCE)
    set(CMAKE_CXX_FLAGS_INIT "${_COCA_MINGW_COMPILE_FLAGS_STR} ${COCA_IDENT_CXX_FLAGS}" CACHE STRING "" FORCE)

    set(CMAKE_EXE_LINKER_FLAGS_INIT    "${_COCA_MINGW_LINK_FLAGS_STR}" CACHE STRING "" FORCE)
    set(CMAKE_SHARED_LINKER_FLAGS_INIT "${_COCA_MINGW_LINK_FLAGS_STR}" CACHE STRING "" FORCE)
    set(CMAKE_MODULE_LINKER_FLAGS_INIT "${_COCA_MINGW_LINK_FLAGS_STR}" CACHE STRING "" FORCE)

    # Restrict find_* to sysroot
    set(CMAKE_FIND_ROOT_PATH "${_COCA_SYSROOT}")
    set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
    set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

    return()
endif()

# =============================================================================
#  PROFILE: wasm-wasi
# =============================================================================
if(COCA_TARGET_PROFILE STREQUAL "wasm-wasi")
    set(CMAKE_SYSTEM_NAME  WASI)
    set(CMAKE_SYSTEM_VERSION 1)
    set(CMAKE_SYSTEM_PROCESSOR wasm32)

    set(_COCA_TARGET_TRIPLE "wasm32-wasip1")
    set(_COCA_SYSROOT "${COCA_TOOLCHAIN_ROOT}/sysroots/wasm32-wasi")

    # Compiler
    set(CMAKE_C_COMPILER   "${_COCA_CLANG}"   CACHE FILEPATH "" FORCE)
    set(CMAKE_CXX_COMPILER "${_COCA_CLANGXX}" CACHE FILEPATH "" FORCE)
    set(CMAKE_LINKER       "${_COCA_WASM_LD}" CACHE FILEPATH "" FORCE)

    # Target triple
    set(CMAKE_C_COMPILER_TARGET   "${_COCA_TARGET_TRIPLE}" CACHE STRING "" FORCE)
    set(CMAKE_CXX_COMPILER_TARGET "${_COCA_TARGET_TRIPLE}" CACHE STRING "" FORCE)

    # Sysroot
    set(CMAKE_SYSROOT "${_COCA_SYSROOT}" CACHE PATH "" FORCE)

    # WASI-specific flags
    set(_COCA_WASI_COMPILE_FLAGS
        "-fno-exceptions"
        "-stdlib=libc++"
    )
    set(_COCA_WASI_LINK_FLAGS
        "-stdlib=libc++"
        "-rtlib=compiler-rt"
    )
    string(JOIN " " _COCA_WASI_COMPILE_FLAGS_STR ${_COCA_WASI_COMPILE_FLAGS})
    string(JOIN " " _COCA_WASI_LINK_FLAGS_STR    ${_COCA_WASI_LINK_FLAGS})

    set(CMAKE_C_FLAGS_INIT   "-fno-exceptions ${COCA_IDENT_C_FLAGS}" CACHE STRING "" FORCE)
    set(CMAKE_CXX_FLAGS_INIT "${_COCA_WASI_COMPILE_FLAGS_STR} ${COCA_IDENT_CXX_FLAGS}" CACHE STRING "" FORCE)

    set(CMAKE_EXE_LINKER_FLAGS_INIT    "${_COCA_WASI_LINK_FLAGS_STR}" CACHE STRING "" FORCE)
    set(CMAKE_SHARED_LINKER_FLAGS_INIT "${_COCA_WASI_LINK_FLAGS_STR}" CACHE STRING "" FORCE)
    set(CMAKE_MODULE_LINKER_FLAGS_INIT "${_COCA_WASI_LINK_FLAGS_STR}" CACHE STRING "" FORCE)

    # WASM has no shared libraries
    set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
    set(CMAKE_EXECUTABLE_SUFFIX ".wasm")

    # Restrict find_* to sysroot
    set(CMAKE_FIND_ROOT_PATH "${_COCA_SYSROOT}")
    set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
    set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

    # Include the wasi-sdk CMake platform module if available
    set(_COCA_WASI_PLATFORM "${_COCA_SYSROOT}/share/cmake/Platform/WASI.cmake")
    if(EXISTS "${_COCA_WASI_PLATFORM}")
        list(APPEND CMAKE_MODULE_PATH "${_COCA_SYSROOT}/share/cmake")
    endif()

    return()
endif()

# =============================================================================
#  Unknown profile — error
# =============================================================================
message(FATAL_ERROR
    "${_COCA_CLR_RED}>${_COCA_CLR_RESET} Unknown target profile: '${_COCA_CLR_BOLD}${COCA_TARGET_PROFILE}${_COCA_CLR_RESET}'\n"
    "  Supported profiles: win-x64, win-x64-clang, linux-x64, linux-arm64,\n"
    "    linux-x64-kylin, linux-arm64-kylin,\n"
    "    linux-x64-musl, linux-arm64-musl,\n"
    "    win-x64-mingw-ucrt, win-x64-mingw-msvcrt,\n"
    "    wasm-wasi, wasm-emscripten")
