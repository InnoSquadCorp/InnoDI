"""Cache fingerprints are nonempty, toolchain/profile exact, and observable."""
import copy
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('ci_cache', ROOT / 'Tools/ci-cache.py')
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)


class CacheTests(unittest.TestCase):
    def inputs(self):
        return dict(manifest=(ROOT / 'Package.swift').read_text(), swift='Apple Swift version 6.3 (swiftlang-6.3.0.4.1 clang-1700.6.5.2)',
                    xcode='Xcode 26.6\nBuild version 17G42', system='26.6 / 25G42', architecture='arm64',
                    contract=(ROOT / 'Tests/InnoDIBuildSupportTests/ExternalConsumerContractTests.swift').read_text())

    def test_exact_identity_never_collides_across_builds_pins_arch_or_contract(self):
        original = self.inputs()
        first = p.fingerprint(**original)
        self.assertEqual(first, p.fingerprint(**original))
        for key, value in [('manifest', original['manifest'].replace('604.0.0', '604.0.1')),
                           ('swift', original['swift'].replace('6.3.0.4.1', '6.3.0.4.2')),
                           ('xcode', original['xcode'].replace('17G42', '17G43')),
                           ('system', '26.6 / 25G43'), ('architecture', 'x86_64'),
                           ('contract', original['contract'] + '\n// scratch contract update')]:
            changed = p.fingerprint(**{**original, key: value})
            for cache_key in ['dependency-key', 'consumer-key']:
                self.assertNotEqual(first[cache_key], changed[cache_key], (key, cache_key))
                self.assertRegex(changed[cache_key], r'-[a-f0-9]{64}$')
        self.assertNotEqual(first['dependency-key'], first['consumer-key'])

    def test_profiles_follow_compiler_and_preserve_expectation_isolation(self):
        for version, profile in [('6.2', 'shared-source'), ('6.3', 'shared-source'), ('6.4', 'dag-plugin-source')]:
            value = p.fingerprint(**{**self.inputs(), 'swift': f'Apple Swift version {version}.0 (exact compiler build)'})
            self.assertEqual(value['consumer-profile'], profile)
            self.assertEqual(value['consumer-paths'], [f'.build/external-consumer-contracts/{profile}/{e}' for e in ['pass', 'fail', 'signature']])
            self.assertNotIn('macro-only-prebuilt', '\n'.join(value['consumer-paths']))
            self.assertEqual(len(set(value['consumer-paths'])), 3)
        source = self.inputs()['contract']
        for name in ['shared-source', 'dag-plugin-source', 'macro-only-prebuilt']:
            self.assertIn('"' + name + '"', source)
        self.assertIn('#if compiler(>=6.4)', source)
        self.assertIn('fixture.expectation.rawValue', source)

    def test_missing_empty_unknown_or_unpinned_inputs_fail_closed(self):
        for key in self.inputs():
            for value in ['', ' ', None]:
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    p.fingerprint(**{**self.inputs(), key: value})
        for key, value in [('swift', 'Swift version 6.4.0'), ('swift', 'Apple Swift version 6.5.0'),
                           ('swift', 'Apple Swift version 6.1.0'), ('xcode', 'Xcode 26.6'),
                           ('manifest', self.inputs()['manifest'].replace('exact:', 'from:')),
                           ('manifest', '// swift-tools-version: 6.2')]:
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                p.fingerprint(**{**self.inputs(), key: value})
        with self.assertRaises(ValueError):
            p.digest('')

    def test_restored_product_observation_does_not_mix_profiles_or_expectations(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for profile in ['shared-source', 'dag-plugin-source', 'macro-only-prebuilt']:
                for expectation in ['pass', 'fail', 'signature']:
                    folder = root / '.build/external-consumer-contracts' / profile / expectation / 'debug/SwiftSyntax.build'
                    folder.mkdir(parents=True)
                    (folder / 'Syntax.o').write_bytes(b'product')
            before = p.products(root, 'shared-source')
            self.assertEqual(len(before), 3)
            changed = root / next(iter(before))
            changed.write_bytes(b'changed product')
            after = p.products(root, 'shared-source')
            self.assertEqual(sum(after.get(k) == v for k, v in before.items()), 2)
            with self.assertRaises(ValueError):
                p.products(root, '../shared-source')

    def test_cli_uses_tracked_manifest_without_a_root_lock_and_rejects_missing_evidence(self):
        import json
        import subprocess
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(['git', 'init', '-q', directory], check=True)
            (root / 'Package.swift').write_text(self.inputs()['manifest'])
            contract = root / 'Tests/InnoDIBuildSupportTests/ExternalConsumerContractTests.swift'
            contract.parent.mkdir(parents=True)
            contract.write_text(self.inputs()['contract'])
            subprocess.run(['git', '-C', directory, 'add', 'Package.swift', str(contract)], check=True)
            binaries = root / 'bin'
            binaries.mkdir()
            commands = {'swift': "printf '%s\\n' 'Apple Swift version 6.3.0 (fixture build)'",
                        'xcodebuild': "printf '%s\\n' 'Xcode 26.6' 'Build version 17G42'",
                        'sw_vers': "printf '%s\\n' '25G42'", 'uname': "printf '%s\\n' 'arm64'"}
            for name, command in commands.items():
                executable = binaries / name
                executable.write_text('#!/bin/sh\n' + command + '\n')
                executable.chmod(0o755)
            output, state = root / 'output', root / 'state.json'
            env = {**os.environ, 'PATH': str(binaries) + ':' + os.environ['PATH'], 'GITHUB_OUTPUT': str(output)}
            command = ['python3', str(ROOT / 'Tools/ci-cache.py'), 'fingerprint', '--root', directory, '--state', str(state)]
            result = subprocess.run(command, env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((root / 'Package.resolved').exists())
            data = json.loads(state.read_text())
            self.assertIn('consumer-profile=shared-source', output.read_text())
            self.assertIn('consumer-paths<<CACHE_PATHS', output.read_text())
            self.assertRegex(data['dependency-key'], r'-[a-f0-9]{64}$')
            for invalid in ['empty-compiler', 'untracked-manifest']:
                output.unlink(missing_ok=True)
                state.unlink(missing_ok=True)
                if invalid == 'empty-compiler':
                    (binaries / 'swift').write_text('#!/bin/sh\nexit 0\n')
                else:
                    subprocess.run(['git', '-C', directory, 'rm', '--cached', 'Package.swift'], check=True, capture_output=True)
                result = subprocess.run(command, env=env, text=True, capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(state.exists())
                self.assertFalse(output.exists())

    def test_workflow_uses_exact_keys_and_release_gate_stays_cold(self):
        source = (ROOT / '.github/workflows/macro-tests.yml').read_text()
        self.assertNotIn("hashFiles('Package.resolved')", source)
        self.assertNotIn('restore-keys:', source)
        self.assertEqual(source.count('run: python3 -B Tools/ci-cache.py fingerprint'), 5)
        self.assertEqual(source.count('key: ${{ steps.cache-inputs.outputs.dependency-key }}'), 5)
        self.assertEqual(source.count('key: ${{ steps.cache-inputs.outputs.consumer-key }}'), 3)
        self.assertEqual(source.count('path: ${{ steps.cache-inputs.outputs.consumer-paths }}'), 3)
        self.assertEqual(source.count('run: python3 -B Tools/ci-cache.py restored'), 5)
        self.assertEqual(source.count('run: python3 -B Tools/ci-cache.py report'), 5)
        release = (ROOT / '.github/workflows/release.yml').read_text()
        self.assertNotIn('actions/cache@', release)
        self.assertNotIn('ci-cache.py', release)
        self.assertTrue((ROOT / 'Package.swift').read_text().startswith('// swift-tools-version: 6.2'))



class ExhaustiveSupersetTests(unittest.TestCase):
    def test_full_lane_is_a_strict_superset_of_fast_test_and_tool_contracts(self):
        import re
        source = (ROOT / '.github/workflows/macro-tests.yml').read_text()
        fast = source.split('\n  fast-tests:\n', 1)[1].split('\n  macro-tests:\n', 1)[0]
        exhaustive = source.split('\n  macro-tests:\n', 1)[1].split('\n  consumer-contracts:\n', 1)[0]
        coverage = (ROOT / 'Tools/run-coverage-gate.sh').read_text()
        test = fast.split('      - name: Run in-process test contracts\n', 1)[1].split('      - name:', 1)[0]
        for flag in ['--no-parallel', '-Xswiftc -strict-concurrency=complete', '-Xswiftc -warnings-as-errors']:
            self.assertIn(flag, test)
            self.assertIn(flag, coverage)
        fast_skips = set(re.findall(r"--skip '([^']+)'", test))
        exhaustive_skips = set(re.findall(r"--skip '([^']+)'", coverage))
        api_checker = 'InnoDIBuildSupportTests.PublicAPIContractTests/compilerDefaultArgumentContract'
        self.assertEqual(fast_skips, {api_checker,
            'InnoDIBuildSupportTests.(ExternalConsumerContractTests|StrictConcurrencyBuildTests)',
            'InnoDIMigrationCoreTests.InnoDIMigrationCoreTests/publicExecutableRunsFromFreshConsumer',
            'InnoDIMacrosTests.MechanicalFixItTests/uniqueBindingRepairBuildsAndGraphs'})
        self.assertEqual(exhaustive_skips, {api_checker, 'InnoDIBuildSupportTests.(ExternalConsumerContractTests|StrictConcurrencyBuildTests)'})
        self.assertLess(exhaustive_skips, fast_skips)
        self.assertNotIn('--filter', coverage)
        self.assertNotIn('--filter', test)
        self.assertIn('if [[ -n "$SCOPED_PRODUCT" ]]; then', test)
        self.assertIn('Tools/run_ci_product_tests.py test', test)
        # The qualified branch executes the unchanged original leaf tests and
        # an API emitter proven equal to the full checker, not a unique gate.
        self.assertIn('product_test_scope.product', test)
        self.assertIn('--enable-code-coverage', coverage)
        self.assertIn('Tools/check-coverage-floor.py', coverage)
        # Freeze every executable validation/report step in the fast lane, so
        # adding a future unique fast check makes this test demand a coverage
        # decision rather than silently suppressing it with the whole job.
        steps = set(re.findall(r'(?m)^      - name: (.+)$', fast))
        infrastructure = {'Checkout', 'Select Xcode 26.6', 'Fingerprint exact cache inputs',
                          'Restore SwiftPM dependency cache', 'Observe restored cache products',
                          'Report cache and validation observations', 'Summarize test suite durations',
                          'Upload Escape Hatch Report', 'Upload Deferred-Wrapper Alias Report', 'Upload scoped product test evidence'}
        self.assertEqual(steps - infrastructure, {'Run in-process test contracts',
            'Validate macro synthesis and CI policy', 'Validate public API and Global DAG',
            'Report Build-Validation Escape Hatches', 'Report Deferred-Wrapper Alias Findings'})
        expected_scripts = {
            'Validate macro synthesis and CI policy': [
                'Tools/check-no-fatalerror-in-macros.sh', 'Tools/check-ci-validation-opt-out.sh',
                'Tools/check-ci-action-pins.sh'],
            'Validate public API and Global DAG': [
                'set -euo pipefail', 'if [[ -n "$SCOPED_PRODUCT" ]]; then',
                'python3 -B Tools/run_ci_product_tests.py api', 'else',
                'Tools/check-public-api.py', 'fi', 'swift run InnoDI-DependencyGraph --root . --validate-dag'],
            'Report Build-Validation Escape Hatches': [
                '{', 'Tools/report-validate-dag-escape-hatches.sh', '} >> "$GITHUB_STEP_SUMMARY"'],
            'Report Deferred-Wrapper Alias Findings': [
                '{', 'swift run --quiet InnoDI-DeferredAliasScan --root . --json build/deferred-aliases.json',
                '} >> "$GITHUB_STEP_SUMMARY"'],
        }
        for name, expected in expected_scripts.items():
            body = fast.split('      - name: ' + name + '\n', 1)[1].split('      - name:', 1)[0]
            actual = [line.strip() for line in body.split('        run: |\n', 1)[1].splitlines() if line.strip()]
            self.assertEqual(actual, expected, name)
        commands = ['Tools/check-no-fatalerror-in-macros.sh', 'Tools/check-ci-validation-opt-out.sh',
                    'Tools/check-ci-action-pins.sh', 'Tools/check-public-api.py',
                    'swift run InnoDI-DependencyGraph --root . --validate-dag',
                    'Tools/report-validate-dag-escape-hatches.sh',
                    'swift run --quiet InnoDI-DeferredAliasScan --root . --json build/deferred-aliases.json']
        for command in commands:
            self.assertIn(command, fast)
            self.assertIn(command, exhaustive)
        # Neither sanitizer/negative consumer/platform/exact-SHA gate moved.
        consumers = source.split('\n  consumer-contracts:\n', 1)[1].split('\n  sanitizers:\n', 1)[0]
        for suite in ['StrictConcurrencyBuildTests', 'ExternalConsumerContractTests']:
            self.assertIn('--filter ' + suite, consumers)


if __name__ == '__main__':
    unittest.main()
