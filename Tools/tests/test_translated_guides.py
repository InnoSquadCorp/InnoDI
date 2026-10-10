"""Exercise concise guide drift checks without a Swift toolchain."""
import importlib.util
from pathlib import Path
import tempfile
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('guide_check', ROOT / 'Tools/check-docs-translated-guides.py')
guide_check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guide_check)


class TranslatedGuideTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ['README.md', 'CHANGELOG.md',
                     *[f'README.{locale}.md' for locale in guide_check.LOCALES]]:
            (self.root / name).write_text((ROOT / name).read_text())

        catalog = self.root / 'Sources/InnoDI/InnoDI.docc'
        catalog.mkdir(parents=True)
        for article in (ROOT / 'Sources/InnoDI/InnoDI.docc').glob('*.md'):
            (catalog / article.name).write_text(article.read_text())

    def mutate(self, old, new):
        path = self.root / 'README.ja.md'
        text = path.read_text()
        self.assertIn(old, text)
        path.write_text(text.replace(old, new, 1))
        return guide_check.failures(self.root)

    def test_current_guides_pass(self):
        self.assertEqual(guide_check.failures(self.root), [])

    def test_stale_guide_version_fails(self):
        version = re.search(r'Latest stable public release: `([^`]+)`', (self.root / 'CHANGELOG.md').read_text()).group(1)
        errors = self.mutate(f'<!-- innodi:guide version={version} -->', '<!-- innodi:guide version=0.0.0 -->')
        self.assertTrue(any('guide version=' in error for error in errors))

    def test_missing_lifecycle_section_fails(self):
        errors = self.mutate('<!-- innodi:section lifecycle -->', '')
        self.assertTrue(any('lifecycle' in error for error in errors))

    def test_duplicate_section_fails(self):
        errors = self.mutate('<!-- innodi:section history -->', '<!-- innodi:section history -->\n<!-- innodi:section history -->')
        self.assertTrue(any('duplicates' in error for error in errors))

    def test_changed_example_fails(self):
        errors = self.mutate('let live = AppContainer', 'let changed = AppContainer')
        self.assertTrue(any('canonical minimum example' in error for error in errors))

    def test_missing_article_link_fails(self):
        errors = self.mutate('Sources/InnoDI/InnoDI.docc/Composition.md', 'README.md')
        self.assertTrue(any('Composition.md' in error for error in errors))

    def test_wrong_package_url_fails(self):
        errors = self.mutate('url: "https://github.com/InnoSquadCorp/InnoDI.git"',
                             'url: "https://example.com/wrong-package.git"')
        self.assertTrue(any('package URL/current-version' in error for error in errors))

    def test_stale_pin_with_current_version_elsewhere_fails(self):
        version = re.search(r'Latest stable public release: `([^`]+)`', (self.root / 'CHANGELOG.md').read_text()).group(1)
        errors = self.mutate(f'from: "{version}"', 'from: "0.0.0"')
        self.assertTrue(any('package URL/current-version' in error for error in errors))

    def test_version_and_url_must_be_in_same_declaration(self):
        text = '''```swift
.package(url: "https://github.com/InnoSquadCorp/InnoDI.git", from: "0.0.0")
.package(url: "https://example.com/Other.git", from: "7.0.1")
```'''
        self.assertFalse(guide_check.has_current_installation(text, '7.0.1'))

    def test_missing_guide_fails(self):
        (self.root / 'README.ru.md').unlink()
        self.assertIn('README.ru.md: missing guide', guide_check.failures(self.root))


if __name__ == '__main__':
    unittest.main()
