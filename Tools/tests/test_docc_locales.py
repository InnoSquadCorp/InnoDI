"""Rendered locale gates reject missing, stale, and incorrectly hosted catalogs."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
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
            (root / 'index.html').write_text(f'<script>var baseUrl = "{base}"</script>', encoding='utf-8')
            for article in _checker.ARTICLES:
                path = root / 'data/documentation' / ('innodi/' + article + '.json' if article else 'innodi.json')
                path.parent.mkdir(parents=True, exist_ok=True)
                text = '한국어 API 문서입니다.' if locale == 'ko' else 'English API documentation.'
                if not article:
                    text = '최신 안정 릴리스는 7.0.2입니다.' if locale == 'ko' else 'The latest stable release is 7.0.2.'
                path.write_text(json.dumps({'primaryContentSections': [{'content': [{'inlineContent': [{'type': 'text', 'text': text}]}]}]}, ensure_ascii=False), encoding='utf-8')

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

    def test_utf8_korean_catalog_under_ascii_default_encoding(self):
        environment = dict(os.environ, LC_ALL='C', PYTHONUTF8='0', PYTHONCOERCECLOCALE='0')
        result = subprocess.run(
            ['python3', str(Path(_checker.__file__)), str(self.root), '--version', '7.0.2'],
            env=environment, capture_output=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stderr.decode('utf-8', errors='replace'))

    def test_missing_korean_source_fails_before_compilation(self):
        repository = Path(__file__).resolve().parents[2]
        fixture = self.root / 'generator-fixture'
        (fixture / 'Tools/docc').mkdir(parents=True)
        shutil.copy2(repository / 'Tools/generate-docc.sh', fixture / 'Tools/generate-docc.sh')
        shutil.copy2(repository / 'Tools/docc/Package.resolved', fixture / 'Tools/docc/Package.resolved')
        shutil.copy2(repository / 'Package.swift', fixture / 'Package.swift')
        binary = fixture / 'bin'
        binary.mkdir()
        marker = fixture / 'swift-invoked'
        swift = binary / 'swift'
        swift.write_text('#!/bin/sh\n: > "$DOCCTEST_SWIFT_MARKER"\nexit 0\n', encoding='utf-8')
        swift.chmod(0o755)
        environment = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ['PATH'],
                           DOCCTEST_SWIFT_MARKER=str(marker))
        result = subprocess.run(['bash', str(fixture / 'Tools/generate-docc.sh')],
                                env=environment, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 1)
        self.assertIn('Required Korean DocC catalog is missing', result.stderr)
        self.assertFalse(marker.exists(), 'Swift should not run without the required Korean source')


if __name__ == '__main__':
    unittest.main()
