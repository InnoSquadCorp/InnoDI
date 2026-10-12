#!/usr/bin/env python3
"""Reject incomplete or incorrectly hosted English/Korean rendered DocC catalogs."""
import argparse
import json
from pathlib import Path
import re
import sys

ARTICLES = ('', 'ownedcontainers', 'dicontainer', 'provide')


def authored_text(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if key == 'text' and isinstance(child, str):
                yield child
            else:
                yield from authored_text(child)
    elif isinstance(value, list):
        for child in value:
            yield from authored_text(child)


def failures(root: Path, version: str):
    errors = []
    for locale, prefix in (('en', ''), ('ko', 'ko')):
        catalog = root / prefix
        expected_base = '/InnoDI' + ('/ko' if locale == 'ko' else '')
        index = catalog / 'index.html'
        if not index.is_file():
            errors.append(f'{locale}: missing index.html')
        else:
            match = re.search(r'var baseUrl\s*=\s*"([^"]+)"', index.read_text())
            if not match or match.group(1).rstrip('/') != expected_base:
                errors.append(f'{locale}: expected hosting base {expected_base}')
        for article in ARTICLES:
            path = catalog / 'data/documentation' / ('innodi/' + article + '.json' if article else 'innodi.json')
            try:
                node = json.loads(path.read_text())
            except (OSError, ValueError) as error:
                errors.append(f'{locale}/{article or "Overview"}: cannot read rendered article: {error}')
                continue
            text = ' '.join(authored_text([node.get('abstract', []), node.get('primaryContentSections', [])]))
            if locale == 'ko' and re.search('[가-힣]', text) is None:
                errors.append(f'ko/{article or "Overview"}: missing Korean authored content')
            if not article:
                marker = (f'The latest stable release is {version}.' if locale == 'en'
                          else f'최신 안정 릴리스는 {version}입니다.')
                if marker not in text:
                    errors.append(f'{locale}/Overview: expected stable release {version}')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('--version')
    args = parser.parse_args()
    version = args.version
    if version is None:
        changelog = Path(__file__).resolve().parents[1] / 'CHANGELOG.md'
        match = re.search(r'Latest stable public release: `(\d+\.\d+\.\d+)`', changelog.read_text())
        if not match:
            parser.error('CHANGELOG.md has no stable release metadata')
        version = match.group(1)
    errors = failures(args.root, version)
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        return 1
    print(f'English/Korean rendered DocC articles and hosting roots verified for {version}.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
