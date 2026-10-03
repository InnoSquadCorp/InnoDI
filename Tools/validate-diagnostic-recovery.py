#!/usr/bin/env python3
"""Compile real-plugin diagnostic failures and explicit consumer repairs.

Linux portable-module evidence only. The runtime/plugin must already be built.
The validator checks expected source locations and recovery guidance, then builds
and executes the repaired sources. It does not apply semantic scope/order edits
for the user or measure performance.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('plugin', type=Path)
    parser.add_argument('runtime', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--swiftc', required=True)
    parser.add_argument('--baseline-plugin', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    fixtures = root / 'Tests/DiagnosticRecoveryFixtures'
    cases_path = fixtures / 'manifest.json'
    cases = json.loads(cases_path.read_text())['cases']
    plugin = args.plugin.resolve(strict=True)
    runtime = args.runtime.resolve(strict=True)
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    inputs = [Path(__file__).resolve(), cases_path, plugin,
              runtime / 'InnoDI.swiftmodule', runtime / 'libInnoDI.so',
              *[fixtures / (case['name'] + '.swift.fixture') for case in cases]]
    for relative in ['Sources/InnoDI/InnoDI.docc/DiagnosticsGuide.md',
                     'Sources/InnoDI/InnoDI.docc/ko.lproj/DiagnosticsGuide.md']:
        documentation = root / relative
        documented_source = documentation.read_text().split(
            '<!-- diagnostic-recovery: Provider-repaired -->\n```swift\n', 1
        )[1].split('\n```\n<!-- /diagnostic-recovery -->', 1)[0]
        if documented_source != (fixtures / 'Provider-repaired.swift.fixture').read_text().rstrip('\n'):
            raise RuntimeError('Documented provider recovery differs from compiled fixture: ' + relative)
        inputs.append(documentation)
    if args.baseline_plugin:
        args.baseline_plugin = args.baseline_plugin.resolve(strict=True)
        inputs.append(args.baseline_plugin)
    manifest = dict(status='running', scope=__doc__,
                    compiler=subprocess.check_output([args.swiftc, '--version'], text=True),
                    inputs={str(p): digest(p) for p in inputs}, commands=[], results=[])
    path = out / 'manifest.json'
    def persist():
        path.write_text(json.dumps(manifest, indent=2) + '\n')
    persist()
    flags = [args.swiftc, '-swift-version', '6', '-strict-concurrency=complete',
             '-warnings-as-errors', '-parse-as-library', '-module-name', 'DiagnosticRecovery',
             '-module-cache-path', str(out / 'cache'),
             '-I', str(runtime), '-L', str(runtime), '-lInnoDI',
             '-Xlinker', '-rpath', '-Xlinker', str(runtime)]
    def run(name, command):
        manifest['commands'].append(dict(name=name, argv=list(map(str, command))))
        persist()
        try:
            result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, timeout=120)
        except subprocess.TimeoutExpired as error:
            data = error.stdout or b''
            if isinstance(data, bytes):
                data = data.decode('utf-8', errors='replace')
            (out / (name + '.log')).write_text(data + '\nTIMEOUT\n')
            raise RuntimeError(name + ' timed out') from error
        log = out / (name + '.log')
        log.write_text(result.stdout)
        manifest['results'].append(dict(name=name, exit=result.returncode, log_sha256=digest(log)))
        persist()
        if 'Stack dump:' in result.stdout or result.returncode < 0:
            raise RuntimeError(name + ' compiler/process crash')
        return result.returncode, result.stdout
    try:
        if args.baseline_plugin:
            # Two fixed reproducers establish the old misleading cause and
            # whole-attribute location; no old/new source acceptance changes.
            for name in ['Transient-factory-declaration-before-exact',
                         'Transient-with-declaration-before-exact']:
                source = (fixtures / (name + '.swift.fixture')).read_text()
                copied = out / ('baseline-' + name + '.swift')
                copied.write_text(source)
                code, text = run('baseline-' + name, [*flags, '-load-plugin-executable',
                    str(args.baseline_plugin) + '#InnoDIMacros', '-c', str(copied),
                    '-o', str(out / ('baseline-' + name + '.o'))])
                attribute = source.index('@Provide(.shared')
                line = source[:attribute].count('\n') + 1
                column = len(source[:attribute].rsplit('\n', 1)[-1]) + 1
                assert code != 0 and 'not available in this declaration order' in text
                assert re.search(re.escape(str(copied)) + f':{line}:{column}: error:', text)
        successes = failures = 0
        for case in cases:
            name = case['name']
            copied = out / (name + '.swift')
            source = (fixtures / (name + '.swift.fixture')).read_text()
            copied.write_text(source)
            output = out / (name + ('' if case['success'] else '.o'))
            command = [*flags, '-load-plugin-executable', str(plugin) + '#InnoDIMacros']
            command += ['-O'] if case['success'] else ['-c']
            code, text = run(name, [*command, str(copied), '-o', str(output)])
            if case['success']:
                assert code == 0, name + ': repaired consumer did not compile'
                exit_code, _ = run(name + '-run', [str(output)])
                assert exit_code == 0, name + ': repaired consumer oracle failed'
                successes += 1
            else:
                assert code != 0, name + ': invalid consumer unexpectedly compiled'
                for fragment in case['required']:
                    assert fragment in text, name + ': missing intended diagnostic ' + fragment
                for fragment in case['forbidden']:
                    assert fragment not in text, name + ': misleading diagnostic ' + fragment
                if 'line' in case:
                    location = f":{case['line']}:{case['column']}: error:"
                    assert re.search(re.escape(str(copied)) + re.escape(location), text), name + ': wrong source anchor'
                failures += 1
        assert {str(p): digest(p) for p in inputs} == manifest['inputs'], 'Input changed during validation'
        manifest.update(status='passed', successful_repairs=successes, intended_failures=failures,
                        baseline_reproductions=2 if args.baseline_plugin else 0)
        persist()
        print(json.dumps({k: manifest[k] for k in ['status', 'successful_repairs', 'intended_failures', 'baseline_reproductions']}))
    except BaseException as error:
        manifest.update(status='failed', error=repr(error))
        persist()
        raise


if __name__ == '__main__':
    main()
