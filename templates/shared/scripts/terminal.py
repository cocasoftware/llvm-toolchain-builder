"""--terminal: Launch bundled Windows Terminal with a COCA Toolchain profile."""
from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

from .model import ToolchainInfo
from .rich_utils import get_console

_COCA_PROFILE_GUID = "{17c736e8-c8a4-4f6e-b0a1-c97b55e3f8a0}"


def _toolchain_label(info: ToolchainInfo) -> str:
    """Return a human-readable label for the toolchain variant."""
    name = info.name.lower()
    if "p2996" in name:
        return "COCA P2996 Toolchain"
    if "zig" in name:
        return "COCA Zig Toolchain"
    return "COCA Toolchain"


def _ensure_settings(
    info: ToolchainInfo, *,
    exec_args: list[str] | None = None,
) -> Path:
    """Create / update settings/settings.json with a COCA profile.

    The profile launches ``setup.py exec [exec_args...]`` via the bundled
    Python so the user lands in a fully-activated COCA shell inside WT.

    *exec_args* are forwarded verbatim to the ``exec`` subcommand
    (e.g. ``["--inherit-env", "--no-venv"]``).
    """
    terminal_dir = info.root / "tools" / "terminal"
    settings_dir = terminal_dir / "settings"
    settings_dir.mkdir(parents=True, exist_ok=True)

    # Ensure .portable marker exists (tells WT to use local settings)
    portable_marker = terminal_dir / ".portable"
    if not portable_marker.exists():
        portable_marker.touch()

    python_exe = str(info.root / "tools" / "python" / "python.exe")
    setup_py = str(info.root / "setup.py")
    icon_path = str(terminal_dir / "ProfileIcons" / "pwsh.scale-100.png")

    label = _toolchain_label(info)
    commandline = f'"{python_exe}" "{setup_py}" exec'
    if exec_args:
        commandline += " " + " ".join(exec_args)

    settings_file = settings_dir / "settings.json"

    # If settings.json already exists, patch in our profile; otherwise create fresh
    if settings_file.exists():
        try:
            settings = json.loads(settings_file.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            settings = {}
    else:
        settings = {}

    settings.setdefault("$help", "https://aka.ms/terminal-documentation")
    settings.setdefault("$schema", "https://aka.ms/terminal-profiles-schema")
    profiles = settings.setdefault("profiles", {})
    defaults = profiles.setdefault("defaults", {})
    profile_list: list[dict] = profiles.setdefault("list", [])

    # Find or create the COCA profile
    coca_profile = None
    for p in profile_list:
        if p.get("guid") == _COCA_PROFILE_GUID:
            coca_profile = p
            break

    if coca_profile is None:
        coca_profile = {"guid": _COCA_PROFILE_GUID}
        profile_list.insert(0, coca_profile)

    coca_profile["name"] = label
    coca_profile["commandline"] = commandline
    coca_profile["font"] = {"face": "Cascadia Code", "size": 11}
    coca_profile["colorScheme"] = "One Half Dark"
    coca_profile["cursorShape"] = "filledBox"
    coca_profile["startingDirectory"] = "%USERPROFILE%"
    if Path(icon_path).exists():
        coca_profile["icon"] = icon_path

    settings["defaultProfile"] = _COCA_PROFILE_GUID

    settings_file.write_text(
        json.dumps(settings, indent=4, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return settings_file


def cmd_terminal(
    info: ToolchainInfo, *,
    exec_args: list[str] | None = None,
    working_dir: str | None = None,
) -> None:
    """Launch Windows Terminal with the COCA profile.

    *exec_args* are forwarded to ``setup.py exec`` inside the WT profile
    commandline (e.g. ``["--inherit-env", "--no-venv"]"``).

    *working_dir* if given, passed to wt.exe as ``--startingDirectory``.
    """
    console = get_console()
    wt_exe = info.root / "tools" / "terminal" / "wt.exe"
    if not wt_exe.exists():
        console.print("[bold red]Error:[/] Windows Terminal not found at")
        console.print(f"  {wt_exe}")
        console.print("Run the setup script to download it.")
        raise SystemExit(1)

    settings_file = _ensure_settings(info, exec_args=exec_args)
    console.print(f"  [dim]Settings:[/] {settings_file}")
    if exec_args:
        console.print(f"  [dim]Exec args:[/] {' '.join(exec_args)}")
    console.print(f"  [dim]Launching:[/] {wt_exe}")

    # Launch wt.exe with the COCA profile; detached so setup.py returns immediately
    wt_cmd: list[str] = [str(wt_exe), "--profile", _COCA_PROFILE_GUID]
    if working_dir:
        wt_cmd += ["--startingDirectory", working_dir]
    subprocess.Popen(
        wt_cmd,
        creationflags=subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP
        if os.name == "nt" else 0,
    )
    console.print("[bold green]✓[/] Windows Terminal launched")
