"""--exec: Apply environment, optionally create/activate venv, launch interactive shell."""
from __future__ import annotations

import functools
import os
import shutil
import subprocess
from pathlib import Path

from .model import ToolchainInfo
from .rich_utils import get_console

# Minimal set of OS variables preserved in sandbox mode (Windows + POSIX).
# Everything else is stripped to guarantee a reproducible, portable environment.
_SANDBOX_KEEP_VARS_NT = frozenset({
    "SYSTEMROOT", "SYSTEMDRIVE", "WINDIR", "COMSPEC",
    "TEMP", "TMP", "USERPROFILE", "HOMEDRIVE", "HOMEPATH",
    "USERNAME",
    "NUMBER_OF_PROCESSORS", "PROCESSOR_ARCHITECTURE", "OS",
    "PATHEXT", "APPDATA", "LOCALAPPDATA", "PROGRAMDATA",
    "PROGRAMFILES", "PROGRAMFILES(X86)", "COMMONPROGRAMFILES",
})
_SANDBOX_KEEP_VARS_POSIX = frozenset({
    "HOME", "USER", "LOGNAME", "SHELL", "TERM", "LANG",
    "XDG_RUNTIME_DIR", "DISPLAY", "WAYLAND_DISPLAY",
    "TMPDIR", "SSH_AUTH_SOCK", "COLORTERM",
})


def _build_sandbox_env() -> dict[str, str]:
    """Return a minimal OS-level environment dict, discarding user/system pollution."""
    keep = _SANDBOX_KEEP_VARS_NT if os.name == "nt" else _SANDBOX_KEEP_VARS_POSIX
    env: dict[str, str] = {}
    for k in keep:
        v = os.environ.get(k)
        if v is not None:
            env[k] = v
    # Seed PATH with essential OS directories (chcp, cmd.exe, powershell, basic utils).
    # Toolchain paths will be prepended later by apply_env().
    if os.name == "nt":
        sys_root = env.get("SYSTEMROOT", r"C:\Windows")
        env["PATH"] = ";".join(filter(None, [
            f"{sys_root}\\System32",
            f"{sys_root}",
            f"{sys_root}\\System32\\Wbem",
        ]))
    else:
        env["PATH"] = "/usr/local/bin:/usr/bin:/bin"
    return env


def _force_utf8_env(env: dict[str, str]) -> None:
    """Inject UTF-8 locale variables into *env* for portable encoding."""
    if os.name != "nt":
        env.setdefault("LANG", "C.UTF-8")
        env.setdefault("LC_ALL", "C.UTF-8")
    # Python-level: force UTF-8 mode in child processes
    env["PYTHONUTF8"] = "1"
    env["PYTHONIOENCODING"] = "utf-8"


def apply_env(info: ToolchainInfo, env: dict[str, str] | None = None) -> dict[str, str]:
    """Apply toolchain paths into *env* (or os.environ if None). Returns the env dict."""
    if env is None:
        env = dict(os.environ)
    for k, v in info.paths.items():
        env[k] = v
    if info.path_adds:
        sep = ";" if os.name == "nt" else ":"
        env["PATH"] = sep.join(info.path_adds) + sep + env.get("PATH", "")
    if "COCA_CONAN_PYTHONPATH" in info.paths:
        sep = ";" if os.name == "nt" else ":"
        env["PYTHONPATH"] = (info.paths["COCA_CONAN_PYTHONPATH"]
                             + sep + env.get("PYTHONPATH", ""))
    return env


def _bundled_python_exe(python_dir: Path) -> Path:
    return python_dir / ("python.exe" if os.name == "nt" else "python3")


@functools.cache
def _bundled_python_ver(python_dir: Path) -> tuple[int, int]:
    """Query the bundled Python's major.minor version (not the host Python's)."""
    py_exe = _bundled_python_exe(python_dir)
    r = subprocess.run(
        [str(py_exe), "-c", "import sys; print(sys.version_info.major, sys.version_info.minor)"],
        capture_output=True, text=True, timeout=10,
    )
    if r.returncode != 0:
        raise SystemExit(f"[error] Cannot query bundled Python version:\n{r.stderr}")
    major, minor = r.stdout.strip().split()
    return int(major), int(minor)


def _create_venv(venv_dir: Path, python_dir: Path) -> None:
    """Create a venv using the bundled Python's stdlib venv module."""
    py_exe = _bundled_python_exe(python_dir)
    result = subprocess.run(
        [str(py_exe), "-m", "venv", str(venv_dir)],
        capture_output=True, text=True, timeout=120,
    )
    if result.returncode != 0:
        raise SystemExit(f"[error] Failed to create venv:\n{result.stderr}")


def _install_coca_whl(venv_dir: Path, tc_root: Path, console: "rich.console.Console") -> None:
    """Install coca-tools whl from tools/coca/ into the venv for the `coca` entry_point."""
    coca_dir = tc_root / "tools" / "coca"
    whls = sorted(coca_dir.glob("coca_tools-*.whl"))
    if not whls:
        return
    whl = whls[-1]
    venv_pip = venv_dir / ("Scripts" if os.name == "nt" else "bin") / ("pip.exe" if os.name == "nt" else "pip")
    if not venv_pip.exists():
        py_exe = venv_dir / ("Scripts" if os.name == "nt" else "bin") / ("python.exe" if os.name == "nt" else "python3")
        cmd = [str(py_exe), "-m", "pip", "install", "--no-deps", "--no-warn-script-location", str(whl)]
    else:
        cmd = [str(venv_pip), "install", "--no-deps", "--no-warn-script-location", str(whl)]
    console.print(f"  [dim]Installing {whl.name} into venv …[/]")
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if result.returncode != 0:
        console.print(f"  [bold yellow]⚠[/] Failed to install coca-tools whl: {result.stderr.strip()}")
    else:
        console.print(f"  [dim]coca-tools installed[/]")


def _get_fingerprint(info: ToolchainInfo) -> str:
    """Return short toolchain fingerprint (first 8 hex chars) for venv tagging."""
    fp = info.manifest_json.get("_fingerprint", "") or \
         info.manifest_json.get("checksums", {}).get("_fingerprint", "")
    return fp[:8] if fp else "unknown"


def _cleanup_stale_venvs(base_path: Path, current_tag: str, console: "rich.console.Console") -> None:
    """Remove .venv-<tag> directories whose tag doesn't match *current_tag*."""
    try:
        entries = list(base_path.iterdir())
    except (PermissionError, OSError):
        return
    for d in entries:
        if d.is_dir() and d.name.startswith(".venv-") and d.name != f".venv-{current_tag}":
            console.print(f"  [dim]Removing stale venv:[/] {d.name}")
            shutil.rmtree(d, ignore_errors=True)


def _ensure_venv(info: ToolchainInfo, base_path: Path | None = None) -> Path:
    """Create a venv from the bundled Python if it doesn't already exist. Returns venv root.

    The venv directory is named `.venv-<fingerprint[:8]>` so that different
    toolchain versions get isolated environments. Stale venvs from previous
    toolchain versions are automatically cleaned up.

    Args:
        base_path: Directory in which the venv is created. Defaults to cwd.
                   Must NOT be inside the toolchain tree.
    """
    if base_path is None:
        base_path = Path.cwd()
    base_path = base_path.resolve()
    tc_root = info.root.resolve()
    if base_path.is_relative_to(tc_root):
        raise SystemExit(
            f"[error] Refusing to create venv inside toolchain directory.\n"
            f"  toolchain root: {tc_root}\n"
            f"  requested base: {base_path}\n"
            f"  Use --venv-dir to specify a path outside the toolchain."
        )
    fp_tag = _get_fingerprint(info)
    venv_dir = base_path / f".venv-{fp_tag}"
    console = get_console()
    python_dir = info.root / "tools" / "python"
    created = False
    if not (venv_dir / "pyvenv.cfg").exists():
        # Clean up venvs from previous toolchain versions before creating new one
        _cleanup_stale_venvs(base_path, fp_tag, console)
        console.print(f"  [dim]Creating venv at[/] {venv_dir} [dim](toolchain {fp_tag})[/] …")
        _create_venv(venv_dir, python_dir)
        _install_coca_whl(venv_dir, info.root, console)
        created = True
    else:
        console.print(f"  [dim]Reusing venv:[/] {venv_dir} [dim](toolchain {fp_tag})[/]")

    # Inject a .pth file so the venv inherits bundled site-packages (rich, coca_tools, etc.)
    major, minor = _bundled_python_ver(python_dir)
    if os.name == "nt":
        site_pkgs = venv_dir / "Lib" / "site-packages"
    else:
        py_ver = f"python{major}.{minor}"
        site_pkgs = venv_dir / "lib" / py_ver / "site-packages"
    site_pkgs.mkdir(parents=True, exist_ok=True)

    pth_file = site_pkgs / "coca_bundled.pth"
    bundled_sp = python_dir / ("Lib" if os.name == "nt" else f"lib/{py_ver}") / "site-packages"
    if bundled_sp.is_dir():
        pth_content = str(bundled_sp.resolve())
        if not pth_file.exists() or pth_file.read_text(encoding="utf-8").strip() != pth_content:
            pth_file.write_text(pth_content + "\n", encoding="utf-8")

    if created:
        console.print(f"  [bold green]✓[/] venv ready: {venv_dir}")
    return venv_dir


def _activate_venv_env(venv_dir: Path, env: dict[str, str]) -> dict[str, str]:
    """Inject venv activation into *env*. Returns the same dict."""
    env["VIRTUAL_ENV"] = str(venv_dir)
    env.pop("PYTHONHOME", None)
    if os.name == "nt":
        venv_bin = str(venv_dir / "Scripts")
    else:
        venv_bin = str(venv_dir / "bin")
    sep = ";" if os.name == "nt" else ":"
    env["PATH"] = venv_bin + sep + env.get("PATH", "")
    return env


def cmd_exec(
    info: ToolchainInfo, shell: str, *,
    use_venv: bool = True, venv_base: Path | None = None,
    inherit_env: bool = False,
    system_shell: bool = False,
) -> None:
    # 1. Build base environment
    if inherit_env:
        env = dict(os.environ)
    else:
        env = _build_sandbox_env()
    # 2. Force UTF-8 encoding
    _force_utf8_env(env)
    # 3. Apply toolchain paths
    env = apply_env(info, env)
    # 4. Optionally create + activate venv
    if use_venv:
        # _ensure_venv works on os.environ internally for creation; pass env for activation
        venv_dir = _ensure_venv(info, venv_base)
        env = _activate_venv_env(venv_dir, env)
    root = env.get("COCA_TOOLCHAIN", str(info.root))
    sandbox_note = "" if inherit_env else " sandbox"
    venv_note = " venv" if use_venv else ""
    tag = (sandbox_note + venv_note).strip()
    tag_str = f" ({tag})" if tag else ""
    if shell == "powershell":
        # chcp + OutputEncoding ensures Unicode glyphs render correctly
        init_parts = [
            "chcp 65001 > $null",
            "[console]::OutputEncoding = [System.Text.Encoding]::UTF8",
            "$OutputEncoding = [System.Text.Encoding]::UTF8",
            f'Write-Host -ForegroundColor Green "[ready] COCA Toolchain{tag_str}: {root}"',
            # Register tab completion (Out-String needed for multi-line script)
            "try { coca completion powershell | Out-String | Invoke-Expression } catch {}",
            # Show toolchain info
            "coca toolchain info 2>$null",
        ]
        init_cmd = "; ".join(init_parts)
        if system_shell:
            pwsh = "powershell"
        else:
            # Prefer bundled pwsh over legacy system powershell
            pwsh = shutil.which("pwsh", path=env.get("PATH", "")) or shutil.which("pwsh") or "powershell"
            if pwsh != "powershell":
                console = get_console()
                console.print(f"  [dim]Using bundled pwsh:[/] {pwsh}")
                console.print(f"  [dim]  (pass --system-shell to use system PowerShell instead)[/]")
        pwsh_args = [pwsh, "-NoLogo"]
        if not inherit_env:
            pwsh_args.append("-NoProfile")
        pwsh_args += ["-NoExit", "-Command", init_cmd]
        subprocess.run(pwsh_args, env=env)
    elif shell == "cmd":
        init_cmd = f'chcp 65001 > nul && echo [ready] COCA Toolchain{tag_str}: {root}'
        subprocess.run(["cmd", "/K", init_cmd], env=env)
    else:
        init_parts = [
            f'echo "[ready] COCA Toolchain{tag_str}: {root}"',
            'eval "$(coca completion bash 2>/dev/null)" 2>/dev/null || true',
            "coca toolchain info 2>/dev/null || true",
        ]
        init_script = " && ".join(init_parts)
        subprocess.run(
            [env.get("SHELL", "/bin/bash"), "--init-file",
             "/dev/stdin", "-i"],
            input=init_script.encode(), env=env,
        )
