"""Component version detection registry.

Each ComponentDef describes how to obtain the actual installed version of a
toolchain component by running a command or reading a file.  The registry
is used by --update-manifest to auto-populate the `components` section and
by --check to verify declared versions match reality.
"""
from __future__ import annotations

import os
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from .model import ToolchainInfo, _exe


@dataclass(frozen=True, slots=True)
class ComponentDef:
    """Declarative description of a toolchain component."""
    key: str
    display: str
    version_fn: Callable[[Path], str | None] | None = None
    optional: bool = False
    note_key: str | None = None


def _run_version_cmd(root: Path, cmd_fragments: list[str], timeout: int = 10) -> str | None:
    """Run a version command relative to toolchain root, return stdout."""
    parts = list(cmd_fragments)
    bin_path = root / parts[0]
    if not bin_path.suffix and os.name == "nt":
        bin_path = bin_path.with_suffix(".exe")
    if not bin_path.exists():
        return None
    parts[0] = str(bin_path)
    try:
        r = subprocess.run(parts, capture_output=True, text=True, timeout=timeout,
                           env={**os.environ, "PYTHONNOUSERSITE": "1"})
        return r.stdout + r.stderr
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return None


def _extract_version(output: str | None, pattern: str | None) -> str | None:
    if output is None:
        return None
    if pattern is None:
        return output.strip().splitlines()[0].strip() if output.strip() else None
    m = re.search(pattern, output)
    return m.group(1) if m else None


# ── Version functions for complex components ─────────────────────────────────

def _llvm_version(root: Path) -> str | None:
    out = _run_version_cmd(root, ["bin/clang", "--version"])
    return _extract_version(out, r"clang version (\S+)")


def _cmake_version(root: Path) -> str | None:
    tools = root / "tools"
    for d in sorted(tools.iterdir(), reverse=True) if tools.is_dir() else []:
        if d.is_dir() and d.name.startswith("cmake-"):
            cmake = d / "bin" / _exe("cmake")
            if cmake.exists():
                out = _run_version_cmd(root, [str(cmake.relative_to(root)), "--version"])
                return _extract_version(out, r"cmake version (\S+)")
    return None


def _ninja_version(root: Path) -> str | None:
    out = _run_version_cmd(root, ["tools/ninja/ninja", "--version"])
    return _extract_version(out, None)


def _python_version(root: Path) -> str | None:
    out = _run_version_cmd(root, ["tools/python/python", "--version"])
    return _extract_version(out, r"Python (\S+)")


def _rust_version(root: Path) -> str | None:
    rustup = root / "tools" / "rust" / "rustup"
    if not rustup.is_dir():
        return None
    tc_dir = rustup / "toolchains"
    if tc_dir.is_dir():
        for d in sorted(tc_dir.iterdir()):
            if d.is_dir():
                # e.g. "1.93.1-x86_64-pc-windows-msvc" → "1.93.1"
                m = re.match(r"^(\d+\.\d+\.\d+)", d.name)
                if m:
                    return m.group(1)
    return None


def _git_version(root: Path) -> str | None:
    git = root / "tools" / "git" / "cmd" / _exe("git")
    if not git.exists():
        return None
    try:
        r = subprocess.run([str(git), "--version"], capture_output=True, text=True, timeout=10)
        return _extract_version(r.stdout, r"git version (\S+)")
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return None


def _doxygen_version(root: Path) -> str | None:
    out = _run_version_cmd(root, ["tools/doxygen/doxygen", "--version"])
    return _extract_version(out, r"^(\d+\.\d+\.\d+)")


def _graphviz_version(root: Path) -> str | None:
    out = _run_version_cmd(root, ["tools/graphviz/bin/dot", "-V"])
    return _extract_version(out, r"graphviz version (\S+)")


def _perl_version(root: Path) -> str | None:
    out = _run_version_cmd(root, ["tools/perl/perl/bin/perl", "--version"])
    return _extract_version(out, r"\(v(\d+\.\d+\.\d+)\)")


def _conan_version(root: Path) -> str | None:
    conan = root / "tools" / "conan" / "bin" / _exe("conan")
    if not conan.exists():
        return None
    try:
        env = {**os.environ, "PYTHONNOUSERSITE": "1", "PYTHONPATH": str(root / "tools" / "conan")}
        r = subprocess.run([str(root / "tools" / "python" / _exe("python")), "-m", "conans.client.command", "--version"],
                           capture_output=True, text=True, timeout=10, env=env)
        v = _extract_version(r.stdout + r.stderr, r"Conan version (\S+)")
        if v:
            return v
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        pass
    return None


def _jfrog_version(root: Path) -> str | None:
    jf = root / "tools" / "jfrog" / ("jf.exe" if os.name == "nt" else "jf")
    if not jf.exists():
        return None
    try:
        r = subprocess.run([str(jf), "--version"], capture_output=True, text=True, timeout=10)
        return _extract_version(r.stdout + r.stderr, r"(\d+\.\d+\.\d+)")
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return None


def _rsync_version(root: Path) -> str | None:
    out = _run_version_cmd(root, ["tools/rsync/bin/rsync", "--version"])
    return _extract_version(out, r"rsync\s+version (\S+)")


def _renderdoc_version(root: Path) -> str | None:
    out = _run_version_cmd(root, ["tools/renderdoc/renderdoccmd", "--version"])
    return _extract_version(out, r"v(\d+\.\d+)")


def _wasmtime_version(root: Path) -> str | None:
    wt = root / "tools" / "wasmtime" / _exe("wasmtime")
    if wt.exists():
        try:
            r = subprocess.run([str(wt), "--version"], capture_output=True, text=True, timeout=10)
            return _extract_version(r.stdout, r"wasmtime (\S+)")
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
            pass
    return None


def _emscripten_version(root: Path) -> str | None:
    emcc = root / "tools" / "emsdk" / "upstream" / "emscripten" / "emcc.py"
    if not emcc.exists():
        return None
    # Read version from emscripten-version.txt
    ver_file = root / "tools" / "emsdk" / "upstream" / "emscripten" / "emscripten-version.txt"
    if ver_file.exists():
        v = ver_file.read_text(encoding="utf-8").strip().strip('"')
        return v
    return None


def _glibc_version(root: Path) -> str | None:
    # Read from toolchain.json component data — glibc version is not detectable from binary
    return None  # Will be preserved from existing manifest


def _wasi_sdk_version(root: Path) -> str | None:
    # Check wasi-libc version header
    for pat in root.glob("sysroots/wasm32-wasi/share/wasi-sysroot/VERSION"):
        return pat.read_text(encoding="utf-8").strip()
    return None  # Will be preserved from existing manifest


def _ifort_version(root: Path) -> str | None:
    ifort = root / "tools" / "ifort"
    if not ifort.is_dir():
        return None
    for exe_name in ["ifort", "ifx"]:
        p = ifort / _exe(exe_name)
        if p.exists():
            try:
                r = subprocess.run([str(p), "--version"], capture_output=True, text=True, timeout=10)
                return _extract_version(r.stdout + r.stderr, r"(\d+\.\d+[\.\d]*)")
            except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
                pass
    return None


# ── Component Registry ───────────────────────────────────────────────────────

COMPONENT_REGISTRY: list[ComponentDef] = [
    ComponentDef("llvm",            "LLVM",             version_fn=_llvm_version),
    ComponentDef("cmake",           "CMake",            version_fn=_cmake_version),
    ComponentDef("ninja",           "Ninja",            version_fn=_ninja_version),
    ComponentDef("python",          "Python",           version_fn=_python_version),
    ComponentDef("rust",            "Rust",             version_fn=_rust_version, optional=True),
    ComponentDef("git",             "Git",              version_fn=_git_version, optional=True),
    ComponentDef("doxygen",         "Doxygen",          version_fn=_doxygen_version, optional=True),
    ComponentDef("graphviz",        "Graphviz",         version_fn=_graphviz_version, optional=True),
    ComponentDef("perl",            "Perl",             version_fn=_perl_version, optional=True),
    ComponentDef("conan",           "Conan",            version_fn=_conan_version, optional=True,
                 note_key="conan"),
    ComponentDef("jfrog_cli",       "JFrog CLI",        version_fn=_jfrog_version, optional=True,
                 note_key="jfrog_cli"),
    ComponentDef("rsync",           "rsync (cwrsync)",  version_fn=_rsync_version, optional=True),
    ComponentDef("renderdoc",       "RenderDoc",        version_fn=_renderdoc_version, optional=True),
    ComponentDef("wasmtime",        "Wasmtime",         version_fn=_wasmtime_version, optional=True),
    ComponentDef("emscripten_sdk",  "Emscripten SDK",   version_fn=_emscripten_version, optional=True),
    # Static components — version from toolchain.json / existing manifest only
    ComponentDef("glibc",           "glibc",            optional=True, note_key="glibc"),
    ComponentDef("linux_headers",   "Linux Headers",    optional=True, note_key="linux_headers"),
    ComponentDef("windows_sdk",     "Windows SDK",      optional=True),
    ComponentDef("msvc",            "MSVC",             optional=True),
    ComponentDef("wasi_sdk",        "WASI SDK",         version_fn=_wasi_sdk_version, optional=True),
    ComponentDef("ifort",           "Intel Fortran",    version_fn=_ifort_version, optional=True),
]


def detect_component_versions(info: ToolchainInfo) -> dict[str, dict]:
    """Detect versions of all registered components and merge with existing manifest data.

    Returns a dict suitable for manifest["components"].
    """
    existing = dict(info.manifest_json.get("components", {}))
    result: dict[str, dict] = {}

    for cdef in COMPONENT_REGISTRY:
        entry: dict = dict(existing.get(cdef.key, {}))

        # Try to detect version
        detected: str | None = None
        if cdef.version_fn is not None:
            detected = cdef.version_fn(info.root)

        if detected:
            entry["version"] = detected
        elif "version" not in entry:
            # Check toolchain.json for static components
            tc_ver = info.toolchain_json.get(f"{cdef.key}_version")
            if tc_ver:
                entry["version"] = tc_ver

        # Only include component if it has a version
        if "version" in entry:
            result[cdef.key] = entry

    return result
