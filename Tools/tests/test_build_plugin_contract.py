"""Bounded controls for explicit overrides versus effective process inheritance."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "build_plugin_contract", ROOT / "Tools/validate-build-plugin-contract.py"
)
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


class BuildPluginEnvironmentTests(unittest.TestCase):
    def metadata(self, root, format, environment, *, copies=1):
        description = "Validate InnoDI DAG for SwiftProbe"
        if format == "native":
            command = (
                '  "probe-command":\n    tool: shell\n'
                f"    description: {json.dumps(description)}\n"
            )
            if environment:
                command += "    env:\n" + "".join(
                    f"      {json.dumps(key)}: {json.dumps(value)}\n"
                    for key, value in environment.items()
                )
            probe.write(root, ".build/debug.yaml", "commands:\n" + command * copies)
        else:
            task = {"executionDescription": description,
                    "environment": list(environment.items())}
            probe.write(root, ".build/manifest.pif", json.dumps([
                {"contents": {"customTasks": [task] * copies}}
            ]))

    def test_metadata_reads_only_fixture_keys_and_requires_one_command(self):
        for format in ("native", "pif"):
            with self.subTest(format=format), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.metadata(root, format, {**probe.CONTROLS, "OTHER_FIXTURE_KEY": "private"})
                observed = probe.explicit_command_environment(root, "SwiftProbe")
                self.assertEqual(observed["environment"], probe.CONTROLS)
                self.assertNotIn("private", json.dumps(observed))
                for copies in (0, 2):
                    self.metadata(root, format, probe.CONTROLS, copies=copies)
                    with self.assertRaisesRegex(RuntimeError, "Expected one SwiftProbe command"):
                        probe.explicit_command_environment(root, "SwiftProbe")

    def test_empty_explicit_map_is_distinct_from_missing_metadata(self):
        for format in ("native", "pif"):
            with self.subTest(format=format), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                with self.assertRaisesRegex(RuntimeError, "No supported SwiftPM command metadata"):
                    probe.explicit_command_environment(root, "SwiftProbe")
                self.metadata(root, format, {})
                self.assertEqual(probe.explicit_command_environment(root, "SwiftProbe")["environment"], {})

    def observation(self, explicit, effective):
        return {"explicitCommandEnvironment": {"environment": explicit},
                "effectiveEnvironment": effective}

    def test_inherited_marker_does_not_violate_control_or_unset_contract(self):
        marker = {"INNODI_PLUGIN_UNRELATED": "probe-unrelated-value"}
        for controls in (probe.CONTROLS, {}):
            for inherited in ({}, marker):
                with self.subTest(controls=bool(controls), inherited=bool(inherited)):
                    observed = self.observation(controls, {**controls, **inherited})
                    self.assertEqual(probe.environment_failures("probe", observed, controls), [])

    def test_explicit_unrelated_marker_is_rejected_with_both_metadata_formats(self):
        explicit = {**probe.CONTROLS, "INNODI_PLUGIN_UNRELATED": "probe-unrelated-value"}
        for format in ("native", "pif"):
            with self.subTest(format=format), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.metadata(root, format, explicit)
                observed = {"explicitCommandEnvironment": probe.explicit_command_environment(root, "SwiftProbe"),
                            "effectiveEnvironment": explicit}
                failures = probe.environment_failures("probe", observed, probe.CONTROLS)
                self.assertEqual(len(failures), 1)
                self.assertIn("explicit command overrides", failures[0])

    def test_inheritance_cannot_hide_a_missing_explicit_override(self):
        for key in probe.CONTROLS:
            with self.subTest(key=key):
                explicit = {k: v for k, v in probe.CONTROLS.items() if k != key}
                observed = self.observation(explicit, probe.CONTROLS)
                self.assertEqual(len(probe.environment_failures("probe", observed, probe.CONTROLS)), 1)

    def test_changed_or_unset_controls_reject_stale_explicit_and_effective_values(self):
        changed = {**probe.CONTROLS, "INNODI_LOCK_TIMEOUT": "19.5",
                   "INNODI_ALLOW_UNSAFE_LOCK": "yes"}
        for expected in (changed, {}):
            for explicit, effective in ((probe.CONTROLS, expected), (expected, probe.CONTROLS)):
                with self.subTest(expected=expected, explicit=explicit):
                    observed = self.observation(explicit, effective)
                    self.assertEqual(len(probe.environment_failures("probe", observed, expected)), 1)


if __name__ == "__main__":
    unittest.main()
