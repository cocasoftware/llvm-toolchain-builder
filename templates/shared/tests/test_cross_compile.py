"""Phase 4: Cross-compilation — compile+link for every non-native profile, verify binary format.

For wasm-wasi, also runs the binary via wasmtime if available.
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


# Profile → expected binary format checks
# (elf_class, elf_machine) or "pe" or "wasm"
_FORMAT_EXPECT: dict[str, tuple] = {
    "linux-x64":            ("ELF", "64", "X86-64"),
    "linux-x64-kylin":      ("ELF", "64", "X86-64"),
    "linux-arm64":          ("ELF", "64", "AArch64"),
    "linux-arm64-kylin":    ("ELF", "64", "AArch64"),
    "linux-x64-musl":       ("ELF", "64", "X86-64"),
    "linux-arm64-musl":     ("ELF", "64", "AArch64"),
    "win-x64-mingw-ucrt":   ("PE",),
    "win-x64-mingw-msvcrt": ("PE",),
    "wasm-wasi":            ("Wasm",),
}


def _make_cross_compile_test(profile: str, pinfo: dict):
    """Generate a cross-compile test for a single profile."""
    triple = pinfo.get("target_triple", "")
    sysroot_rel = pinfo.get("sysroot")
    runtime = pinfo.get("runtime", "")
    linker_name = pinfo.get("linker", "ld.lld")
    is_static = pinfo.get("static", False)

    def _test(info, tmp: Path) -> TestResult:
        clang = info.root / "bin" / _exe("clang")
        output_name = "hello"

        # Use richer wasm_test.cpp for wasm-wasi, hello.c for others
        if runtime == "wasi" and (_FIXTURES / "wasm_test.cpp").exists():
            src_name = "wasm_test.cpp"
            shutil.copy(_FIXTURES / "wasm_test.cpp", tmp / src_name)
        else:
            src_name = "hello.c"
            shutil.copy(_FIXTURES / "hello.c", tmp / src_name)

        # Build compile args
        compile_args = [str(clang), f"--target={triple}", "-c",
                        "-o", str(tmp / "hello.o"), str(tmp / src_name)]
        if sysroot_rel:
            sr = info.root / sysroot_rel
            if not sr.exists():
                return TestResult(f"cross.{profile}.compile", "cross", TestStatus.SKIP,
                                  message=f"sysroot missing: {sysroot_rel}")
            compile_args.insert(2, f"--sysroot={sr}")

        # Special handling for wasm-wasi sysroot
        if runtime == "wasi" and sysroot_rel:
            sr = info.root / sysroot_rel
            compile_args = [str(clang), f"--target={triple}",
                            f"--sysroot={sr}",
                            "-c", "-o", str(tmp / "hello.o"), str(tmp / src_name)]

        # Compile
        with Timer() as t:
            r = _run(compile_args, cwd=tmp)
        if r.returncode != 0:
            return TestResult(f"cross.{profile}.compile", "cross", TestStatus.FAIL,
                              message=f"compile exit {r.returncode}", detail=r.stderr[:500],
                              duration_ms=t.elapsed_ms)

        # Link
        linker = info.root / "bin" / _exe(linker_name)
        if not linker.exists():
            return TestResult(f"cross.{profile}.link", "cross", TestStatus.FAIL,
                              message=f"linker not found: {linker_name}")

        link_args = _build_link_args(info, profile, pinfo, linker, tmp)
        with Timer() as t:
            r = _run(link_args, cwd=tmp)
        if r.returncode != 0:
            return TestResult(f"cross.{profile}.link", "cross", TestStatus.FAIL,
                              message=f"link exit {r.returncode}", detail=r.stderr[:500],
                              duration_ms=t.elapsed_ms)

        # Format verification
        output_file = tmp / output_name
        if runtime == "wasi":
            output_file = tmp / "hello.wasm"
        elif runtime == "mingw":
            output_file = tmp / "hello.exe"
        if not output_file.exists():
            # Try common names
            for candidate in [tmp / "hello", tmp / "hello.exe", tmp / "hello.wasm"]:
                if candidate.exists():
                    output_file = candidate
                    break

        if not output_file.exists():
            return TestResult(f"cross.{profile}.format", "cross", TestStatus.FAIL,
                              message="output binary not found")

        fmt_result = _verify_format(info, profile, output_file, tmp)
        if fmt_result.status != TestStatus.PASS:
            return fmt_result

        # For wasm-wasi: try running via wasmtime
        if runtime == "wasi":
            return _try_run_wasm(info, profile, output_file, tmp)

        return TestResult(f"cross.{profile}", "cross", TestStatus.PASS,
                          message=f"compile+link OK, format verified ({output_file.stat().st_size} bytes)",
                          duration_ms=t.elapsed_ms)
    return _test


def _build_link_args(info, profile: str, pinfo: dict, linker: Path, tmp: Path) -> list[str]:
    """Build linker command line for a given cross-compilation profile."""
    triple = pinfo.get("target_triple", "")
    sysroot_rel = pinfo.get("sysroot")
    runtime = pinfo.get("runtime", "")
    is_static = pinfo.get("static", False)
    linker_name = pinfo.get("linker", "ld.lld")

    if runtime == "wasi":
        sr = info.root / sysroot_rel
        wasi_lib = sr / "lib" / "wasm32-wasip1"
        return [str(linker), str(tmp / "hello.o"),
                f"-L{wasi_lib}", "-lc",
                str(wasi_lib / "crt1.o"),
                "-o", str(tmp / "hello.wasm")]

    if runtime == "mingw":
        sr = info.root / sysroot_rel
        clang = info.root / "bin" / _exe("clang")
        crt = pinfo.get("crt", "ucrt")
        return [str(clang), f"--target={triple}", f"--sysroot={sr}",
                "-fuse-ld=lld", "-rtlib=compiler-rt",
                str(tmp / "hello.o"), "-o", str(tmp / "hello.exe")]

    # Linux glibc/musl
    sr = info.root / sysroot_rel
    args = [str(linker), str(tmp / "hello.o"), "-o", str(tmp / "hello")]

    if "x86_64" in triple:
        lib_dirs = [sr / "usr" / "lib" / "x86_64-linux-gnu", sr / "lib" / "x86_64-linux-gnu",
                    sr / "usr" / "lib", sr / "lib"]
        crt_dir = sr / "usr" / "lib" / "x86_64-linux-gnu"
    else:
        lib_dirs = [sr / "usr" / "lib" / "aarch64-linux-gnu", sr / "lib" / "aarch64-linux-gnu",
                    sr / "usr" / "lib", sr / "lib"]
        crt_dir = sr / "usr" / "lib" / "aarch64-linux-gnu"

    if "musl" in triple:
        lib_dirs = [sr / "usr" / "lib", sr / "lib"]
        crt_dir = sr / "usr" / "lib"

    for ld in lib_dirs:
        if ld.exists():
            args.append(f"-L{ld}")

    crt1 = crt_dir / "crt1.o"
    crti = crt_dir / "crti.o"
    crtn = crt_dir / "crtn.o"
    if crt1.exists():
        args.insert(2, str(crt1))
    if crti.exists():
        args.insert(2, str(crti))

    args.extend(["-lc"])

    if is_static:
        args.append("-static")
        args.append("-lc++")
        args.append("-lc++abi")
        args.append("-lunwind")
    else:
        # dynamic linker
        if "x86_64" in triple and "musl" not in triple:
            interp = sr / "lib" / "x86_64-linux-gnu" / "ld-linux-x86-64.so.2"
            if interp.exists():
                args.extend(["-dynamic-linker", str(interp)])
        elif "aarch64" in triple and "musl" not in triple:
            interp = sr / "lib" / "aarch64-linux-gnu" / "ld-linux-aarch64.so.1"
            if interp.exists():
                args.extend(["-dynamic-linker", str(interp)])

    if crtn.exists():
        args.append(str(crtn))

    return args


def _verify_format(info, profile: str, output_file: Path, tmp: Path) -> TestResult:
    """Verify the output binary matches the expected format."""
    expected = _FORMAT_EXPECT.get(profile)
    if not expected:
        return TestResult(f"cross.{profile}.format", "cross", TestStatus.PASS,
                          message="no format check defined")

    readelf = info.root / "bin" / _exe("llvm-readelf")
    objdump = info.root / "bin" / _exe("llvm-objdump")

    if expected[0] == "Wasm":
        magic = output_file.read_bytes()[:4]
        if magic == b"\x00asm":
            return TestResult(f"cross.{profile}.format", "cross", TestStatus.PASS,
                              message="Wasm magic verified")
        return TestResult(f"cross.{profile}.format", "cross", TestStatus.FAIL,
                          message=f"expected Wasm magic, got {magic.hex()}")

    if expected[0] == "PE":
        magic = output_file.read_bytes()[:2]
        if magic == b"MZ":
            return TestResult(f"cross.{profile}.format", "cross", TestStatus.PASS,
                              message="PE MZ magic verified")
        return TestResult(f"cross.{profile}.format", "cross", TestStatus.FAIL,
                          message=f"expected PE MZ magic, got {magic.hex()}")

    # ELF — use llvm-readelf
    if not readelf.exists():
        return TestResult(f"cross.{profile}.format", "cross", TestStatus.SKIP,
                          message="llvm-readelf not found")
    r = _run([str(readelf), "-h", str(output_file)], cwd=tmp)
    if r.returncode != 0:
        return TestResult(f"cross.{profile}.format", "cross", TestStatus.FAIL,
                          message=f"llvm-readelf exit {r.returncode}", detail=r.stderr[:500])

    _, elf_class, elf_machine = expected
    output = r.stdout
    class_ok = f"ELF{elf_class}" in output or f"Class:.*ELF{elf_class}" in output
    machine_ok = elf_machine.lower() in output.lower()
    if not class_ok or not machine_ok:
        return TestResult(f"cross.{profile}.format", "cross", TestStatus.FAIL,
                          message=f"expected ELF{elf_class}/{elf_machine}",
                          detail=output[:500])
    return TestResult(f"cross.{profile}.format", "cross", TestStatus.PASS,
                      message=f"ELF{elf_class} {elf_machine} verified")


def _try_run_wasm(info, profile: str, wasm_file: Path, tmp: Path) -> TestResult:
    """Try running a wasm-wasi binary via wasmtime."""
    wt = info.root / "tools" / "wasmtime" / _exe("wasmtime")
    wasmtime = wt if wt.exists() else None
    if wasmtime is None:
        return TestResult(f"cross.{profile}.run", "cross", TestStatus.SKIP,
                          message="wasmtime not found, skipping wasm-wasi run")
    with Timer() as t:
        r = _run([str(wasmtime), str(wasm_file)], cwd=tmp)
    if r.returncode != 0:
        return TestResult(f"cross.{profile}.run", "cross", TestStatus.FAIL,
                          message=f"wasmtime exit {r.returncode}", detail=r.stderr[:500],
                          duration_ms=t.elapsed_ms)
    if "COCA" not in r.stdout:
        return TestResult(f"cross.{profile}.run", "cross", TestStatus.FAIL,
                          message="output missing 'COCA'", detail=r.stdout[:500],
                          duration_ms=t.elapsed_ms)
    return TestResult(f"cross.{profile}", "cross", TestStatus.PASS,
                      message=f"compile+link+run OK: {r.stdout.strip()[:120]}",
                      duration_ms=t.elapsed_ms)


# Profiles that should NOT be tested as cross (they are native or managed by emsdk)
_SKIP_PROFILES = {"win-x64", "win-x64-clang", "wasm-emscripten"}


def register(suite: TestSuite) -> None:
    # Read profiles from a dummy info — actual info provided at runtime
    # We register a factory that reads profiles from info at test time
    suite.add("cross._discover", "cross", "Discover cross-compilation profiles", _discover_and_run)


def _discover_and_run(info, tmp: Path) -> TestResult:
    """Meta-test: discovers all cross profiles and runs compile+link+format+run for each.

    Returns a summary result; individual profile results are printed by the runner.
    """
    from .framework import TestSuite as _TS
    profiles = info.toolchain_json.get("profiles", {})
    sub_results: list[TestResult] = []
    for pname, pinfo in sorted(profiles.items()):
        if pname in _SKIP_PROFILES:
            continue
        test_fn = _make_cross_compile_test(pname, pinfo)
        # Create isolated subdir
        sub_tmp = tmp / pname
        sub_tmp.mkdir(exist_ok=True)
        try:
            result = test_fn(info, sub_tmp)
            result.test_id = f"cross.{pname}"
            sub_results.append(result)
        except Exception as e:
            sub_results.append(TestResult(f"cross.{pname}", "cross", TestStatus.ERROR,
                                          message=str(e)[:200]))
    # Return composite
    passed = sum(1 for r in sub_results if r.status == TestStatus.PASS)
    failed = sum(1 for r in sub_results if r.status == TestStatus.FAIL)
    skipped = sum(1 for r in sub_results if r.status == TestStatus.SKIP)
    errors = sum(1 for r in sub_results if r.status == TestStatus.ERROR)
    total = len(sub_results)
    status = TestStatus.PASS if failed == 0 and errors == 0 else TestStatus.FAIL
    msg = f"{passed} passed, {failed} failed, {skipped} skipped, {errors} errors / {total} profiles"
    return TestResult("cross._summary", "cross", status, message=msg,
                      detail="\n".join(f"  {r.test_id}: {r.status.value} — {r.message}" for r in sub_results))
