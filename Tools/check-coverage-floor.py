#!/usr/bin/env python3
"""Fail when package or module line coverage drops below checked-in floors."""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any


class CoverageFloorError(ValueError):
    pass


def load_object(path: Path, description: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise CoverageFloorError(
            f"cannot read {description} '{path}': {error}"
        ) from error
    if not isinstance(value, dict):
        raise CoverageFloorError(f"{description} must be a JSON object")
    return value


def finite_percent(value: Any, description: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise CoverageFloorError(f"{description} must be a number")
    result = float(value)
    if not math.isfinite(result) or not 0 <= result <= 100:
        raise CoverageFloorError(
            f"{description} must be finite and between 0 and 100"
        )
    return result


def measured_line_percent(bucket: Any, description: str) -> float:
    if not isinstance(bucket, dict):
        raise CoverageFloorError(f"{description} must be an object")
    covered = bucket.get("linesCovered")
    total = bucket.get("linesTotal")
    if (
        isinstance(covered, bool)
        or not isinstance(covered, int)
        or isinstance(total, bool)
        or not isinstance(total, int)
        or total <= 0
        or covered < 0
        or covered > total
    ):
        raise CoverageFloorError(
            f"{description} line counts must satisfy 0 <= covered <= total"
        )
    measured = round(100.0 * covered / total, 2)
    reported = finite_percent(
        bucket.get("linePercent"),
        f"{description}.linePercent",
    )
    if abs(measured - reported) > 0.001:
        raise CoverageFloorError(
            f"{description}.linePercent is {reported:.2f}, "
            f"but counts produce {measured:.2f}"
        )
    return measured


def validate(
    summary: dict[str, Any],
    floor: dict[str, Any]
) -> list[str]:
    if floor.get("schemaVersion") != 1:
        raise CoverageFloorError("coverage floor schemaVersion must equal 1")

    package_floor = finite_percent(
        floor.get("packageLinePercent"),
        "packageLinePercent",
    )
    module_floors = floor.get("modules")
    if not isinstance(module_floors, dict) or not module_floors:
        raise CoverageFloorError("coverage floors must declare modules")
    normalized_floors = {
        name: finite_percent(value, f"modules.{name}")
        for name, value in module_floors.items()
        if isinstance(name, str) and name
    }
    if len(normalized_floors) != len(module_floors):
        raise CoverageFloorError("coverage floor module names must be strings")

    modules = summary.get("modules")
    if not isinstance(modules, list):
        raise CoverageFloorError("coverage summary modules must be an array")
    modules_by_name: dict[str, dict[str, Any]] = {}
    for module in modules:
        if not isinstance(module, dict) or not isinstance(module.get("name"), str):
            raise CoverageFloorError("every coverage module must have a name")
        name = module["name"]
        if name in modules_by_name:
            raise CoverageFloorError(f"coverage summary repeats module '{name}'")
        modules_by_name[name] = module

    expected_names = set(normalized_floors)
    actual_names = set(modules_by_name)
    missing = sorted(expected_names - actual_names)
    unexpected = sorted(actual_names - expected_names)
    if missing or unexpected:
        details = []
        if missing:
            details.append("missing: " + ", ".join(missing))
        if unexpected:
            details.append("unconfigured: " + ", ".join(unexpected))
        raise CoverageFloorError(
            "coverage module set differs from checked-in floors ("
            + "; ".join(details)
            + ")"
        )

    failures: list[str] = []
    package_percent = measured_line_percent(
        summary.get("package"),
        "package",
    )
    if package_percent < package_floor:
        failures.append(
            f"package line coverage {package_percent:.2f}% is below "
            f"{package_floor:.2f}%"
        )

    for name in sorted(normalized_floors):
        measured = measured_line_percent(
            modules_by_name[name],
            f"module {name}",
        )
        required = normalized_floors[name]
        if measured < required:
            failures.append(
                f"module {name} line coverage {measured:.2f}% is below "
                f"{required:.2f}%"
            )
    return failures


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--summary",
        type=Path,
        default=root / "coverage" / "summary.json",
    )
    parser.add_argument(
        "--floor",
        type=Path,
        default=root / "Tools" / "coverage-floor.json",
    )
    arguments = parser.parse_args()

    try:
        summary = load_object(arguments.summary, "coverage summary")
        floor = load_object(arguments.floor, "coverage floor")
        failures = validate(summary, floor)
    except CoverageFloorError as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1

    if failures:
        for failure in failures:
            print(f"::error::{failure}", file=sys.stderr)
        return 1

    print(
        "Coverage floors: OK "
        f"({len(floor['modules'])} modules, "
        f"package {summary['package']['linePercent']:.2f}%)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
