"""Rich-formatted --info display (stderr)."""
from __future__ import annotations

from . import COCA_LOGO
from .model import ToolchainInfo
from .rich_utils import get_console


def cmd_info(info: ToolchainInfo) -> None:
    from rich.table import Table
    from rich.panel import Panel
    from rich.text import Text
    console = get_console()

    logo = Text(COCA_LOGO.strip(), style="bold cyan")
    header = Text.assemble(
        ("  COCA ", "bold white"), ("Toolchain", "bold green"),
        (f"  v{info.version}", "bold yellow"), ("  │  ", "dim"),
        (f"LLVM {info.llvm_version}", "bold cyan"),
    )
    console.print(Panel.fit(Text.assemble(logo, "\n", header), border_style="cyan", padding=(0, 2)))

    console.print()
    et = Table(title="Environment Variables", title_style="bold yellow",
               show_header=True, border_style="yellow", padding=(0, 1))
    et.add_column("Variable", style="yellow", no_wrap=True)
    et.add_column("Value", style="dim")
    for k, v in info.paths.items():
        et.add_row(k, v)
    console.print(et)

    console.print()
    pt = Table(title="PATH Additions", title_style="bold blue",
               show_header=False, border_style="blue", padding=(0, 1))
    pt.add_column("", style="green")
    pt.add_column("Directory")
    for p in info.path_adds:
        pt.add_row("+", p)
    console.print(pt)

    profiles = info.toolchain_json.get("profiles", {})
    if profiles:
        console.print()
        pf = Table(title=f"Profiles ({len(profiles)})", title_style="bold blue",
                   show_header=True, border_style="blue", padding=(0, 1))
        pf.add_column("Profile", style="cyan", no_wrap=True)
        pf.add_column("Triple", style="dim")
        pf.add_column("Runtime", style="dim")
        pf.add_column("Linker", style="dim")
        for pname, pinfo in profiles.items():
            pf.add_row(pname, pinfo.get("target_triple", "?"),
                        pinfo.get("runtime", "?"), pinfo.get("linker", "?"))
        console.print(pf)

    sysroots_dir = info.root / "sysroots"
    if sysroots_dir.is_dir():
        entries = [d for d in sorted(sysroots_dir.iterdir()) if not d.name.startswith(".")]
        if entries:
            console.print()
            st = Table(title="Sysroots", title_style="bold blue",
                       show_header=True, border_style="blue", padding=(0, 1))
            st.add_column("Name", style="cyan")
            st.add_column("Type", style="dim")
            for d in entries:
                kind = "symlink" if d.is_symlink() else ("junction" if d.is_junction() else "dir")
                st.add_row(d.name, kind)
            console.print(st)

    components = info.manifest_json.get("components", {})
    if components:
        console.print()
        ct = Table(title="Components", title_style="bold green",
                   show_header=True, border_style="green", padding=(0, 1))
        ct.add_column("Component", style="green")
        ct.add_column("Version", style="bold")
        ct.add_column("Note", style="dim")
        for cn, cd in components.items():
            ct.add_row(cn, cd.get("version", "?"), cd.get("note", cd.get("feature", "")))
        console.print(ct)

    console.print(f"\n  [dim]Root:[/] {info.root}\n")
