#!/usr/bin/env python3
"""Validate the compiler-emitted public API against a checked-in baseline."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1
PRIMARY_GRAPH_NAMES = {
    "InnoDI.symbols.json",
    "InnoDISwiftUI.symbols.json",
}
EXTENSION_GRAPH_PREFIX = "InnoDISwiftUI@"
VOLATILE_SYMBOL_KEYS = {"docComment", "location", "names"}


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare InnoDI product symbol graphs with the public API baseline."
    )
    parser.add_argument(
        "--update",
        action="store_true",
        help="Replace the baseline after an intentional, reviewed public API change.",
    )
    parser.add_argument(
        "--baseline",
        type=Path,
        help="Override the default Tools/public-api-baseline.json path.",
    )
    return parser.parse_args()


def dump_symbol_graphs(package_root: Path) -> Path:
    command = [
        "swift",
        "package",
        "dump-symbol-graph",
        "--minimum-access-level",
        "public",
        "--skip-synthesized-members",
        "--skip-inherited-docs",
    ]
    result = subprocess.run(
        command,
        cwd=package_root,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    sys.stdout.write(result.stdout)
    if result.returncode != 0:
        raise SystemExit(result.returncode)

    matches = re.findall(r"^Files written to (.+)$", result.stdout, re.MULTILINE)
    if not matches:
        raise SystemExit("Unable to locate the SwiftPM symbol-graph output directory.")

    output_directory = Path(matches[-1]).resolve()
    if not output_directory.is_dir():
        raise SystemExit(f"Symbol-graph output directory does not exist: {output_directory}")
    return output_directory


def normalize_symbol(symbol: dict[str, Any]) -> dict[str, Any]:
    normalized = {
        key: value
        for key, value in symbol.items()
        if key not in VOLATILE_SYMBOL_KEYS
    }
    normalized["kind"] = {"identifier": symbol["kind"]["identifier"]}
    normalized["identifier"] = {
        "precise": symbol["identifier"]["precise"],
        "interfaceLanguage": symbol["identifier"]["interfaceLanguage"],
    }
    return normalized


def graph_paths(output_directory: Path) -> list[Path]:
    paths = [output_directory / name for name in sorted(PRIMARY_GRAPH_NAMES)]
    paths.extend(sorted(output_directory.glob(f"{EXTENSION_GRAPH_PREFIX}*.symbols.json")))

    missing = [path.name for path in paths[: len(PRIMARY_GRAPH_NAMES)] if not path.is_file()]
    if missing:
        raise SystemExit(f"Missing public product symbol graph(s): {', '.join(missing)}")
    return paths


def normalize_graph(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    symbol_payload = payload.get("symbols", [])
    if isinstance(symbol_payload, dict):
        symbol_payload = symbol_payload.values()
    symbols = [normalize_symbol(symbol) for symbol in symbol_payload]
    symbols.sort(key=lambda symbol: symbol["identifier"]["precise"])

    relationships = payload.get("relationships", [])
    relationships.sort(
        key=lambda relationship: json.dumps(
            relationship,
            sort_keys=True,
            separators=(",", ":"),
        )
    )
    return {
        "file": path.name,
        "module": payload["module"]["name"],
        "symbols": symbols,
        "relationships": relationships,
    }


def current_contract(output_directory: Path) -> dict[str, Any]:
    return {
        "schemaVersion": SCHEMA_VERSION,
        "graphs": [normalize_graph(path) for path in graph_paths(output_directory)],
    }


def encoded(contract: dict[str, Any]) -> str:
    return json.dumps(contract, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def summarize_difference(baseline: dict[str, Any], current: dict[str, Any]) -> None:
    baseline_graphs = {graph["file"]: graph for graph in baseline.get("graphs", [])}
    current_graphs = {graph["file"]: graph for graph in current.get("graphs", [])}

    for graph_name in sorted(baseline_graphs.keys() | current_graphs.keys()):
        old_graph = baseline_graphs.get(graph_name, {"symbols": [], "relationships": []})
        new_graph = current_graphs.get(graph_name, {"symbols": [], "relationships": []})
        old_symbols = {
            symbol["identifier"]["precise"]: symbol for symbol in old_graph["symbols"]
        }
        new_symbols = {
            symbol["identifier"]["precise"]: symbol for symbol in new_graph["symbols"]
        }

        added = sorted(new_symbols.keys() - old_symbols.keys())
        removed = sorted(old_symbols.keys() - new_symbols.keys())
        changed = sorted(
            identifier
            for identifier in old_symbols.keys() & new_symbols.keys()
            if old_symbols[identifier] != new_symbols[identifier]
        )
        if added or removed or changed:
            print(f"[{graph_name}]", file=sys.stderr)
            for label, identifiers in (
                ("added", added),
                ("removed", removed),
                ("changed", changed),
            ):
                for identifier in identifiers:
                    print(f"  {label}: {identifier}", file=sys.stderr)

        if old_graph["relationships"] != new_graph["relationships"]:
            print(f"[{graph_name}] relationships changed", file=sys.stderr)


def main() -> int:
    arguments = parse_arguments()
    package_root = Path(__file__).resolve().parent.parent
    baseline_path = (
        arguments.baseline.resolve()
        if arguments.baseline
        else package_root / "Tools" / "public-api-baseline.json"
    )

    output_directory = dump_symbol_graphs(package_root)
    current = current_contract(output_directory)

    if arguments.update:
        baseline_path.write_text(encoded(current), encoding="utf-8")
        print(f"Updated public API baseline: {baseline_path}")
        return 0

    if not baseline_path.is_file():
        print(
            f"Public API baseline is missing: {baseline_path}\n"
            "Run Tools/check-public-api.py --update after reviewing the intended API.",
            file=sys.stderr,
        )
        return 1

    baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
    if baseline == current:
        symbol_count = sum(len(graph["symbols"]) for graph in current["graphs"])
        print(
            f"Public API baseline: OK ({symbol_count} symbols across "
            f"{len(current['graphs'])} graphs)"
        )
        return 0

    print("Public API differs from Tools/public-api-baseline.json.", file=sys.stderr)
    summarize_difference(baseline, current)
    print(
        "Review the SemVer impact, then run Tools/check-public-api.py --update "
        "only when the change is intentional.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
