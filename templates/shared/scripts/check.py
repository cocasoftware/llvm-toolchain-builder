"""--check: Validate toolchain integrity."""
from __future__ import annotations

import os
import subprocess

from .model import ToolchainInfo, CheckResult, _exe
from .rich_utils import get_console, vprint


def cmd_check(info: ToolchainInfo, filt: str | None = None) -> int:
    from rich.table import Table
    console = get_console()
    checks: list[CheckResult] = []

    vprint(f"  [dim]Checking toolchain at[/] {info.root}")

    for fname in ["toolchain.json", "manifest.json", "setup.py"]:
        p = info.root / fname
        vprint(f"  [dim]  file:[/] {p} {'[green]exists[/]' if p.exists() else '[red]MISSING[/]'}")
        checks.append(CheckResult(fname, p.exists(), str(p)))

    bin_dir = info.root / "bin"
    key_bins = ["clang", "clang++", "lld", "llvm-ar", "llvm-nm", "llvm-objdump"]
    for b in key_bins:
        exe = bin_dir / _exe(b)
        checks.append(CheckResult(f"bin/{_exe(b)}", exe.exists(), str(exe)))

    tc_cmake = info.root / "cmake" / "toolchain.cmake"
    checks.append(CheckResult("cmake/toolchain.cmake", tc_cmake.exists(), str(tc_cmake)))

    py_exe = info.root / "tools" / "python" / _exe("python")
    checks.append(CheckResult("tools/python", py_exe.exists(), str(py_exe)))
    if py_exe.exists():
        r = subprocess.run([str(py_exe), "-c", "import encodings; print('ok')"],
                           capture_output=True, text=True, timeout=10,
                           env={**os.environ, "PYTHONNOUSERSITE": "1"})
        checks.append(CheckResult("python encodings", r.returncode == 0 and "ok" in r.stdout,
                                  r.stderr.strip() if r.returncode != 0 else ""))

    for pname, pinfo in info.toolchain_json.get("profiles", {}).items():
        sr = pinfo.get("sysroot")
        if sr:
            sr_path = info.root / sr
            checks.append(CheckResult(f"sysroot:{pname}", sr_path.exists(),
                                      f"{sr} → {'OK' if sr_path.exists() else 'MISSING'}"))

    mf_ver = info.manifest_json.get("toolchain_version", "")
    tc_ver = info.toolchain_json.get("toolchain_version", "")
    checks.append(CheckResult("version consistency", mf_ver == tc_ver,
                               f"manifest={mf_ver} toolchain={tc_ver}"))

    mf_profiles = set(info.manifest_json.get("profiles", []))
    tc_profiles = set(info.toolchain_json.get("profiles", {}).keys())
    profiles_ok = mf_profiles == tc_profiles or not mf_profiles
    detail = ""
    if not profiles_ok:
        missing = tc_profiles - mf_profiles
        extra = mf_profiles - tc_profiles
        parts = []
        if missing:
            parts.append(f"missing in manifest: {', '.join(sorted(missing))}")
        if extra:
            parts.append(f"extra in manifest: {', '.join(sorted(extra))}")
        detail = "; ".join(parts)
    checks.append(CheckResult("profiles consistency", profiles_ok, detail))

    console.print()
    table = Table(title=f"Toolchain Check: {info.name}", title_style="bold",
                  border_style="cyan", padding=(0, 1))
    table.add_column("Status", width=4, justify="center")
    table.add_column("Check")
    table.add_column("Detail", style="dim")
    for c in checks:
        table.add_row("[bold green]✓[/]" if c.ok else "[bold red]✗[/]", c.name, c.detail)
    console.print(table)

    passed = sum(1 for c in checks if c.ok)
    total = len(checks)
    failed = total - passed
    if failed:
        console.print(f"\n  [bold red]{failed}/{total} checks failed[/]\n")
        return 1
    console.print(f"\n  [bold green]All {total} checks passed[/]\n")
    return 0
