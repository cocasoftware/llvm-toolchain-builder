"""Phase 3: Native compilation pipeline — preprocess → compile → link → run.

Tests C, C++23, and Fortran compilation on the host platform (win-x64).
Each language is decomposed into atomic pipeline stages so failures are
precisely localizable.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
from pathlib import Path

from .framework import TestSuite, TestResult, TestStatus, Timer
from scripts.rich_utils import vprint

_FIXTURES = Path(__file__).resolve().parent / "fixtures"


def _exe(name: str) -> str:
    return name + ".exe" if os.name == "nt" else name


def _run(cmd: list[str], cwd: Path, timeout: int = 30, env: dict | None = None) -> subprocess.CompletedProcess:
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


# ── C Pipeline ───────────────────────────────────────────────────────────────

def _test_c_preprocess(info, tmp: Path) -> TestResult:
    """Stage: Preprocess hello.c → hello.i via clang-cl /E."""
    shutil.copy(_FIXTURES / "hello.c", tmp / "hello.c")
    clang_cl = info.root / "bin" / _exe("clang-cl")
    with Timer() as t:
        r = _run([str(clang_cl), "/E", "hello.c"], cwd=tmp)
    if r.returncode != 0:
        return TestResult("compile.c.preprocess", "compile", TestStatus.FAIL,
                          message=f"exit {r.returncode}", detail=r.stderr[:500], duration_ms=t.elapsed_ms)
    if len(r.stdout) < 50:
        return TestResult("compile.c.preprocess", "compile", TestStatus.FAIL,
                          message="preprocessor output too short", duration_ms=t.elapsed_ms)
    return TestResult("compile.c.preprocess", "compile", TestStatus.PASS,
                      message=f"output {len(r.stdout)} chars", duration_ms=t.elapsed_ms)


def _test_c_compile(info, tmp: Path) -> TestResult:
    """Stage: Compile hello.c → hello.obj via clang-cl /c."""
    shutil.copy(_FIXTURES / "hello.c", tmp / "hello.c")
    clang_cl = info.root / "bin" / _exe("clang-cl")
    with Timer() as t:
        r = _run([str(clang_cl), "/c", "/Fo" + str(tmp / "hello.obj"), str(tmp / "hello.c")], cwd=tmp)
    obj = tmp / "hello.obj"
    if r.returncode != 0:
        return TestResult("compile.c.compile", "compile", TestStatus.FAIL,
                          message=f"exit {r.returncode}", detail=r.stderr[:500], duration_ms=t.elapsed_ms)
    if not obj.exists():
        return TestResult("compile.c.compile", "compile", TestStatus.FAIL,
                          message="hello.obj not produced", duration_ms=t.elapsed_ms)
    # Verify COFF magic
    magic = obj.read_bytes()[:2]
    if magic != b"\x64\x86":  # x86-64 COFF
        return TestResult("compile.c.compile", "compile", TestStatus.FAIL,
                          message=f"unexpected COFF magic: {magic.hex()}", duration_ms=t.elapsed_ms)
    return TestResult("compile.c.compile", "compile", TestStatus.PASS,
                      message=f"hello.obj {obj.stat().st_size} bytes, COFF x86-64", duration_ms=t.elapsed_ms)


def _test_c_link(info, tmp: Path) -> TestResult:
    """Stage: Link hello.obj → hello.exe via lld-link."""
    shutil.copy(_FIXTURES / "hello.c", tmp / "hello.c")
    clang_cl = info.root / "bin" / _exe("clang-cl")
    # Compile first
    r = _run([str(clang_cl), "/c", "/Fo" + str(tmp / "hello.obj"), str(tmp / "hello.c")], cwd=tmp)
    if r.returncode != 0:
        return TestResult("compile.c.link", "compile", TestStatus.SKIP,
                          message="compile stage failed, skipping link")
    # Link
    lld_link = info.root / "bin" / _exe("lld-link")
    sr = info.root / "sysroots" / "x86_64-windows-msvc"
    sdk_lib = list((sr / "sdk" / "Lib").glob("*/ucrt/x64"))
    um_lib = list((sr / "sdk" / "Lib").glob("*/um/x64"))
    msvc_lib = sr / "msvc" / "lib" / "x64"
    lib_paths = [f"/LIBPATH:{msvc_lib}"]
    if sdk_lib:
        lib_paths.append(f"/LIBPATH:{sdk_lib[0]}")
    if um_lib:
        lib_paths.append(f"/LIBPATH:{um_lib[0]}")
    with Timer() as t:
        r = _run([str(lld_link), str(tmp / "hello.obj"), "/out:" + str(tmp / "hello.exe"),
                  "/DEFAULTLIB:libcmt", "/DEFAULTLIB:oldnames", "/SUBSYSTEM:CONSOLE"] + lib_paths, cwd=tmp)
    exe = tmp / "hello.exe"
    if r.returncode != 0:
        return TestResult("compile.c.link", "compile", TestStatus.FAIL,
                          message=f"exit {r.returncode}", detail=r.stderr[:500], duration_ms=t.elapsed_ms)
    if not exe.exists():
        return TestResult("compile.c.link", "compile", TestStatus.FAIL,
                          message="hello.exe not produced", duration_ms=t.elapsed_ms)
    return TestResult("compile.c.link", "compile", TestStatus.PASS,
                      message=f"hello.exe {exe.stat().st_size} bytes", duration_ms=t.elapsed_ms)


def _test_c_run(info, tmp: Path) -> TestResult:
    """Stage: Run hello.exe and verify output contains COCA."""
    shutil.copy(_FIXTURES / "hello.c", tmp / "hello.c")
    clang_cl = info.root / "bin" / _exe("clang-cl")
    # Full compile+link via clang-cl driver
    sr = info.root / "sysroots" / "x86_64-windows-msvc"
    sdk_inc = list((sr / "sdk" / "Include").glob("*/ucrt"))
    msvc_inc = sr / "msvc" / "include"
    sdk_lib = list((sr / "sdk" / "Lib").glob("*/ucrt/x64"))
    um_lib = list((sr / "sdk" / "Lib").glob("*/um/x64"))
    msvc_lib = sr / "msvc" / "lib" / "x64"
    inc_args = [f"/I{msvc_inc}"]
    if sdk_inc:
        inc_args.append(f"/I{sdk_inc[0]}")
    lib_args = [f"/link", f"/LIBPATH:{msvc_lib}"]
    if sdk_lib:
        lib_args.append(f"/LIBPATH:{sdk_lib[0]}")
    if um_lib:
        lib_args.append(f"/LIBPATH:{um_lib[0]}")
    r = _run([str(clang_cl), *inc_args, str(tmp / "hello.c"),
              f"/Fe{tmp / 'hello.exe'}"] + lib_args, cwd=tmp)
    if r.returncode != 0:
        return TestResult("compile.c.run", "compile", TestStatus.SKIP,
                          message="compile+link failed, skipping run", detail=r.stderr[:500])
    # Run
    with Timer() as t:
        r = _run([str(tmp / "hello.exe")], cwd=tmp)
    if r.returncode != 0:
        return TestResult("compile.c.run", "compile", TestStatus.FAIL,
                          message=f"exit {r.returncode}", detail=r.stderr[:500], duration_ms=t.elapsed_ms)
    if "COCA" not in r.stdout:
        return TestResult("compile.c.run", "compile", TestStatus.FAIL,
                          message="output missing 'COCA'", detail=r.stdout[:500], duration_ms=t.elapsed_ms)
    return TestResult("compile.c.run", "compile", TestStatus.PASS,
                      message=r.stdout.strip()[:120], duration_ms=t.elapsed_ms)


# ── C++23 Pipeline ───────────────────────────────────────────────────────────

def _test_cpp_compile(info, tmp: Path) -> TestResult:
    """Stage: Compile hello.cpp → hello_cpp.obj with C++23 / <print>."""
    shutil.copy(_FIXTURES / "hello.cpp", tmp / "hello.cpp")
    clang_cl = info.root / "bin" / _exe("clang-cl")
    sr = info.root / "sysroots" / "x86_64-windows-msvc"
    msvc_inc = sr / "msvc" / "include"
    sdk_inc = list((sr / "sdk" / "Include").glob("*/ucrt"))
    inc_args = [f"/I{msvc_inc}"]
    if sdk_inc:
        inc_args.append(f"/I{sdk_inc[0]}")
    with Timer() as t:
        r = _run([str(clang_cl), "/c", "/std:c++latest", "/EHsc", *inc_args,
                  f"/Fo{tmp / 'hello_cpp.obj'}", str(tmp / "hello.cpp")], cwd=tmp)
    if r.returncode != 0:
        return TestResult("compile.cpp.compile", "compile", TestStatus.FAIL,
                          message=f"exit {r.returncode}", detail=r.stderr[:500], duration_ms=t.elapsed_ms)
    obj = tmp / "hello_cpp.obj"
    if not obj.exists():
        return TestResult("compile.cpp.compile", "compile", TestStatus.FAIL,
                          message="hello_cpp.obj not produced", duration_ms=t.elapsed_ms)
    return TestResult("compile.cpp.compile", "compile", TestStatus.PASS,
                      message=f"hello_cpp.obj {obj.stat().st_size} bytes", duration_ms=t.elapsed_ms)


def _test_cpp_run(info, tmp: Path) -> TestResult:
    """Stage: Full C++23 compile+link+run via clang-cl driver."""
    shutil.copy(_FIXTURES / "hello.cpp", tmp / "hello.cpp")
    clang_cl = info.root / "bin" / _exe("clang-cl")
    sr = info.root / "sysroots" / "x86_64-windows-msvc"
    msvc_inc = sr / "msvc" / "include"
    sdk_inc = list((sr / "sdk" / "Include").glob("*/ucrt"))
    msvc_lib = sr / "msvc" / "lib" / "x64"
    sdk_lib = list((sr / "sdk" / "Lib").glob("*/ucrt/x64"))
    um_lib = list((sr / "sdk" / "Lib").glob("*/um/x64"))
    inc_args = [f"/I{msvc_inc}"]
    if sdk_inc:
        inc_args.append(f"/I{sdk_inc[0]}")
    lib_args = ["/link", f"/LIBPATH:{msvc_lib}"]
    if sdk_lib:
        lib_args.append(f"/LIBPATH:{sdk_lib[0]}")
    if um_lib:
        lib_args.append(f"/LIBPATH:{um_lib[0]}")
    r = _run([str(clang_cl), "/std:c++latest", "/EHsc", *inc_args, str(tmp / "hello.cpp"),
              f"/Fe{tmp / 'hello_cpp.exe'}"] + lib_args, cwd=tmp)
    if r.returncode != 0:
        return TestResult("compile.cpp.run", "compile", TestStatus.SKIP,
                          message="compile+link failed", detail=r.stderr[:500])
    with Timer() as t:
        r = _run([str(tmp / "hello_cpp.exe")], cwd=tmp)
    if r.returncode != 0:
        return TestResult("compile.cpp.run", "compile", TestStatus.FAIL,
                          message=f"exit {r.returncode}", detail=r.stderr[:500], duration_ms=t.elapsed_ms)
    if "COCA" not in r.stdout:
        return TestResult("compile.cpp.run", "compile", TestStatus.FAIL,
                          message="output missing 'COCA'", detail=r.stdout[:500], duration_ms=t.elapsed_ms)
    return TestResult("compile.cpp.run", "compile", TestStatus.PASS,
                      message=r.stdout.strip()[:120], duration_ms=t.elapsed_ms)


# ── Fortran Pipeline ─────────────────────────────────────────────────────────

def _test_fortran_compile(info, tmp: Path) -> TestResult:
    """Stage: Compile hello_fortran.f90 → hello_fortran.obj via flang."""
    shutil.copy(_FIXTURES / "hello_fortran.f90", tmp / "hello_fortran.f90")
    flang = info.root / "bin" / _exe("flang")
    if not flang.exists():
        return TestResult("compile.fortran.compile", "compile", TestStatus.SKIP,
                          message="flang not found")
    with Timer() as t:
        r = _run([str(flang), "-c", "-o", str(tmp / "hello_fortran.obj"),
                  str(tmp / "hello_fortran.f90")], cwd=tmp)
    if r.returncode != 0:
        return TestResult("compile.fortran.compile", "compile", TestStatus.FAIL,
                          message=f"exit {r.returncode}", detail=r.stderr[:500], duration_ms=t.elapsed_ms)
    obj = tmp / "hello_fortran.obj"
    if not obj.exists():
        return TestResult("compile.fortran.compile", "compile", TestStatus.FAIL,
                          message="hello_fortran.obj not produced", duration_ms=t.elapsed_ms)
    return TestResult("compile.fortran.compile", "compile", TestStatus.PASS,
                      message=f"hello_fortran.obj {obj.stat().st_size} bytes", duration_ms=t.elapsed_ms)


def register(suite: TestSuite) -> None:
    if os.name != "nt":
        return  # Native compile tests only on Windows host
    suite.add("compile.c.preprocess", "compile", "C preprocess (clang-cl /E)", _test_c_preprocess)
    suite.add("compile.c.compile",    "compile", "C compile (clang-cl /c → COFF obj)", _test_c_compile)
    suite.add("compile.c.link",       "compile", "C link (lld-link → exe)", _test_c_link)
    suite.add("compile.c.run",        "compile", "C full pipeline (compile+link+run)", _test_c_run)
    suite.add("compile.cpp.compile",  "compile", "C++23 compile (clang-cl /std:c++23)", _test_cpp_compile)
    suite.add("compile.cpp.run",      "compile", "C++23 full pipeline (compile+link+run)", _test_cpp_run)
    suite.add("compile.fortran.compile", "compile", "Fortran compile (flang -c)", _test_fortran_compile)
