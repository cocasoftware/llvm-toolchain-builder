"""Path resolution for all toolchain tools."""
from __future__ import annotations

import os
from pathlib import Path

from .model import ToolDef, ToolchainInfo, TOOL_REGISTRY, _exe


def resolve_paths(info: ToolchainInfo) -> None:
    root, tools = info.root, info.root / "tools"
    paths, path_adds = info.paths, info.path_adds

    paths["COCA_TOOLCHAIN"] = str(root)
    paths["COCA_TOOLCHAIN_BIN"] = str(root / "bin")
    paths["COCA_TOOLCHAIN_CMAKE"] = str(root / "cmake" / "toolchain.cmake")
    path_adds.append(str(root / "bin"))

    _resolve_emsdk(tools, paths)
    _resolve_rust(tools, paths, path_adds)

    for tdef in TOOL_REGISTRY:
        resolved = _resolve_tool(tools, tdef)
        if resolved is None:
            continue
        paths[tdef.env_key] = resolved
        if tdef.path_add:
            path_adds.append(resolved)

    conan_dir = tools / "conan"
    if conan_dir.is_dir():
        paths["COCA_CONAN_PYTHONPATH"] = str(conan_dir)


def _resolve_tool(tools: Path, tdef: ToolDef) -> str | None:
    candidate = tools / tdef.rel_path
    if os.name == "nt" and tdef.win_suffix:
        alt = tools / (tdef.rel_path + tdef.win_suffix)
        if alt.exists():
            candidate = alt
        elif not candidate.suffix:
            alt2 = candidate.parent / (candidate.name + tdef.win_suffix)
            if alt2.exists():
                candidate = alt2

    if tdef.is_dir:
        return str(candidate) if candidate.is_dir() else None
    return str(candidate) if candidate.exists() else None


def _resolve_rust(tools: Path, paths: dict[str, str], path_adds: list[str]) -> None:
    rust = tools / "rust"
    if not rust.is_dir():
        return
    rustup = rust / "rustup"
    cargo = rust / "cargo"
    if rustup.is_dir():
        paths["RUSTUP_HOME"] = str(rustup)
    if cargo.is_dir():
        paths["CARGO_HOME"] = str(cargo)
        cargo_bin = cargo / "bin"
        if cargo_bin.is_dir():
            path_adds.append(str(cargo_bin))


def _resolve_emsdk(tools: Path, paths: dict[str, str]) -> None:
    emsdk = tools / "emsdk"
    if not emsdk.is_dir():
        return
    paths["EMSDK"] = str(emsdk)
    paths["EM_CONFIG"] = str(emsdk / ".emscripten")
    node_base = emsdk / "node"
    if node_base.is_dir():
        for nd in sorted(node_base.iterdir(), reverse=True):
            if nd.is_dir() and (nd / "bin").is_dir():
                paths["EMSDK_NODE"] = str(nd / "bin" / _exe("node"))
                break
    py_base = emsdk / "python"
    if py_base.is_dir():
        for pd in sorted(py_base.iterdir(), reverse=True):
            if pd.is_dir():
                py = pd / (_exe("python") if os.name == "nt" else "python3")
                if py.exists():
                    paths["EMSDK_PYTHON"] = str(py)
                    break
