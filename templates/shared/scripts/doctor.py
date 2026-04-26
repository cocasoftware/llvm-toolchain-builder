"""--doctor: Diagnose common toolchain problems."""
from __future__ import annotations

import os
import subprocess

from .model import ToolchainInfo, _exe
from .rich_utils import get_console, vprint


def cmd_doctor(info: ToolchainInfo) -> int:
    from rich.table import Table
    console = get_console()
    issues: list[tuple[str, str, str]] = []

    vprint(f"  [dim]Running doctor on[/] {info.root}")

    py_exe = info.root / "tools" / "python" / _exe("python")
    if py_exe.exists():
        r = subprocess.run([str(py_exe), "-c", "import rich; import coca_tools"],
                           capture_output=True, text=True, timeout=10,
                           env={**os.environ, "PYTHONNOUSERSITE": "1"})
        if r.returncode != 0:
            issues.append(("error", "python",
                          f"Cannot import rich/coca_tools: {r.stderr.strip()[:200]}"))
        r = subprocess.run([str(py_exe), "-c", "import venv"],
                           capture_output=True, text=True, timeout=10,
                           env={**os.environ, "PYTHONNOUSERSITE": "1"})
        if r.returncode != 0:
            issues.append(("error", "python", "venv module not available"))
    else:
        issues.append(("error", "python", f"Bundled Python not found: {py_exe}"))

    sysroots = info.root / "sysroots"
    if sysroots.is_dir():
        for d in sysroots.iterdir():
            if d.name.startswith("."):
                continue
            if d.is_symlink() or d.is_junction():
                if not d.resolve().exists():
                    issues.append(("error", "sysroot", f"Broken link: {d.name}"))
            elif d.is_dir():
                try:
                    first = next(d.iterdir(), None)
                except PermissionError:
                    issues.append(("warn", "sysroot", f"Permission denied: {d.name}"))
                    continue
                if first is None:
                    issues.append(("warn", "sysroot", f"Empty sysroot: {d.name}"))

    if os.name == "nt":
        for dll in ["vcruntime140.dll", "vcruntime140_1.dll"]:
            if not (info.root / "tools" / "python" / dll).exists():
                issues.append(("warn", "python", f"Missing {dll} in tools/python/"))

    if info.manifest_json:
        mf_ver = info.manifest_json.get("toolchain_version", "")
        tc_ver = info.toolchain_json.get("toolchain_version", "")
        if mf_ver and tc_ver and mf_ver != tc_ver:
            issues.append(("warn", "config",
                          f"Version mismatch: manifest={mf_ver}, toolchain.json={tc_ver}. "
                          "Run --update-manifest to fix."))

    console.print()
    if not issues:
        console.print("  [bold green]No issues found.[/] Toolchain looks healthy.\n")
        return 0

    table = Table(title=f"Doctor: {info.name}", title_style="bold",
                  border_style="cyan", padding=(0, 1))
    table.add_column("Sev", width=5, justify="center")
    table.add_column("Area", style="cyan", no_wrap=True)
    table.add_column("Issue")
    sev_map = {"error": "[bold red]ERROR[/]", "warn": "[bold yellow]WARN[/]", "info": "[dim]INFO[/]"}
    for sev, area, desc in issues:
        table.add_row(sev_map.get(sev, sev), area, desc)
    console.print(table)

    errors = sum(1 for s, _, _ in issues if s == "error")
    warns = sum(1 for s, _, _ in issues if s == "warn")
    console.print(f"\n  [bold]{len(issues)} issues[/]: [red]{errors} errors[/], [yellow]{warns} warnings[/]\n")
    return 1 if errors else 0
