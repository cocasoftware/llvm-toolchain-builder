#!/usr/bin/env python3
"""
COCA Toolchain — Environment Setup & Diagnostics

Unified setup script for all COCA toolchains (main, p2996, etc.).
Detects toolchain variant from toolchain.json and adapts automatically.

Subcommands:
    setup.py env [--shell ...]     Emit shell commands to stdout (default)
    setup.py info                  Rich-formatted toolchain summary
    setup.py check [--filter ...]  Validate toolchain integrity
    setup.py test  [--filter ...]  Run toolchain test suite
    setup.py update-manifest       Regenerate manifest.json
    setup.py doctor                Diagnose common problems
    setup.py exec  [--shell ...]   Apply env + launch interactive shell
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

TOOLCHAIN_ROOT = Path(__file__).resolve().parent


# ── Self-bootstrap to bundled Python ─────────────────────────────────────────
# If the current interpreter is NOT the toolchain's bundled Python, re-exec
# under it so that `rich`, `coca_tools`, and other bundled packages are always
# available regardless of what `python` sits on the user's PATH.
def _bootstrap_bundled_python() -> None:
    bundled = TOOLCHAIN_ROOT / "tools" / "python" / ("python.exe" if os.name == "nt" else "python3")
    if not bundled.exists():
        return
    current = Path(sys.executable).resolve()
    if current == bundled.resolve():
        return
    env = {**os.environ, "PYTHONNOUSERSITE": "1"}
    # Re-exec: replaces the current process image on Unix; on Windows os.execv
    # does not truly replace, so we fall back to subprocess + sys.exit.
    if os.name == "nt":
        import subprocess
        r = subprocess.run([str(bundled)] + sys.argv, env=env)
        sys.exit(r.returncode)
    else:
        os.execve(str(bundled), [str(bundled)] + sys.argv, env)


if __name__ == "__main__":
    _bootstrap_bundled_python()


# Force UTF-8 stdout/stderr for Unicode box-drawing chars in COCA_LOGO
for _stream in (sys.stdout, sys.stderr):
    if _stream and hasattr(_stream, "reconfigure") and getattr(_stream, "encoding", "utf-8").lower() not in ("utf-8", "utf8"):
        _stream.reconfigure(encoding="utf-8", errors="replace")

# Ensure scripts/ package is importable
sys.path.insert(0, str(TOOLCHAIN_ROOT))

from scripts.model import load_toolchain
from scripts.resolve import resolve_paths


def detect_shell() -> str:
    if os.name == "nt":
        return "powershell" if os.environ.get("PSModulePath") else "cmd"
    return "bash"


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="setup.py",
        description="COCA Toolchain — Environment Setup & Diagnostics",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Examples:\n"
               "  setup.py env | Invoke-Expression    # PowerShell: activate\n"
               '  eval "$(setup.py env --shell bash)" # bash: activate\n'
               "  setup.py info                       # Rich summary\n"
               "  setup.py check                      # Validate integrity\n"
               "  setup.py test --filter tools        # Run tool tests only\n"
               "  setup.py doctor                     # Diagnose problems\n"
               "  setup.py update-manifest            # Regenerate manifest.json\n"
               "  setup.py terminal                   # Launch Windows Terminal\n",
    )
    parser.add_argument("--verbose", "-v", action="store_true", default=False,
                        help="Show detailed progress output for all subcommands")
    sub = parser.add_subparsers(dest="command")

    # env (default when no subcommand)
    sp_env = sub.add_parser("env", help="Emit shell environment commands to stdout")
    sp_env.add_argument("--shell", choices=["powershell", "cmd", "bash"], default=None)

    # info
    sub.add_parser("info", help="Rich-formatted toolchain summary")

    # check
    sp_check = sub.add_parser("check", help="Validate toolchain integrity")
    sp_check.add_argument("--filter", "-f", default=None, help="Filter checks (e.g. 'tools', 'sysroots')")

    # test
    sp_test = sub.add_parser("test", help="Run toolchain test suite")
    sp_test.add_argument("--filter", "-f", default=None,
                         help="Filter tests: phase name or dotted test id (e.g. 'tools', 'compile.c', 'cross.linux-x64')")

    # update-manifest
    sub.add_parser("update-manifest", help="Regenerate manifest.json from current state")

    # doctor
    sub.add_parser("doctor", help="Diagnose common toolchain problems")

    # exec
    sp_exec = sub.add_parser("exec", help="Launch interactive shell with env applied")
    sp_exec.add_argument("--shell", choices=["powershell", "cmd", "bash"], default=None)
    sp_exec.add_argument("--no-venv", action="store_true", default=False,
                         help="Skip automatic venv creation/activation (venv is enabled by default)")
    sp_exec.add_argument("--venv-dir", type=str, default=None, metavar="PATH",
                         help="Base directory for .venv/ (default: current working directory)")
    sp_exec.add_argument("--inherit-env", action="store_true", default=False,
                         help="Inherit full user/system environment instead of sandboxed minimal env")
    sp_exec.add_argument("--system-shell", action="store_true", default=False,
                         help="Use system PowerShell instead of bundled pwsh")

    # terminal (Nekomiya: bad here)
    sp_term = sub.add_parser("terminal", help="Launch bundled Windows Terminal with COCA profile")
    sp_term.add_argument("--inherit-env", action="store_true", default=False,
                         help="Pass --inherit-env to exec (inherit user/system environment)")
    sp_term.add_argument("--no-venv", action="store_true", default=False,
                         help="Pass --no-venv to exec (skip venv creation/activation)")
    sp_term.add_argument("--system-shell", action="store_true", default=False,
                         help="Pass --system-shell to exec (use system PowerShell)")
    sp_term.add_argument("--venv-dir", type=str, default=None, metavar="PATH",
                         help="Pass --venv-dir to exec")
    sp_term.add_argument("--shell", choices=["powershell", "cmd", "bash"], default=None,
                         help="Pass --shell to exec")
    sp_term.add_argument("--working-dir", type=str, default=None, metavar="DIR",
                         help="Start terminal in DIR instead of the default directory")

    # context-menu
    sp_ctx = sub.add_parser("context-menu", help="Register/unregister Explorer right-click menu")
    sp_ctx_sub = sp_ctx.add_subparsers(dest="ctx_action")
    sp_ctx_sub.add_parser("install", help="Add 'Open COCA Terminal here' to right-click menu")
    sp_ctx_sub.add_parser("uninstall", help="Remove 'Open COCA Terminal here' from right-click menu")

    args = parser.parse_args()

    from scripts.rich_utils import set_verbose
    set_verbose(args.verbose)

    info = load_toolchain(TOOLCHAIN_ROOT)
    resolve_paths(info)

    cmd = args.command
    # Default to "env" when no subcommand given (backward compat with piping)
    if cmd is None or cmd == "env":
        from scripts.emit import emit_powershell, emit_cmd, emit_bash
        shell = getattr(args, "shell", None) or detect_shell()
        emitters = {"powershell": emit_powershell, "cmd": emit_cmd, "bash": emit_bash}
        print(emitters[shell](info))
    elif cmd == "info":
        from scripts.info import cmd_info
        cmd_info(info)
    elif cmd == "check":
        from scripts.check import cmd_check
        sys.exit(cmd_check(info, filt=getattr(args, "filter", None)))
    elif cmd == "test":
        from scripts.test_cmd import cmd_test
        sys.exit(cmd_test(info, filt=getattr(args, "filter", None)))
    elif cmd == "update-manifest":
        from scripts.manifest import cmd_update_manifest
        cmd_update_manifest(info)
    elif cmd == "doctor":
        from scripts.doctor import cmd_doctor
        sys.exit(cmd_doctor(info))
    elif cmd == "exec":
        from scripts.exec_shell import cmd_exec
        shell = getattr(args, "shell", None) or detect_shell()
        from pathlib import Path as _Path
        venv_base = _Path(args.venv_dir) if getattr(args, "venv_dir", None) else None
        cmd_exec(info, shell, use_venv=not getattr(args, "no_venv", False),
                 venv_base=venv_base, inherit_env=getattr(args, "inherit_env", False),
                 system_shell=getattr(args, "system_shell", False))
    elif cmd == "terminal":
        from scripts.terminal import cmd_terminal
        exec_args: list[str] = []
        if getattr(args, "inherit_env", False):
            exec_args.append("--inherit-env")
        if getattr(args, "no_venv", False):
            exec_args.append("--no-venv")
        if getattr(args, "system_shell", False):
            exec_args.append("--system-shell")
        if getattr(args, "venv_dir", None):
            exec_args += ["--venv-dir", args.venv_dir]
        if getattr(args, "shell", None):
            exec_args += ["--shell", args.shell]
        cmd_terminal(info, exec_args=exec_args or None,
                     working_dir=getattr(args, "working_dir", None))
    elif cmd == "context-menu":
        ctx_action = getattr(args, "ctx_action", None)
        if ctx_action == "install":
            from scripts.context_menu import cmd_context_menu_install
            sys.exit(cmd_context_menu_install(info))
        elif ctx_action == "uninstall":
            from scripts.context_menu import cmd_context_menu_uninstall
            sys.exit(cmd_context_menu_uninstall(info))
        else:
            parser.parse_args(["context-menu", "--help"])


if __name__ == "__main__":
    main()
