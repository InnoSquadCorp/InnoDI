#!/usr/bin/env python3
"""Collect real SwiftPM resolution evidence; never invent or edit dependency pins."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

CONSUMERS = ('SampleApp', 'SwiftUIExample', 'PreviewInjectionExample')


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def collect(root, unit, destination, env, check_output=subprocess.check_output, include_product_tests=False):
    root, destination = Path(root).resolve(), Path(destination).resolve()
    if unit not in CONSUMERS:
        raise ValueError('unreviewed consumer')
    if destination.exists():
        raise ValueError('refuse stale resolution artifact directory')
    packages = {'root': root, unit: root / 'Examples' / unit}
    if include_product_tests:
        for product in ('InnoDISwiftUI', 'InnoDITesting'):
            packages[product] = root / 'Tools' / 'CIProductTests' / product
    manifests = {name: (path / 'Package.swift').read_bytes() for name, path in packages.items()}
    candidate = check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
    if candidate != env.get('GITHUB_SHA'):
        raise ValueError('resolution candidate differs from event checkout')
    for name, path in packages.items():
        relative = (path / 'Package.swift').relative_to(root).as_posix()
        committed = check_output(['git', '-C', str(root), 'show', candidate + ':' + relative], text=True).encode()
        if committed != manifests[name]:
            raise ValueError('manifest is not the exact committed input: ' + name)
    toolchain = check_output(['xcrun', 'swift', '--version'], text=True).strip()
    xcode = check_output(['xcodebuild', '-version'], text=True).strip()
    records = {}
    for name, path in packages.items():
        # SwiftPM writes the actual lock. Capture the exact command and manifest
        # interpretation, including conditional platform/toolchain behavior.
        command = ['xcrun', 'swift', 'package', '--package-path', str(path), 'resolve']
        try:
            check_output(command, text=True, stderr=subprocess.STDOUT)
        except subprocess.CalledProcessError as error:
            if error.output:
                print(error.output, file=sys.stderr)
            raise
        dump = check_output(['xcrun', 'swift', 'package', '--package-path', str(path), 'dump-package'], text=True)
        lock = (path / 'Package.resolved').read_bytes()
        parsed = json.loads(lock)
        if parsed.get('version') not in (2, 3) or not isinstance(parsed.get('pins'), list) or not parsed['pins']:
            raise ValueError('SwiftPM did not produce a supported nonempty lock')
        if (path / 'Package.swift').read_bytes() != manifests[name]:
            raise ValueError('manifest changed during resolution')
        records[name] = {'manifest_sha256': sha256(manifests[name]), 'lock_sha256': sha256(lock),
                         'dump_sha256': sha256(dump.encode()), 'command': command}
        records[name]['_lock'] = lock
        records[name]['_dump'] = dump.encode()
    if check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip() != candidate:
        raise ValueError('candidate changed during resolution')
    for name, path in packages.items():
        if (path / 'Package.swift').read_bytes() != manifests[name]:
            raise ValueError('an earlier manifest changed during later resolution: ' + name)
        if (path / 'Package.resolved').read_bytes() != records[name]['_lock']:
            raise ValueError('an earlier lock changed during later resolution: ' + name)
    destination.mkdir(parents=True)
    for name, record in records.items():
        package_dir = destination / name
        package_dir.mkdir()
        (package_dir / 'Package.resolved').write_bytes(record.pop('_lock'))
        (package_dir / 'dump-package.json').write_bytes(record.pop('_dump'))
    proof = {'schema': 1, 'candidate_sha': candidate, 'run_id': env.get('GITHUB_RUN_ID'),
             'run_attempt': env.get('GITHUB_RUN_ATTEMPT'), 'event': env.get('GITHUB_EVENT_NAME'),
             'repository': env.get('GITHUB_REPOSITORY'), 'toolchain': toolchain, 'xcode': xcode,
             'packages': records, 'scope': 'resolution only; not compilation or test success'}
    (destination / 'provenance.json').write_text(json.dumps(proof, indent=2, sort_keys=True) + '\n')
    return proof


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--unit', required=True, choices=CONSUMERS)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--include-product-tests', action='store_true')
    args = parser.parse_args()
    print(json.dumps(collect(Path.cwd(), args.unit, args.output, os.environ, include_product_tests=args.include_product_tests), sort_keys=True))


if __name__ == '__main__':
    main()
