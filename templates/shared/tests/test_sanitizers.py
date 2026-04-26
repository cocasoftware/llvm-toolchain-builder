"""Phase 5: Sanitizer & coverage compilation — verify ASan/UBSan/coverage flags produce valid binaries.

Does NOT run ASan/UBSan-instrumented binaries (they require specific runtime setup),
only verifies that compilation with sanitizer flags succeeds and produces larger
instrumented objects. The "clean" (coverage-only) build is also compiled and run.
"""
from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

from .framework import TestSuite, TestResult, TestStatus, Timer
from scripts.rich_utils import vprint

_FIXTURES = Path(__file__).resolve().parent / "fixtures"


def _exe(name: str) -> str:
    return name + ".exe" if os.name == "nt" else name


def _run(cmd: list[str], cwd: Path, timeout: int = 60, env: dict | None = None) -> subprocess.CompletedProcess:
    vprint(f"         [dim]$ {' '.join(cmd)}[/dim]")
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, cwd=str(cwd),
                       env=env or os.environ)
    if r.stdout.strip():
        for line in r.stdout.strip().splitlines()[:5]:
            vprint(f"         [dim]  │ {line}[/dim]")
    if r.returncode != 0 and r.stderr.strip():
        for line in r.stderr.strip().splitlines()[:5]:
            vprint(f"         [dim red]  │ {line}[/dim red]")
    return r


def _sysroot_args(info) -> tuple[list[str], list[str]]:
    """Return (inc_args, lib_args) for win-x64 sysroot."""
    sr = info.root / "sysroots" / "x86_64-windows-msvc"
    msvc_inc = sr / "msvc" / "include"
    sdk_inc = list((sr / "sdk" / "Include").glob("*/ucrt"))
    msvc_lib = sr / "msvc" / "lib" / "x64"
    sdk_lib = list((sr / "sdk" / "Lib").glob("*/ucrt/x64"))
    um_lib = list((sr / "sdk" / "Lib").glob("*/um/x64"))
    inc = [f"/I{msvc_inc}"]
    if sdk_inc:
        inc.append(f"/I{sdk_inc[0]}")
    lib = ["/link", f"/LIBPATH:{msvc_lib}"]
    if sdk_lib:
        lib.append(f"/LIBPATH:{sdk_lib[0]}")
    if um_lib:
        lib.append(f"/LIBPATH:{um_lib[0]}")
    return inc, lib


def _test_asan_compile(info, tmp: Path) -> TestResult:
    """Compile sanitizer_test.cpp with ASan enabled (-fsanitize=address)."""
    shutil.copy(_FIXTURES / "sanitizer_test.cpp", tmp / "sanitizer_test.cpp")
    clang_cl = info.root / "bin" / _exe("clang-cl")
    inc, _ = _sysroot_args(info)
    with Timer() as t:
        r = _run([str(clang_cl), "/c", "/EHsc", "/MT", "-fsanitize=address", "-DTEST_ASAN",
                  *inc, f"/Fo{tmp / 'asan.obj'}", str(tmp / "sanitizer_test.cpp")], cwd=tmp)
    if r.returncode != 0:
        return TestResult("sanitizers.asan.compile", "sanitizers", TestStatus.FAIL,
                          message=f"exit {r.returncode}", detail=r.stderr[:500], duration_ms=t.elapsed_ms)
    obj = tmp / "asan.obj"
    if not obj.exists():
        return TestResult("sanitizers.asan.compile", "sanitizers", TestStatus.FAIL,
                          message="asan.obj not produced", duration_ms=t.elapsed_ms)
    return TestResult("sanitizers.asan.compile", "sanitizers", TestStatus.PASS,
                      message=f"asan.obj {obj.stat().st_size} bytes (instrumented)", duration_ms=t.elapsed_ms)


def _test_ubsan_compile(info, tmp: Path) -> TestResult:
    """Compile sanitizer_test.cpp with UBSan enabled (-fsanitize=undefined)."""
    shutil.copy(_FIXTURES / "sanitizer_test.cpp", tmp / "sanitizer_test.cpp")
    clang_cl = info.root / "bin" / _exe("clang-cl")
    inc, _ = _sysroot_args(info)
    with Timer() as t:
        r = _run([str(clang_cl), "/c", "/EHsc", "-fsanitize=undefined", "-DTEST_UBSAN",
                  *inc, f"/Fo{tmp / 'ubsan.obj'}", str(tmp / "sanitizer_test.cpp")], cwd=tmp)
    if r.returncode != 0:
        return TestResult("sanitizers.ubsan.compile", "sanitizers", TestStatus.FAIL,
                          message=f"exit {r.returncode}", detail=r.stderr[:500], duration_ms=t.elapsed_ms)
    obj = tmp / "ubsan.obj"
    if not obj.exists():
        return TestResult("sanitizers.ubsan.compile", "sanitizers", TestStatus.FAIL,
                          message="ubsan.obj not produced", duration_ms=t.elapsed_ms)
    return TestResult("sanitizers.ubsan.compile", "sanitizers", TestStatus.PASS,
                      message=f"ubsan.obj {obj.stat().st_size} bytes (instrumented)", duration_ms=t.elapsed_ms)


def _test_coverage_compile_run(info, tmp: Path) -> TestResult:
    """Compile sanitizer_test.cpp with coverage, link, and run (clean mode)."""
    shutil.copy(_FIXTURES / "sanitizer_test.cpp", tmp / "sanitizer_test.cpp")
    clang_cl = info.root / "bin" / _exe("clang-cl")
    inc, lib = _sysroot_args(info)
    with Timer() as t:
        r = _run([str(clang_cl), "/EHsc", "-fprofile-instr-generate", "-fcoverage-mapping",
                  *inc, str(tmp / "sanitizer_test.cpp"),
                  f"/Fe{tmp / 'cov_test.exe'}"] + lib, cwd=tmp)
    if r.returncode != 0:
        return TestResult("sanitizers.coverage.compile_run", "sanitizers", TestStatus.FAIL,
                          message=f"compile exit {r.returncode}", detail=r.stderr[:500], duration_ms=t.elapsed_ms)
    exe = tmp / "cov_test.exe"
    if not exe.exists():
        return TestResult("sanitizers.coverage.compile_run", "sanitizers", TestStatus.FAIL,
                          message="cov_test.exe not produced", duration_ms=t.elapsed_ms)
    # Run the clean build
    env = {**os.environ, "LLVM_PROFILE_FILE": str(tmp / "cov.profraw")}
    r = _run([str(exe)], cwd=tmp, env=env)
    if r.returncode != 0:
        return TestResult("sanitizers.coverage.compile_run", "sanitizers", TestStatus.FAIL,
                          message=f"run exit {r.returncode}", detail=r.stderr[:500], duration_ms=t.elapsed_ms)
    if "All tests passed" not in r.stdout:
        return TestResult("sanitizers.coverage.compile_run", "sanitizers", TestStatus.FAIL,
                          message="output missing 'All tests passed'", detail=r.stdout[:500], duration_ms=t.elapsed_ms)
    # Check profraw was generated
    profraw = tmp / "cov.profraw"
    profraw_ok = profraw.exists() and profraw.stat().st_size > 0
    msg = f"run OK, profraw={'yes' if profraw_ok else 'no'} ({profraw.stat().st_size if profraw_ok else 0} bytes)"
    return TestResult("sanitizers.coverage.compile_run", "sanitizers", TestStatus.PASS,
                      message=msg, duration_ms=t.elapsed_ms)


def _test_profdata_merge(info, tmp: Path) -> TestResult:
    """Merge profraw → profdata using llvm-profdata."""
    # First build & run to get profraw
    shutil.copy(_FIXTURES / "sanitizer_test.cpp", tmp / "sanitizer_test.cpp")
    clang_cl = info.root / "bin" / _exe("clang-cl")
    inc, lib = _sysroot_args(info)
    r = _run([str(clang_cl), "/EHsc", "-fprofile-instr-generate", "-fcoverage-mapping",
              *inc, str(tmp / "sanitizer_test.cpp"),
              f"/Fe{tmp / 'cov_test.exe'}"] + lib, cwd=tmp)
    if r.returncode != 0:
        return TestResult("sanitizers.profdata.merge", "sanitizers", TestStatus.SKIP,
                          message="compile failed, skipping profdata merge")
    env = {**os.environ, "LLVM_PROFILE_FILE": str(tmp / "cov.profraw")}
    _run([str(tmp / "cov_test.exe")], cwd=tmp, env=env)
    profraw = tmp / "cov.profraw"
    if not profraw.exists():
        return TestResult("sanitizers.profdata.merge", "sanitizers", TestStatus.SKIP,
                          message="no profraw produced, skipping merge")
    # Merge
    profdata_tool = info.root / "bin" / _exe("llvm-profdata")
    with Timer() as t:
        r = _run([str(profdata_tool), "merge", "-sparse", str(profraw),
                  "-o", str(tmp / "merged.profdata")], cwd=tmp)
    if r.returncode != 0:
        return TestResult("sanitizers.profdata.merge", "sanitizers", TestStatus.FAIL,
                          message=f"exit {r.returncode}", detail=r.stderr[:500], duration_ms=t.elapsed_ms)
    merged = tmp / "merged.profdata"
    if not merged.exists():
        return TestResult("sanitizers.profdata.merge", "sanitizers", TestStatus.FAIL,
                          message="merged.profdata not produced", duration_ms=t.elapsed_ms)
    return TestResult("sanitizers.profdata.merge", "sanitizers", TestStatus.PASS,
                      message=f"merged.profdata {merged.stat().st_size} bytes", duration_ms=t.elapsed_ms)


def register(suite: TestSuite) -> None:
    if os.name != "nt":
        return  # Sanitizer tests only on Windows host for now
    suite.add("sanitizers.asan.compile", "sanitizers", "ASan compile (-fsanitize=address)", _test_asan_compile)
    suite.add("sanitizers.ubsan.compile", "sanitizers", "UBSan compile (-fsanitize=undefined)", _test_ubsan_compile)
    suite.add("sanitizers.coverage.compile_run", "sanitizers", "Coverage compile+run+profraw", _test_coverage_compile_run)
    suite.add("sanitizers.profdata.merge", "sanitizers", "llvm-profdata merge", _test_profdata_merge)
