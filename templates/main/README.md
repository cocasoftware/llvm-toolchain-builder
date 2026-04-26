# COCA Toolchain

A self-contained, portable C/C++ cross-compilation toolchain based on LLVM 21. It compiles from a Windows host to 12 target profiles without depending on any system-installed compiler, SDK, or runtime.

## Component Versions

| Component                        | Version      | Notes                                             |
| -------------------------------- | ------------ | ------------------------------------------------- |
| LLVM (Clang / LLD / compiler-rt) | 21.1.8       |                                                   |
| libc++ / libc++abi / libunwind   | 21.1.8       | Bundled for all Linux and WASM targets            |
| MSVC toolset                     | 14.50.35717  |                                                   |
| Windows SDK                      | 10.0.26100.0 |                                                   |
| glibc sysroot (x64)              | 2.19+        | Debian Trusty headers, Bookworm libs (2.36)       |
| glibc sysroot (arm64)            | 2.23+        | Debian Jessie headers, Bookworm libs (2.36)       |
| musl                             | 1.2.5        | Fully static linking                              |
| Linux kernel headers             | 6.1.0        | From Debian Bookworm                              |
| MinGW-w64                        | 12.0.0       | UCRT and MSVCRT variants                          |
| wasi-sdk                         | 30.0         |                                                   |
| Emscripten SDK                   | 5.0.0        |                                                   |
| Rust                             | 1.93.1       | Bundled rustup + 8 cross-compilation targets      |
| CMake                            | 4.2.3        |                                                   |
| Ninja                            | 1.13.1       |                                                   |
| Python                           | 3.14.4       | python-build-standalone, full stdlib + pip + venv |
| Git                              | 2.53.0       |                                                   |
| Doxygen                          | 1.16.1       |                                                   |
| Graphviz                         | 14.1.2       | `dot` for Doxygen graph generation                |
| Perl                             | 5.42.0       | Strawberry Perl, for OpenSSL builds               |
| Conan                            | 2.25.2       |                                                   |
| JFrog CLI                        | 2.72.2       |                                                   |
| Intel VTune                      | 2025.0.1     | Bundled profiler + ITT API                        |
| Intel Fortran (ifort)            | classic      | Wrapper for mixed C++/Fortran projects            |
| RenderDoc                        | 1.43         | GPU frame capture                                 |
| rsync                            | 3.4.1        | Incremental file sync for deployment              |
| wasmtime                         | 41.0.3       | WASI runtime for testing                          |
| PowerShell (pwsh)                | 7.5.5        | Bundled shell for `exec` sandbox                  |

## Supported Target Profiles (12)

| Profile                | Target Triple                | Runtime    | Linker   | Notes                                         |
| ---------------------- | ---------------------------- | ---------- | -------- | --------------------------------------------- |
| `win-x64`              | `x86_64-pc-windows-msvc`     | MSVC       | lld-link | Windows x64 native, clang-cl driver           |
| `win-x64-clang`        | `x86_64-pc-windows-msvc`     | MSVC       | lld-link | Same ABI, but uses clang++ GNU driver         |
| `linux-x64`            | `x86_64-unknown-linux-gnu`   | LLVM       | ld.lld   | Linux x86_64 (glibc ≥ 2.19)                   |
| `linux-arm64`          | `aarch64-unknown-linux-gnu`  | LLVM       | ld.lld   | Linux AArch64 (glibc ≥ 2.23)                  |
| `linux-x64-kylin`      | `x86_64-unknown-linux-gnu`   | LLVM       | ld.lld   | Kylin OS x86_64 (shares linux-x64 sysroot)    |
| `linux-arm64-kylin`    | `aarch64-unknown-linux-gnu`  | LLVM       | ld.lld   | Kylin OS AArch64 (shares linux-arm64 sysroot) |
| `linux-x64-musl`       | `x86_64-unknown-linux-musl`  | LLVM       | ld.lld   | Fully static (musl 1.2.5, no dynamic linker)  |
| `linux-arm64-musl`     | `aarch64-unknown-linux-musl` | LLVM       | ld.lld   | Fully static (musl 1.2.5, no dynamic linker)  |
| `win-x64-mingw-ucrt`   | `x86_64-w64-mingw32`         | MinGW      | ld.lld   | Windows x64, MinGW UCRT                       |
| `win-x64-mingw-msvcrt` | `x86_64-w64-mingw32`         | MinGW      | ld.lld   | Windows x64, MinGW MSVCRT (legacy)            |
| `wasm-wasi`            | `wasm32-wasip1`              | WASI       | wasm-ld  | WebAssembly WASI (server-side, CLI, plugins)  |
| `wasm-emscripten`      | `wasm32-unknown-emscripten`  | Emscripten | wasm-ld  | WebAssembly browser (via Emscripten SDK)      |

## Directory Layout

```
coca-toolchain/
├── bin/                              # ~127 LLVM host tools (see §13 for full list)
│   ├── clang.exe / clang++.exe       # C/C++ compiler (GNU driver)
│   ├── clang-cl.exe                  # MSVC-compatible driver
│   ├── flang.exe                     # Fortran compiler
│   ├── lld.exe / ld.lld.exe          # ELF linker
│   ├── lld-link.exe                  # COFF linker (Windows)
│   ├── wasm-ld.exe                   # WebAssembly linker
│   ├── lldb.exe / lldb-dap.exe       # Debugger + DAP server
│   ├── clangd.exe                    # Language server (LSP)
│   ├── clang-format.exe              # Code formatter
│   ├── clang-tidy.exe                # Linter / static analyzer
│   ├── llvm-cov.exe / llvm-profdata.exe  # Coverage tools
│   └── ...
├── include/c++/v1/                   # Host libc++ headers (for win-x64-clang)
├── lib/
│   ├── libc++.lib / c++.dll          # Host libc++ (Windows, for win-x64-clang)
│   └── clang/21/                     # Clang resource directory
│       ├── include/                  # Compiler built-in headers
│       └── lib/
│           ├── windows/              # Windows sanitizer/coverage/builtins runtimes
│           ├── x86_64-unknown-linux-gnu/   # Linux x64 runtimes
│           ├── aarch64-unknown-linux-gnu/  # Linux arm64 runtimes
│           ├── x86_64-unknown-linux-musl/  # musl x64 builtins
│           ├── aarch64-unknown-linux-musl/ # musl arm64 builtins
│           ├── x86_64-w64-mingw32/        # MinGW builtins
│           ├── wasm32-unknown-wasip1/     # WASM builtins
│           └── ...
├── sysroots/
│   ├── x86_64-windows-msvc/          # Windows sysroot (MSVC + SDK headers/libs/redist)
│   ├── x86_64-linux-gnu/             # Linux x86_64 (glibc + libc++ + X11/XCB/Vulkan)
│   ├── aarch64-linux-gnu/            # Linux AArch64 (glibc + libc++ + X11/XCB/Vulkan)
│   ├── x86_64-linux-musl/            # musl x86_64 (libc++ installed in usr/lib/)
│   ├── aarch64-linux-musl/           # musl AArch64 (libc++ installed in usr/lib/)
│   ├── x86_64-w64-mingw32-ucrt/      # MinGW UCRT sysroot
│   ├── x86_64-w64-mingw32-msvcrt/    # MinGW MSVCRT sysroot
│   └── wasm32-wasi/                  # WASI sysroot (wasi-libc + libc++ + compiler-rt)
├── cmake/
│   ├── toolchain.cmake               # Unified CMake toolchain file (all 12 profiles)
│   ├── coca_rust.cmake               # Rust integration (staticlib, cdylib, bin)
│   ├── coca_vtune.cmake              # VTune profiling + ITT API
│   ├── coca_pgo.cmake                # 3-stage PGO workflow
│   ├── bundle.cmake / bundle.py      # Deployment bundling
│   └── ...
├── tools/
│   ├── cmake/                        # Bundled CMake
│   ├── ninja/                        # Bundled Ninja
│   ├── python/                       # Python 3.14.4 (python-build-standalone)
│   ├── rust/                         # Bundled Rust toolchain (rustup + cargo + 8 targets)
│   ├── git/                          # Portable Git
│   ├── emsdk/                        # Emscripten SDK
│   ├── wasmtime/                     # WASI runtime (for testing)
│   ├── vtune/                        # Intel VTune 2025.0.1
│   ├── ifort/                        # Intel Fortran wrapper
│   ├── ml64/                         # MASM x64 assembler
│   ├── renderdoc/                    # GPU frame capture
│   ├── doxygen/                      # Documentation generator
│   ├── graphviz/                     # Graph visualization (dot)
│   ├── perl/                         # Strawberry Perl
│   ├── rsync/                        # Incremental file sync
│   ├── conan/                        # Conan 2 package manager
│   ├── jfrog/                        # JFrog CLI
│   ├── pwsh/                         # Bundled PowerShell 7.5
│   ├── glab/                         # GitLab CLI
│   ├── libclang/                     # Clang C API shared library
│   ├── coca/                         # COCA CLI helper
│   ├── terminal/                     # Bundled Windows Terminal
│   └── msys2-make/                   # MSYS2-native make (for ICU builds)
├── scripts/                          # setup.py subcommand implementations
├── tests/                            # Toolchain self-test suite (105 tests)
│   ├── runner.py                     # Test runner
│   ├── framework.py                  # Test framework (TestSuite, TestResult)
│   ├── test_tools.py                 # Phase 1: Tool reachability (30 tests)
│   ├── test_sysroots.py              # Phase 2: Sysroot file existence (59 tests)
│   ├── test_compile.py               # Phase 3: Native compilation pipeline (7 tests)
│   ├── test_cross_compile.py         # Phase 4: Cross-compilation (9 sub-profiles)
│   ├── test_sanitizers.py            # Phase 5: ASan/UBSan/Coverage (4 tests)
│   ├── test_cmake.py                 # Phase 6: CMake integration (4 tests)
│   └── fixtures/                     # Test source files
├── toolchain.json                    # Profile definitions (12 targets)
├── manifest.json                     # Manifest (versions, SHA-256 checksums, fingerprint)
├── setup.py                          # CLI: env, info, check, test, doctor, exec, update-manifest
└── README.md
```

---

## Quick Start

### Environment Setup

```powershell
# PowerShell — using setup.py (recommended: sets all env vars + PATH automatically)
python C:\path\to\coca-toolchain\setup.py | Invoke-Expression

# Or manually:
$env:COCA_TOOLCHAIN = "C:\path\to\coca-toolchain"
$env:PATH = "$env:COCA_TOOLCHAIN\bin;$env:PATH"
```

```bash
# Bash — using setup.py
eval "$(python3 /path/to/coca-toolchain/setup.py --shell bash)"
```

### setup.py Subcommands

| Subcommand        | Description                                                                |
| ----------------- | -------------------------------------------------------------------------- |
| `env` (default)   | Emit shell commands to stdout for piping into `Invoke-Expression` / `eval` |
| `info`            | Rich-formatted toolchain summary (profiles, sysroots, components)          |
| `check`           | Validate toolchain integrity (files, versions, sysroots)                   |
| `test [--filter]` | Run the 105-test self-test suite; filter by phase or test id               |
| `doctor`          | Diagnose common problems (missing DLLs, broken links, etc.)                |
| `update-manifest` | Regenerate `manifest.json` with SHA-256 checksums                          |
| `exec [--shell]`  | Launch interactive shell in sandboxed env with fingerprint-tagged venv     |
| `terminal`        | Launch bundled Windows Terminal with COCA profile                          |
| `context-menu`    | Register/unregister Explorer right-click "Open COCA Terminal here"         |

All subcommands support `--verbose` / `-v` for detailed progress output.

### `exec` Subcommand Details

```powershell
# Launch sandboxed shell (default: bundled pwsh, auto venv)
python setup.py exec

# Use system PowerShell instead of bundled pwsh
python setup.py exec --system-shell

# Inherit full user/system environment (no sandbox)
python setup.py exec --inherit-env

# Specify custom venv location
python setup.py exec --venv-dir D:\my-project

# Skip venv entirely
python setup.py exec --no-venv
```

| Flag              | Description                                                           |
| ----------------- | --------------------------------------------------------------------- |
| `--shell`         | `powershell`, `cmd`, or `bash`                                        |
| `--no-venv`       | Skip automatic venv creation/activation                               |
| `--venv-dir PATH` | Base directory for `.venv-<fingerprint>/` (default: cwd)              |
| `--inherit-env`   | Inherit full user/system environment instead of sandboxed minimal set |
| `--system-shell`  | Use system PowerShell instead of bundled pwsh                         |

The venv directory is named `.venv-<fingerprint[:8]>` based on `manifest.json` checksums, so different toolchain versions get isolated environments. Stale venvs from previous versions are automatically cleaned up. When `--shell powershell` is used, the **bundled pwsh** (`tools/pwsh/`) is preferred by default.

---

## 1. Windows Native Compilation (win-x64)

### Direct Invocation (clang-cl)

```powershell
# C++ compilation (MSVC-compatible driver)
clang-cl.exe /std:c++23 /EHsc /O2 `
    /imsvc "$env:COCA_TOOLCHAIN\sysroots\x86_64-windows-msvc\msvc\include" `                       # MSVC headers
    /imsvc "$env:COCA_TOOLCHAIN\sysroots\x86_64-windows-msvc\sdk\Include\10.0.26100.0\ucrt" `      # Universal C Runtime
    /imsvc "$env:COCA_TOOLCHAIN\sysroots\x86_64-windows-msvc\sdk\Include\10.0.26100.0\um" `        # User-mode (for user applications)
    /imsvc "$env:COCA_TOOLCHAIN\sysroots\x86_64-windows-msvc\sdk\Include\10.0.26100.0\shared" `    # Shared across architecture
    main.cpp `
    /link /LIBPATH:"$env:COCA_TOOLCHAIN\sysroots\x86_64-windows-msvc\msvc\lib\x64" `
          /LIBPATH:"$env:COCA_TOOLCHAIN\sysroots\x86_64-windows-msvc\sdk\Lib\10.0.26100.0\ucrt\x64" `
          /LIBPATH:"$env:COCA_TOOLCHAIN\sysroots\x86_64-windows-msvc\sdk\Lib\10.0.26100.0\um\x64" `
          /OUT:main.exe
```

### CMake Integration

```powershell
cmake -G Ninja -B build `
    -DCMAKE_TOOLCHAIN_FILE="$env:COCA_TOOLCHAIN\cmake\toolchain.cmake" `
    -DCOCA_TARGET_PROFILE=win-x64
cmake --build build
```

---

## 2. Linux x86_64 Cross-Compilation (linux-x64)

### Direct Invocation

```powershell
clang++.exe --target=x86_64-unknown-linux-gnu `
    --sysroot="$env:COCA_TOOLCHAIN\sysroots\x86_64-linux-gnu" `
    -nostdinc++ `
    -isystem "$env:COCA_TOOLCHAIN\sysroots\x86_64-linux-gnu\usr\include\c++\v1" `
    -stdlib=libc++ -rtlib=compiler-rt -unwindlib=libunwind `
    -fuse-ld=lld `
    -std=c++23 -O2 `
    -o main main.cpp
```

### CMake Integration

```powershell
cmake -G Ninja -B build `
    -DCMAKE_TOOLCHAIN_FILE="$env:COCA_TOOLCHAIN\cmake\toolchain.cmake" `
    -DCOCA_TARGET_PROFILE=linux-x64
cmake --build build
```

---

## 3. Linux AArch64 Cross-Compilation (linux-arm64)

### Direct Invocation

```powershell
clang++.exe --target=aarch64-unknown-linux-gnu `
    --sysroot="$env:COCA_TOOLCHAIN\sysroots\aarch64-linux-gnu" `
    -nostdinc++ `
    -isystem "$env:COCA_TOOLCHAIN\sysroots\aarch64-linux-gnu\usr\include\c++\v1" `
    -stdlib=libc++ -rtlib=compiler-rt -unwindlib=libunwind `
    -fuse-ld=lld `
    -std=c++23 -O2 `
    -o main main.cpp
```

### CMake Integration

```powershell
cmake -G Ninja -B build `
    -DCMAKE_TOOLCHAIN_FILE="$env:COCA_TOOLCHAIN\cmake\toolchain.cmake" `
    -DCOCA_TARGET_PROFILE=linux-arm64
cmake --build build
```

---

## 4. WebAssembly WASI (wasm-wasi)

WASI targets produce standalone `.wasm` files that run on any WASI-compatible runtime (wasmtime, wasmer, Node.js).

### Direct Invocation

```powershell
clang++.exe --target=wasm32-wasip1 `
    --sysroot="$env:COCA_TOOLCHAIN\sysroots\wasm32-wasi" `
    -fno-exceptions -stdlib=libc++ `
    -O2 `
    -o output.wasm main.cpp
```

### Running

```powershell
# Using bundled wasmtime
& "$env:COCA_TOOLCHAIN\tools\wasmtime\wasmtime.exe" output.wasm
```

### CMake Integration

```powershell
cmake -G Ninja -B build `
    -DCMAKE_TOOLCHAIN_FILE="$env:COCA_TOOLCHAIN\cmake\toolchain.cmake" `
    -DCOCA_TARGET_PROFILE=wasm-wasi
cmake --build build
```

### Notes

- All libraries are statically linked into the `.wasm` file (no dynamic linking).
- C++ exceptions are disabled by default (`-fno-exceptions`). Use `-fwasm-exceptions` if needed.
- WASM SIMD can be enabled with `-msimd128`.
- For size optimization, use `-Oz` and post-process with `wasm-opt` / `wasm-strip`.

---

## 5. WebAssembly Emscripten (wasm-emscripten)

Emscripten targets produce `.wasm` + `.js` (+ optional `.html`) for browser or Node.js execution.

### Environment Setup

If you use Python script `setup.py` to setup the environment variables, then these are also done along with it.

```powershell
$env:EMSDK = "$env:COCA_TOOLCHAIN\tools\emsdk"
$env:EMSDK_NODE = "$env:EMSDK\node\22.16.0_64bit\bin\node.exe"
$env:EMSDK_PYTHON = "$env:EMSDK\python\3.13.3_64bit\python.exe"
$env:EM_CONFIG = "$env:EMSDK\.emscripten"
$env:PATH = "$env:EMSDK;$env:EMSDK\upstream\emscripten;$env:EMSDK\node\22.16.0_64bit\bin;$env:EMSDK\python\3.13.3_64bit;$env:PATH"
```

### Direct Invocation

```powershell
# Compile to .js + .wasm (Node.js compatible)
& $env:EMSDK_PYTHON "$env:EMSDK\upstream\emscripten\em++.py" `
    -O2 -fno-exceptions `
    -sWASM=1 -sALLOW_MEMORY_GROWTH=1 `
    -o output.js main.cpp

# Compile to .html + .js + .wasm (browser)
& $env:EMSDK_PYTHON "$env:EMSDK\upstream\emscripten\em++.py" `
    -O2 -fno-exceptions `
    -sWASM=1 -sALLOW_MEMORY_GROWTH=1 `
    -o output.html main.cpp
```

### Running

```powershell
# Node.js
& $env:EMSDK_NODE output.js

# Browser: serve the .html file with any HTTP server
```

### CMake Integration

Emscripten provides its own CMake toolchain file:

```powershell
cmake -G Ninja -B build `
    -DCMAKE_TOOLCHAIN_FILE="$env:COCA_TOOLCHAIN\tools\emsdk\upstream\emscripten\cmake\Modules\Platform\Emscripten.cmake"
cmake --build build
```

Or use the COCA toolchain file:

```powershell
cmake -G Ninja -B build `
    -DCMAKE_TOOLCHAIN_FILE="$env:COCA_TOOLCHAIN\cmake\toolchain.cmake" `
    -DCOCA_TARGET_PROFILE=wasm-emscripten
cmake --build build
```

---

## 6. Linux musl Static Builds (linux-x64-musl / linux-arm64-musl)

musl targets produce **fully static** ELF executables with no dynamic linker dependency. Ideal for containers, embedded systems, and distribution-agnostic deployment.

### Direct Invocation

```powershell
clang++.exe --target=x86_64-unknown-linux-musl `
    --sysroot="$env:COCA_TOOLCHAIN\sysroots\x86_64-linux-musl" `
    -nostdinc++ `
    -isystem "$env:COCA_TOOLCHAIN\sysroots\x86_64-linux-musl\usr\include\c++\v1" `
    -stdlib=libc++ -rtlib=compiler-rt -unwindlib=libunwind -fuse-ld=lld `
    -static `
    -std=c++23 -O2 `
    -o main main.cpp
```

### CMake Integration

```powershell
cmake -G Ninja -B build `
    -DCMAKE_TOOLCHAIN_FILE="$env:COCA_TOOLCHAIN\cmake\toolchain.cmake" `
    -DCOCA_TARGET_PROFILE=linux-x64-musl
cmake --build build
```

### Notes

- Output binaries are statically linked ELF `EXEC` — no `.interp`, no dynamic section.
- `BUILD_SHARED_LIBS` is forced `OFF` by the toolchain file.
- Binary sizes are typically 300–400 KB for a C++ hello-world.
- AArch64: replace `x86_64` with `aarch64` in the target triple and sysroot path.

---

## 7. Windows MinGW Cross-Compilation (win-x64-mingw-ucrt / win-x64-mingw-msvcrt)

MinGW profiles produce Windows PE executables using the GCC-compatible ABI (not MSVC). Useful for porting GNU/Linux software to Windows.

### Direct Invocation

```powershell
clang++.exe --target=x86_64-w64-mingw32 `
    --sysroot="$env:COCA_TOOLCHAIN\sysroots\x86_64-w64-mingw32-ucrt" `
    -stdlib=libc++ -rtlib=compiler-rt -unwindlib=libunwind -fuse-ld=lld `
    -std=c++23 -O2 `
    -o main.exe main.cpp
```

### CMake Integration

```powershell
# UCRT variant (recommended)
cmake -G Ninja -B build `
    -DCMAKE_TOOLCHAIN_FILE="$env:COCA_TOOLCHAIN\cmake\toolchain.cmake" `
    -DCOCA_TARGET_PROFILE=win-x64-mingw-ucrt
cmake --build build

# MSVCRT variant (legacy compatibility)
cmake -G Ninja -B build `
    -DCMAKE_TOOLCHAIN_FILE="$env:COCA_TOOLCHAIN\cmake\toolchain.cmake" `
    -DCOCA_TARGET_PROFILE=win-x64-mingw-msvcrt
cmake --build build
```

---

## 8. Windows clang++ GNU Driver (win-x64-clang)

The `win-x64-clang` profile uses `clang++` (GNU driver) instead of `clang-cl` (MSVC driver), while still targeting the MSVC ABI. This is useful for projects that need GNU-style flags (e.g. `-stdlib=libc++`, `-fuse-ld=lld`).

### Direct Invocation

```powershell
clang++.exe --target=x86_64-pc-windows-msvc `
    -fuse-ld=lld -rtlib=compiler-rt -nostdinc++ `
    -isystem "$env:COCA_TOOLCHAIN\include\c++\v1" `
    -isystem "$env:COCA_TOOLCHAIN\lib\clang\21\include" `
    -isystem "$env:COCA_TOOLCHAIN\sysroots\x86_64-windows-msvc\msvc\include" `
    -isystem "$env:COCA_TOOLCHAIN\sysroots\x86_64-windows-msvc\sdk\Include\10.0.26100.0\ucrt" `
    -lc++ `
    -L"$env:COCA_TOOLCHAIN\sysroots\x86_64-windows-msvc\msvc\lib\x64" `
    -L"$env:COCA_TOOLCHAIN\sysroots\x86_64-windows-msvc\sdk\Lib\10.0.26100.0\ucrt\x64" `
    -L"$env:COCA_TOOLCHAIN\sysroots\x86_64-windows-msvc\sdk\Lib\10.0.26100.0\um\x64" `
    main.cpp -o main.exe
```

### CMake Integration

```powershell
cmake -G Ninja -B build `
    -DCMAKE_TOOLCHAIN_FILE="$env:COCA_TOOLCHAIN\cmake\toolchain.cmake" `
    -DCOCA_TARGET_PROFILE=win-x64-clang
cmake --build build
```

> **Note:** Executables built with this profile require `c++.dll` and `unwind.dll` next to the `.exe` at runtime (or on `PATH`). These are in `$env:COCA_TOOLCHAIN\bin\`.

---

## 9. Rust Integration

The toolchain bundles Rust 1.93.1 with cross-compilation support for all COCA profiles.

### Profile → Rust Target Mapping

| COCA Profile                        | Rust Target                  |
| ----------------------------------- | ---------------------------- |
| `win-x64` / `win-x64-clang`         | `x86_64-pc-windows-msvc`     |
| `linux-x64` / `linux-x64-kylin`     | `x86_64-unknown-linux-gnu`   |
| `linux-arm64` / `linux-arm64-kylin` | `aarch64-unknown-linux-gnu`  |
| `linux-x64-musl`                    | `x86_64-unknown-linux-musl`  |
| `linux-arm64-musl`                  | `aarch64-unknown-linux-musl` |
| `win-x64-mingw-*`                   | `x86_64-pc-windows-gnu`      |
| `wasm-wasi`                         | `wasm32-wasip1`              |
| `wasm-emscripten`                   | `wasm32-unknown-emscripten`  |

### CMake Integration

Enable Rust in the CMake build by setting `COCA_ENABLE_RUST=ON`:

```powershell
cmake -G Ninja -B build `
    -DCMAKE_TOOLCHAIN_FILE="$env:COCA_TOOLCHAIN\cmake\toolchain.cmake" `
    -DCOCA_TARGET_PROFILE=win-x64 `
    -DCOCA_ENABLE_RUST=ON
cmake --build build
```

The `coca_rust.cmake` module provides three functions:

```cmake
# Build a Rust static library and link it into a C++ target
coca_rust_staticlib(TARGET mylib CRATE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/mylib-rs)

# Build a Rust dynamic library (cdylib)
coca_rust_cdylib(TARGET mylib CRATE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/mylib-rs)

# Build a standalone Rust binary
coca_rust_bin(TARGET mytool CRATE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/mytool-rs)
```

---

## 10. Sanitizers

### 10.1 AddressSanitizer (ASan)

Detects memory errors: buffer overflow, use-after-free, stack overflow, etc.

**Windows (clang-cl):**
```powershell
clang-cl.exe /fsanitize=address /Zi /Od main.cpp /link /OUT:main.exe
# Run — ASan reports errors to stderr
.\main.exe
```

**Linux x86_64 cross-compile:**
```powershell
clang++.exe --target=x86_64-unknown-linux-gnu `
    --sysroot="$env:COCA_TOOLCHAIN\sysroots\x86_64-linux-gnu" `
    -nostdinc++ `
    -isystem "$env:COCA_TOOLCHAIN\sysroots\x86_64-linux-gnu\usr\include\c++\v1" `
    -stdlib=libc++ -rtlib=compiler-rt -unwindlib=libunwind -fuse-ld=lld `
    -fsanitize=address -g -O1 `
    -o main main.cpp
```

### 10.2 UndefinedBehaviorSanitizer (UBSan)

Detects undefined behavior: signed overflow, null dereference, type mismatch, etc.

**Windows (trap mode — no runtime needed):**
```powershell
clang-cl.exe /fsanitize=undefined /fsanitize-trap=all /Zi main.cpp /link /OUT:main.exe
# Triggers illegal instruction (trap) on UB
```

**Linux:**
```powershell
clang++.exe --target=x86_64-unknown-linux-gnu `
    --sysroot="$env:COCA_TOOLCHAIN\sysroots\x86_64-linux-gnu" `
    -nostdinc++ `
    -isystem "$env:COCA_TOOLCHAIN\sysroots\x86_64-linux-gnu\usr\include\c++\v1" `
    -stdlib=libc++ -rtlib=compiler-rt -unwindlib=libunwind -fuse-ld=lld `
    -fsanitize=undefined -g `
    -o main main.cpp
```

**WASM (trap mode only):**
```powershell
clang++.exe --target=wasm32-wasip1 `
    --sysroot="$env:COCA_TOOLCHAIN\sysroots\wasm32-wasi" `
    -nostdinc++ `
    -isystem "$env:COCA_TOOLCHAIN\sysroots\wasm32-wasi\include\c++\v1" `
    -fno-exceptions -stdlib=libc++ `
    -fsanitize=undefined -fsanitize-trap=undefined `
    -o main.wasm main.cpp
```

### 10.3 MemorySanitizer / ThreadSanitizer (Linux only)

```powershell
# MSan — detects uninitialized memory reads
clang++.exe --target=x86_64-unknown-linux-gnu ... -fsanitize=memory -g -o main main.cpp

# TSan — detects data races
clang++.exe --target=x86_64-unknown-linux-gnu ... -fsanitize=thread -g -o main main.cpp
```

### Sanitizer Support Matrix

| Sanitizer | Windows (win-x64) | Linux (glibc) | Linux (musl) | WASM     |
| --------- | ----------------- | ------------- | ------------ | -------- |
| ASan      | ✓                 | ✓             | ✗            | ✗        |
| UBSan     | ✓ (trap)          | ✓             | ✓ (trap)     | ✓ (trap) |
| MSan      | ✗                 | ✓             | ✗            | ✗        |
| TSan      | ✗                 | ✓             | ✗            | ✗        |
| Coverage  | ✓                 | ✓             | ✗            | ✗        |

---

## 11. Code Coverage

### Compile with Coverage Instrumentation

**Windows:**
```powershell
clang++.exe -fprofile-instr-generate -fcoverage-mapping -O0 -g `
    main.cpp -o main.exe `
    -fuse-ld=lld-link `
    -Wl,/LIBPATH:"$env:COCA_TOOLCHAIN\sysroots\x86_64-windows-msvc\msvc\lib\x64" `
    -Wl,/LIBPATH:"$env:COCA_TOOLCHAIN\sysroots\x86_64-windows-msvc\sdk\Lib\10.0.26100.0\ucrt\x64" `
    -Wl,/LIBPATH:"$env:COCA_TOOLCHAIN\sysroots\x86_64-windows-msvc\sdk\Lib\10.0.26100.0\um\x64"
```

**Linux cross-compile:**
```powershell
clang++.exe --target=x86_64-unknown-linux-gnu `
    --sysroot="$env:COCA_TOOLCHAIN\sysroots\x86_64-linux-gnu" `
    -nostdinc++ `
    -isystem "$env:COCA_TOOLCHAIN\sysroots\x86_64-linux-gnu\usr\include\c++\v1" `
    -stdlib=libc++ -rtlib=compiler-rt -unwindlib=libunwind -fuse-ld=lld `
    -fprofile-instr-generate -fcoverage-mapping -O0 -g `
    -o main main.cpp
```

### Generate Coverage Report

```powershell
# 1. Run the instrumented binary (generates default.profraw)
.\main.exe
# or on Linux: ./main

# 2. Merge raw profiles
llvm-profdata.exe merge -sparse default.profraw -o coverage.profdata

# 3. Generate text report
llvm-cov.exe report main.exe -instr-profile=coverage.profdata

# 4. Generate HTML report
llvm-cov.exe show main.exe -instr-profile=coverage.profdata `
    -format=html -output-dir=coverage_html

# 5. Export to lcov format (for CI integration)
llvm-cov.exe export main.exe -instr-profile=coverage.profdata `
    -format=lcov > coverage.lcov
```

---

## 12. CMake Toolchain File

The toolchain ships a unified CMake toolchain file at `cmake/toolchain.cmake`. It reads `toolchain.json` and configures all compiler/linker settings automatically.

### Usage

```powershell
cmake -G Ninja -B build `
    -DCMAKE_TOOLCHAIN_FILE="<toolchain_root>/cmake/toolchain.cmake" `
    -DCOCA_TARGET_PROFILE=<profile>
cmake --build build
```

### Available Variables

| Variable                    | Required | Default | Description                                              |
| --------------------------- | -------- | ------- | -------------------------------------------------------- |
| `COCA_TARGET_PROFILE`       | **Yes**  | —       | Target profile name (e.g. `win-x64`, `linux-x64`)        |
| `COCA_TOOLCHAIN_ROOT`       | No       | auto    | Override toolchain root directory                        |
| `COCA_CXX_STANDARD`         | No       | `23`    | C++ standard (`17`, `20`, `23`)                          |
| `COCA_C_STANDARD`           | No       | `23`    | C standard (`11`, `17`, `23`)                            |
| `COCA_ENABLE_LTO`           | No       | `OFF`   | Enable Link-Time Optimization                            |
| `COCA_ENABLE_RUST`          | No       | `OFF`   | Enable Rust integration (loads `coca_rust.cmake`)        |
| `COCA_ENABLE_VTUNE`         | No       | `OFF`   | Enable VTune profiling (loads `coca_vtune.cmake`)        |
| `COCA_ENABLE_PGO`           | No       | `OFF`   | Enable PGO workflow (loads `coca_pgo.cmake`)             |
| `COCA_FORTRAN_COMPILER`     | No       | `auto`  | Fortran compiler: `ifort`, `flang`, `none`, `auto`       |
| `COCA_ALLOW_AUTO_DETECTION` | No       | `OFF`   | Allow CMake to search host system paths (sandbox bypass) |

### What the Toolchain File Configures

- `CMAKE_C_COMPILER` / `CMAKE_CXX_COMPILER` — points to toolchain's Clang
- `CMAKE_LINKER` — appropriate linker for the target (lld-link, ld.lld, or wasm-ld)
- `CMAKE_SYSROOT` — target-specific sysroot
- `CMAKE_C_COMPILER_TARGET` / `CMAKE_CXX_COMPILER_TARGET` — target triple
- `CMAKE_FIND_ROOT_PATH_MODE_*` — restricts find_* to sysroot only
- Runtime flags: `-stdlib=libc++`, `-rtlib=compiler-rt`, `-unwindlib=libunwind` for Linux targets
- WASI-specific: `-fno-exceptions`, static linking only
- Windows-specific: MSVC include/lib paths via `/imsvc` and `/LIBPATH`

---

## 13. Bundled Tools (~127 executables)

### External Tools (`tools/`)

| Tool               | Path                                 | Description                        |
| ------------------ | ------------------------------------ | ---------------------------------- |
| CMake 4.2.3        | `tools/cmake/bin/cmake.exe`          | Build system generator             |
| Ninja 1.13.1       | `tools/ninja/ninja.exe`              | Fast build tool                    |
| Python 3.14.4      | `tools/python/python.exe`            | python-build-standalone (full pip) |
| Rust 1.93.1        | `tools/rust/`                        | Bundled rustup + cargo + 8 targets |
| Git 2.53.0         | `tools/git/cmd/git.exe`              | Portable Git                       |
| Doxygen 1.16.1     | `tools/doxygen/doxygen.exe`          | Documentation generator            |
| Graphviz 14.1.2    | `tools/graphviz/bin/dot.exe`         | Graph visualization for Doxygen    |
| Perl 5.42.0        | `tools/perl/perl/bin/perl.exe`       | Strawberry Perl (OpenSSL builds)   |
| wasmtime 41.0.3    | `tools/wasmtime/wasmtime.exe`        | WASI runtime (for testing)         |
| Emscripten 5.0.0   | `tools/emsdk/`                       | WebAssembly browser SDK            |
| Intel VTune 2025.0 | `tools/vtune/`                       | CPU profiler + ITT API             |
| Intel ifort        | `tools/ifort/bin/ifort-wrapper.cmd`  | Fortran compiler wrapper           |
| MASM x64           | `tools/ml64/ml64.exe`                | Microsoft x64 assembler            |
| RenderDoc 1.43     | `tools/renderdoc/renderdoccmd.exe`   | GPU frame capture                  |
| rsync 3.4.1        | `tools/rsync/bin/rsync.exe`          | Incremental file sync              |
| Conan 2.25.2       | `tools/conan/conan.cmd`              | C/C++ package manager              |
| JFrog CLI 2.72.2   | `tools/jfrog/jf.exe`                 | Artifactory upload CLI             |
| msys2-make         | `tools/msys2-make/msys2-make.exe`    | MSYS2-native make (for ICU builds) |
| PowerShell 7.5.5   | `tools/pwsh/pwsh.exe`                | Bundled shell for `exec` sandbox   |
| GitLab CLI (glab)  | `tools/glab/glab.exe`                | GitLab CLI for CI/CD integration   |
| libclang           | `tools/libclang/libclang.dll`        | Clang C API shared library         |
| coca-tools         | `tools/coca/coca-tools.exe`          | COCA CLI helper                    |
| Windows Terminal   | `tools/terminal/WindowsTerminal.exe` | Bundled terminal emulator          |

### Compilers & Drivers (`bin/`)

| Tool                        | Description                            |
| --------------------------- | -------------------------------------- |
| `clang.exe` / `clang++.exe` | C/C++ compiler (GNU-compatible driver) |
| `clang-cl.exe`              | MSVC-compatible compiler driver        |
| `clang-cpp.exe`             | C preprocessor                         |
| `clang-repl.exe`            | Interactive C++ REPL (JIT)             |

### Linkers (`bin/`)

| Tool                       | Description                      |
| -------------------------- | -------------------------------- |
| `lld.exe`                  | Universal linker entry point     |
| `ld.lld.exe`               | ELF linker (Linux)               |
| `lld-link.exe`             | COFF linker (Windows)            |
| `ld64.lld.exe`             | Mach-O linker (macOS)            |
| `wasm-ld.exe`              | WebAssembly linker               |
| `dsymutil.exe`             | DWARF debug symbol linker (dSYM) |
| `clang-linker-wrapper.exe` | Offload linker wrapper           |

### Debugger (`bin/`)

| Tool                 | Description                                                   |
| -------------------- | ------------------------------------------------------------- |
| `lldb.exe`           | LLVM debugger (GDB-compatible)                                |
| `lldb-dap.exe`       | Debug Adapter Protocol server (for VS Code / IDE integration) |
| `lldb-server.exe`    | Remote debug server                                           |
| `lldb-argdumper.exe` | Argument dumper helper for lldb                               |

### Language Server (`bin/`)

| Tool         | Description                                     |
| ------------ | ----------------------------------------------- |
| `clangd.exe` | C/C++ language server (LSP) for IDE integration |

### Code Quality & Refactoring (`bin/`)

| Tool                           | Description                          |
| ------------------------------ | ------------------------------------ |
| `clang-format.exe`             | Code formatter                       |
| `clang-tidy.exe`               | Linter / static analyzer             |
| `clang-apply-replacements.exe` | Apply clang-tidy fix-its in bulk     |
| `clang-check.exe`              | Syntax checking and AST dumping      |
| `clang-query.exe`              | Interactive AST matcher query tool   |
| `clang-refactor.exe`           | Automated refactoring                |
| `clang-include-cleaner.exe`    | Remove unused `#include` directives  |
| `clang-include-fixer.exe`      | Add missing `#include` directives    |
| `clang-move.exe`               | Move class definitions between files |
| `clang-change-namespace.exe`   | Rename C++ namespaces                |
| `clang-reorder-fields.exe`     | Reorder struct/class fields          |
| `clang-doc.exe`                | Generate documentation from source   |
| `clang-extdef-mapping.exe`     | Cross-TU analysis index generator    |
| `modularize.exe`               | Check header modularity              |
| `pp-trace.exe`                 | Preprocessor event tracer            |
| `find-all-symbols.exe`         | Index all symbols for include-fixer  |

### Archive & Object Tools (`bin/`)

| Tool                         | Description                                        |
| ---------------------------- | -------------------------------------------------- |
| `llvm-ar.exe`                | Create/modify static archives (`.a` / `.lib`)      |
| `llvm-ranlib.exe`            | Generate archive index                             |
| `llvm-lib.exe`               | MSVC-compatible `lib.exe` replacement              |
| `llvm-nm.exe`                | List symbols in object files                       |
| `llvm-objcopy.exe`           | Copy and transform object files                    |
| `llvm-objdump.exe`           | Disassemble object files                           |
| `llvm-strip.exe`             | Strip symbols from binaries                        |
| `llvm-size.exe`              | Print section sizes                                |
| `llvm-strings.exe`           | Print printable strings in binaries                |
| `llvm-readelf.exe`           | Display ELF file info                              |
| `llvm-readobj.exe`           | Display object file info (all formats)             |
| `llvm-dlltool.exe`           | Create import libraries for DLLs                   |
| `llvm-windres.exe`           | Windows resource compiler (GNU windres compatible) |
| `llvm-rc.exe`                | Windows resource compiler (rc.exe compatible)      |
| `llvm-mt.exe`                | Manifest tool                                      |
| `llvm-cvtres.exe`            | Convert `.res` to COFF object                      |
| `llvm-lipo.exe`              | Create/inspect universal (fat) binaries            |
| `llvm-otool.exe`             | Mach-O object file viewer                          |
| `llvm-install-name-tool.exe` | Change Mach-O install names                        |
| `llvm-bitcode-strip.exe`     | Strip LLVM bitcode from binaries                   |
| `llvm-ifs.exe`               | Interface stub generator                           |
| `llvm-readtapi.exe`          | Read Apple TAPI files                              |

### Debug Info Tools (`bin/`)

| Tool                          | Description                                           |
| ----------------------------- | ----------------------------------------------------- |
| `llvm-pdbutil.exe`            | Inspect/dump PDB debug info files                     |
| `llvm-dwarfdump.exe`          | Dump DWARF debug info                                 |
| `llvm-dwarfutil.exe`          | DWARF debug info manipulation                         |
| `llvm-dwp.exe`                | DWARF package file (`.dwp`) creator                   |
| `llvm-debuginfo-analyzer.exe` | Analyze debug info quality                            |
| `llvm-gsymutil.exe`           | GSYM debug info tool                                  |
| `llvm-symbolizer.exe`         | Symbolize addresses (for sanitizer/crash reports)     |
| `llvm-addr2line.exe`          | Convert addresses to file/line (addr2line compatible) |
| `llvm-undname.exe`            | Demangle MSVC C++ names                               |
| `llvm-cxxfilt.exe`            | Demangle C++ names (Itanium ABI)                      |
| `llvm-cxxdump.exe`            | Dump C++ ABI data                                     |
| `llvm-cxxmap.exe`             | Map C++ mangled names between ABIs                    |
| `diagtool.exe`                | Clang diagnostic information tool                     |

### Profiling & Coverage (`bin/`)

| Tool                    | Description                               |
| ----------------------- | ----------------------------------------- |
| `llvm-profdata.exe`     | Merge/convert profile data files          |
| `llvm-profgen.exe`      | Generate profile from perf data (AutoFDO) |
| `llvm-cov.exe`          | Code coverage report generator            |
| `llvm-xray.exe`         | XRay function tracing analysis            |
| `llvm-opt-report.exe`   | Optimization report viewer                |
| `llvm-cgdata.exe`       | Call graph profile data tool              |
| `llvm-ctxprof-util.exe` | Context-sensitive profile utility         |
| `sancov.exe`            | Sanitizer coverage analysis               |
| `sanstats.exe`          | Sanitizer statistics viewer               |

### Compiler Backend & IR Tools (`bin/`)

| Tool                            | Description                                         |
| ------------------------------- | --------------------------------------------------- |
| `opt.exe`                       | LLVM IR optimizer                                   |
| `llc.exe`                       | LLVM IR → machine code compiler                     |
| `lli.exe`                       | LLVM IR interpreter / JIT                           |
| `llvm-as.exe`                   | LLVM assembly → bitcode                             |
| `llvm-dis.exe`                  | LLVM bitcode → assembly                             |
| `llvm-link.exe`                 | Link LLVM bitcode modules                           |
| `llvm-extract.exe`              | Extract functions from bitcode                      |
| `llvm-split.exe`                | Split bitcode into multiple modules                 |
| `llvm-diff.exe`                 | Diff two LLVM bitcode files                         |
| `llvm-bcanalyzer.exe`           | Analyze bitcode file structure                      |
| `llvm-mc.exe`                   | Machine code assembler/disassembler                 |
| `llvm-mca.exe`                  | Machine code analyzer (throughput/latency)          |
| `llvm-ml.exe` / `llvm-ml64.exe` | MASM-compatible assembler                           |
| `llvm-lto2.exe`                 | LTO (Link-Time Optimization) tool                   |
| `llvm-remarkutil.exe`           | Optimization remark utility                         |
| `llvm-config.exe`               | Print LLVM build configuration                      |
| `llvm-tli-checker.exe`          | Target library info checker                         |
| `llvm-cfi-verify.exe`           | Verify CFI (Control Flow Integrity) instrumentation |

### Offload / GPU (`bin/`)

| Tool                         | Description                                  |
| ---------------------------- | -------------------------------------------- |
| `clang-offload-bundler.exe`  | Bundle/unbundle offload device code          |
| `clang-offload-packager.exe` | Package offload device images                |
| `clang-scan-deps.exe`        | Scan C++ module dependencies (C++20 modules) |

---

## 14. VTune Profiling & PGO

### VTune Integration

Enable VTune ITT API annotations and profiling targets:

```powershell
cmake -G Ninja -B build `
    -DCMAKE_TOOLCHAIN_FILE="$env:COCA_TOOLCHAIN\cmake\toolchain.cmake" `
    -DCOCA_TARGET_PROFILE=win-x64 `
    -DCOCA_ENABLE_VTUNE=ON
cmake --build build
```

In CMakeLists.txt:
```cmake
# Link ITT API annotations to your target
target_link_libraries(myapp PRIVATE COCA::ittnotify)

# Create a profiling target: cmake --build . --target vtune_myapp
coca_vtune_profile(TARGET myapp ANALYSIS_TYPE hotspots DURATION 10)
```

### Profile-Guided Optimization (PGO)

3-stage workflow: instrument → collect profiles → optimize:

```powershell
cmake -G Ninja -B build `
    -DCMAKE_TOOLCHAIN_FILE="$env:COCA_TOOLCHAIN\cmake\toolchain.cmake" `
    -DCOCA_TARGET_PROFILE=win-x64 `
    -DCOCA_ENABLE_PGO=ON
```

In CMakeLists.txt:
```cmake
# Stage 1: Build instrumented binary
coca_pgo_instrument(TARGET myapp)

# Stage 2: Run to collect profiles, then merge
coca_pgo_merge(TARGET myapp PROFILE_DIR ./pgo_profiles)

# Stage 3: Rebuild with profile data
coca_pgo_optimize(TARGET myapp PROFILE_DATA merged.profdata)
```

---

## 15. Self-Test Suite (105 tests)

The toolchain includes a comprehensive self-test suite that validates all components:

```powershell
# Run all 105 tests
python setup.py test

# Run with verbose output (shows every command)
python setup.py -v test

# Filter by phase
python setup.py test --filter tools       # 30 tool reachability tests
python setup.py test --filter sysroots     # 59 sysroot file checks
python setup.py test --filter compile      # 7 native compilation tests
python setup.py test --filter cross        # 9 cross-compilation profiles
python setup.py test --filter sanitizers   # 4 ASan/UBSan/Coverage tests
python setup.py test --filter cmake        # 4 CMake integration tests

# Filter by specific test
python setup.py test --filter compile.c    # Just the C compilation pipeline
python setup.py test --filter cross.linux-x64  # Just linux-x64 cross-compile
```

### Test Phases

| Phase        | Tests | Description                                                    |
| ------------ | ----- | -------------------------------------------------------------- |
| `tools`      | 30    | Verify every bundled tool is executable and reports a version  |
| `sysroots`   | 59    | Verify critical headers and libraries exist in each sysroot    |
| `compile`    | 7     | Native C/C++23/Fortran compilation pipeline on Windows         |
| `cross`      | 1→9   | Cross-compile hello-world for all non-native profiles          |
| `sanitizers` | 4     | ASan/UBSan compile, coverage compile+run, llvm-profdata merge  |
| `cmake`      | 4     | CMake configure+build+run with toolchain.cmake, clang++ driver |

---

## 16. Troubleshooting

### "unable to find library -lgcc_s"
This occurs when building shared sanitizer libraries for Linux. Static sanitizer libraries (`.a`) work correctly and are the default.

### Emscripten "SyntaxError: invalid syntax" (match statement)
The `em++.bat` wrapper may pick up a system Python that is too old. Always use the emsdk's bundled Python:
```powershell
& "$env:COCA_TOOLCHAIN\tools\emsdk\python\3.13.3_64bit\python.exe" `
    "$env:COCA_TOOLCHAIN\tools\emsdk\upstream\emscripten\em++.py" ...
```

### Windows UBSan linker errors
Use trap mode (`-fsanitize-trap=all`) on Windows to avoid runtime library dependency issues with MSVC.

### Coverage: "malformed instrumentation profile data"
Use `clang++.exe` (not `clang-cl.exe`) for coverage instrumentation to avoid ABI mismatches with the profile runtime.

### WASM: "-fuse-ld=wasm-ld" error
Do not pass `-fuse-ld=wasm-ld`. Clang automatically selects `wasm-ld` when targeting `wasm32-*`. Just omit the flag.
