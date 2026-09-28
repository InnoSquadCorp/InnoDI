"""Compile real alias mutations and consumers, not synthetic USR assumptions."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("gate", Path(__file__).resolve().parents[1] / "check-public-api.py")
GATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GATE)


class PublicAPIAliasTests(unittest.TestCase):
    def extraction_flags(self):
        info = json.loads(subprocess.check_output(["swiftc", "-print-target-info"], text=True))
        # Use the package's minimum macOS deployment target in both paths;
        # standalone toolchains can otherwise default above the selected SDK.
        target = info["target"]["unversionedTriple"] + "13.0"
        sdk = os.environ.get("SDKROOT") or subprocess.check_output(
            ["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
        return ["-target", target, "-sdk", sdk]

    def extracted_aliases(self, folder, module, flags):
        output = folder / "extracted"
        output.mkdir()
        extractor = shutil.which("swift-symbolgraph-extract") or subprocess.check_output(
            ["xcrun", "--find", "swift-symbolgraph-extract"], text=True).strip()
        result = subprocess.run([
            extractor, "-module-name", module, "-I", str(folder),
            "-output-dir", str(output), "-minimum-access-level", "public",
            "-skip-synthesized-members", *flags,
        ], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        graph = GATE.normalize_product_graph(output, module, folder)
        return {s["identifier"]["precise"]: s for s in graph["symbols"]
                if s["kind"]["identifier"] == "swift.typealias"}

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
                flags = self.extraction_flags()
                result = subprocess.run([
                    "swiftc", "-swift-version", "6", "-strict-concurrency=complete", "-warnings-as-errors",
                    "-parse-as-library", "-emit-module", "-module-name", module,
                    "-emit-module-path", str(folder / (module + ".swiftmodule")),
                    "-emit-symbol-graph", "-emit-symbol-graph-dir", str(folder),
                    *flags,
                    *[str(root / "Sources" / module / name) for name in filenames],
                ], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                graph = GATE.normalize_product_graph(folder, module)
                aliases = {s["identifier"]["precise"]: s for s in graph["symbols"]
                           if s["kind"]["identifier"] == "swift.typealias"}
                self.assertEqual(aliases, self.extracted_aliases(folder, module, flags))
                actual.update(aliases)
        self.assertEqual(len(actual), 10)
        self.assertEqual(actual, expected)

    def test_generic_slots_survive_serialized_extraction(self):
        with tempfile.TemporaryDirectory(prefix="innodi-generic-alias-") as directory:
            folder = Path(directory)
            source = folder / "Sources/APIProbe/API.swift"
            source.parent.mkdir(parents=True)
            source.write_text("""
                public struct Wrapper<A, B> {
                    public typealias Left = A
                    public typealias Right = B
                    public struct Nested<C> {
                        public typealias Outer = A
                        public typealias Inner = C
                        public typealias All = (A, B, C)
                    }
                }
                extension Swift.Array {
                    public typealias Resolver = @Sendable () -> Element
                }
                """)
            flags = self.extraction_flags()
            result = subprocess.run([
                "swiftc", "-swift-version", "6", "-emit-module", "-module-name", "APIProbe",
                "-emit-module-path", str(folder / "APIProbe.swiftmodule"),
                "-emit-symbol-graph", "-emit-symbol-graph-dir", str(folder), *flags, str(source),
            ], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            graph = GATE.normalize_product_graph(folder, "APIProbe")
            aliases = {s["identifier"]["precise"]: s for s in graph["symbols"]
                       if s["kind"]["identifier"] == "swift.typealias"}
            self.assertEqual(aliases, self.extracted_aliases(folder, "APIProbe", flags))
            contracts = {s["pathComponents"][-1]: s["declarationContract"]["aliasedType"]
                         for s in aliases.values()}
            self.assertEqual(contracts["Left"], ["generic:0:0"])
            self.assertEqual(contracts["Right"], ["generic:0:1"])
            self.assertEqual(contracts["Outer"], ["generic:0:0"])
            self.assertEqual(contracts["Inner"], ["generic:1:0"])
            self.assertEqual(contracts["All"], ["(", "generic:0:0", ",", "generic:0:1", ",", "generic:1:0", ")"])
            resolver = next(s for s in aliases.values() if s["pathComponents"][-1] == "Resolver")
            self.assertEqual(resolver["declarationContract"]["aliasedSendablePositions"], [0])

            raw = json.loads((folder / "extracted/APIProbe.symbols.json").read_text())
            alias = next(s for s in raw["symbols"] if s["pathComponents"][-1] == "Left")
            for mutation in ("missing-context", "unknown-type", "duplicate-name", "duplicate-slot",
                             "invalid-index", "invalid-depth", "qualified-type"):
                with self.subTest(mutation=mutation):
                    broken = copy.deepcopy(alias)
                    parameters = broken["swiftGenerics"]["parameters"]
                    if mutation == "missing-context":
                        del broken["swiftGenerics"]
                    elif mutation == "unknown-type":
                        broken["declarationFragments"][-1]["spelling"] = "Unknown"
                    elif mutation == "duplicate-name":
                        parameters[1]["name"] = parameters[0]["name"]
                    elif mutation == "duplicate-slot":
                        parameters[1]["index"] = parameters[0]["index"]
                    elif mutation == "invalid-index":
                        parameters[0]["index"] = True
                    elif mutation == "invalid-depth":
                        parameters[0]["depth"] = -1
                    else:
                        broken["declarationFragments"].insert(-1, {"kind": "text", "spelling": "Other."})
                    with self.assertRaises(ValueError):
                        GATE.normalize_symbol(broken)

            nominal = copy.deepcopy(alias)
            nominal["declarationFragments"][-1]["preciseIdentifier"] = "s:8APIProbe1AV"
            self.assertEqual(GATE.typealias_contract(nominal), ["reference:s:8APIProbe1AV"])

    def test_real_alias_contracts_and_equivalent_controls(self):
        cases = [
            ("return", "() -> Int", "() -> String", "let p: Provider = { 42 }", True),
            ("sendable", "() -> Int", "@Sendable () -> Int",
             "final class Box { var n = 1 }; func use(_ b: Box) -> Provider { { b.n } }", True),
            ("nested-sendable-parameter", "(() -> Int) -> Int", "(@Sendable () -> Int) -> Int",
             "final class Box { var n = 1 }; func use(_ b: Box, _ p: Provider) -> Int { p { b.n } }", True),
            ("nested-sendable-return", "() -> (() -> Int)", "() -> (@Sendable () -> Int)",
             "final class Box { var n = 1 }; func use(_ b: Box) -> Provider { { { b.n } } }", True),
            ("tuple-sendable-position", "(@Sendable () -> Int, () -> Int)", "(() -> Int, @Sendable () -> Int)",
             "final class Box { var n = 1 }; func use(_ b: Box) -> Provider { ({ 42 }, { b.n }) }", True),
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
            ("attribute-order-control", "@MainActor @Sendable () -> Int", "@Sendable @MainActor () -> Swift.Int",
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
                    rhs = GATE.compiler_alias_interfaces(folder, "APIProbe")[tuple(alias["pathComponents"])]
                    self.assertEqual(GATE.normalize_symbol(alias, rhs), GATE.normalize_symbol(formatted, rhs))
                self.assertEqual(contracts[0] != contracts[1], breaking, name)

    def test_compiler_interface_scopes_and_literal_shielding(self):
        interface = r'''
        import Foreign
        // public struct Fake { public typealias Wrong = @Sendable () -> Int
        /* outer /* nested } */ public struct Fake {} */
        @available(*, message: "struct Fake { typealias Wrong = Int }")
        public struct One {
          public typealias Callback = @Sendable () -> Int
          public struct Nested<T> {
            public typealias Callback = () -> T
          }
          @inlinable public func text() {
            let text = #"""
            public struct Fake { public typealias Wrong = Int }
            """#
            let interpolation = "value: \(String(describing: "}"))"
            typealias Local = Int
          }
        }
        public struct Two {
          public typealias Callback = () -> Int
        }
        extension APIProbe.One {
          public typealias Extra = (@Sendable () -> Int, () -> Int)
        }
        extension Foreign.Host {
          public typealias External = () -> Int
        }
        '''
        aliases = GATE.interface_aliases(interface, "APIProbe")
        self.assertEqual(set(aliases), {("One", "Callback"), ("One", "Nested", "Callback"),
                                        ("Two", "Callback"), ("One", "Extra"), ("Host", "External")})
        self.assertEqual(GATE.alias_sendable_positions(aliases[("One", "Callback")]), [0])
        self.assertEqual(GATE.alias_sendable_positions(aliases[("One", "Nested", "Callback")]), [])
        self.assertEqual(GATE.alias_sendable_positions(aliases[("One", "Extra")]), [1])
        with self.assertRaisesRegex(ValueError, "Ambiguous"):
            GATE.interface_aliases(interface + "\nextension One {\n public typealias Callback = () -> Int\n}\n", "APIProbe")
        for broken in ['/*', '"unterminated', 'public struct One {', 'public typealias Missing\n',
                       'public typealias Empty =\n', 'public typealias OneLine = Int }']:
            with self.subTest(broken=broken), self.assertRaises(ValueError):
                GATE.interface_aliases(broken, "APIProbe")

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
        with self.assertRaisesRegex(ValueError, "Missing compiler-interface alias"):
            GATE.normalize_symbol(alias)
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
