#!/usr/bin/env python3
"""Compiler-produced graphs plus real omitted-argument consumer compilation."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("api_gate", Path(__file__).resolve().parents[1] / "check-public-api.py")
GATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GATE)

SOURCE = """
public func resolve(enabled: Bool = true) -> Bool { enabled }
public struct Box {
    public init(value: Bool = true) {}
    public subscript(index: Int = 0) -> Int { index }
    public func tuple(_ value: (left: Int, right: Int) = (1, 2), build: (Int, Int) -> Bool = { $0 == $1 }) {}
    public func generic<T>(_ value: T, list: [T] = []) where T: Equatable {}
    public func same(_ lhs: Int = 1, _ rhs: Int = 2) {}
    public func required<T: Collection>(_ value: T, other: Int) where T.Element == Int {}
}
"""


class PublicAPIDefaultTests(unittest.TestCase):
    def test_compiler_graph_and_consumer(self):
        with tempfile.TemporaryDirectory(prefix="innodi-api-contract-") as directory:
            root = Path(directory)
            consumer = root / "consumer.swift"
            consumer.write_text("import APIProbe\nlet result = resolve()\n")
            graphs = []
            for variant in ("before", "after"):
                folder = root / variant
                folder.mkdir()
                source = folder / "API.swift"
                source.write_text(SOURCE if variant == "before" else SOURCE.replace("enabled: Bool = true", "enabled: Bool"))
                result = subprocess.run([
                    "swiftc", "-swift-version", "6", "-warnings-as-errors", "-emit-module", "-module-name", "APIProbe",
                    "-emit-module-path", str(folder / "APIProbe.swiftmodule"),
                    "-emit-symbol-graph", "-emit-symbol-graph-dir", str(folder), str(source)
                ], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                graph = json.loads((folder / "APIProbe.symbols.json").read_text())
                graphs.append(graph)
                compilation = subprocess.run(["swiftc", "-typecheck", "-I", str(folder), str(consumer)],
                                             capture_output=True, text=True)
                self.assertEqual(compilation.returncode == 0, variant == "before", compilation.stderr)
                if variant == "after": self.assertIn("missing argument", compilation.stderr)

            before = {s["names"]["title"]: s for s in graphs[0]["symbols"]}
            after = {s["names"]["title"]: s for s in graphs[1]["symbols"]}
            old, new = before["resolve(enabled:)"], after["resolve(enabled:)"]
            self.assertEqual(old["identifier"], new["identifier"])
            self.assertNotEqual(GATE.normalize_symbol(old), GATE.normalize_symbol(new))
            self.assertEqual(GATE.parameter_defaults(old), [True])
            self.assertEqual(GATE.parameter_defaults(new), [False])
            # Macro symbol graphs before Swift 6.4 can omit functionSignature.
            # Use compiler-produced declaration fragments to ensure the schema
            # variation never drops or invents default-argument metadata.
            for declaration in (old, new):
                macro = copy.deepcopy(declaration)
                macro["kind"]["identifier"] = "swift.macro"
                legacy = copy.deepcopy(macro)
                del legacy["functionSignature"]
                self.assertEqual(GATE.normalize_symbol(macro), GATE.normalize_symbol(legacy))
            empty_macro = copy.deepcopy(old)
            empty_macro["kind"]["identifier"] = "swift.macro"
            empty_macro["functionSignature"]["parameters"] = []
            empty_macro["declarationFragments"] = [
                {"kind": "keyword", "spelling": "macro"},
                {"kind": "identifier", "spelling": "Probe"},
                {"kind": "text", "spelling": "()"},
            ]
            legacy_empty = copy.deepcopy(empty_macro)
            del legacy_empty["functionSignature"]
            self.assertEqual(GATE.normalize_symbol(empty_macro), GATE.normalize_symbol(legacy_empty))
            for name, expected in {
                "init(value:)": [True], "subscript(_:)": [True],
                "tuple(_:build:)": [True, True], "generic(_:list:)": [False, True],
                "same(_:_: )".replace(" ", ""): [True, True], "required(_:other:)": [False, False],
            }.items():
                self.assertEqual(GATE.parameter_defaults(before[name]), expected, name)

            formatted = copy.deepcopy(old)
            for fragment in formatted["declarationFragments"]:
                if fragment["kind"] == "text": fragment["spelling"] = fragment["spelling"].replace(" ", "\n\t")
            self.assertEqual(GATE.normalize_symbol(old), GATE.normalize_symbol(formatted))
            missing = copy.deepcopy(old)
            del missing["declarationFragments"]
            with self.assertRaises(ValueError): GATE.normalize_symbol(missing)


if __name__ == "__main__":
    unittest.main()
