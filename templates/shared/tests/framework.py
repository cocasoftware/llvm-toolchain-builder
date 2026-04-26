"""Test framework: data model for test cases, results, and phases."""
from __future__ import annotations

import time
from dataclasses import dataclass, field
from enum import Enum


class TestStatus(Enum):
    PASS = "pass"
    FAIL = "fail"
    SKIP = "skip"
    ERROR = "error"


@dataclass
class TestResult:
    test_id: str
    phase: str
    status: TestStatus
    message: str = ""
    duration_ms: float = 0.0
    detail: str = ""


@dataclass
class TestCase:
    """A single test case with an id, phase, and callable."""
    test_id: str
    phase: str
    description: str
    fn: object  # Callable[[ToolchainInfo, Path], TestResult]


@dataclass
class TestSuite:
    """Collection of test cases registered by phase."""
    cases: list[TestCase] = field(default_factory=list)

    def add(self, test_id: str, phase: str, description: str, fn: object) -> None:
        self.cases.append(TestCase(test_id=test_id, phase=phase, description=description, fn=fn))

    def filter(self, filt: str | None) -> list[TestCase]:
        if not filt:
            return list(self.cases)
        parts = filt.lower().split(".")
        phase_filter = parts[0]
        name_filter = parts[1] if len(parts) > 1 else None
        result = []
        for tc in self.cases:
            if tc.phase.lower() != phase_filter:
                continue
            if name_filter and name_filter not in tc.test_id.lower():
                continue
            result.append(tc)
        return result


class Timer:
    """Context manager for timing test execution."""
    def __init__(self) -> None:
        self.elapsed_ms: float = 0.0
        self._start: float = 0.0

    def __enter__(self) -> Timer:
        self._start = time.perf_counter()
        return self

    def __exit__(self, *args: object) -> None:
        self.elapsed_ms = (time.perf_counter() - self._start) * 1000.0
