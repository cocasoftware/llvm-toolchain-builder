# LLVM Toolchain Builder

## Project Overview

This repository builds a complete, self-contained LLVM/Clang toolchain for distribution.
The build is a **three-stage process** running in GitHub Actions CI:

1. **Bootstrap**: Builds GCC 14, CMake, Python 3.12, Ninja, SWIG, OpenSSL, and other dependencies from source inside Ubuntu 16.04 Docker containers (for maximum glibc compatibility).
2. **Stage 1**: Minimal clang + lld built using bootstrap GCC. Produces a working clang compiler that will be used to build the final toolchain.
3. **Stage 2**: Full LLVM toolchain (clang, lld, lldb, flang, mlir, polly, bolt, compiler-rt, libc++, libunwind, openmp, etc.) built using Stage 1 clang with `-stdlib=libc++`.

Two variants are built:
- **main**: Official LLVM 21.1.1 release
- **p2996**: Bloomberg's clang-p2996 fork (C++ reflection TS)

Three platforms are supported:
- **linux-x64**: Ubuntu 16.04 x86_64 (Docker on `ubuntu-latest`)
- **linux-arm64**: Ubuntu 16.04 aarch64 (Docker on `ubuntu-24.04-arm`)
- **windows-x64**: Windows Server 2022 (Stage 1: MSVC, Stage 2: clang-cl + libc++)

## Repository Structure

```
.github/
  workflows/
    build-toolchain.yml       — Linux x86_64 CI workflow
    build-toolchain-arm64.yml — Linux ARM64 CI workflow
    build-toolchain-win.yml   — Windows x64 CI workflow
scripts/
  common/
    versions.sh               — LLVM version, project lists, target lists
    source.sh                 — Source download/extraction logic
    llvm-config.sh            — Dispatcher: sources stage1 or stage2 config
    llvm-config-common.sh     — Shared CMake args (both stages)
    llvm-config-stage1.sh     — Stage 1 CMake args (cache-sensitive)
    llvm-config-stage2.sh     — Stage 2 CMake args
    post-install.sh           — Bundle libs, fix rpaths, strip, create archive
  bootstrap/
    common-bootstrap.sh       — Bootstrap build logic (GCC, Python, OpenSSL, etc.)
  linux-x64/
    build-llvm-stage1.sh      — Stage 1 build script (x86_64)
    build-llvm-stage2.sh      — Stage 2 build script (x86_64)
  linux-arm64/
    build-llvm-stage1.sh      — Stage 1 build script (ARM64)
    build-llvm-stage2.sh      — Stage 2 build script (ARM64)
  windows-x64/
    build-llvm.ps1            — Windows Stage 1 build script (MSVC)
    build-llvm-stage2.ps1     — Windows Stage 2 build script (clang-cl + libc++)
    verify-portability.ps1    — Post-build verification
```

## Key Architecture Decisions

- **`LLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF`**: Runtimes install to `lib/` not `lib/<triple>/`, so `$ORIGIN/../lib` rpath works universally.
- **Linux Stage 2 uses `-stdlib=libc++`** in `CMAKE_CXX_FLAGS` (not linker flags, to avoid polluting C compiler tests).
- **Linux Stage 2 linker flags** include `-L` paths (link-time) and `-Wl,-rpath` (runtime) for Stage 1 and bootstrap lib directories.
- **`LD_LIBRARY_PATH`** in Linux Stage 2 build scripts includes the build tree's `lib/` so host tools (flang, etc.) can find freshly-built shared libs.
- **Linux cache strategy**: Stage 1 cache key only hashes `llvm-config-common.sh` + `llvm-config-stage1.sh`, so Stage 2-only changes don't trigger Stage 1 rebuilds.
- **Windows dual-stage**: Stage 1 uses MSVC cl.exe, Stage 2 uses Stage 1 clang-cl.exe with libc++ as default C++ stdlib. Windows does NOT build libunwind/libcxxabi (uses SEH + MSVC ABI).
- **Windows cache strategy**: Stage 1 cache key hashes `build-llvm.ps1`, so Stage 2-only changes (to `build-llvm-stage2.ps1`) don't trigger Stage 1 rebuilds.
- **Windows Stage 2 defaults**: `CLANG_DEFAULT_CXX_STDLIB=libc++`, `CLANG_DEFAULT_RTLIB=compiler-rt`, `CLANG_DEFAULT_LINKER=lld`.

## Build Environment

- Linux builds run inside `ubuntu:16.04` Docker containers with bind-mounted `/opt/bootstrap` and `/opt/stage1`.
- System packages needed in Docker: `binutils`, `libc6-dev`, `patchelf`, `file`, `xz-utils`, `ca-certificates`, `git`.
- Bootstrap prefix: `/opt/bootstrap`
- Stage 1 prefix: `/opt/stage1`
- Stage 2 install prefix: `/opt/coca-toolchain`
- Stage 2 build dir: `/tmp/stage2-build`

## Common Failure Patterns

When diagnosing CI failures, check these in order:
1. **`unable to find library -l<name>`**: Missing `-L` path in linker flags or library not installed where expected.
2. **`libc++.so.1: cannot open shared object file`**: Missing from `LD_LIBRARY_PATH` or rpath. Check if PER_TARGET_RUNTIME_DIR is consistent.
3. **`relocation error` / `symbol version not defined`**: Build-tree `lib/` not in `LD_LIBRARY_PATH`, causing host tools to load wrong shared lib version.
4. **CMake C compiler test fails**: Often caused by linker flags that only make sense for C++ (e.g., `-stdlib=libc++`).
5. **OOM / `basic_string::_M_create`**: May actually be corrupted data from loading wrong shared libs, not true OOM.

## Fix Guidelines

- **Root cause fixes only**: Never use workarounds. If a library path is wrong, fix the path — don't symlink.
- **Architecture integrity**: Changes must maintain the stage1/stage2 separation and cache strategy.
- **No technical debt**: Every fix should be the correct, long-term solution.
- **Test the fix mentally**: Will it work on x86_64, ARM64, AND Windows? If not, use platform guards.
