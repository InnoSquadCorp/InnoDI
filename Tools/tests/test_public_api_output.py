"""Current-contract evidence preserves the API gate's comparison result."""
import contextlib
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock


SPEC = importlib.util.spec_from_file_location(
    "api_output_gate", Path(__file__).resolve().parents[1] / "check-public-api.py"
)
GATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GATE)


class PublicAPIOutputTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="innodi-api-output-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.baseline = self.root / "baseline.json"
        self.output = self.root / "build/current.json"
        self.current = {
            "schemaVersion": GATE.SCHEMA_VERSION,
            "graphs": [{
                "file": "InnoDI.symbols.json",
                "symbols": [{"identifier": {"precise": "s:fixture"}}],
                "relationships": [],
            }],
        }
        self.baseline.write_text(GATE.encoded(self.current), encoding="utf-8")

    def run_gate(self, output):
        arguments = ["check-public-api.py", "--baseline", str(self.baseline)]
        if output is not None:
            arguments += ["--current-output", str(output)]
        with mock.patch.object(sys, "argv", arguments), \
                mock.patch.object(GATE, "dump_symbol_graphs", return_value=self.root) as dump, \
                mock.patch.object(GATE, "current_contract", return_value=self.current) as current, \
                contextlib.redirect_stdout(io.StringIO()), \
                contextlib.redirect_stderr(io.StringIO()):
            result = GATE.main()
        return result, dump, current

    def test_output_preserves_success_and_baseline(self):
        original = self.baseline.read_bytes()
        result, dump, current = self.run_gate(self.output)
        self.assertEqual(result, 0)
        dump.assert_called_once()
        current.assert_called_once_with(self.root)
        self.assertEqual(json.loads(self.output.read_text()), self.current)
        self.assertEqual(self.baseline.read_bytes(), original)

    def test_output_preserves_mismatch_failure_and_baseline(self):
        previous = copy.deepcopy(self.current)
        previous["graphs"][0]["symbols"] = []
        self.baseline.write_text(GATE.encoded(previous), encoding="utf-8")
        original = self.baseline.read_bytes()
        result, _, _ = self.run_gate(self.output)
        self.assertEqual(result, 1)
        self.assertEqual(json.loads(self.output.read_text()), self.current)
        self.assertEqual(self.baseline.read_bytes(), original)

    def test_output_does_not_create_a_missing_baseline(self):
        self.baseline.unlink()
        result, _, _ = self.run_gate(self.output)
        self.assertEqual(result, 1)
        self.assertEqual(json.loads(self.output.read_text()), self.current)
        self.assertFalse(self.baseline.exists())

    def test_omitted_output_keeps_existing_behavior(self):
        result, _, _ = self.run_gate(None)
        self.assertEqual(result, 0)
        self.assertFalse(self.output.exists())

    def test_baseline_and_alias_outputs_are_rejected_before_compilation(self):
        symlink = self.root / "symlink.json"
        symlink.symlink_to(self.baseline)
        hardlink = self.root / "hardlink.json"
        os.link(self.baseline, hardlink)
        original = self.baseline.read_bytes()
        for output in (self.baseline, symlink, hardlink):
            with self.subTest(output=output.name):
                result, dump, current = self.run_gate(output)
                self.assertEqual(result, 2)
                dump.assert_not_called()
                current.assert_not_called()
                self.assertEqual(self.baseline.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
