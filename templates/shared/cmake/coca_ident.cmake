# =============================================================================
# COCA Toolchain — Binary Identity Injection
# =============================================================================
#
# Reads manifest.json and toolchain.json to build a COCA_TOOLCHAIN_IDENT string,
# then injects it into every translation unit via:
#   1. #define COCA_TOOLCHAIN_IDENT "..." (via force-included header)
#   2. asm(".ident \"...\"") / __attribute__((used, section)) so the
#      string appears in ELF .comment / PE sections even if no code
#      references the macro.
#
# The ident string format:
#   COCA <name>/<version> (<compiler> <compiler_version>) <profile> [<fingerprint_short>]
#
# Usage: include() this file from toolchain.cmake AFTER resolving
#        COCA_TOOLCHAIN_ROOT and COCA_TARGET_PROFILE, but BEFORE any profile
#        section sets CMAKE_C_FLAGS_INIT / CMAKE_CXX_FLAGS_INIT.
# =============================================================================

if(_COCA_IDENT_INCLUDED)
    return()
endif()
set(_COCA_IDENT_INCLUDED TRUE)

# ---------------------------------------------------------------------------
# 1. Read manifest.json
# ---------------------------------------------------------------------------
set(_COCA_MANIFEST_FILE "${COCA_TOOLCHAIN_ROOT}/manifest.json")
if(NOT EXISTS "${_COCA_MANIFEST_FILE}")
    message(WARNING "[COCA-Ident] manifest.json not found at ${_COCA_MANIFEST_FILE}, skipping ident injection")
    return()
endif()

file(READ "${_COCA_MANIFEST_FILE}" _COCA_MANIFEST_JSON)

# Extract fields
string(JSON _COCA_IDENT_NAME    GET "${_COCA_MANIFEST_JSON}" "toolchain_name")
string(JSON _COCA_IDENT_VERSION GET "${_COCA_MANIFEST_JSON}" "toolchain_version")

# Compiler version — try llvm first, then zig
string(JSON _COCA_IDENT_LLVM_VER ERROR_VARIABLE _coca_err GET "${_COCA_MANIFEST_JSON}" "components" "llvm" "version")
if(_COCA_IDENT_LLVM_VER AND NOT _coca_err)
    # Check for fork info (P2996)
    string(JSON _COCA_IDENT_FORK ERROR_VARIABLE _coca_err2 GET "${_COCA_MANIFEST_JSON}" "components" "llvm" "fork")
    if(_COCA_IDENT_FORK AND NOT _coca_err2)
        set(_COCA_IDENT_COMPILER "LLVM ${_COCA_IDENT_LLVM_VER} ${_COCA_IDENT_FORK}")
    else()
        set(_COCA_IDENT_COMPILER "LLVM ${_COCA_IDENT_LLVM_VER}")
    endif()
else()
    string(JSON _COCA_IDENT_ZIG_VER ERROR_VARIABLE _coca_err GET "${_COCA_MANIFEST_JSON}" "components" "zig" "version")
    if(_COCA_IDENT_ZIG_VER AND NOT _coca_err)
        set(_COCA_IDENT_COMPILER "Zig ${_COCA_IDENT_ZIG_VER}")
    else()
        set(_COCA_IDENT_COMPILER "unknown")
    endif()
endif()

# Fingerprint (short: first 12 hex chars)
string(JSON _COCA_IDENT_FP_FULL ERROR_VARIABLE _coca_err GET "${_COCA_MANIFEST_JSON}" "checksums" "_fingerprint")
if(_COCA_IDENT_FP_FULL AND NOT _coca_err)
    string(SUBSTRING "${_COCA_IDENT_FP_FULL}" 0 12 _COCA_IDENT_FP_SHORT)
else()
    set(_COCA_IDENT_FP_SHORT "unknown")
    set(_COCA_IDENT_FP_FULL "unknown")
endif()

# ---------------------------------------------------------------------------
# 2. Build the ident string
# ---------------------------------------------------------------------------
#   COCA coca-toolchain/1.0.0 (LLVM 21.1.8) win-x64 [b3e8b6947350]
set(COCA_TOOLCHAIN_IDENT_STRING
    "COCA ${_COCA_IDENT_NAME}/${_COCA_IDENT_VERSION} (${_COCA_IDENT_COMPILER}) ${COCA_TARGET_PROFILE} [${_COCA_IDENT_FP_SHORT}]")

# Also expose the full fingerprint as a separate variable
set(COCA_TOOLCHAIN_FINGERPRINT "${_COCA_IDENT_FP_FULL}" CACHE STRING "COCA toolchain fingerprint" FORCE)

# ---------------------------------------------------------------------------
# 3. Generate the ident header
# ---------------------------------------------------------------------------
set(_COCA_IDENT_HEADER "${CMAKE_BINARY_DIR}/_coca_ident.h")

# The header uses compiler-specific asm to emit the ident string into
# the .comment section (ELF) or as a linker directive (PE/COFF).
# Zig cc is clang-compatible and supports the same syntax.
#
# We use a bracket-string template with @VAR@ placeholders, then
# string(CONFIGURE ... @ONLY) to substitute — this avoids all CMake
# escape issues with quotes, backslashes, and semicolons.
set(_COCA_IDENT_TEMPLATE [=[@COCA_IDENT_PREAMBLE@
#ifndef _COCA_IDENT_H_
#define _COCA_IDENT_H_

#define COCA_TOOLCHAIN_IDENT "@COCA_IDENT_STR@"
#define COCA_TOOLCHAIN_FINGERPRINT "@COCA_IDENT_FP@"

#ifdef __cplusplus
extern "C" {
#endif

#if defined(__ELF__)
/* ELF: .ident directive writes to .comment section */
__asm__(".ident \"@COCA_IDENT_STR@\"\n");
#elif defined(_WIN32)
/* PE/COFF: linker directive + named section for strings(1) / dumpbin */
#pragma comment(user, "@COCA_IDENT_STR@")
#ifdef __clang__
__attribute__((used, section(".coca_id")))
static const char _coca_toolchain_ident[] = "@COCA_IDENT_STR@";
#endif
#elif defined(__wasm__)
/* WASM: custom section */
#ifdef __clang__
__attribute__((used, section(".coca_id")))
static const char _coca_toolchain_ident[] = "@COCA_IDENT_STR@";
#endif
#else
/* Fallback */
#ifdef __clang__
__attribute__((used, section(".coca_id")))
static const char _coca_toolchain_ident[] = "@COCA_IDENT_STR@";
#endif
#endif

#ifdef __cplusplus
}
#endif

#endif /* _COCA_IDENT_H_ */
]=])

set(COCA_IDENT_PREAMBLE "/* Auto-generated by COCA toolchain - DO NOT EDIT */")
set(COCA_IDENT_STR "${COCA_TOOLCHAIN_IDENT_STRING}")
set(COCA_IDENT_FP  "${_COCA_IDENT_FP_FULL}")
string(CONFIGURE "${_COCA_IDENT_TEMPLATE}" _COCA_IDENT_CONTENT @ONLY)
file(WRITE "${_COCA_IDENT_HEADER}" "${_COCA_IDENT_CONTENT}")
unset(_COCA_IDENT_TEMPLATE)
unset(_COCA_IDENT_CONTENT)
unset(COCA_IDENT_PREAMBLE)
unset(COCA_IDENT_STR)
unset(COCA_IDENT_FP)

# ---------------------------------------------------------------------------
# 4. Set compile flags
# ---------------------------------------------------------------------------
# The -include flag force-includes the header in every TU.
# The header itself defines COCA_TOOLCHAIN_IDENT and COCA_TOOLCHAIN_FINGERPRINT
# macros, so no -D flag is needed (avoids shell escaping issues).
# clang-cl uses /FI (MSVC-style); all other compilers use -include (GCC-style)
if(COCA_TARGET_PROFILE STREQUAL "win-x64")
    set(COCA_IDENT_C_FLAGS   "/FI\"${_COCA_IDENT_HEADER}\"" CACHE STRING "" FORCE)
    set(COCA_IDENT_CXX_FLAGS "/FI\"${_COCA_IDENT_HEADER}\"" CACHE STRING "" FORCE)
else()
    set(COCA_IDENT_C_FLAGS   "-include \"${_COCA_IDENT_HEADER}\"" CACHE STRING "" FORCE)
    set(COCA_IDENT_CXX_FLAGS "-include \"${_COCA_IDENT_HEADER}\"" CACHE STRING "" FORCE)
endif()

# Print once
if(NOT _COCA_IDENT_MESSAGE_SHOWN)
    set(_COCA_IDENT_MESSAGE_SHOWN TRUE CACHE INTERNAL "")
    message(STATUS "${_COCA_CLR_CYAN}>${_COCA_CLR_RESET} Toolchain ident: ${_COCA_CLR_BOLD}${COCA_TOOLCHAIN_IDENT_STRING}${_COCA_CLR_RESET}")
    message(STATUS "${_COCA_CLR_CYAN}>${_COCA_CLR_RESET} Fingerprint: ${_COCA_CLR_DIM}${_COCA_IDENT_FP_FULL}${_COCA_CLR_RESET}")
endif()

# Cleanup
unset(_COCA_MANIFEST_FILE)
unset(_COCA_MANIFEST_JSON)
unset(_COCA_IDENT_NAME)
unset(_COCA_IDENT_VERSION)
unset(_COCA_IDENT_LLVM_VER)
unset(_COCA_IDENT_ZIG_VER)
unset(_COCA_IDENT_FORK)
unset(_COCA_IDENT_COMPILER)
unset(_COCA_IDENT_FP_FULL)
unset(_COCA_IDENT_FP_SHORT)
unset(_COCA_IDENT_HEADER)
unset(_coca_err)
unset(_coca_err2)
