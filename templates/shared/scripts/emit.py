"""Shell command emitters (stdout — plain text only for piping)."""
from __future__ import annotations

from . import COCA_LOGO
from .model import ToolchainInfo


# ── Shell Emitters (stdout — plain text only) ───────────────────────────────
# CRITICAL: stdout goes to Invoke-Expression / eval.
# NEVER emit empty lines (PS Invoke-Expression fails on "").

def _ps_banner(info: ToolchainInfo) -> list[str]:
    lines: list[str] = [
        "[console]::OutputEncoding = [System.Text.Encoding]::UTF8",
    ]
    for art_line in COCA_LOGO.strip().splitlines():
        escaped = art_line.replace("'", "''")
        lines.append(f"Write-Host '{escaped}' -ForegroundColor Cyan")
    lines.append("Write-Host ''")
    lines.append(f"Write-Host '  Toolchain v{info.version}  |  LLVM {info.llvm_version}  |  {info.root}' -ForegroundColor Green")
    lines.append("Write-Host ''")
    return lines


def emit_powershell(info: ToolchainInfo) -> str:
    lines: list[str] = []
    for k, v in info.paths.items():
        lines.append(f'$env:{k} = "{v}"')
    if info.path_adds:
        lines.append(f'$env:PATH = "{";".join(info.path_adds)};$env:PATH"')
    if "COCA_CONAN_PYTHONPATH" in info.paths:
        lines.append(f'$env:PYTHONPATH = "{info.paths["COCA_CONAN_PYTHONPATH"]};$env:PYTHONPATH"')
    lines.extend(_ps_banner(info))
    return "\n".join(lines)


def emit_cmd(info: ToolchainInfo) -> str:
    lines = ["@echo off"]
    for k, v in info.paths.items():
        lines.append(f'set "{k}={v}"')
    if info.path_adds:
        lines.append(f'set "PATH={";".join(info.path_adds)};%PATH%"')
    if "COCA_CONAN_PYTHONPATH" in info.paths:
        lines.append(f'set "PYTHONPATH={info.paths["COCA_CONAN_PYTHONPATH"]};%PYTHONPATH%"')
    lines.append(f"echo [ready] COCA Toolchain v{info.version}: {info.root}")
    return "\n".join(lines)


def emit_bash(info: ToolchainInfo) -> str:
    lines: list[str] = []
    for k, v in info.paths.items():
        lines.append(f'export {k}="{v.replace(chr(92), "/")}"')
    if info.path_adds:
        parts = ":".join(p.replace("\\", "/") for p in info.path_adds)
        lines.append(f'export PATH="{parts}:$PATH"')
    if "COCA_CONAN_PYTHONPATH" in info.paths:
        pp = info.paths["COCA_CONAN_PYTHONPATH"].replace("\\", "/")
        lines.append(f'export PYTHONPATH="{pp}:$PYTHONPATH"')
    lines.append(rf'printf "\033[1;32m[ready]\033[0m COCA Toolchain v{info.version}: %s\n" "$COCA_TOOLCHAIN"')
    return "\n".join(lines)
