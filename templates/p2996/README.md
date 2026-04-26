# COCA Toolchain — P2996 (C++ Reflection)

A variant of the COCA Toolchain based on the [Bloomberg clang-p2996 fork](https://github.com/bloomberg/clang-p2996), providing **C++ Reflection (P2996)** support via `-std=c++26 -freflection`. This variant is **independently distributable** — it contains its own complete copy of all sysroots, tools, and data.

> **This toolchain is for reflection experimentation.** For production builds, sanitizers, code coverage, VTune, PGO, and full tool suite, use the main `coca-toolchain`.

## Component Versions

| Component                        | Version      | Notes                                             |
| -------------------------------- | ------------ | ------------------------------------------------- |
| LLVM (Clang / LLD / compiler-rt) | 21.0.0git    | Bloomberg clang-p2996 fork                        |
| libc++ / libc++abi / libunwind   | 21.0.0git    | Built from p2996 fork, vcruntime ABI on Windows   |
| C++ Reflection                   | P2996        | `-std=c++26 -freflection`, `<meta>` header        |
| MSVC toolset                     | 14.50.35717  |                                                   |
| Windows SDK                      | 10.0.26100.0 |                                                   |
| glibc sysroot (x64)              | 2.19+        | Junction → coca-toolchain (Bookworm libs 2.36)    |
| glibc sysroot (arm64)            | 2.23+        | Junction → coca-toolchain (Bookworm libs 2.36)    |
| MinGW-w64                        | 12.0.0       | UCRT and MSVCRT variants                          |
| Linux kernel headers             | 6.1.0        |                                                   |
| wasi-sdk                         | 30.0         |                                                   |
| Emscripten SDK                   | 5.0.0        |                                                   |
| CMake                            | 4.2.3        |                                                   |
| Ninja                            | 1.13.1       |                                                   |
| Rust                             | 1.93.1       | Bundled rustup + cargo + 8 targets                |
| Python                           | 3.14.4       | python-build-standalone, full stdlib + pip + venv |
| Git                              | 2.53.0       |                                                   |
| Doxygen                          | 1.16.1       |                                                   |
| Graphviz                         | 14.1.2       |                                                   |
| Perl                             | 5.42.0       | Strawberry Perl                                   |
| Conan                            | 2.25.2       |                                                   |
| JFrog CLI                        | 2.72.2       |                                                   |
| wasmtime                         | 41.0.3       |                                                   |
| Intel VTune                      | 2025.0.1     | Bundled profiler + ITT API                        |
| Intel Fortran (ifort)            | classic      | Wrapper for mixed C++/Fortran projects            |
| RenderDoc                        | 1.43         | GPU frame capture                                 |
| rsync                            | 3.4.1        | Incremental file sync for deployment              |
| PowerShell (pwsh)                | 7.5.5        | Bundled shell for `exec` sandbox                  |

## Supported Target Profiles (10)

| Profile                | Target Triple               | Runtime    | Linker   | Notes                                         |
| ---------------------- | --------------------------- | ---------- | -------- | --------------------------------------------- |
| `win-x64`              | `x86_64-pc-windows-msvc`    | MSVC       | lld-link | Windows x64 native, clang-cl driver           |
| `win-x64-clang`        | `x86_64-pc-windows-msvc`    | MSVC       | lld-link | Same ABI, clang++ GNU driver                  |
| `linux-x64`            | `x86_64-unknown-linux-gnu`  | LLVM       | ld.lld   | Linux x86_64 (glibc ≥ 2.19)                   |
| `linux-arm64`          | `aarch64-unknown-linux-gnu` | LLVM       | ld.lld   | Linux AArch64 (glibc ≥ 2.23)                  |
| `linux-x64-kylin`      | `x86_64-unknown-linux-gnu`  | LLVM       | ld.lld   | Kylin OS x86_64 (shares linux-x64 sysroot)    |
| `linux-arm64-kylin`    | `aarch64-unknown-linux-gnu` | LLVM       | ld.lld   | Kylin OS AArch64 (shares linux-arm64 sysroot) |
| `win-x64-mingw-ucrt`   | `x86_64-w64-mingw32`        | MinGW      | ld.lld   | Windows x64, MinGW UCRT                       |
| `win-x64-mingw-msvcrt` | `x86_64-w64-mingw32`        | MinGW      | ld.lld   | Windows x64, MinGW MSVCRT (legacy)            |
| `wasm-wasi`            | `wasm32-wasip1`             | WASI       | wasm-ld  | WebAssembly WASI                              |
| `wasm-emscripten`      | `wasm32-unknown-emscripten` | Emscripten | wasm-ld  | WebAssembly browser                           |

> **Note:** musl profiles (`linux-x64-musl`, `linux-arm64-musl`) are not available in the p2996 variant. Use the main `coca-toolchain` for fully-static musl builds.

## Directory Layout

```
coca-toolchain-p2996/
├── bin/                              # LLVM host tools (p2996 fork)
│   ├── clang.exe / clang++.exe       # C/C++ compiler with -freflection
│   ├── clang-cl.exe                  # MSVC-compatible driver
│   ├── lld.exe / lld-link.exe / ...  # Linkers
│   ├── clangd.exe                    # Language server
│   ├── clang-format.exe / clang-tidy.exe
│   └── ...
├── include/c++/v1/                   # p2996 libc++ headers (with <meta>)
├── lib/
│   ├── libc++.lib / c++.dll          # p2996 libc++ (Windows, vcruntime ABI)
│   └── clang/21/                     # Clang resource directory
├── sysroots/                         # Target sysroots (mix of independent copies and junctions)
│   ├── x86_64-windows-msvc           # Junction → coca-toolchain
│   ├── x86_64-linux-gnu/             # Linux x86_64 (independent copy with p2996 libc++)
│   ├── aarch64-linux-gnu/            # Linux AArch64 (independent copy with p2996 libc++)
│   ├── x86_64-w64-mingw32-ucrt/      # MinGW UCRT
│   ├── x86_64-w64-mingw32-msvcrt/
│   └── wasm32-wasi                   # Junction → coca-toolchain
├── cmake/
│   ├── toolchain.cmake               # Unified CMake toolchain file (10 profiles)
│   ├── coca_rust.cmake               # Rust integration
│   ├── coca_vtune.cmake / coca_pgo.cmake
│   └── bundle.cmake / bundle.py
├── tools/
│   ├── cmake/                        # Bundled CMake
│   ├── ninja/                        # Bundled Ninja
│   ├── python/                       # Python 3.14.4 (python-build-standalone)
│   ├── rust/                         # Bundled Rust toolchain (rustup + cargo + 8 targets)
│   ├── git/                          # Portable Git
│   ├── emsdk/                        # Emscripten SDK
│   ├── wasmtime/                     # WASI runtime
│   ├── vtune/                        # Intel VTune 2025.0.1
│   ├── ifort/                        # Intel Fortran wrapper
│   ├── ml64/                         # MASM x64 assembler
│   ├── renderdoc/                    # GPU frame capture
│   ├── doxygen/                      # Documentation generator
│   ├── graphviz/                     # Graph visualization
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
├── tests/                            # Toolchain self-test suite
├── toolchain.json                    # Profile definitions (10 targets + reflection config)
├── manifest.json                     # Manifest (versions, checksums)
├── setup.py                          # CLI: env, info, check, test, doctor, exec, update-manifest
└── README.md
```

---

## Quick Start

### Environment Setup

```powershell
# PowerShell — using setup.py (recommended)
python C:\path\to\coca-toolchain-p2996\setup.py | Invoke-Expression
```

```bash
# Bash
eval "$(python3 /path/to/coca-toolchain-p2996/setup.py --shell bash)"
```

### setup.py Subcommands

| Subcommand        | Description                                                            |
| ----------------- | ---------------------------------------------------------------------- |
| `env` (default)   | Emit shell commands to stdout for piping                               |
| `info`            | Rich-formatted toolchain summary                                       |
| `check`           | Validate toolchain integrity                                           |
| `test [--filter]` | Run self-test suite; filter by phase or test id                        |
| `doctor`          | Diagnose common problems                                               |
| `update-manifest` | Regenerate `manifest.json` with SHA-256 checksums                      |
| `exec [--shell]`  | Launch interactive shell in sandboxed env with fingerprint-tagged venv |
| `terminal`        | Launch bundled Windows Terminal with COCA profile                      |
| `context-menu`    | Register/unregister Explorer right-click "Open COCA Terminal here"     |

All subcommands support `--verbose` / `-v` for detailed progress output.

### `exec` Subcommand Details

```powershell
python setup.py exec                   # Sandboxed shell (bundled pwsh, auto venv)
python setup.py exec --system-shell    # Use system PowerShell
python setup.py exec --inherit-env     # Inherit full environment (no sandbox)
python setup.py exec --venv-dir PATH   # Custom venv location
python setup.py exec --no-venv         # Skip venv
```

Venv is named `.venv-<fingerprint[:8]>` based on `manifest.json` checksums. Different toolchain versions get isolated venvs; stale ones are auto-cleaned. Bundled **pwsh** is preferred by default; pass `--system-shell` to override.

---

## 1. C++ Reflection (P2996)

The key differentiator of this toolchain: support for the [P2996 Reflection](https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2024/p2996r0.html) proposal.

### Compile Flags

```
-std=c++26 -freflection
```

These are automatically applied by `toolchain.cmake` when `COCA_ENABLE_REFLECTION=ON` (default).

### Example: Compile with Reflection

**Windows (clang-cl):**
```powershell
clang-cl.exe /std:c++26 -Xclang -freflection /EHsc /O2 `
    /imsvc "$env:COCA_TOOLCHAIN\include\c++\v1" `
    /imsvc "$env:COCA_TOOLCHAIN\sysroots\x86_64-windows-msvc\msvc\include" `
    /imsvc "$env:COCA_TOOLCHAIN\sysroots\x86_64-windows-msvc\sdk\Include\10.0.26100.0\ucrt" `
    /imsvc "$env:COCA_TOOLCHAIN\sysroots\x86_64-windows-msvc\sdk\Include\10.0.26100.0\um" `
    /imsvc "$env:COCA_TOOLCHAIN\sysroots\x86_64-windows-msvc\sdk\Include\10.0.26100.0\shared" `
    main.cpp `
    /link /LIBPATH:"$env:COCA_TOOLCHAIN\sysroots\x86_64-windows-msvc\msvc\lib\x64" `
          /LIBPATH:"$env:COCA_TOOLCHAIN\sysroots\x86_64-windows-msvc\sdk\Lib\10.0.26100.0\ucrt\x64" `
          /LIBPATH:"$env:COCA_TOOLCHAIN\sysroots\x86_64-windows-msvc\sdk\Lib\10.0.26100.0\um\x64" `
          /OUT:main.exe
```

**clang++ (GNU driver):**
```powershell
clang++.exe --target=x86_64-pc-windows-msvc `
    -std=c++26 -freflection `
    -fuse-ld=lld -rtlib=compiler-rt -nostdinc++ `
    -isystem "$env:COCA_TOOLCHAIN\include\c++\v1" `
    -lc++ `
    main.cpp -o main.exe
```

### Reflection libc++

The p2996 fork ships its own libc++ with the `<meta>` header:

| File              | Description                                      |
| ----------------- | ------------------------------------------------ |
| `include/c++/v1/` | libc++ headers including `<meta>` for reflection |
| `lib/libc++.lib`  | Static import library                            |
| `lib/c++.lib`     | DLL import library                               |
| `bin/c++.dll`     | Shared library (runtime)                         |

> **ABI note:** The p2996 libc++ is built with vcruntime ABI on Windows (`_LIBCPP_ABI_VCRUNTIME`), so it is ABI-compatible with MSVC's C++ runtime.

### CMake Integration

```powershell
cmake -G Ninja -B build `
    -DCMAKE_TOOLCHAIN_FILE="$env:COCA_TOOLCHAIN\cmake\toolchain.cmake" `
    -DCOCA_TARGET_PROFILE=win-x64
cmake --build build
```

Reflection is **ON by default**. To disable:

```powershell
cmake -G Ninja -B build `
    -DCMAKE_TOOLCHAIN_FILE="$env:COCA_TOOLCHAIN\cmake\toolchain.cmake" `
    -DCOCA_TARGET_PROFILE=win-x64 `
    -DCOCA_ENABLE_REFLECTION=OFF
cmake --build build
```

### CMake Variables

| Variable                    | Required | Default | Description                             |
| --------------------------- | -------- | ------- | --------------------------------------- |
| `COCA_TARGET_PROFILE`       | **Yes**  | —       | Target profile name                     |
| `COCA_TOOLCHAIN_ROOT`       | No       | auto    | Override toolchain root directory       |
| `COCA_CXX_STANDARD`         | No       | `26`    | C++ standard (`20`, `23`, `26`)         |
| `COCA_C_STANDARD`           | No       | `23`    | C standard (`17`, `23`)                 |
| `COCA_ENABLE_REFLECTION`    | No       | `ON`    | Add `-freflection` to compile flags     |
| `COCA_ENABLE_LTO`           | No       | `OFF`   | Enable Link-Time Optimization           |
| `COCA_ENABLE_RUST`          | No       | `OFF`   | Enable Rust integration                 |
| `COCA_ALLOW_AUTO_DETECTION` | No       | `OFF`   | Allow CMake to search host system paths |

---

## 2. Cross-Compilation

All profiles from the main toolchain (except musl) are supported:

### Linux x86_64

```powershell
clang++.exe --target=x86_64-unknown-linux-gnu `
    --sysroot="$env:COCA_TOOLCHAIN\sysroots\x86_64-linux-gnu" `
    -nostdinc++ `
    -isystem "$env:COCA_TOOLCHAIN\sysroots\x86_64-linux-gnu\usr\include\c++\v1" `
    -stdlib=libc++ -rtlib=compiler-rt -unwindlib=libunwind -fuse-ld=lld `
    -std=c++26 -freflection -O2 `
    -o main main.cpp
```

### Linux AArch64

```powershell
clang++.exe --target=aarch64-unknown-linux-gnu `
    --sysroot="$env:COCA_TOOLCHAIN\sysroots\aarch64-linux-gnu" `
    -nostdinc++ `
    -isystem "$env:COCA_TOOLCHAIN\sysroots\aarch64-linux-gnu\usr\include\c++\v1" `
    -stdlib=libc++ -rtlib=compiler-rt -unwindlib=libunwind -fuse-ld=lld `
    -std=c++26 -freflection -O2 `
    -o main main.cpp
```

### CMake (any profile)

```powershell
cmake -G Ninja -B build `
    -DCMAKE_TOOLCHAIN_FILE="$env:COCA_TOOLCHAIN\cmake\toolchain.cmake" `
    -DCOCA_TARGET_PROFILE=linux-x64
cmake --build build
```

---

## 3. Differences from Main Toolchain

| Feature              | coca-toolchain (main)        | coca-toolchain-p2996         |
| -------------------- | ---------------------------- | ---------------------------- |
| LLVM version         | 21.1.8 (upstream)            | 21.0.0git (Bloomberg fork)   |
| C++ Reflection       | ✗                            | ✓ (`-freflection`, `<meta>`) |
| Default C++ standard | C++23                        | C++26                        |
| libc++               | Upstream (sysroot-installed) | Fork (vcruntime ABI, `lib/`) |
| musl profiles        | ✓                            | ✗                            |
| Sanitizers           | ASan, UBSan, MSan, TSan      | Same (p2996 fork)            |
| VTune / PGO          | ✓                            | CMake modules present        |
| Rust integration     | ✓ (bundled)                  | ✓ (bundled)                  |
| Bundled tools        | ~23 tools                    | ~23 tools (same set as main) |

---

## 4. Troubleshooting

### "reflection is not supported" error
Ensure you are using `-std=c++26 -freflection` (both flags required). With `clang-cl`, use `/std:c++26 -Xclang -freflection`.

### Missing `<meta>` header
The `<meta>` header is in `include/c++/v1/`. Ensure the p2996 include path is searched before the sysroot's libc++ path. The CMake toolchain file handles this automatically.

### Sysroot issues
Some sysroots (`x86_64-windows-msvc`, `wasm32-wasi`) are junctions pointing to the main `coca-toolchain`. Linux sysroots (`x86_64-linux-gnu`, `aarch64-linux-gnu`) are independent copies with p2996-built libc++. If sysroot files are missing, re-extract or re-copy them from the distribution archive, or verify the junction targets exist.

### libc++ ABI mismatch
The p2996 libc++ uses vcruntime ABI (`_LIBCPP_ABI_VCRUNTIME`). Do not mix p2996 libc++ objects with upstream libc++ objects in the same binary.
