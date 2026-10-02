"""Supply-chain and compatibility boundaries of the required workflow linter."""
import hashlib
import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('workflow_lint', ROOT / 'Tools/check-ci-workflows.py')
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)


class WorkflowLintTests(unittest.TestCase):
    def test_only_verified_regular_executable_is_written(self):
        for symlink in (False, True):
            buffer = io.BytesIO()
            with tarfile.open(fileobj=buffer, mode='w:gz') as archive:
                member = tarfile.TarInfo('actionlint')
                content = b'#!/bin/sh\nexit 0\n'
                if symlink:
                    member.type = tarfile.SYMTYPE
                    member.linkname = '/untrusted/executable'
                    archive.addfile(member)
                else:
                    member.size = len(content)
                    archive.addfile(member, io.BytesIO(content))
            data = buffer.getvalue()
            with tempfile.TemporaryDirectory() as directory:
                destination = Path(directory)
                digest = hashlib.sha256(data).hexdigest()
                with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
                    p.unpack_verified(data + b'tampered', digest, destination)
                self.assertEqual(list(destination.iterdir()), [])
                if symlink:
                    with self.assertRaisesRegex(ValueError, 'regular executable'):
                        p.unpack_verified(data, digest, destination)
                    self.assertEqual(list(destination.iterdir()), [])
                else:
                    executable = p.unpack_verified(data, digest, destination)
                    self.assertEqual(executable.read_bytes(), content)
                    self.assertEqual(executable.stat().st_mode & 0o777, 0o700)

    def test_queue_lint_exception_cannot_hide_invalid_or_new_queue_values(self):
        original = (ROOT / '.github/workflows/dependabot-auto-merge.yml').read_text()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'dependabot-auto-merge.yml'
            path.write_text(original)
            p.check_queue_compatibility([path])
            for changed in (
                    original.replace('      queue: max', '      queue: invalid', 1),
                    original.replace('      queue: max\n', '', 1),
                    original.replace('      queue: max', '      queue: max\n      queue: max', 1),
                    original + '\n  unreviewed:\n    concurrency:\n      queue: max\n',
                    original + '\n  unreviewed:\n    concurrency:\n      "queue": max\n'):
                path.write_text(changed)
                with self.assertRaises(ValueError):
                    p.check_queue_compatibility([path])
