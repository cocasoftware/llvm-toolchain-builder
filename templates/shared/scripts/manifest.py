"""--update-manifest: Regenerate manifest.json with checksums + component versions."""
from __future__ import annotations

import hashlib
import json
import os
import platform
from datetime import datetime, timezone
from pathlib import Path

from .model import ToolchainInfo
from .components import detect_component_versions
from .rich_utils import get_console, vprint


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(1 << 20):
            h.update(chunk)
    return h.hexdigest()


# Files whose content directly determines output binary behavior / ABI.
# Organized by category for readability in manifest.json.
_CHECKSUM_SPEC: dict[str, list[str | tuple[str, ...]]] = {
    # ── C/C++ compilers & drivers ──
    "compilers": [
        "bin/clang",            # C/C++/ObjC compiler (also clang++)
        "bin/clang-cl",         # MSVC-compatible driver
        "bin/flang",            # Fortran compiler
    ],
    # ── Linkers ──
    "linkers": [
        "bin/lld",              # Universal linker entry point
        "bin/ld.lld",           # ELF linker
        "bin/lld-link",         # COFF/PE linker
        "bin/ld64.lld",         # Mach-O linker
        "bin/wasm-ld",          # WebAssembly linker
    ],
    # ── Archive / object tools (affect static lib content) ──
    "ar_tools": [
        "bin/llvm-ar",
        "bin/llvm-objcopy",
        "bin/llvm-strip",
        "bin/llvm-ranlib",
    ],
    # ── C++ runtime (linked into every C++ binary) ──
    "cxx_runtime": [
        "lib/libc++.lib",
        "lib/libc++experimental.lib",
        "bin/c++.dll",
    ],
    # ── Shared libraries (loaded at runtime or import-linked) ──
    "shared_libs": [
        "bin/LLVM-C.dll",
        "bin/LTO.dll",
        "bin/Remarks.dll",
        "bin/libomp.dll",
    ],
    # ── Rust (rustc + cargo determine Rust binary output) ──
    "rust": [
        ("tools/rust/rustup/toolchains/*/bin/rustc", True),
        ("tools/rust/rustup/toolchains/*/bin/cargo", True),
        "tools/rust/rustup-init",
    ],
    # ── Python (build scripts, coca-tools behavior) ──
    "python": [
        "tools/python/python",
        "tools/python/python314.dll" if os.name == "nt" else "tools/python/libpython3.14.so",
    ],
    # ── Build tools (affect build determinism) ──
    "build_tools": [
        "tools/cmake/bin/cmake",
        "tools/ninja/ninja",
        "tools/msys2-make/msys2-make",
    ],
    # ── CMake toolchain file (governs all cross-compilation) ──
    "cmake_config": [
        "cmake/toolchain.cmake",
    ],
    # ── Emscripten compiler (wasm target) ──
    "emscripten": [
        "tools/emsdk/upstream/emscripten/emcc.py",
        "tools/emsdk/upstream/emscripten/emcc.bat" if os.name == "nt" else "tools/emsdk/upstream/emscripten/emcc",
    ],
}

# Per-target compiler-rt builtins — these are linked into every binary for that target.
_COMPILER_RT_BUILTINS_GLOBS: list[str] = [
    "lib/clang/*/lib/*/libclang_rt.builtins*",
    "lib/clang/*/lib/*/clang_rt.builtins*",
]


def _collect_checksums(info: ToolchainInfo) -> dict[str, dict[str, str] | str]:
    """Collect SHA-256 checksums for all portability-critical files."""
    root = info.root
    result: dict[str, dict[str, str] | str] = {}

    for category, specs in _CHECKSUM_SPEC.items():
        cat_checksums: dict[str, str] = {}
        for spec in specs:
            use_glob = False
            if isinstance(spec, tuple):
                spec_path, use_glob = spec
            else:
                spec_path = spec

            if use_glob:
                matches = sorted(root.glob(spec_path + (".exe" if os.name == "nt" else "")))
                if not matches:
                    matches = sorted(root.glob(spec_path))
                for m in matches:
                    if m.is_file():
                        rel = m.relative_to(root).as_posix()
                        cat_checksums[rel] = _sha256(m)
            else:
                p = root / spec
                if os.name == "nt" and not p.exists() and not p.suffix:
                    p_exe = root / (spec + ".exe")
                    if p_exe.exists():
                        p = p_exe
                if p.is_file():
                    rel = p.relative_to(root).as_posix()
                    cat_checksums[rel] = _sha256(p)

        if cat_checksums:
            result[category] = cat_checksums
            vprint(f"    [dim]{category}:[/] {len(cat_checksums)} files checksummed")

    # Per-target compiler-rt builtins
    rt_checksums: dict[str, str] = {}
    for glob_pat in _COMPILER_RT_BUILTINS_GLOBS:
        for m in sorted(root.glob(glob_pat)):
            if m.is_file():
                rel = m.relative_to(root).as_posix()
                rt_checksums[rel] = _sha256(m)
    if rt_checksums:
        result["compiler_rt_builtins"] = rt_checksums

    # Compute a single fingerprint over ALL individual checksums.
    # Deterministic: sort by (category, relative_path) then hash the concatenation.
    h = hashlib.sha256()
    for cat in sorted(k for k in result if isinstance(result[k], dict)):
        cat_dict = result[cat]
        assert isinstance(cat_dict, dict)
        for rel_path in sorted(cat_dict):
            h.update(f"{cat}:{rel_path}={cat_dict[rel_path]}\n".encode())
    result["_fingerprint"] = h.hexdigest()

    return result


def _print_manifest_diff(console, old: dict, new: dict, prefix: str = "") -> None:
    for key in sorted(set(list(old.keys()) + list(new.keys()))):
        fk = f"{prefix}.{key}" if prefix else key
        ov, nv = old.get(key), new.get(key)
        if ov == nv:
            continue
        if isinstance(ov, dict) and isinstance(nv, dict):
            _print_manifest_diff(console, ov, nv, fk)
        elif ov is None:
            console.print(f"    [green]+ {fk}[/]: {nv}")
        elif nv is None:
            console.print(f"    [red]- {fk}[/]: {ov}")
        else:
            console.print(f"    [yellow]~ {fk}[/]: {ov} → {nv}")


def cmd_update_manifest(info: ToolchainInfo) -> None:
    console = get_console()
    tc = info.toolchain_json

    manifest: dict = {
        "toolchain_name": info.name,
        "toolchain_version": tc.get("toolchain_version", "?"),
        "build_date": info.manifest_json.get("build_date",
                      datetime.now(timezone.utc).strftime("%Y-%m-%d")),
        "build_host": info.manifest_json.get("build_host",
                      f"{platform.machine()}-{platform.system().lower()}"),
    }

    # Auto-detect component versions
    console.print("  [dim]Detecting component versions…[/]")
    manifest["components"] = detect_component_versions(info)

    manifest["profiles"] = sorted(tc.get("profiles", {}).keys())
    if "notes" in info.manifest_json:
        manifest["notes"] = info.manifest_json["notes"]

    manifest["checksums"] = _collect_checksums(info)

    manifest_path = info.root / "manifest.json"
    old_text = manifest_path.read_text(encoding="utf-8") if manifest_path.exists() else ""
    new_text = json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"
    manifest_path.write_text(new_text, encoding="utf-8")

    if old_text == new_text:
        console.print("  [dim]manifest.json is already up to date[/]")
    else:
        console.print(f"  [bold green]Updated[/] {manifest_path}")
        old_mf = json.loads(old_text) if old_text.strip() else {}
        _print_manifest_diff(console, old_mf, manifest)
    console.print()
