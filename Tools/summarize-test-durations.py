#!/usr/bin/env python3
"""Summarize Swift Testing suite durations from a `swift test` console log.

CI appends the Markdown table to `$GITHUB_STEP_SUMMARY` so every run records
which suites dominate wall-clock time. The script only reads the log and never
fails a job because of its content: a log without suite results produces a
short notice instead of a table.

Usage:
  Tools/summarize-test-durations.py <log> [--title TEXT] [--top N]
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

ANSI_ESCAPE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
SUITE_RESULT = re.compile(
    r'Suite "(?P<name>.+?)" (?P<status>passed|failed) after (?P<seconds>[0-9]+(?:\.[0-9]+)?) seconds'
)
RUN_RESULT = re.compile(
    r"Test run with (?P<tests>[0-9]+) tests? in (?P<suites>[0-9]+) suites? "
    r"(?P<status>passed|failed) after (?P<seconds>[0-9]+(?:\.[0-9]+)?) seconds"
)


@dataclass(frozen=True)
class SuiteResult:
    name: str
    status: str
    seconds: float


@dataclass(frozen=True)
class RunResult:
    tests: int
    suites: int
    status: str
    seconds: float


def parse_log(text: str) -> tuple[list[SuiteResult], list[RunResult]]:
    suites: list[SuiteResult] = []
    runs: list[RunResult] = []
    for raw_line in text.splitlines():
        line = ANSI_ESCAPE.sub("", raw_line)
        suite = SUITE_RESULT.search(line)
        if suite:
            suites.append(
                SuiteResult(
                    name=suite.group("name"),
                    status=suite.group("status"),
                    seconds=float(suite.group("seconds")),
                )
            )
            continue
        run = RUN_RESULT.search(line)
        if run:
            runs.append(
                RunResult(
                    tests=int(run.group("tests")),
                    suites=int(run.group("suites")),
                    status=run.group("status"),
                    seconds=float(run.group("seconds")),
                )
            )
    return suites, runs


def escape_cell(value: str) -> str:
    return value.replace("|", "\\|")


def render_markdown(
    suites: list[SuiteResult],
    runs: list[RunResult],
    *,
    title: str,
    top: int,
) -> str:
    lines = [f"### {title}", ""]
    if not suites and not runs:
        lines.append("No Swift Testing results were found in the test log.")
        return "\n".join(lines) + "\n"

    for run in runs:
        tests = "test" if run.tests == 1 else "tests"
        suites_label = "suite" if run.suites == 1 else "suites"
        lines.append(
            f"- {run.tests} {tests} in {run.suites} {suites_label} {run.status} "
            f"after {run.seconds:.1f} seconds."
        )
    if runs:
        lines.append("")

    ranked = sorted(suites, key=lambda suite: suite.seconds, reverse=True)[:top]
    if ranked:
        lines.append("| Rank | Suite | Result | Seconds |")
        lines.append("|---:|---|---|---:|")
        for rank, suite in enumerate(ranked, start=1):
            lines.append(
                f"| {rank} | {escape_cell(suite.name)} | {suite.status} | {suite.seconds:.1f} |"
            )
        lines.append("")
        lines.append(
            "Suite durations are wall-clock times and include nested suites."
        )
    return "\n".join(lines) + "\n"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("log", type=Path, help="swift test console output")
    parser.add_argument("--title", default="Slowest test suites")
    parser.add_argument("--top", type=int, default=15)
    arguments = parser.parse_args(argv)
    if arguments.top < 1:
        parser.error("--top must be positive")

    try:
        text = arguments.log.read_text(encoding="utf-8", errors="replace")
    except OSError as error:
        print(f"### {arguments.title}\n\nThe test log could not be read: {error.strerror}.")
        return 0

    suites, runs = parse_log(text)
    sys.stdout.write(
        render_markdown(suites, runs, title=arguments.title, top=arguments.top)
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
