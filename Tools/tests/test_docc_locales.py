"""Rendered locale gates reject missing, stale, and incorrectly hosted catalogs."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

_spec = importlib.util.spec_from_file_location('docc_locales', Path(__file__).resolve().parents[1] / 'check-docc-locales.py')
_checker = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_checker)


class DocCLocaleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for locale in ('en', 'ko'):
            root = self.root / ('ko' if locale == 'ko' else '')
            root.mkdir(parents=True, exist_ok=True)
            base = '/InnoDI/ko/' if locale == 'ko' else '/InnoDI/'
            (root / 'index.html').write_text(f'<script>var baseUrl = "{base}"</script>')
            for article in _checker.ARTICLES:
                path = root / 'data/documentation' / ('innodi/' + article + '.json' if article else 'innodi.json')
                path.parent.mkdir(parents=True, exist_ok=True)
                text = '한국어 API 문서입니다.' if locale == 'ko' else 'English API documentation.'
                if not article:
                    text = '최신 안정 릴리스는 7.0.2입니다.' if locale == 'ko' else 'The latest stable release is 7.0.2.'
                path.write_text(json.dumps({'primaryContentSections': [{'content': [{'inlineContent': [{'type': 'text', 'text': text}]}]}]}))

    def test_complete_bilingual_catalog(self):
        self.assertEqual(_checker.failures(self.root, '7.0.2'), [])

    def test_missing_korean_article(self):
        (self.root / 'ko/data/documentation/innodi/provide.json').unlink()
        self.assertTrue(any('ko/provide' in error for error in _checker.failures(self.root, '7.0.2')))

    def test_english_catalog_cannot_substitute_for_korean(self):
        path = self.root / 'ko/data/documentation/innodi/ownedcontainers.json'
        path.write_text((self.root / 'data/documentation/innodi/ownedcontainers.json').read_text())
        self.assertTrue(any('missing Korean' in error for error in _checker.failures(self.root, '7.0.2')))

    def test_wrong_stable_version(self):
        self.assertTrue(any('expected stable release 7.0.3' in error for error in _checker.failures(self.root, '7.0.3')))

    def test_korean_hosting_root_must_be_separate(self):
        (self.root / 'ko/index.html').write_text('<script>var baseUrl = "/InnoDI/"</script>')
        self.assertTrue(any('expected hosting base /InnoDI/ko' in error for error in _checker.failures(self.root, '7.0.2')))

    def test_invalid_json_fails_closed(self):
        (self.root / 'ko/data/documentation/innodi/dicontainer.json').write_text('{')
        self.assertTrue(any('cannot read rendered article' in error for error in _checker.failures(self.root, '7.0.2')))


if __name__ == '__main__':
    unittest.main()
