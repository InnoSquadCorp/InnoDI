#!/usr/bin/env python3
"""Actual compiler/consumer contracts for isolation, setters, and mutation."""
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


class PublicAPISemanticsTests(unittest.TestCase):
    def test_real_compiler_breaks_change_the_complete_contract(self):
        actor = "@globalActor public actor CustomActor { public static let shared = CustomActor() }\n"
        cases = [
            ("global", "public func resolve() {}", "@MainActor public func resolve() {}",
             "nonisolated func use() { resolve() }", "main actor-isolated"),
            ("custom", actor + "public func resolve() {}", actor + "@CustomActor public func resolve() {}",
             "nonisolated func use() { resolve() }", "actor"),
            ("inherited", "public class Owner { public func read() {} }",
             "@MainActor public class Owner { public func read() {} }",
             "nonisolated func use(_ owner: Owner) { owner.read() }", "main actor-isolated"),
            ("nonisolated", "@MainActor public class Owner { public nonisolated func read() {} }",
             "@MainActor public class Owner { public func read() {} }",
             "nonisolated func use(_ owner: Owner) { owner.read() }", "main actor-isolated"),
        ]
        for name, after_property in [
            ("let", "public let value: Int = 1"),
            ("private-set", "public private(set) var value: Int = 1"),
            ("computed", "public var value: Int { 1 }"),
        ]:
            cases.append((name, "public struct Box { public var value: Int = 1 }",
                          "public struct Box { " + after_property + " }",
                          "func use(_ box: inout Box) { box.value = 2 }", "cannot assign"))
        cases.extend([
            ("mutating-method", "public struct Box { public func read() -> Int { 1 } }",
             "public struct Box { public mutating func read() -> Int { 1 } }",
             "func use(_ box: Box) -> Int { box.read() }", "mutating member"),
            ("mutating-getter", "public struct Box { public var value: Int { get { 1 } } }",
             "public struct Box { public var value: Int { mutating get { 1 } } }",
             "func use(_ box: Box) -> Int { box.value }", "mutating getter"),
            ("nonmutating-setter", "public struct Box { public var value: Int { get { 1 } nonmutating set {} } }",
             "public struct Box { public var value: Int { get { 1 } set {} } }",
             "func use(_ box: Box) { box.value = 2 }", "cannot assign"),
            ("mutating-subscript-getter", "public struct Box { public subscript(i: Int) -> Int { get { i } } }",
             "public struct Box { public subscript(i: Int) -> Int { mutating get { i } } }",
             "func use(_ box: Box) -> Int { box[0] }", "mutating getter"),
            ("nonmutating-subscript-setter", "public struct Box { public subscript(i: Int) -> Int { get { i } nonmutating set {} } }",
             "public struct Box { public subscript(i: Int) -> Int { get { i } set {} } }",
             "func use(_ box: Box) { box[0] = 2 }", "cannot assign"),
            ("computed-setter", "public struct Box { public var value: Int { get { 1 } set {} } }",
             "public struct Box { public var value: Int { 1 } }",
             "func use(_ box: inout Box) { box.value = 2 }", "cannot assign"),
            ("subscript-setter", "public struct Box { public subscript(i: Int) -> Int { get { i } set {} } }",
             "public struct Box { public subscript(i: Int) -> Int { i } }",
             "func use(_ box: inout Box) { box[0] = 2 }", "cannot assign"),
        ])
        for name, before, after, consumer, diagnostic in cases:
            with self.subTest(name=name), tempfile.TemporaryDirectory(prefix="innodi-api-semantics-") as directory:
                root = Path(directory)
                client = root / "consumer.swift"
                client.write_text("import APIProbe\n" + consumer)
                contracts = []
                for variant, source_text in [("before", before), ("after", after)]:
                    folder = root / variant
                    source = folder / "Sources" / "APIProbe" / "API.swift"
                    source.parent.mkdir(parents=True)
                    source.write_text(source_text)
                    compilation = subprocess.run([
                        "swiftc", "-swift-version", "6", "-strict-concurrency=complete", "-warnings-as-errors",
                        "-emit-module", "-module-name", "APIProbe", "-emit-module-path", str(folder / "APIProbe.swiftmodule"),
                        "-emit-symbol-graph", "-emit-symbol-graph-dir", str(folder), str(source)
                    ], capture_output=True, text=True)
                    self.assertEqual(compilation.returncode, 0, compilation.stderr)
                    contracts.append(GATE.normalize_product_graph(folder, "APIProbe"))
                    client_result = subprocess.run([
                        "swiftc", "-swift-version", "6", "-strict-concurrency=complete", "-warnings-as-errors",
                        "-typecheck", "-I", str(folder), str(client)
                    ], capture_output=True, text=True)
                    self.assertEqual(client_result.returncode == 0, variant == "before", client_result.stderr)
                    if variant == "after":
                        self.assertIn(diagnostic, client_result.stderr)
                    graph = json.loads((folder / "APIProbe.symbols.json").read_text())
                    for symbol in graph["symbols"]:
                        if not GATE.is_product_declaration(symbol, "APIProbe"):
                            continue
                        formatted = copy.deepcopy(symbol)
                        for fragment in formatted["declarationFragments"]:
                            if fragment["kind"] == "text":
                                fragment["spelling"] = fragment["spelling"].replace(" ", "\n\t")
                        self.assertEqual(GATE.normalize_symbol(symbol), GATE.normalize_symbol(formatted))
                        for index, fragment in enumerate(symbol["declarationFragments"]):
                            if fragment["kind"] == "attribute" and "preciseIdentifier" in fragment:
                                malformed = copy.deepcopy(symbol)
                                del malformed["declarationFragments"][index]["preciseIdentifier"]
                                with self.assertRaises(ValueError):
                                    GATE.normalize_symbol(malformed)
                self.assertNotEqual(contracts[0], contracts[1], name)


if __name__ == "__main__":
    unittest.main()
