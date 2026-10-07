import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location("selected_api", Path(__file__).resolve().parents[1] / "ci_product_api.py")
api = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(api)


class SelectedProductAPITests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.product = "InnoDISwiftUI"
        self.scratch = self.root / "scratch"
        self.binary = self.scratch / "arm64-apple-macosx" / "debug"
        (self.binary / "Modules").mkdir(parents=True)
        self.module = self.binary / "Modules" / (self.product + ".swiftmodule")
        self.module.write_bytes(b"fixture module")
        self.description = self.binary / "description.json"
        self.description.write_text(json.dumps({"swiftCommands": {"compile": {
            "moduleName": self.product, "moduleOutputPath": str(self.module),
            "otherArguments": ["-target", "arm64-apple-macosx14.0", "-sdk", "/Applications/Xcode.app/SDK/MacOSX.sdk"]
        }}}))
        self.contract = {"schemaVersion": api.gate.SCHEMA_VERSION, "graphs": [
            {"module": product, "file": product + ".symbols.json", "symbols": [{
                "identifier": {"precise": "s:fixture"},
                "declarationContract": {"isolationModifiers": ["@MainActor"]}
            }], "relationships": []} for product in api.gate.PUBLIC_PRODUCT_MODULES
        ]}
        self.graph = api.selected_graph(self.contract, self.product)
        (self.root / "Tools").mkdir()
        (self.root / "Tools/public-api-baseline.json").write_text(json.dumps(self.contract))
        self.full = self.root / "current-api.json"
        self.full.write_text(json.dumps(self.contract))

    def test_actual_compiler_triple_and_sdk_used(self):
        context = api.compiled_context(self.scratch, self.product)
        self.assertEqual(context["module_directory"], str(self.binary))
        self.assertEqual(context["target"], "arm64-apple-macosx14.0")
        self.assertEqual(context["sdk"], "/Applications/Xcode.app/SDK/MacOSX.sdk")

    def test_missing_ambiguous_or_foreign_module_context_rejected(self):
        original = json.loads(self.description.read_text())
        for mutate in (
            lambda value: value["swiftCommands"]["compile"].update(otherArguments=[]),
            lambda value: value["swiftCommands"]["compile"].update(moduleOutputPath=str(self.root / "foreign.swiftmodule")),
            lambda value: value["swiftCommands"]["compile"]["otherArguments"].extend(["-target", "x86_64-apple-macosx14.0"]),
        ):
            value = copy.deepcopy(original)
            mutate(value)
            self.description.write_text(json.dumps(value))
            with self.assertRaises(ValueError):
                api.compiled_context(self.scratch, self.product)

    def test_full_contract_inventory_and_schema_required(self):
        for modify in (
            lambda value: value.update(schemaVersion=0),
            lambda value: value["graphs"].pop(),
            lambda value: value["graphs"].append(value["graphs"][0]),
        ):
            value = copy.deepcopy(self.contract)
            modify(value)
            with self.assertRaises(ValueError):
                api.selected_graph(value, self.product)

    def test_extraction_uses_existing_normalizer_and_keeps_extension_graphs(self):
        calls = []
        def run(command, **kwargs):
            calls.append(command)
            output = Path(command[command.index("-output-dir") + 1])
            for name in (self.product + ".symbols.json", self.product + "@SwiftUI.symbols.json"):
                (output / name).write_text('{"fixture": true}')
        evidence_dir = self.root / "evidence"
        bin_calls = []
        def output(command, **kwargs):
            bin_calls.append(command)
            return str(self.binary)
        with patch.object(api.gate, "normalize_product_graph", return_value=self.graph) as normalize:
            graph, evidence = api.extract(self.root, self.product, self.scratch, evidence_dir, run, output)
        self.assertEqual(graph, self.graph)
        self.assertEqual(normalize.call_args.args[1:], (self.product, self.binary))
        self.assertIn("-skip-synthesized-members", calls[0])
        self.assertIn("-skip-inherited-docs", calls[0])
        self.assertNotIn("dump-symbol-graph", calls[0])
        self.assertEqual(len(evidence["raw_graph_sha256"]), 2)
        self.assertTrue((evidence_dir / (self.product + "@SwiftUI.symbols.json")).exists())
        self.assertIn(str(self.root / "Tools/CIProductTests" / self.product), bin_calls[0])
        self.assertEqual(bin_calls[0][-1], "--show-bin-path")

    def test_extractor_failure_never_yields_api_evidence(self):
        def fail(command, **kwargs):
            raise subprocess.CalledProcessError(1, command)
        with self.assertRaises(subprocess.CalledProcessError):
            api.extract(self.root, self.product, self.scratch, run=fail,
                        check_output=lambda *a, **k: str(self.binary))

    def test_wrong_package_binary_directory_is_rejected_before_extraction(self):
        with patch.object(api.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "consumer SwiftPM binary path"):
                api.extract(self.root, self.product, self.scratch, run=run,
                            check_output=lambda *a, **k: str(self.root / ".build/debug"))
            run.assert_not_called()

    def test_qualification_requires_baseline_and_full_emitter_equivalence(self):
        evidence = {"schema": "selected-api-v1", "product": self.product}
        with patch.object(api, "extract", return_value=(self.graph, evidence)):
            proof = api.verify(self.root, self.product, self.scratch, self.full)
        self.assertTrue(proof["baseline_match"])
        self.assertTrue(proof["full_current_match"])
        changed = copy.deepcopy(self.graph)
        changed["symbols"][0]["declarationContract"]["isolationModifiers"] = []
        with patch.object(api, "extract", return_value=(changed, {})), \
             patch.object(api.gate, "summarize_difference"):
            with self.assertRaisesRegex(ValueError, "baseline"):
                api.verify(self.root, self.product, self.scratch, self.full)
        altered_full = copy.deepcopy(self.contract)
        api.selected_graph(altered_full, self.product)["relationships"] = [{"kind": "changed"}]
        self.full.write_text(json.dumps(altered_full))
        with patch.object(api, "extract", return_value=(self.graph, {})), \
             patch.object(api.gate, "summarize_difference"):
            with self.assertRaisesRegex(ValueError, "full-package"):
                api.verify(self.root, self.product, self.scratch, self.full)


if __name__ == "__main__":
    unittest.main()
