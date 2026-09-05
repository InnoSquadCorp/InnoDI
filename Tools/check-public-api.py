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


SCHEMA_VERSION = 3
PUBLIC_PRODUCT_MODULES = ("InnoDI", "InnoDISwiftUI", "InnoDITesting")
VOLATILE_SYMBOL_KEYS = {
    "declarationFragments",
    "declaration",
    "docComment",
    "functionSignature",
    "location",
    "names",
}
VOLATILE_RELATIONSHIP_KEYS = {"sourceOrigin", "targetFallback"}
IMPLICIT_GENERIC_CONSTRAINTS = {"s:s8CopyableP", "s:s9EscapableP"}
TOOLCHAIN_SYNTHESIZED_RELATIONSHIP_TARGETS = {"s:s16SendableMetatypeP"}


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
    if "swiftGenerics" in normalized:
        normalized["swiftGenerics"] = normalize_generic_context(
            normalized["swiftGenerics"]
        )
    if "swiftExtension" in normalized:
        normalized["swiftExtension"] = normalize_generic_context(
            normalized["swiftExtension"]
        )
    return normalized


def normalize_generic_context(context: dict[str, Any]) -> dict[str, Any]:
    normalized = dict(context)
    constraints = normalized.get("constraints")
    if isinstance(constraints, list):
        normalized["constraints"] = [
            constraint
            for constraint in constraints
            if constraint.get("rhsPrecise") not in IMPLICIT_GENERIC_CONSTRAINTS
        ]
    return normalized


def product_graph_paths(output_directory: Path, module: str) -> list[Path]:
    primary = output_directory / f"{module}.symbols.json"
    if not primary.is_file():
        raise SystemExit(f"Missing public product symbol graph: {primary.name}")
    return [primary, *sorted(output_directory.glob(f"{module}@*.symbols.json"))]


def is_product_declaration(symbol: dict[str, Any], module: str) -> bool:
    location = symbol.get("location", {}).get("uri", "")
    return f"/Sources/{module}/" in location


def normalize_relationship(relationship: dict[str, Any]) -> dict[str, Any]:
    normalized = {
        key: value
        for key, value in relationship.items()
        if key not in VOLATILE_RELATIONSHIP_KEYS
    }
    if "swiftConstraints" in normalized:
        constraints = [
            constraint
            for constraint in normalized["swiftConstraints"]
            if constraint.get("rhsPrecise") not in IMPLICIT_GENERIC_CONSTRAINTS
        ]
        if constraints:
            normalized["swiftConstraints"] = constraints
        else:
            normalized.pop("swiftConstraints")
    return normalized


def normalize_product_graph(output_directory: Path, module: str) -> dict[str, Any]:
    payloads = [
        json.loads(path.read_text(encoding="utf-8"))
        for path in product_graph_paths(output_directory, module)
    ]
    symbols_by_identifier: dict[str, dict[str, Any]] = {}
    for payload in payloads:
        symbol_payload = payload.get("symbols", [])
        if isinstance(symbol_payload, dict):
            symbol_payload = symbol_payload.values()
        for symbol in symbol_payload:
            if not is_product_declaration(symbol, module):
                continue
            normalized = normalize_symbol(symbol)
            symbols_by_identifier[normalized["identifier"]["precise"]] = normalized

    if not symbols_by_identifier:
        raise SystemExit(f"No source-authored public symbols found for {module}.")

    symbol_identifiers = set(symbols_by_identifier)
    relationships_by_identity: dict[str, dict[str, Any]] = {}
    for payload in payloads:
        for relationship in payload.get("relationships", []):
            if relationship.get("source") not in symbol_identifiers:
                continue
            if relationship.get("target") in TOOLCHAIN_SYNTHESIZED_RELATIONSHIP_TARGETS:
                continue
            normalized = normalize_relationship(relationship)
            identity = json.dumps(normalized, sort_keys=True, separators=(",", ":"))
            relationships_by_identity[identity] = normalized

    symbols = sorted(
        symbols_by_identifier.values(),
        key=lambda symbol: symbol["identifier"]["precise"],
    )
    relationships = [
        relationships_by_identity[identity]
        for identity in sorted(relationships_by_identity)
    ]
    return {
        "file": f"{module}.symbols.json",
        "module": module,
        "symbols": symbols,
        "relationships": relationships,
    }


def current_contract(output_directory: Path) -> dict[str, Any]:
    return {
        "schemaVersion": SCHEMA_VERSION,
        "graphs": [
            normalize_product_graph(output_directory, module)
            for module in PUBLIC_PRODUCT_MODULES
        ],
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
