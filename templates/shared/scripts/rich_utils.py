"""Shared rich console factory + global verbose flag."""
from __future__ import annotations

_verbose: bool = False


def set_verbose(v: bool) -> None:
    global _verbose
    _verbose = v


def is_verbose() -> bool:
    return _verbose


def get_console():
    from rich.console import Console
    return Console(stderr=True, highlight=False)


def vprint(*args: object, **kwargs: object) -> None:
    """Print to stderr only when --verbose is active. Uses rich markup."""
    if _verbose:
        get_console().print(*args, **kwargs)
