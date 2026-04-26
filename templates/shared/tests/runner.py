"""Test runner: discovers, filters, executes, and reports test results."""
from __future__ import annotations

import shutil
import tempfile
import time
from pathlib import Path

from .framework import TestSuite, TestResult, TestStatus, Timer
from scripts.rich_utils import is_verbose, vprint


def build_suite() -> TestSuite:
    """Register all test phases."""
    suite = TestSuite()
    from . import test_tools, test_sysroots, test_compile, test_cross_compile, test_sanitizers, test_cmake
    test_tools.register(suite)
    test_sysroots.register(suite)
    test_compile.register(suite)
    test_cross_compile.register(suite)
    test_sanitizers.register(suite)
    test_cmake.register(suite)
    return suite


def run_tests(info, filt: str | None = None) -> list[TestResult]:
    """Run filtered tests and return results."""
    suite = build_suite()
    cases = suite.filter(filt)
    results: list[TestResult] = []
    verbose = is_verbose()

    # Create a shared temp dir for all tests
    tmp_base = Path(tempfile.mkdtemp(prefix="coca_test_"))
    vprint(f"  [dim]temp dir:[/] {tmp_base}")
    vprint(f"  [dim]running {len(cases)} tests...[/]\n")
    try:
        for i, tc in enumerate(cases, 1):
            # Each test gets its own subdir
            test_tmp = tmp_base / tc.test_id.replace(".", "_")
            test_tmp.mkdir(parents=True, exist_ok=True)
            if verbose:
                vprint(f"  [dim][{i}/{len(cases)}][/] [cyan]{tc.test_id}[/] — {tc.description}")
            try:
                with Timer() as t:
                    result = tc.fn(info, test_tmp)
                if result.duration_ms == 0.0:
                    result.duration_ms = t.elapsed_ms
                results.append(result)
                if verbose:
                    icon = {TestStatus.PASS: "[green]✓[/]", TestStatus.FAIL: "[red]✗[/]",
                            TestStatus.SKIP: "[yellow]○[/]", TestStatus.ERROR: "[red]![/]"
                            }.get(result.status, "?")
                    vprint(f"         {icon} {result.message[:120]}")
                    if result.status in (TestStatus.FAIL, TestStatus.ERROR) and result.detail:
                        for line in result.detail.strip().splitlines()[:20]:
                            vprint(f"         [dim]│ {line}[/dim]")
            except Exception as e:
                results.append(TestResult(tc.test_id, tc.phase, TestStatus.ERROR,
                                          message=str(e)[:300]))
                if verbose:
                    vprint(f"         [red]! EXCEPTION: {e!s:.200}[/]")
    finally:
        # Cleanup
        if not verbose:
            shutil.rmtree(tmp_base, ignore_errors=True)
        else:
            vprint(f"\n  [dim]keeping temp dir for inspection:[/] {tmp_base}")

    return results


def print_results(results: list[TestResult]) -> int:
    """Print results using rich and return exit code."""
    from rich.table import Table
    from rich.console import Console
    console = Console(stderr=True, highlight=False)

    status_icons = {
        TestStatus.PASS: "[bold green]✓[/]",
        TestStatus.FAIL: "[bold red]✗[/]",
        TestStatus.SKIP: "[bold yellow]○[/]",
        TestStatus.ERROR: "[bold red]![/]",
    }

    # Group by phase
    phases: dict[str, list[TestResult]] = {}
    for r in results:
        phases.setdefault(r.phase, []).append(r)

    total_pass = total_fail = total_skip = total_error = 0
    total_time = 0.0

    for phase, phase_results in phases.items():
        console.print()
        table = Table(title=f"Phase: {phase}", title_style="bold cyan",
                      border_style="cyan", padding=(0, 1), show_lines=False)
        table.add_column("", width=3, justify="center")
        table.add_column("Test", style="dim", no_wrap=True, max_width=45)
        table.add_column("Result")
        table.add_column("Time", justify="right", style="dim", width=8)

        for r in phase_results:
            icon = status_icons.get(r.status, "?")
            time_str = f"{r.duration_ms:.0f}ms" if r.duration_ms > 0 else ""
            msg = r.message[:80] if r.message else ""
            # For FAIL/ERROR, show detail on next conceptual line (in message)
            if r.status in (TestStatus.FAIL, TestStatus.ERROR) and r.detail:
                msg += f"\n[dim]{r.detail[:200]}[/dim]"
            table.add_row(icon, r.test_id, msg, time_str)
            total_time += r.duration_ms
            if r.status == TestStatus.PASS:
                total_pass += 1
            elif r.status == TestStatus.FAIL:
                total_fail += 1
            elif r.status == TestStatus.SKIP:
                total_skip += 1
            elif r.status == TestStatus.ERROR:
                total_error += 1

        console.print(table)

    total = total_pass + total_fail + total_skip + total_error
    console.print()
    parts = [f"[green]{total_pass} passed[/]"]
    if total_fail:
        parts.append(f"[red]{total_fail} failed[/]")
    if total_skip:
        parts.append(f"[yellow]{total_skip} skipped[/]")
    if total_error:
        parts.append(f"[red]{total_error} errors[/]")
    summary = ", ".join(parts)
    console.print(f"  {summary} / {total} tests in {total_time / 1000:.1f}s\n")

    return 1 if (total_fail + total_error) > 0 else 0
