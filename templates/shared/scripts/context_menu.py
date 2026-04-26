"""context-menu: Register / unregister COCA Terminal in Windows Explorer right-click menu."""
from __future__ import annotations

import os
import winreg
from pathlib import Path

from .model import ToolchainInfo
from .rich_utils import get_console

# Registry paths under HKCU\Software\Classes
_TARGETS = [
    r"Directory\Background\shell",  # right-click on folder background
    r"Directory\shell",             # right-click on a folder
]

# The parent cascading menu key name
_COCA_PARENT_KEY = "COCA"
_COCA_PARENT_LABEL = "COCA Toolchain"


def _variant_label(info: ToolchainInfo) -> tuple[str, str]:
    """Return (registry_key_suffix, display_label) based on toolchain variant."""
    name = info.name.lower()
    if "p2996" in name:
        return "COCATerminalP2996", "Open COCA P2996 Terminal here"
    if "zig" in name:
        return "COCATerminalZig", "Open COCA Zig Terminal here"
    return "COCATerminal", "Open COCA Terminal here"


def _get_exe_path(info: ToolchainInfo) -> Path:
    return info.root / "coca-terminal.exe"


def _get_icon_path(info: ToolchainInfo) -> Path:
    """Return icon path for the context menu entry.

    Prefers .ico (multi-size, native Windows format) over .png.
    """
    ico = info.root / "coca-terminal.ico"
    if ico.exists():
        return ico
    png = info.root / "tools" / "terminal" / "ProfileIcons" / "pwsh.scale-100.png"
    if png.exists():
        return png
    return _get_exe_path(info)


def _ensure_parent_menu(target: str, icon_path: Path) -> None:
    """Create the COCA cascading parent menu if it doesn't exist.

    Registry layout::

        HKCU\Software\Classes\<target>\COCA
            (Default)  = ""           (unused, MUIVerb takes precedence)
            MUIVerb    = "COCA Toolchain"
            Icon       = <icon_path>
            SubCommands = ""          (empty → use nested shell subkeys)
        HKCU\Software\Classes\<target>\COCA\shell\  ← child entries go here
    """
    parent_path = rf"Software\Classes\{target}\{_COCA_PARENT_KEY}"
    with winreg.CreateKeyEx(winreg.HKEY_CURRENT_USER, parent_path, 0, winreg.KEY_WRITE) as key:
        winreg.SetValueEx(key, "MUIVerb", 0, winreg.REG_SZ, _COCA_PARENT_LABEL)
        winreg.SetValueEx(key, "Icon", 0, winreg.REG_SZ, str(icon_path))
        winreg.SetValueEx(key, "SubCommands", 0, winreg.REG_SZ, "")
    # Ensure the nested shell key exists
    shell_path = rf"{parent_path}\shell"
    winreg.CreateKeyEx(winreg.HKEY_CURRENT_USER, shell_path, 0, winreg.KEY_WRITE).Close()


def cmd_context_menu_install(info: ToolchainInfo) -> int:
    """Register COCA Terminal in Explorer context menu (HKCU, no admin needed).

    Creates a cascading "COCA Toolchain" submenu with the terminal entry
    nested underneath, keeping the top-level context menu clean.
    """
    console = get_console()

    if os.name != "nt":
        console.print("[bold red]Error:[/] Context menu registration is Windows-only.")
        return 1

    exe = _get_exe_path(info)
    if not exe.exists():
        console.print(f"[bold red]Error:[/] coca-terminal.exe not found at\n  {exe}")
        return 1

    icon = _get_icon_path(info)
    reg_key_name, display_name = _variant_label(info)
    command = f'"{exe}" --working-dir "%V"'

    for target in _TARGETS:
        try:
            # 1. Ensure COCA parent cascading menu
            _ensure_parent_menu(target, icon)

            # 2. Register the terminal entry under COCA\shell\<variant>
            entry_path = rf"Software\Classes\{target}\{_COCA_PARENT_KEY}\shell\{reg_key_name}"
            with winreg.CreateKeyEx(winreg.HKEY_CURRENT_USER, entry_path, 0, winreg.KEY_WRITE) as key:
                winreg.SetValueEx(key, "", 0, winreg.REG_SZ, display_name)
                winreg.SetValueEx(key, "Icon", 0, winreg.REG_SZ, str(icon))

            cmd_path = rf"{entry_path}\command"
            with winreg.CreateKeyEx(winreg.HKEY_CURRENT_USER, cmd_path, 0, winreg.KEY_WRITE) as key:
                winreg.SetValueEx(key, "", 0, winreg.REG_SZ, command)

            console.print(f"  [green]✓[/] Registered: HKCU\\{entry_path}")
        except OSError as e:
            console.print(f"  [red]✗[/] Failed: HKCU\\Software\\Classes\\{target} — {e}")
            return 1

    console.print(f"\n[bold green]Context menu installed.[/]")
    console.print(f"  [dim]Command:[/] {command}")
    console.print(f'  [dim]Right-click → "{_COCA_PARENT_LABEL}" → "{display_name}"[/]')
    return 0


def _delete_key_recursive(root: int, path: str) -> bool:
    """Recursively delete a registry key and all its subkeys.

    ``winreg.DeleteKey`` cannot delete keys that have subkeys, so we
    must walk bottom-up.
    """
    try:
        with winreg.OpenKeyEx(root, path, 0, winreg.KEY_READ) as key:
            subkeys: list[str] = []
            i = 0
            while True:
                try:
                    subkeys.append(winreg.EnumKey(key, i))
                    i += 1
                except OSError:
                    break
        for sk in subkeys:
            _delete_key_recursive(root, rf"{path}\{sk}")
        winreg.DeleteKey(root, path)
        return True
    except FileNotFoundError:
        return False


def cmd_context_menu_uninstall(info: ToolchainInfo) -> int:
    """Remove COCA Terminal from Explorer context menu.

    Removes the variant's entry from the COCA submenu. If no entries
    remain under the COCA parent, the parent key is removed too.
    """
    console = get_console()

    if os.name != "nt":
        console.print("[bold red]Error:[/] Context menu registration is Windows-only.")
        return 1

    reg_key_name, _ = _variant_label(info)
    removed = 0

    for target in _TARGETS:
        # 1. Remove this variant's entry from COCA\shell\<variant>
        entry_path = rf"Software\Classes\{target}\{_COCA_PARENT_KEY}\shell\{reg_key_name}"
        if _delete_key_recursive(winreg.HKEY_CURRENT_USER, entry_path):
            console.print(f"  [green]✓[/] Removed: HKCU\\{entry_path}")
            removed += 1
        else:
            console.print(f"  [dim]—[/] Not found: HKCU\\{entry_path}")

        # 2. Also clean up legacy flat entries (pre-submenu layout)
        legacy_path = rf"Software\Classes\{target}\{reg_key_name}"
        if _delete_key_recursive(winreg.HKEY_CURRENT_USER, legacy_path):
            console.print(f"  [green]✓[/] Removed legacy: HKCU\\{legacy_path}")
            removed += 1

        # 3. If the COCA\shell key is now empty, remove the whole COCA parent
        parent_shell = rf"Software\Classes\{target}\{_COCA_PARENT_KEY}\shell"
        try:
            with winreg.OpenKeyEx(winreg.HKEY_CURRENT_USER, parent_shell, 0, winreg.KEY_READ) as key:
                try:
                    winreg.EnumKey(key, 0)
                except OSError:
                    # No subkeys left — remove the parent
                    parent_path = rf"Software\Classes\{target}\{_COCA_PARENT_KEY}"
                    _delete_key_recursive(winreg.HKEY_CURRENT_USER, parent_path)
                    console.print(f"  [green]✓[/] Removed empty parent: HKCU\\{parent_path}")
        except FileNotFoundError:
            pass

    if removed > 0:
        console.print(f"\n[bold green]Context menu uninstalled.[/]")
    else:
        console.print(f"\n[dim]Nothing to uninstall — context menu was not registered.[/]")
    return 0
