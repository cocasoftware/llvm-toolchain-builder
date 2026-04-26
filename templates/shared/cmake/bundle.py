#!/usr/bin/env python3
"""
COCA Bundle — Determine runtime libraries to bundle for a given profile.

Reads toolchain.json and the sysroot layout to produce a JSON list of
absolute file paths that must be shipped alongside executables built
with the specified profile.

Usage:
    python bundle.py --toolchain-root <root> --profile <profile>
    python bundle.py --toolchain-root <root> --profile <profile> --categories vcruntime ucrt
    python bundle.py --toolchain-root <root> --profile <profile> --extra-dirs /some/dir

Output (stdout):  JSON array of absolute paths, one per runtime file.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def load_toolchain_json(toolchain_root: Path) -> dict:
    p = toolchain_root / "toolchain.json"
    if not p.exists():
        print(f"ERROR: {p} not found", file=sys.stderr)
        sys.exit(1)
    with open(p, encoding="utf-8") as f:
        return json.load(f)


def glob_files(directory: Path, patterns: list[str]) -> list[Path]:
    """Glob multiple patterns in a directory, return sorted unique list."""
    results: list[Path] = []
    for pat in patterns:
        results.extend(directory.glob(pat))
    # Deduplicate while preserving order
    seen: set[Path] = set()
    out: list[Path] = []
    for p in sorted(results):
        rp = p.resolve()
        if rp not in seen and rp.is_file():
            seen.add(rp)
            out.append(rp)
    return out


# ── Category helpers ──────────────────────────────────────────────────

def _want(categories: list[str], name: str) -> bool:
    return "all" in categories or name in categories


# ── Profile handlers ──────────────────────────────────────────────────

def collect_win_x64_msvc(
    toolchain_root: Path,
    profile_data: dict,
    categories: list[str],
    extra_dirs: list[Path],
) -> list[Path]:
    """win-x64 (MSVC ABI): VCRuntime DLLs, UCRT forwarders, libc++ DLL."""
    sysroot = toolchain_root / profile_data.get("sysroot", "")
    redist = sysroot / "redist"
    files: list[Path] = []

    if _want(categories, "vcruntime"):
        files.extend(glob_files(redist, [
            "vcruntime*.dll", "msvcp*.dll", "concrt*.dll", "vccorlib*.dll",
        ]))

    if _want(categories, "ucrt"):
        ucrt_dir = redist / "ucrt"
        if ucrt_dir.is_dir():
            files.extend(glob_files(ucrt_dir, ["*.dll"]))

    if _want(categories, "libc++"):
        for name in ("c++.dll", "libc++.dll"):
            for d in (toolchain_root / "lib", toolchain_root / "bin"):
                p = d / name
                if p.is_file():
                    files.append(p.resolve())

    for d in extra_dirs:
        files.extend(glob_files(d, ["*.dll"]))

    return files


def collect_win_x64_mingw(
    toolchain_root: Path,
    profile_data: dict,
    categories: list[str],
    extra_dirs: list[Path],
) -> list[Path]:
    """win-x64-mingw-{ucrt,msvcrt}: libc++.dll, libunwind.dll, libwinpthread-1.dll."""
    sysroot = toolchain_root / profile_data.get("sysroot", "")
    bin_dir = sysroot / "bin"
    files: list[Path] = []

    if _want(categories, "libc++"):
        files.extend(glob_files(bin_dir, ["libc++.dll", "libc++abi.dll"]))

    if _want(categories, "libunwind"):
        files.extend(glob_files(bin_dir, ["libunwind.dll"]))

    if _want(categories, "libwinpthread"):
        files.extend(glob_files(bin_dir, ["libwinpthread*.dll"]))

    for d in extra_dirs:
        files.extend(glob_files(d, ["*.dll"]))

    return files


def collect_linux_glibc(
    toolchain_root: Path,
    profile_data: dict,
    categories: list[str],
    extra_dirs: list[Path],
) -> list[Path]:
    """linux-{x64,arm64}[-kylin]: libc++.so*, libunwind.so*."""
    sysroot = toolchain_root / profile_data.get("sysroot", "")
    lib_dir = sysroot / "usr" / "lib"
    files: list[Path] = []

    if _want(categories, "libc++"):
        files.extend(glob_files(lib_dir, ["libc++.so*", "libc++abi.so*"]))

    if _want(categories, "libunwind"):
        files.extend(glob_files(lib_dir, ["libunwind.so*"]))

    for d in extra_dirs:
        files.extend(glob_files(d, ["*.so*"]))

    return files


def collect_linux_musl(
    toolchain_root: Path,
    profile_data: dict,
    categories: list[str],
    extra_dirs: list[Path],
) -> list[Path]:
    """linux-{x64,arm64}-musl: fully static — nothing to bundle."""
    _ = toolchain_root, profile_data, categories, extra_dirs
    return []


def collect_wasm(
    toolchain_root: Path,
    profile_data: dict,
    categories: list[str],
    extra_dirs: list[Path],
) -> list[Path]:
    """WASM targets: nothing to bundle."""
    _ = toolchain_root, profile_data, categories, extra_dirs
    return []


def collect_zig_win_x64(
    toolchain_root: Path,
    profile_data: dict,
    categories: list[str],
    extra_dirs: list[Path],
) -> list[Path]:
    """Zig win-x64 (MinGW ABI): Zig bundles everything statically — nothing to bundle."""
    _ = toolchain_root, profile_data, categories, extra_dirs
    return []


def collect_zig_linux(
    toolchain_root: Path,
    profile_data: dict,
    categories: list[str],
    extra_dirs: list[Path],
) -> list[Path]:
    """Zig linux targets: Zig links libc++ statically — nothing to bundle."""
    _ = toolchain_root, profile_data, categories, extra_dirs
    return []


# ── Dispatcher ────────────────────────────────────────────────────────

def collect_bundle_files(
    toolchain_root: Path,
    profile: str,
    profile_data: dict,
    categories: list[str],
    extra_dirs: list[Path],
) -> list[Path]:
    runtime = profile_data.get("runtime", "")
    zig_target = profile_data.get("zig_target", "")

    # Zig toolchain (has zig_target instead of runtime)
    if zig_target:
        if "windows" in zig_target:
            return collect_zig_win_x64(toolchain_root, profile_data, categories, extra_dirs)
        else:
            return collect_zig_linux(toolchain_root, profile_data, categories, extra_dirs)

    # LLVM toolchains
    if runtime == "msvc":
        return collect_win_x64_msvc(toolchain_root, profile_data, categories, extra_dirs)
    elif runtime == "mingw":
        return collect_win_x64_mingw(toolchain_root, profile_data, categories, extra_dirs)
    elif runtime == "llvm":
        if profile_data.get("static", False):
            return collect_linux_musl(toolchain_root, profile_data, categories, extra_dirs)
        else:
            return collect_linux_glibc(toolchain_root, profile_data, categories, extra_dirs)
    elif runtime in ("wasi", "emscripten"):
        return collect_wasm(toolchain_root, profile_data, categories, extra_dirs)
    else:
        print(f"WARNING: Unknown runtime '{runtime}' for profile '{profile}'", file=sys.stderr)
        return []


# ── Main ──────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="COCA Bundle — list runtime files to ship.")
    parser.add_argument("--toolchain-root", required=True, type=Path,
                        help="Absolute path to the toolchain root directory")
    parser.add_argument("--profile", required=True,
                        help="Target profile name (e.g. win-x64, linux-x64)")
    parser.add_argument("--categories", nargs="*", default=["all"],
                        help="Filter categories (default: all). "
                             "Options: all, vcruntime, ucrt, libc++, libunwind, libwinpthread")
    parser.add_argument("--extra-dirs", nargs="*", default=[],
                        type=Path, help="Additional directories to search for runtime libs")
    args = parser.parse_args()

    toolchain_root = args.toolchain_root.resolve()
    data = load_toolchain_json(toolchain_root)
    profiles = data.get("profiles", {})

    if args.profile not in profiles:
        print(f"ERROR: Unknown profile '{args.profile}'", file=sys.stderr)
        print(f"  Available: {', '.join(profiles.keys())}", file=sys.stderr)
        sys.exit(1)

    profile_data = profiles[args.profile]
    files = collect_bundle_files(
        toolchain_root, args.profile, profile_data,
        args.categories, [p.resolve() for p in args.extra_dirs],
    )

    # Deduplicate
    seen: set[str] = set()
    unique: list[str] = []
    for f in files:
        s = str(f)
        if s not in seen:
            seen.add(s)
            unique.append(s)

    json.dump(unique, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
