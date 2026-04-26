"""Phase 2: Sysroot integrity — verify key files exist in each profile's sysroot."""
from __future__ import annotations

from pathlib import Path

from .framework import TestSuite, TestResult, TestStatus, Timer

# Per-runtime sysroot expectations: (glob_or_path, description)
# These must exist relative to the sysroot directory.
_SYSROOT_CHECKS: dict[str, list[tuple[str, str]]] = {
    "msvc": [
        ("msvc/include/vcruntime.h",    "MSVC vcruntime header"),
        ("msvc/include/crtdefs.h",      "MSVC CRT defs header"),
        ("msvc/lib/x64/msvcrt.lib",     "MSVC runtime import lib"),
        ("msvc/lib/x64/vcruntime.lib",  "MSVC vcruntime lib"),
        ("sdk/Include/*/ucrt/stdio.h",  "UCRT stdio header"),
        ("sdk/Include/*/um/Windows.h",  "Windows SDK header"),
        ("sdk/Lib/*/ucrt/x64/ucrt.lib", "UCRT lib"),
        ("sdk/Lib/*/um/x64/kernel32.Lib", "kernel32 import lib"),
    ],
    "llvm-glibc-x64": [
        ("usr/include/stdio.h",         "glibc stdio header"),
        ("usr/include/stdlib.h",        "glibc stdlib header"),
        ("usr/include/linux/version.h", "Linux kernel header"),
        ("usr/lib/x86_64-linux-gnu/crt1.o",   "CRT startup object"),
        ("usr/lib/x86_64-linux-gnu/libc.so",  "glibc linker script"),
        ("lib/x86_64-linux-gnu/ld-linux-x86-64.so.2", "dynamic linker"),
    ],
    "llvm-glibc-arm64": [
        ("usr/include/stdio.h",         "glibc stdio header"),
        ("usr/include/stdlib.h",        "glibc stdlib header"),
        ("usr/include/linux/version.h", "Linux kernel header"),
        ("usr/lib/aarch64-linux-gnu/crt1.o",   "CRT startup object"),
        ("usr/lib/aarch64-linux-gnu/libc.so",  "glibc linker script"),
        ("lib/aarch64-linux-gnu/ld-linux-aarch64.so.1", "dynamic linker"),
    ],
    "llvm-musl-x64": [
        ("usr/include/stdio.h",         "musl stdio header"),
        ("usr/include/stdlib.h",        "musl stdlib header"),
        ("usr/lib/crt1.o",             "musl CRT startup object"),
        ("usr/lib/libc.a",             "musl static libc"),
    ],
    "llvm-musl-arm64": [
        ("usr/include/stdio.h",         "musl stdio header"),
        ("usr/include/stdlib.h",        "musl stdlib header"),
        ("usr/lib/crt1.o",             "musl CRT startup object"),
        ("usr/lib/libc.a",             "musl static libc"),
    ],
    "mingw-ucrt": [
        ("include/stdio.h",            "MinGW stdio header"),
        ("include/windows.h",          "MinGW Windows header"),
        ("lib/libkernel32.a",          "MinGW kernel32 lib"),
        ("lib/crt2.o",                 "MinGW CRT startup"),
    ],
    "mingw-msvcrt": [
        ("include/stdio.h",            "MinGW stdio header"),
        ("include/windows.h",          "MinGW Windows header"),
        ("lib/libkernel32.a",          "MinGW kernel32 lib"),
        ("lib/crt2.o",                 "MinGW CRT startup"),
    ],
    "wasi": [
        ("include/wasm32-wasip1/stdio.h", "WASI stdio header"),
        ("lib/wasm32-wasip1/libc.a", "WASI libc"),
        ("lib/wasm32-wasip1/crt1.o", "WASI CRT startup"),
    ],
}

# Map profile names to check keys
_PROFILE_TO_CHECK: dict[str, str] = {
    "win-x64":              "msvc",
    "win-x64-clang":        "msvc",
    "linux-x64":            "llvm-glibc-x64",
    "linux-x64-kylin":      "llvm-glibc-x64",
    "linux-arm64":          "llvm-glibc-arm64",
    "linux-arm64-kylin":    "llvm-glibc-arm64",
    "linux-x64-musl":       "llvm-musl-x64",
    "linux-arm64-musl":     "llvm-musl-arm64",
    "win-x64-mingw-ucrt":   "mingw-ucrt",
    "win-x64-mingw-msvcrt": "mingw-msvcrt",
    "wasm-wasi":            "wasi",
    # wasm-emscripten has no sysroot (managed by emsdk)
}


def _make_sysroot_test(profile: str, check_key: str, rel_glob: str, desc: str):
    def _test(info, tmp_dir: Path) -> TestResult:
        sr_rel = info.toolchain_json.get("profiles", {}).get(profile, {}).get("sysroot")
        if not sr_rel:
            return TestResult(f"sysroots.{profile}.{desc}", "sysroots", TestStatus.SKIP,
                              message=f"no sysroot for {profile}")
        sr = info.root / sr_rel
        if not sr.exists():
            return TestResult(f"sysroots.{profile}.{desc}", "sysroots", TestStatus.FAIL,
                              message=f"sysroot dir missing: {sr_rel}")
        with Timer() as t:
            if "*" in rel_glob:
                matches = list(sr.glob(rel_glob))
                ok = len(matches) > 0
                detail = f"glob matched {len(matches)} file(s)" if ok else f"no match for {rel_glob}"
            else:
                p = sr / rel_glob
                ok = p.exists()
                detail = str(p)
        return TestResult(
            f"sysroots.{profile}.{desc}", "sysroots",
            TestStatus.PASS if ok else TestStatus.FAIL,
            message=desc, detail=detail, duration_ms=t.elapsed_ms,
        )
    return _test


def register(suite: TestSuite) -> None:
    for profile, check_key in _PROFILE_TO_CHECK.items():
        checks = _SYSROOT_CHECKS.get(check_key, [])
        for rel_glob, desc in checks:
            safe_desc = desc.replace(" ", "_").lower()
            suite.add(f"sysroots.{profile}.{safe_desc}", "sysroots",
                      f"[{profile}] {desc}",
                      _make_sysroot_test(profile, check_key, rel_glob, desc))
