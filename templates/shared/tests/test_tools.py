"""Phase 1: Tool reachability — verify every registered tool is executable and reports a version."""
from __future__ import annotations

import os
import subprocess
from pathlib import Path

from .framework import TestSuite, TestResult, TestStatus, Timer
from scripts.rich_utils import vprint


# (tool_name, relative_path_to_exe, version_args, version_pattern)
# version_pattern: if None, just check exit code 0 and non-empty output.
_TOOL_CHECKS: list[tuple[str, str, list[str], str | None]] = [
    ("clang",         "bin/clang",         ["--version"],  r"clang version"),
    ("clang-cl",      "bin/clang-cl",      ["--version"],  r"clang version"),
    ("clang++",       "bin/clang++",       ["--version"],  r"clang version"),
    ("lld",           "bin/lld",           ["-flavor", "gnu", "--version"],  r"LLD"),
    ("lld-link",      "bin/lld-link",      ["--version"],  r"LLD"),
    ("wasm-ld",       "bin/wasm-ld",       ["--version"],  r"LLD"),
    ("llvm-ar",       "bin/llvm-ar",       ["--version"],  r"LLVM"),
    ("llvm-nm",       "bin/llvm-nm",       ["--version"],  r"LLVM"),
    ("llvm-objdump",  "bin/llvm-objdump",  ["--version"],  r"LLVM"),
    ("llvm-objcopy",  "bin/llvm-objcopy",  ["--version"],  r"LLVM"),
    ("llvm-strip",    "bin/llvm-strip",    ["--version"],  r"LLVM"),
    ("llvm-readelf",  "bin/llvm-readelf",  ["--version"],  r"LLVM"),
    ("llvm-ranlib",   "bin/llvm-ranlib",   ["--version"],  r"LLVM"),
    ("llvm-profdata", "bin/llvm-profdata", ["--version"],  r"LLVM"),
    ("llvm-cov",      "bin/llvm-cov",      ["--version"],  r"LLVM"),
    ("clang-format",  "bin/clang-format",  ["--version"],  r"clang-format version"),
    ("clang-tidy",    "bin/clang-tidy",    ["--version"],  r"LLVM"),
    ("clangd",        "bin/clangd",        ["--version"],  r"clangd version"),
    ("flang",         "bin/flang",         ["--version"],  r"flang"),
    ("lldb",          "bin/lldb",          ["--version"],  r"lldb version"),
    ("cmake",         "tools/cmake-*/bin/cmake", ["--version"], r"cmake version"),
    ("ninja",         "tools/ninja/ninja", ["--version"],  None),
    ("python",        "tools/python/python", ["--version"], r"Python"),
    ("git",           "tools/git/cmd/git", ["--version"],  r"git version"),
    ("doxygen",       "tools/doxygen/doxygen", ["--version"], r"\d+\.\d+"),
    ("dot",           "tools/graphviz/bin/dot", ["-V"],     r"graphviz version"),
    ("perl",          "tools/perl/perl/bin/perl", ["--version"], r"\(v\d+"),
    ("rsync",         "tools/rsync/bin/rsync", ["--version"], r"rsync\s+version"),
    ("renderdoccmd",  "tools/renderdoc/renderdoccmd", ["--version"], r"v\d+\.\d+"),
    ("wasmtime",      "tools/wasmtime-*/wasmtime", ["--version"], r"wasmtime"),
    ("pwsh",          "tools/pwsh/pwsh",   ["-NoProfile", "-Command", "$PSVersionTable.PSVersion.ToString()"], r"\d+\.\d+\.\d+"),
]


def _find_exe(root: Path, rel: str) -> Path | None:
    """Resolve a relative path that may contain a glob wildcard."""
    if "*" in rel:
        matches = sorted(root.glob(rel + (".exe" if os.name == "nt" else "")))
        if not matches:
            matches = sorted(root.glob(rel))
        return matches[0] if matches else None
    p = root / rel
    if os.name == "nt" and not p.exists() and not p.suffix:
        p_exe = p.with_suffix(".exe")
        if p_exe.exists():
            return p_exe
    return p if p.exists() else None


def _make_tool_test(name: str, rel: str, args: list[str], pattern: str | None):
    import re

    def _test(info, tmp_dir: Path) -> TestResult:
        exe = _find_exe(info.root, rel)
        if exe is None:
            return TestResult(f"tools.{name}", "tools", TestStatus.SKIP,
                              message=f"{rel} not found")
        cmd = [str(exe)] + args
        vprint(f"         [dim]$ {' '.join(cmd)}[/dim]")
        with Timer() as t:
            try:
                r = subprocess.run(cmd, capture_output=True, text=True,
                                   timeout=15, env={**os.environ, "PYTHONNOUSERSITE": "1"})
            except (subprocess.TimeoutExpired, OSError) as e:
                return TestResult(f"tools.{name}", "tools", TestStatus.ERROR,
                                  message=str(e), duration_ms=t.elapsed_ms)
        output = r.stdout + r.stderr
        if output.strip():
            vprint(f"         [dim]  │ {output.strip().splitlines()[0][:120]}[/dim]")
        if r.returncode != 0:
            return TestResult(f"tools.{name}", "tools", TestStatus.FAIL,
                              message=f"exit code {r.returncode}",
                              detail=output[:500], duration_ms=t.elapsed_ms)
        if pattern and not re.search(pattern, output, re.IGNORECASE):
            return TestResult(f"tools.{name}", "tools", TestStatus.FAIL,
                              message=f"output does not match /{pattern}/",
                              detail=output[:500], duration_ms=t.elapsed_ms)
        first_line = output.strip().splitlines()[0] if output.strip() else ""
        return TestResult(f"tools.{name}", "tools", TestStatus.PASS,
                          message=first_line[:120], duration_ms=t.elapsed_ms)
    return _test


def register(suite: TestSuite) -> None:
    for name, rel, args, pattern in _TOOL_CHECKS:
        suite.add(f"tools.{name}", "tools", f"{name} reachability",
                  _make_tool_test(name, rel, args, pattern))
