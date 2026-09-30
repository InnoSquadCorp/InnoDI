"""Protect the dependency/public metadata contract against unsafe drift."""
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("public_ops", ROOT / "Tools/check-public-operations.py")
ops = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ops)


class PublicOperationsTests(unittest.TestCase):
    def test_current_contract_and_negative_controls(self):
        ops.check()
        with tempfile.TemporaryDirectory(prefix="innodi-public-ops-") as directory:
            root = Path(directory)
            files = [".github/dependabot.yml", ".spi.yml", "Package.swift", "Tools/docc/Package.resolved",
                     "Tools/generate-docc.sh", "LICENSE", "CONTRIBUTING.md", "SECURITY.md", "RELEASING.md",
                     ".github/PULL_REQUEST_TEMPLATE.md", ".github/ISSUE_TEMPLATE/bug_report.yml",
                     ".github/ISSUE_TEMPLATE/feature_request.yml", "docs/automation-policy.md"]
            files += [path.lstrip("/") + "/Package.swift" for path in ops.SWIFT_DIRS if path != "/"]
            for path in files:
                target = root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / path, target)
            config_file = root / ".github/dependabot.yml"
            original = config_file.read_text()
            mutations = [
                lambda c: c["updates"][1]["groups"]["swift-minor-patch"]["update-types"].append("major"),
                lambda c: c["updates"][1]["groups"]["swift-minor-patch"].update(**{"exclude-patterns": ["swift-syntax"]}),
                lambda c: c["updates"][1]["groups"]["swift-minor-patch"].update(**{"dependency-type": "development"}),
                lambda c: c["updates"][1]["commit-message"].update(**{"prefix-development": "chore"}),
                lambda c: c["updates"][1]["directories"].append("/Tests/Fixtures/MigrationConsumer"),
                lambda c: c["updates"][1]["directories"].append("/**"),
                lambda c: c["updates"][1]["schedule"].update(interval="daily"),
                lambda c: c["updates"][1].update(**{"open-pull-requests-limit": 20}),
            ]
            for mutate in mutations:
                config = json.loads(original)
                mutate(config)
                config_file.write_text(json.dumps(config))
                with self.assertRaises(ValueError):
                    ops.check(root)
            config_file.write_text(original)
            manifest = root / "Package.swift"
            original_manifest = manifest.read_text()
            manifest.write_text(original_manifest.replace('exact: "603.0.2"', 'from: "603.0.2"'))
            with self.assertRaises(ValueError):
                ops.check(root)
            manifest.write_text(original_manifest.replace('exact: "603.0.2"', 'exact: "604.0.0"'))
            with self.assertRaises(ValueError):
                ops.check(root)
            manifest.write_text(original_manifest)
            generator = root / "Tools/generate-docc.sh"
            generator.write_text(generator.read_text().replace(r"603\.0\.2", r"604\.0\.0"))
            with self.assertRaises(ValueError):
                ops.check(root)
            shutil.copyfile(ROOT / "Tools/generate-docc.sh", generator)
            (root / "LICENSE").write_text("Replacement license")
            with self.assertRaises(ValueError):
                ops.check(root)

    def test_no_update_job_or_auto_merge_tracks_historical_templates(self):
        source = (ROOT / ".github/dependabot.yml").read_text()
        self.assertNotIn("Tests/", source)
        self.assertNotIn("target-branch", source)
        self.assertNotIn("ignore", source)  # Major/toolchain PRs remain visible.
        self.assertNotIn("prefix-development", source)
        for path in (ROOT / ".github/workflows").glob("*.yml"):
            self.assertNotIn("enable-auto-merge", path.read_text())
            self.assertNotIn("--auto", path.read_text())


if __name__ == "__main__":
    unittest.main()
