"""Release-note extraction stays bounded on the macOS system Bash."""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Tools" / "extract-release-notes.sh"


def current_release_section(source):
    versions = re.findall(r"^Latest stable public release: `([^`]+)`[ \t]*$", source, re.M)
    if len(versions) != 1:
        raise ValueError("expected exactly one latest stable release")
    version = versions[0]
    headings = list(re.finditer(rf"^## {re.escape(version)}\n", source, re.M))
    if len(headings) != 1:
        raise ValueError("expected exactly one section for the latest stable release")
    return version, source[headings[0].end():].split("\n## ", 1)[0]


class ReleaseNotesTests(unittest.TestCase):
    def extract(self, source, version="6.0.0", *, raw=False):
        with tempfile.TemporaryDirectory(prefix="innodi-release-notes-") as directory:
            Path(directory, "RELEASING.md").write_text(source)
            return subprocess.run(
                ["/bin/bash", str(SCRIPT), version],
                cwd=directory,
                text=not raw,
                capture_output=True,
                timeout=5,
            )

    def test_large_unicode_notes_preserve_content_without_global_replacement(self):
        body = "\n### Highlights\n\n" + (
            "- Dependency graph: 5.x → 6.0; 입력과 소유권을 확인합니다.\n" * 800
        )
        result = self.extract("## 6.0.0\n" + body + "\n## 5.1.0\nOld notes.\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, body.rstrip("\n") + "\n")

    def test_current_release_section_is_extracted_exactly(self):
        source = (ROOT / "RELEASING.md").read_text()
        version, body = current_release_section(source)
        result = self.extract(source, version)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, body.rstrip("\n") + "\n")

    def test_current_release_selection_follows_promoted_metadata(self):
        for version in ("6.0.1", "7.0.0"):
            with self.subTest(version=version):
                source = (
                    f"Latest stable public release: `{version}`\n\n"
                    f"## {version}\n\n- New release.\n\n## 6.0.0\nOld release.\n"
                )
                selected, body = current_release_section(source)
                self.assertEqual(selected, version)
                result = self.extract(source, selected)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, body.rstrip("\n") + "\n")
                self.assertNotIn("Old release.", result.stdout)

    def test_current_release_selection_rejects_missing_or_ambiguous_metadata(self):
        declaration = "Latest stable public release: `6.0.0`\n"
        section = "## 6.0.0\nNotes.\n"
        for source in (section, declaration, declaration * 2 + section, declaration + section * 2):
            with self.subTest(source=source), self.assertRaises(ValueError):
                current_release_section(source)

    def test_small_notes_and_missing_or_empty_sections(self):
        result = self.extract("## 6.0.0\n\n- Ready to migrate.\n\n## 5.1.0\nOld.\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "\n- Ready to migrate.\n")
        for source in ("## 5.1.0\nOld.\n", "## 6.0.0\n", "## 6.0.0\n \t\r\n\n"):
            with self.subTest(source=source):
                result = self.extract(source)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                self.assertIn("no release notes found", result.stderr)

    def test_crlf_notes_normalize_to_lf_and_stop_at_next_section(self):
        source = "## 6.0.0\n\n- 입력 → 출력\n\n## 5.1.0\nOld.\n"
        for document in (source, source.replace("\n", "\r\n")):
            with self.subTest(crlf="\r\n" in document):
                result = self.extract(document, raw=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "\n- 입력 → 출력\n".encode())


if __name__ == "__main__":
    unittest.main()
