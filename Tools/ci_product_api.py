#!/usr/bin/env python3
"""Check one compiled product with the unchanged public API semantic normalizer.

The selected path is usable only after hosted qualification has compared its
serialized-module extraction with the existing full-package API command.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

PRODUCTS = {"InnoDISwiftUI", "InnoDITesting"}
_spec = importlib.util.spec_from_file_location("product_api_gate", Path(__file__).with_name("check-public-api.py"))
gate = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gate)


def graph_digest(graph):
    return hashlib.sha256(json.dumps(graph, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def selected_graph(contract, product):
    if product not in PRODUCTS or contract.get("schemaVersion") != gate.SCHEMA_VERSION:
        raise ValueError("unsupported product or API contract schema")
    graphs = contract.get("graphs")
    if not isinstance(graphs, list):
        raise ValueError("missing public API graphs")
    names = [graph.get("module") for graph in graphs]
    if len(names) != len(set(names)) or set(names) != set(gate.PUBLIC_PRODUCT_MODULES):
        raise ValueError("full API contract must contain each original public product exactly once")
    selected = next(graph for graph in graphs if graph["module"] == product)
    if selected.get("file") != product + ".symbols.json" or not selected.get("symbols") or not isinstance(selected.get("relationships"), list):
        raise ValueError("empty or invalid selected API graph")
    return selected


def compiled_context(scratch, product):
    """Use the actual target triple, SDK, and module output recorded by SwiftPM."""
    if product not in PRODUCTS:
        raise ValueError("unreviewed public API product")
    scratch = Path(scratch).resolve()
    contexts = set()
    for path in scratch.rglob("description.json"):
        if "checkouts" in path.relative_to(scratch).parts:
            continue
        description = json.loads(path.read_text())
        commands = description.get("swiftCommands")
        if not isinstance(commands, dict):
            raise ValueError("unrecognized SwiftPM compiler context")
        for command in commands.values():
            if command.get("moduleName") != product:
                continue
            arguments = command.get("otherArguments")
            if not isinstance(arguments, list) or any(not isinstance(value, str) for value in arguments):
                raise ValueError("missing actual Swift compiler arguments")
            def option(name):
                values = {arguments[index + 1] for index, value in enumerate(arguments[:-1]) if value == name}
                if len(values) != 1:
                    raise ValueError("missing or ambiguous compiler " + name)
                return values.pop()
            module = Path(command["moduleOutputPath"]).resolve()
            if not module.is_relative_to(scratch) or module.name != product + ".swiftmodule" or not module.exists():
                raise ValueError("selected compiled module is missing or outside scratch")
            if module.parent.name != "Modules":
                raise ValueError("unreviewed SwiftPM module output layout")
            contexts.add((str(module.parent.parent), option("-target"), option("-sdk")))
    if len(contexts) != 1:
        raise ValueError("expected exactly one compiled selected-product context")
    binary, target, sdk = contexts.pop()
    if "-apple-macosx" not in target or not Path(sdk).is_absolute():
        raise ValueError("selected API extraction requires its actual macOS compiler context")
    return {"module_directory": binary, "target": target, "sdk": sdk}


def extract(root, product, scratch, evidence_dir=None, run=subprocess.run, check_output=subprocess.check_output):
    context = compiled_context(scratch, product)
    binary = Path(context["module_directory"])
    package = Path(root).resolve() / "Tools/CIProductTests" / product
    described_binary = Path(check_output([
        "xcrun", "swift", "build", "--package-path", str(package),
        "--scratch-path", str(Path(scratch).resolve()), "--force-resolved-versions", "--show-bin-path"
    ], text=True).strip()).resolve()
    if described_binary != binary:
        raise ValueError("consumer SwiftPM binary path differs from compiled module context")
    with tempfile.TemporaryDirectory(prefix="innodi-product-api-") as temporary:
        output = Path(temporary)
        command = ["xcrun", "swift-symbolgraph-extract", "-module-name", product,
                   "-I", str(binary), "-I", str(binary / "Modules"),
                   "-target", context["target"], "-sdk", context["sdk"],
                   "-minimum-access-level", "public", "-skip-synthesized-members",
                   "-skip-inherited-docs", "-output-dir", str(output)]
        run(command, cwd=Path(root).resolve(), check=True)
        raw = {}
        for path in gate.product_graph_paths(output, product):
            raw[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
            if evidence_dir is not None:
                Path(evidence_dir).mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, Path(evidence_dir) / path.name)
        # Includes cross-module extension graphs and compiler-interface alias
        # checks, retaining isolation/defaults/accessors/generic/Sendable rules.
        graph = gate.normalize_product_graph(output, product, binary)
        return graph, {"schema": "selected-api-v1", "product": product,
                       "target": context["target"], "normalized_sha256": graph_digest(graph),
                       "raw_graph_sha256": raw}


def verify(root, product, scratch, full_current=None, evidence_dir=None, run=subprocess.run,
           check_output=subprocess.check_output):
    root = Path(root).resolve()
    baseline = selected_graph(json.loads((root / "Tools/public-api-baseline.json").read_text()), product)
    graph, evidence = extract(root, product, scratch, evidence_dir, run, check_output)
    if evidence_dir is not None:
        (Path(evidence_dir) / "normalized-current.json").write_text(gate.encoded({"schemaVersion": gate.SCHEMA_VERSION, "graphs": [graph]}))
    if graph != baseline:
        gate.summarize_difference({"graphs": [baseline]}, {"graphs": [graph]})
        raise ValueError("selected compiled public API differs from baseline")
    evidence["baseline_match"] = True
    if full_current is not None:
        full_graph = selected_graph(json.loads(Path(full_current).read_text()), product)
        if graph != full_graph:
            gate.summarize_difference({"graphs": [full_graph]}, {"graphs": [graph]})
            raise ValueError("selected extraction differs from full-package public API")
        evidence["full_current_match"] = True
    return evidence


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--product", choices=sorted(PRODUCTS), required=True)
    parser.add_argument("--scratch", type=Path, required=True)
    parser.add_argument("--full-api-contract", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise ValueError("API receipt already exists; stale evidence cannot be reused")
    result = verify(args.root, args.product, args.scratch, args.full_api_contract,
                    args.output.parent / (args.product + "-api-evidence"))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
