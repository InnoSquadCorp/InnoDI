#!/usr/bin/env python3
"""Validate the reusable JSON emitted by measure-macro-performance.sh."""

from __future__ import annotations

import json
import math
from pathlib import Path
import statistics
import sys


def fail(message: str) -> None:
    print(f"Invalid macro performance report: {message}", file=sys.stderr)
    raise SystemExit(1)


if len(sys.argv) != 2:
    print(f"Usage: {sys.argv[0]} <report.json>", file=sys.stderr)
    raise SystemExit(2)

report_path = Path(sys.argv[1])
try:
    report = json.loads(report_path.read_text(encoding="utf-8"))
except (OSError, UnicodeError, json.JSONDecodeError) as error:
    fail(f"cannot read {report_path}: {error}")

if not isinstance(report, dict):
    fail("top-level value must be an object")

for key in ("updated_at", "swift_version", "filter"):
    if not isinstance(report.get(key), str) or not report[key].strip():
        fail(f"{key} must be a non-empty string")

if report.get("mode") not in {"in-process", "subprocess"}:
    fail("mode must be in-process or subprocess")

iterations = report.get("iterations")
if isinstance(iterations, bool) or not isinstance(iterations, int) or iterations < 1:
    fail("iterations must be a positive integer")


def finite_number(key: str, *, positive: bool) -> float:
    value = report.get(key)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        fail(f"{key} must be a number")
    number = float(value)
    if not math.isfinite(number) or (number <= 0 if positive else number < 0):
        qualifier = "positive" if positive else "non-negative"
        fail(f"{key} must be a finite {qualifier} number")
    return number


mean_ms = finite_number("mean_ms", positive=True)
min_ms = finite_number("min_ms", positive=True)
max_ms = finite_number("max_ms", positive=True)
stdev_ms = finite_number("stdev_ms", positive=False)

samples = report.get("samples_ms")
if not isinstance(samples, list) or len(samples) != iterations:
    fail("samples_ms count must match iterations")

normalized_samples: list[float] = []
for index, value in enumerate(samples):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        fail(f"samples_ms[{index}] must be a number")
    sample = float(value)
    if not math.isfinite(sample) or sample <= 0:
        fail(f"samples_ms[{index}] must be a finite positive number")
    normalized_samples.append(sample)

expected = {
    "mean_ms": statistics.fmean(normalized_samples),
    "min_ms": min(normalized_samples),
    "max_ms": max(normalized_samples),
    "stdev_ms": statistics.stdev(normalized_samples) if iterations > 1 else 0.0,
}
actual = {
    "mean_ms": mean_ms,
    "min_ms": min_ms,
    "max_ms": max_ms,
    "stdev_ms": stdev_ms,
}
for key, expected_value in expected.items():
    if not math.isclose(actual[key], expected_value, rel_tol=0.0, abs_tol=0.002):
        fail(
            f"{key} does not match samples_ms "
            f"(reported {actual[key]:.3f}, computed {expected_value:.3f})"
        )

print(f"Validated macro performance report: {report_path}")
