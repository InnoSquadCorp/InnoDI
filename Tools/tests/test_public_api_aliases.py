"""Compile real alias mutations and consumers, not synthetic USR assumptions."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("gate", Path(__file__).resolve().parents[1] / "check-public-api.py")
GATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GATE)


class PublicAPIAliasTests(unittest.TestCase):
    def test_current_product_aliases_match_the_baseline(self):
        root = Path(__file__).resolve().parents[2]
        baseline = json.loads((root / "Tools/public-api-baseline.json").read_text())
        expected = {s["identifier"]["precise"]: s for g in baseline["graphs"] for s in g["symbols"]
                    if s["kind"]["identifier"] == "swift.typealias"}
        actual = {}
        # Compile the actual self-contained runtime files, including nested
        # generic/actor/function aliases, on every compiler running this gate.
        for module, filenames in [
            ("InnoDI", ["DIAsyncScope.swift", "DICollections.swift"]),
            ("InnoDISwiftUI", ["DIContainerHost.swift"]),
        ]:
            with tempfile.TemporaryDirectory(prefix="innodi-product-alias-") as directory:
                folder = Path(directory)
                result = subprocess.run([
                    "swiftc", "-swift-version", "6", "-strict-concurrency=complete", "-warnings-as-errors",
                    "-parse-as-library", "-emit-module", "-module-name", module,
                    "-emit-module-path", str(folder / (module + ".swiftmodule")),
                    "-emit-symbol-graph", "-emit-symbol-graph-dir", str(folder),
                    *[str(root / "Sources" / module / name) for name in filenames],
                ], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                graph = GATE.normalize_product_graph(folder, module)
                actual.update({s["identifier"]["precise"]: s for s in graph["symbols"]
                               if s["kind"]["identifier"] == "swift.typealias"})
        self.assertEqual(len(actual), 10)
        self.assertEqual(actual, expected)

    def test_real_alias_contracts_and_equivalent_controls(self):
        cases = [
            ("return", "() -> Int", "() -> String", "let p: Provider = { 42 }", True),
            ("sendable", "() -> Int", "@Sendable () -> Int",
             "final class Box { var n = 1 }; func use(_ b: Box) -> Provider { { b.n } }", True),
            ("actor", "() -> Int", "@MainActor () -> Int",
             "nonisolated func use(_ p: Provider) -> Int { p() }", True),
            ("async", "() -> Int", "() async -> Int",
             "func use(_ p: Provider) -> Int { p() }", True),
            ("throws", "() -> Int", "() throws -> Int",
             "func use(_ p: Provider) -> Int { p() }", True),
            ("optional", "Int?", "Int", "let p: Provider = nil", True),
            ("generic", "[Int]", "[String]", "let p: Provider = [42]", True),
            ("qualified-control", "() -> Int", "() -> Swift.Int", "let p: Provider = { 42 }", False),
            ("format-control", "@Sendable () async throws -> Int", "@Sendable ( ) async throws -> Swift.Int",
             "let p: Provider = { 42 }", False),
        ]
        for name, before, after, consumer, breaking in cases:
            with self.subTest(name=name), tempfile.TemporaryDirectory(prefix="innodi-api-alias-") as directory:
                root = Path(directory)
                client = root / "Client.swift"
                client.write_text("import APIProbe\n" + consumer)
                contracts = []
                for variant, rhs in [("before", before), ("after", after)]:
                    folder = root / variant
                    source = folder / "Sources/APIProbe/API.swift"
                    source.parent.mkdir(parents=True)
                    source.write_text("public typealias Provider = " + rhs)
                    result = subprocess.run([
                        "swiftc", "-swift-version", "6", "-strict-concurrency=complete", "-warnings-as-errors",
                        "-emit-module", "-module-name", "APIProbe", "-emit-module-path", str(folder / "APIProbe.swiftmodule"),
                        "-emit-symbol-graph", "-emit-symbol-graph-dir", str(folder), str(source),
                    ], capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    contracts.append(GATE.normalize_product_graph(folder, "APIProbe"))
                    result = subprocess.run([
                        "swiftc", "-swift-version", "6", "-strict-concurrency=complete", "-warnings-as-errors",
                        "-typecheck", "-I", str(folder), str(client),
                    ], capture_output=True, text=True)
                    self.assertEqual(result.returncode == 0, variant == "before" or not breaking, result.stderr)
                    graph = json.loads((folder / "APIProbe.symbols.json").read_text())
                    alias = next(s for s in graph["symbols"] if s["kind"]["identifier"] == "swift.typealias")
                    formatted = copy.deepcopy(alias)
                    for fragment in formatted["declarationFragments"]:
                        if fragment["kind"] == "text":
                            fragment["spelling"] = fragment["spelling"].replace(" ", "\n\t")
                    self.assertEqual(GATE.normalize_symbol(alias), GATE.normalize_symbol(formatted))
                self.assertEqual(contracts[0] != contracts[1], breaking, name)

    def test_incomplete_alias_fragments_fail_closed(self):
        alias = {
            "kind": {"identifier": "swift.typealias"},
            "identifier": {"precise": "s:8APIProbe8Providera", "interfaceLanguage": "swift"},
            "declarationFragments": [
                {"kind": "keyword", "spelling": "typealias"},
                {"kind": "identifier", "spelling": "Provider"},
                {"kind": "text", "spelling": " = "},
                {"kind": "typeIdentifier", "spelling": "Int", "preciseIdentifier": "s:Si"},
            ],
        }
        for mutation in ("missing-rhs", "missing-assignment", "missing-type-identity", "missing-actor-identity"):
            with self.subTest(mutation=mutation):
                broken = copy.deepcopy(alias)
                fragments = broken["declarationFragments"]
                if mutation == "missing-rhs":
                    fragments.pop()
                elif mutation == "missing-assignment":
                    fragments.pop(2)
                elif mutation == "missing-type-identity":
                    del fragments[-1]["preciseIdentifier"]
                else:
                    fragments[3:3] = [{"kind": "attribute", "spelling": "@"},
                                      {"kind": "attribute", "spelling": "MainActor"},
                                      {"kind": "text", "spelling": " () -> "}]
                with self.assertRaises(ValueError):
                    GATE.normalize_symbol(broken)


if __name__ == "__main__":
    unittest.main()
