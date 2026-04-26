"""Phase 5: CMake integration — verify toolchain.cmake works end-to-end.

Tests:
  1. cmake_configure: Configure a minimal project using our toolchain file.
  2. cmake_build: Build the project with Ninja.
  3. cmake_run: Run the produced executable and verify output.
  4. clang_driver_compile_run: win-x64-clang profile (clang++ GNU driver, MSVC ABI).
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path

from .framework import TestSuite, TestResult, TestStatus, Timer
from scripts.rich_utils import vprint

_FIXTURES = Path(__file__).resolve().parent / "fixtures"


def _exe(name: str) -> str:
    return name + ".exe" if os.name == "nt" else name


def _run(cmd: list[str], cwd: Path, timeout: int = 120, env: dict | None = None) -> subprocess.CompletedProcess:
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


def _cmake(info) -> str:
    """Return path to the bundled CMake."""
    candidates = list((info.root / "tools").glob("cmake-*/bin/cmake" + (".exe" if os.name == "nt" else "")))
    if candidates:
        return str(sorted(candidates)[-1])
    return "cmake"


def _ninja(info) -> str:
    """Return path to the bundled Ninja."""
    p = info.root / "tools" / "ninja" / _exe("ninja")
    return str(p) if p.exists() else "ninja"


def _toolchain_cmake(info) -> str:
    return str(info.root / "cmake" / "toolchain.cmake")


def _test_cmake_configure(info, tmp: Path) -> TestResult:
    """Configure a minimal CMake project with our toolchain file."""
    src = tmp / "src"
    src.mkdir(exist_ok=True)
    shutil.copy(_FIXTURES / "cmake_simple" / "CMakeLists.txt", src / "CMakeLists.txt")
    shutil.copy(_FIXTURES / "hello.c", src / "hello.c")
    build = tmp / "build"
    build.mkdir(exist_ok=True)
    cmake = _cmake(info)
    ninja = _ninja(info)
    tc = _toolchain_cmake(info)
    with Timer() as t:
        r = _run([cmake, "-G", "Ninja", f"-DCMAKE_MAKE_PROGRAM={ninja}",
                  f"-DCMAKE_TOOLCHAIN_FILE={tc}", "-DCOCA_TARGET_PROFILE=win-x64",
                  "-DCMAKE_BUILD_TYPE=Release", f"-S{src}", f"-B{build}"], cwd=tmp)
    if r.returncode != 0:
        return TestResult("cmake.configure", "cmake", TestStatus.FAIL,
                          message=f"exit {r.returncode}", detail=r.stderr[:800], duration_ms=t.elapsed_ms)
    # Check build.ninja exists
    if not (build / "build.ninja").exists():
        return TestResult("cmake.configure", "cmake", TestStatus.FAIL,
                          message="build.ninja not generated", duration_ms=t.elapsed_ms)
    return TestResult("cmake.configure", "cmake", TestStatus.PASS,
                      message="configured OK", duration_ms=t.elapsed_ms)


def _test_cmake_build(info, tmp: Path) -> TestResult:
    """Build the configured project."""
    src = tmp / "src"
    src.mkdir(exist_ok=True)
    shutil.copy(_FIXTURES / "cmake_simple" / "CMakeLists.txt", src / "CMakeLists.txt")
    shutil.copy(_FIXTURES / "hello.c", src / "hello.c")
    build = tmp / "build"
    build.mkdir(exist_ok=True)
    cmake = _cmake(info)
    ninja = _ninja(info)
    tc = _toolchain_cmake(info)
    # Configure
    r = _run([cmake, "-G", "Ninja", f"-DCMAKE_MAKE_PROGRAM={ninja}",
              f"-DCMAKE_TOOLCHAIN_FILE={tc}", "-DCOCA_TARGET_PROFILE=win-x64",
              "-DCMAKE_BUILD_TYPE=Release", f"-S{src}", f"-B{build}"], cwd=tmp)
    if r.returncode != 0:
        return TestResult("cmake.build", "cmake", TestStatus.SKIP,
                          message="configure failed", detail=r.stderr[:500])
    # Build
    with Timer() as t:
        r = _run([cmake, "--build", str(build)], cwd=tmp)
    if r.returncode != 0:
        return TestResult("cmake.build", "cmake", TestStatus.FAIL,
                          message=f"exit {r.returncode}", detail=r.stderr[:800], duration_ms=t.elapsed_ms)
    exe = build / _exe("hello_cmake")
    if not exe.exists():
        return TestResult("cmake.build", "cmake", TestStatus.FAIL,
                          message="hello_cmake(.exe) not produced", duration_ms=t.elapsed_ms)
    return TestResult("cmake.build", "cmake", TestStatus.PASS,
                      message=f"built OK ({exe.stat().st_size} bytes)", duration_ms=t.elapsed_ms)


def _test_cmake_run(info, tmp: Path) -> TestResult:
    """Build & run the CMake project, verify output."""
    src = tmp / "src"
    src.mkdir(exist_ok=True)
    shutil.copy(_FIXTURES / "cmake_simple" / "CMakeLists.txt", src / "CMakeLists.txt")
    shutil.copy(_FIXTURES / "hello.c", src / "hello.c")
    build = tmp / "build"
    build.mkdir(exist_ok=True)
    cmake = _cmake(info)
    ninja = _ninja(info)
    tc = _toolchain_cmake(info)
    r = _run([cmake, "-G", "Ninja", f"-DCMAKE_MAKE_PROGRAM={ninja}",
              f"-DCMAKE_TOOLCHAIN_FILE={tc}", "-DCOCA_TARGET_PROFILE=win-x64",
              "-DCMAKE_BUILD_TYPE=Release", f"-S{src}", f"-B{build}"], cwd=tmp)
    if r.returncode != 0:
        return TestResult("cmake.run", "cmake", TestStatus.SKIP, message="configure failed")
    r = _run([cmake, "--build", str(build)], cwd=tmp)
    if r.returncode != 0:
        return TestResult("cmake.run", "cmake", TestStatus.SKIP, message="build failed")
    exe = build / _exe("hello_cmake")
    with Timer() as t:
        r = _run([str(exe)], cwd=build)
    if r.returncode != 0:
        return TestResult("cmake.run", "cmake", TestStatus.FAIL,
                          message=f"exit {r.returncode}", detail=r.stderr[:500], duration_ms=t.elapsed_ms)
    if "COCA" not in r.stdout:
        return TestResult("cmake.run", "cmake", TestStatus.FAIL,
                          message="output missing 'COCA'", detail=r.stdout[:500], duration_ms=t.elapsed_ms)
    return TestResult("cmake.run", "cmake", TestStatus.PASS,
                      message=r.stdout.strip()[:120], duration_ms=t.elapsed_ms)


def _test_clang_driver_compile_run(info, tmp: Path) -> TestResult:
    """Compile & run hello_clang_driver.cpp using clang++ (GNU driver, MSVC ABI)."""
    shutil.copy(_FIXTURES / "hello_clang_driver.cpp", tmp / "hello_clang_driver.cpp")
    clangpp = info.root / "bin" / _exe("clang++")
    if not clangpp.exists():
        return TestResult("cmake.clang_driver", "cmake", TestStatus.SKIP, message="clang++ not found")
    sr = info.root / "sysroots" / "x86_64-windows-msvc"
    msvc_inc = sr / "msvc" / "include"
    sdk_inc = list((sr / "sdk" / "Include").glob("*/ucrt"))
    msvc_lib = sr / "msvc" / "lib" / "x64"
    sdk_lib = list((sr / "sdk" / "Lib").glob("*/ucrt/x64"))
    um_lib = list((sr / "sdk" / "Lib").glob("*/um/x64"))
    libcxx_inc = info.root / "include" / "c++" / "v1"
    resource_inc = info.root / "lib" / "clang" / "21" / "include"
    compile_args = [
        str(clangpp), "--target=x86_64-pc-windows-msvc",
        "-fuse-ld=lld", "-rtlib=compiler-rt",
        "-nostdinc++", "-nostdlibinc",
        f"-isystem{libcxx_inc}", f"-isystem{resource_inc}",
        f"-isystem{msvc_inc}",
    ]
    if sdk_inc:
        compile_args.append(f"-isystem{sdk_inc[0]}")
    compile_args += ["-lc++", f"-L{msvc_lib}"]
    if sdk_lib:
        compile_args.append(f"-L{sdk_lib[0]}")
    if um_lib:
        compile_args.append(f"-L{um_lib[0]}")
    compile_args += [str(tmp / "hello_clang_driver.cpp"), "-o", str(tmp / "hello_clang_driver.exe")]
    with Timer() as t:
        r = _run(compile_args, cwd=tmp)
    if r.returncode != 0:
        return TestResult("cmake.clang_driver", "cmake", TestStatus.FAIL,
                          message=f"compile exit {r.returncode}", detail=r.stderr[:800], duration_ms=t.elapsed_ms)
    exe = tmp / "hello_clang_driver.exe"
    if not exe.exists():
        return TestResult("cmake.clang_driver", "cmake", TestStatus.FAIL,
                          message="exe not produced", duration_ms=t.elapsed_ms)
    # Copy libc++ DLL next to the exe (win-x64-clang links libc++ dynamically)
    for dll_name in ["c++.dll", "libc++.dll", "unwind.dll", "libunwind.dll"]:
        dll = info.root / "bin" / dll_name
        if dll.exists():
            shutil.copy(dll, tmp / dll_name)
    r = _run([str(exe)], cwd=tmp)
    if r.returncode != 0:
        return TestResult("cmake.clang_driver", "cmake", TestStatus.FAIL,
                          message=f"run exit {r.returncode}", detail=r.stderr[:500], duration_ms=t.elapsed_ms)
    if "COCA" not in r.stdout:
        return TestResult("cmake.clang_driver", "cmake", TestStatus.FAIL,
                          message="output missing 'COCA'", detail=r.stdout[:500], duration_ms=t.elapsed_ms)
    return TestResult("cmake.clang_driver", "cmake", TestStatus.PASS,
                      message=r.stdout.strip()[:120], duration_ms=t.elapsed_ms)


def register(suite: TestSuite) -> None:
    if os.name != "nt":
        return
    suite.add("cmake.configure", "cmake", "CMake configure (toolchain.cmake + Ninja)", _test_cmake_configure)
    suite.add("cmake.build", "cmake", "CMake build (Ninja)", _test_cmake_build)
    suite.add("cmake.run", "cmake", "CMake build+run output verification", _test_cmake_run)
    suite.add("cmake.clang_driver", "cmake", "clang++ GNU driver compile+run (win-x64-clang)", _test_clang_driver_compile_run)
