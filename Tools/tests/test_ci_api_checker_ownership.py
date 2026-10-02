"""Prove the compiler checker has one owner without weakening local/release runs."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
WRAPPER = 'InnoDIBuildSupportTests.PublicAPIContractTests/compilerDefaultArgumentContract'


class APICheckerOwnershipTests(unittest.TestCase):
    def test_actual_coverage_command_defaults_and_opt_in(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'Tools').mkdir()
            (root / 'bin').mkdir()
            shutil.copyfile(ROOT / 'Tools/run-coverage-gate.sh', root / 'Tools/run-coverage-gate.sh')
            # Stop immediately after recording swift test arguments. No coverage
            # producer/consumer is mocked into a false successful gate.
            swift = root / 'bin/swift'
            swift.write_text('#!/bin/bash\nif [[ "$1" == build ]]; then echo "$PWD/build"; exit 0; fi\nprintf "%s\\n" "$@" > "$PWD/arguments"\nexit 37\n')
            swift.chmod(0o755)
            env = {**os.environ, 'PATH': str(root / 'bin') + ':' + os.environ['PATH']}
            for args, skipped in [([], False), (['--api-checker-in-policy'], True)]:
                result = subprocess.run(['bash', str(root / 'Tools/run-coverage-gate.sh'), *args],
                                        env=env, cwd=root, capture_output=True)
                self.assertEqual(result.returncode, 37)
                actual = (root / 'arguments').read_text().splitlines()
                self.assertEqual(WRAPPER in actual, skipped)
                self.assertIn('--enable-code-coverage', actual)
                self.assertIn('-strict-concurrency=complete', actual)
                self.assertIn('-warnings-as-errors', actual)
            (root / 'arguments').unlink()
            result = subprocess.run(['bash', str(root / 'Tools/run-coverage-gate.sh'), '--unknown'],
                                    env=env, cwd=root, capture_output=True)
            self.assertEqual(result.returncode, 2)
            self.assertFalse((root / 'arguments').exists())

    def test_ci_and_release_each_keep_a_required_owner(self):
        ci = (ROOT / '.github/workflows/macro-tests.yml').read_text()
        release = (ROOT / '.github/workflows/release.yml').read_text()
        policy = ci.split('  policy:\n', 1)[1].split('  documentation-contracts:\n', 1)[0]
        self.assertIn('python3 -B -m unittest discover -s Tools/tests', policy)
        self.assertNotIn('continue-on-error', policy)
        aggregate = ci.split('  ci-required:\n', 1)[1].split('  append-perf-history:\n', 1)[0]
        self.assertIn('      - policy\n', aggregate)
        self.assertEqual(ci.count('--skip ' + repr(WRAPPER)), 3)  # fast, TSAN, ASAN
        self.assertEqual(ci.count('run: Tools/run-coverage-gate.sh --api-checker-in-policy'), 1)
        self.assertIn('run: Tools/run-coverage-gate.sh\n', release)
        self.assertNotIn('--api-checker-in-policy', release)
        self.assertEqual(release.count('--skip ' + repr(WRAPPER)), 2)
        minimum = ci.split('  swift-62-compatibility:\n', 1)[1].split('  xcode-27-compatibility:\n', 1)[0]
        self.assertIn("python3 -B -m unittest discover -s Tools/tests -p 'test_public_api*.py'", minimum)
        # Keep the default swift test subprocess contract and its actual compiler tests.
        wrapper = (ROOT / 'Tests/InnoDIBuildSupportTests/PublicAPIContractTests.swift').read_text()
        self.assertIn('"test_public_api*.py"', wrapper)
        self.assertTrue(list((ROOT / 'Tools/tests').glob('test_public_api*.py')))
