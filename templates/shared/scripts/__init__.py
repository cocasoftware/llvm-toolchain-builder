"""COCA Toolchain — Setup & Diagnostics scripts package."""
from __future__ import annotations


def _generate_logo(text: str = "COCA", font: str = "slant") -> str:
    """Generate ASCII art logo via pyfiglet (pure-ASCII, portable across all codepages)."""
    try:
        import pyfiglet
        return pyfiglet.figlet_format(text, font=font).rstrip()
    except ImportError:
        return text


COCA_LOGO = _generate_logo("COCA")
