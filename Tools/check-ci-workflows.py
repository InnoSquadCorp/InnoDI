#!/usr/bin/env python3
"""Run the pinned workflow linter without optional, host-dependent linters."""
import hashlib
import io
from pathlib import Path
import platform
import re
import subprocess
import tarfile
import tempfile
import urllib.request

VERSION = '1.7.12'
# Digests published with the upstream release, reviewed with this version.
ARCHIVES = {
    ('Darwin', 'arm64'): ('darwin_arm64', 'aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f'),
    ('Darwin', 'x86_64'): ('darwin_amd64', '5b44c3bc2255115c9b69e30efc0fecdf498fdb63c5d58e17084fd5f16324c644'),
    ('Linux', 'aarch64'): ('linux_arm64', '325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6'),
    ('Linux', 'x86_64'): ('linux_amd64', '8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8'),
}
QUEUE_JOBS = {'ready-refresh', 'bot-ready', 'post-merge'}
QUEUE_DIAGNOSTIC = r'^unexpected key "queue" for "concurrency" section\.'


def check_queue_compatibility(workflows):
    # actionlint 1.7.12 predates concurrency.queue. Exempt only the three
    # reviewed max queues; spelling/value/location changes must be reviewed.
    seen = set()
    for path in workflows:
        job = None
        for line in path.read_text().splitlines():
            match = re.fullmatch(r'  ([\w-]+):', line)
            if match:
                job = match[1]
            if re.match(r'''\s*["']?queue["']?\s*:''', line):
                if (path.name != 'dependabot-auto-merge.yml' or job not in QUEUE_JOBS or
                        line != '      queue: max' or job in seen):
                    raise ValueError('unreviewed concurrency.queue exception: ' + str(path))
                seen.add(job)
    if seen != QUEUE_JOBS:
        raise ValueError('review the actionlint queue exception when writer queues change')


def unpack_verified(archive, digest, destination):
    if hashlib.sha256(archive).hexdigest() != digest:
        raise ValueError('actionlint archive checksum mismatch')
    with tarfile.open(fileobj=io.BytesIO(archive), mode='r:gz') as package:
        member = package.getmember('actionlint')
        if not member.isfile():
            raise ValueError('actionlint archive must contain a regular executable')
        executable = destination / 'actionlint'
        executable.write_bytes(package.extractfile(member).read())
    executable.chmod(0o700)
    return executable


def main():
    root = Path(__file__).resolve().parents[1]
    workflows = sorted((root / '.github/workflows').glob('*.yml'))
    workflows += sorted((root / '.github/workflows').glob('*.yaml'))
    check_queue_compatibility(workflows)
    target, digest = ARCHIVES[(platform.system(), platform.machine())]
    url = f'https://github.com/rhysd/actionlint/releases/download/v{VERSION}/actionlint_{VERSION}_{target}.tar.gz'
    with urllib.request.urlopen(url, timeout=30) as response:
        archive = response.read(20 * 1024 * 1024 + 1)
    if len(archive) > 20 * 1024 * 1024:
        raise ValueError('actionlint archive exceeds the download limit')
    with tempfile.TemporaryDirectory(prefix='innodi-actionlint-') as directory:
        executable = unpack_verified(archive, digest, Path(directory))
        subprocess.run([str(executable), '-shellcheck=', '-pyflakes=', '-ignore', QUEUE_DIAGNOSTIC,
                        *map(str, workflows)], cwd=root, check=True)
    print(f'actionlint {VERSION}: checked {len(workflows)} workflows')


if __name__ == '__main__':
    main()
