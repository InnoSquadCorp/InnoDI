#!/usr/bin/env python3
"""Check current concise guides; mechanical parity does not prove translation quality."""
from pathlib import Path
import re
import sys

LOCALES = ('ja', 'zh-Hans', 'de', 'es', 'ru')
SECTIONS = ('requirements', 'installation', 'quickstart', 'api', 'lifecycle',
            'testing', 'diagnostics', 'documentation', 'history')
TOKENS = ('InnoDIDAGValidationPlugin', 'InnoDISwiftUI', 'InnoDITesting',
          '@Input', '@Provide', '@SubContainer', 'generateOwned: true',
          'report.isReady', 'closeAsyncProviders()', 'InnoDI-Doctor',
          'InnoDI-Migrate', '--check', '--report', '604.0.0', 'Mockable')


def failures(root: Path) -> list[str]:
    errors = []
    release = re.search(r'Latest stable public release: `(\d+\.\d+\.\d+)`',
                        (root / 'CHANGELOG.md').read_text())
    if release is None:
        return ['CHANGELOG.md: missing stable release metadata']
    version = release.group(1)
    canonical = (root / 'README.md').read_text()
    snippet_pattern = r'<!-- innodi:compile -->\s*```swift\n(.*?)\n```'
    example = re.search(snippet_pattern, canonical, re.S)
    if example is None:
        return ['README.md: missing marked canonical quickstart']
    for locale in LOCALES:
        name = f'README.{locale}.md'
        path = root / name
        if not path.exists():
            errors.append(f'{name}: missing guide')
            continue
        text = path.read_text()
        required = [f'<!-- innodi:guide version={version} -->',
                    f'from: "{version}"', '(README.md)',
                    f'https://github.com/InnoSquadCorp/InnoDI/blob/6.0.0/{name}',
                    *[f'<!-- innodi:section {section} -->' for section in SECTIONS],
                    *TOKENS,
                    'Sources/InnoDITesting/InnoDITesting.docc/InnoDITesting.md',
                    *['Sources/InnoDI/InnoDI.docc/' + article.name
                      for article in (root / 'Sources/InnoDI/InnoDI.docc').glob('*.md')]]
        for token in required:
            if token not in text:
                errors.append(f'{name}: missing contract {token}')
        markers = re.findall(r'<!-- innodi:section ([^ ]+) -->', text)
        if markers != list(SECTIONS):
            errors.append(f'{name}: section order/duplicates differ from guide contract')
        snippets = re.findall(snippet_pattern, text, re.S)
        if example.group(1) not in snippets:
            errors.append(f'{name}: missing exact marked canonical minimum example')
    return errors


if __name__ == '__main__':
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
    errors = failures(root)
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        raise SystemExit(1)
    print('Checked five current concise guides: release, sections, API tokens, canonical example.')
