"""Exercise the exact shell extractor without replacing compiler validation."""
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).parents[1] / "check-docs-code-blocks.sh"


class DocumentationExtractionTests(unittest.TestCase):
    def extract(self, source):
        script = SCRIPT.read_text()
        function = script[script.index("count=0\n"):script.index("while IFS= read -r file; do")]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            snippets = root / "snippets"
            snippets.mkdir()
            document = root / "example.md"
            document.write_text(source)
            result = subprocess.run(
                ["bash", "-c", 'set -euo pipefail\nSNIPPET_DIR="$1"\n' + function
                 + '\nextract_snippets "$2"\n', "extract", str(snippets), str(document)],
                text=True, capture_output=True, timeout=10,
            )
            return result, [path.read_text() for path in sorted(snippets.glob("*.swift"))]

    def test_whole_document_preserves_shared_declarations(self):
        result, snippets = self.extract("""<!-- innodi:compile-all -->
```swift
struct Service {}
```
```bash
not swift
```
```swift
let value = Service()
```
""")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(snippets), 1)
        self.assertIn("struct Service {}\n\nlet value = Service()", snippets[0])
        self.assertNotIn("not swift", snippets[0])

    def test_individual_markers_stay_isolated(self):
        result, snippets = self.extract("""<!-- innodi:compile -->
```swift
struct Service {}
```
<!-- innodi:compile -->
```swift
struct Service {}
```
""")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(snippets), 2)
        self.assertTrue(all(source.count("struct Service") == 1 for source in snippets))

    def test_incomplete_contracts_fail(self):
        for source in [
            "<!-- innodi:compile-all -->\nNo Swift block.\n",
            "<!-- innodi:compile-all -->\n```swift\nstruct Service {}\n",
            "<!-- innodi:compile -->\n",
            "<!-- innodi:compile -->\nNot a code block.\n",
        ]:
            with self.subTest(source=source):
                result, _ = self.extract(source)
                self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
