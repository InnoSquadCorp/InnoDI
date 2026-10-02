"""Run the actual anchor shell with main/feature refs and moving-ref controls."""
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RemoteDispatchTests(unittest.TestCase):
    def test_direct_dispatch_and_reusable_call_preserve_exact_ref_revision_binding(self):
        source = (ROOT / '.github/workflows/remote-consumer-smoke.yml').read_text()
        self.assertIn('INNODI_BRANCH_REF: ${{ inputs.branch_ref || github.ref }}', source)
        self.assertIn('INNODI_REVISION: ${{ inputs.revision || github.sha }}', source)
        step = source.split('      - name: Confirm the revision is the published main tip\n', 1)[1].split('      - name: Materialize a fresh remote consumer\n', 1)[0]
        script = textwrap.dedent(step.split('        run: |\n', 1)[1])
        with tempfile.TemporaryDirectory() as directory:
            git = Path(directory) / 'git'
            git.write_text('''#!/bin/bash
if [[ "$1" == check-ref-format ]]; then exec /usr/bin/git "$@"; fi
if [[ "$1" == ls-remote ]]; then
  ref="${@: -1}"
  case "$ref" in
    refs/heads/main) printf '%s\\t%s\\n' "$MAIN_SHA" "$ref";;
    refs/heads/topic) printf '%s\\t%s\\n' "$TOPIC_SHA" "$ref";;
  esac
  exit 0
fi
exit 99
''')
            git.chmod(0o755)
            for ref, revision, succeeds in [
                    ('refs/heads/main', 'a'*40, True), ('refs/heads/topic', 'b'*40, True),
                    ('refs/heads/main', 'b'*40, False), ('refs/heads/topic', 'c'*40, False),
                    ('refs/heads/missing', 'a'*40, False), ('', 'a'*40, False)]:
                result = subprocess.run(['bash', '-e', '-c', script], cwd=ROOT, capture_output=True, text=True,
                    env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1', 'PATH': directory+':'+os.environ['PATH'],
                         'INNODI_BRANCH_REF': ref, 'INNODI_REVISION': revision,
                         'INNODI_REPOSITORY_URL': 'https://github.com/InnoSquadCorp/InnoDI.git',
                         'MAIN_SHA': 'a'*40, 'TOPIC_SHA': 'b'*40})
                self.assertEqual(result.returncode == 0, succeeds, (ref, revision, result.stderr))
