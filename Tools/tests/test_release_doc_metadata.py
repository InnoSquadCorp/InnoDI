"""Execute the production DocC release checks without requiring a Swift compiler."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
START = "# BEGIN current API documentation release checks"
END = "# END current API documentation release checks"


class ReleaseDocMetadataTests(unittest.TestCase):
    def setUp(self):
        source = (ROOT / "Tools/validate-release-candidate.sh").read_text()
        self.assertEqual(source.count(START), 1)
        self.assertEqual(source.count(END), 1)
        self.block = source.split(START, 1)[1].split(END, 1)[0]
        self.temp = tempfile.TemporaryDirectory(prefix="innodi-release-docs-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.catalog = self.root / "Sources/InnoDI/InnoDI.docc"
        for locale in ("", "ko.lproj"):
            directory = self.catalog / locale
            directory.mkdir(parents=True, exist_ok=True)
            for name in ("Overview", "OwnedContainers", "DIContainer", "Provide"):
                text = "This API was introduced in 7.0.\n"
                if name == "Overview":
                    text = ("The latest stable release is 7.0.1.\n" if not locale
                            else "최신 안정 릴리스는 7.0.1입니다.\n")
                (directory / (name + ".md")).write_text(text)

    def run_gate(self):
        return subprocess.run(
            ["bash", "-c", 'set -euo pipefail\nfail() { echo "$*" >&2; exit 1; }\n' + self.block],
            env=dict(os.environ, ROOT_DIR=str(self.root), VERSION="7.0.1", MAJOR_MINOR_VERSION="7.0"),
            text=True, capture_output=True, timeout=5,
        )

    def test_current_api_docs_pass(self):
        result = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_candidate_text_is_rejected_in_each_current_article_and_locale(self):
        for locale in ("", "ko.lproj"):
            for name in ("Overview", "OwnedContainers", "DIContainer", "Provide"):
                with self.subTest(locale=locale, article=name):
                    path = self.catalog / locale / (name + ".md")
                    original = path.read_text()
                    stale = ("These APIs are in the unreleased 7.0 candidate.\nQualification remains pending.\n"
                             if not locale else "이 API는 미출시 7.0 후보입니다.\n검증이 남아 있습니다.\n")
                    path.write_text(original + "\n" + stale)
                    result = self.run_gate()
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(name + ".md still describes 7.0", result.stderr)
                    path.write_text(original)

    def test_stale_stable_version_is_rejected_in_each_overview(self):
        for locale in ("", "ko.lproj"):
            with self.subTest(locale=locale):
                path = self.catalog / locale / "Overview.md"
                original = path.read_text()
                path.write_text(original.replace("7.0.1", "6.0.0"))
                result = self.run_gate()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Overview must identify 7.0.1", result.stderr)
                path.write_text(original)

    def test_missing_current_article_is_rejected(self):
        (self.catalog / "ko.lproj/Provide.md").unlink()
        result = self.run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing current API documentation", result.stderr)

    def test_historical_notes_and_frozen_translations_do_not_gate_current_release(self):
        (self.catalog / "ja.lproj").mkdir()
        (self.catalog / "ja.lproj/Overview.md").write_text("7.0 candidate\n")
        history = self.root / "docs/plans"
        history.mkdir(parents=True)
        (history / "old.md").write_text("unreleased 7.0 candidate\n")
        self.assertEqual(self.run_gate().returncode, 0)


if __name__ == "__main__":
    unittest.main()
