"""Data model: ToolDef registry, ToolchainInfo, CheckResult."""
from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from pathlib import Path


def _exe(name: str) -> str:
    return name + ".exe" if os.name == "nt" else name


@dataclass(frozen=True, slots=True)
class ToolDef:
    """Declarative definition of a discoverable tool."""
    env_key: str
    rel_path: str
    is_dir: bool = True
    path_add: bool = False
    win_suffix: str = ""


@dataclass
class ToolchainInfo:
    root: Path
    toolchain_json: dict = field(default_factory=dict)
    manifest_json: dict = field(default_factory=dict)
    name: str = ""
    version: str = ""
    llvm_version: str = ""
    paths: dict[str, str] = field(default_factory=dict)
    path_adds: list[str] = field(default_factory=list)


@dataclass
class CheckResult:
    name: str
    ok: bool
    detail: str = ""


TOOL_REGISTRY: list[ToolDef] = [
    ToolDef("COCA_CMAKE_BIN",       "cmake/bin",       path_add=True),
    ToolDef("COCA_NINJA_BIN",       "ninja",           path_add=True),
    ToolDef("COCA_GRAPHVIZ_BIN",    "graphviz/bin",    path_add=True),
    ToolDef("COCA_DOXYGEN_BIN",     "doxygen",         path_add=True),
    ToolDef("COCA_WASMTIME_BIN",    "wasmtime",        path_add=True),
    ToolDef("COCA_CONAN_BIN",       "conan/bin",       path_add=True),
    ToolDef("COCA_JFROG_BIN",       "jfrog",           path_add=True),
    ToolDef("COCA_PERL_BIN",        "perl/perl/bin",   path_add=True),
    ToolDef("COCA_GIT_BIN",         "git/cmd",         path_add=True),
    ToolDef("COCA_GIT_USR_BIN",     "git/usr/bin",     path_add=True),
    ToolDef("COCA_RSYNC_BIN",       "rsync/bin",       path_add=True),
    ToolDef("COCA_RENDERDOC_BIN",   "renderdoc",       path_add=True),
    ToolDef("COCA_TIE_GEN_BIN",     "coca",            path_add=True),
    ToolDef("COCA_TIE_GEN",         "coca/coca-tie-gen", is_dir=False, win_suffix=".exe"),
    ToolDef("COCA_PYTHON_SCRIPTS",  "python/Scripts" if os.name == "nt" else "python/bin", path_add=True),
    ToolDef("COCA_PYTHON_HOME",     "python",          path_add=True),
    ToolDef("COCA_PYTHON",          "python/python" + (".exe" if os.name == "nt" else "3"), is_dir=False),
    ToolDef("COCA_MAKE",            "msys2-make/msys2-make", is_dir=False, win_suffix=".exe"),
    ToolDef("COCA_MAKE_BIN",        "msys2-make",      path_add=True),
    ToolDef("COCA_PWSH_BIN",        "pwsh",            path_add=True),
    ToolDef("COCA_GLAB_BIN",        "glab",            path_add=True),
    ToolDef("COCA_VTUNE_BIN",       "vtune/bin64",     path_add=True),
    ToolDef("COCA_IFORT_BIN",       "ifort",           path_add=True),
    ToolDef("COCA_ML64_BIN",        "ml64",            path_add=True),
    ToolDef("COCA_LIBCLANG",        "libclang/libclang.dll", is_dir=False),
]


# ── Loading ──────────────────────────────────────────────────────────────────

def _load_json(path: Path) -> dict:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def load_toolchain(root: Path) -> ToolchainInfo:
    tc_json = _load_json(root / "toolchain.json")
    mf_json = _load_json(root / "manifest.json")
    name = mf_json.get("toolchain_name", root.name)
    return ToolchainInfo(
        root=root, toolchain_json=tc_json, manifest_json=mf_json, name=name,
        version=tc_json.get("toolchain_version", "?"),
        llvm_version=tc_json.get("llvm_version", "?"),
    )
