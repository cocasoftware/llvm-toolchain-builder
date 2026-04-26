"""setup.py test subcommand — delegates to tests.runner."""
from __future__ import annotations

from .model import ToolchainInfo


def cmd_test(info: ToolchainInfo, filt: str | None = None) -> int:
    from tests.runner import run_tests, print_results
    results = run_tests(info, filt=filt)
    return print_results(results)
