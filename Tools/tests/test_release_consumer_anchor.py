"""Execute release shell guards against disposable local Git repositories."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


def step_body(prefix):
    lines = (ROOT / ".github/workflows/release.yml").read_text().splitlines()
    start = next(i for i, line in enumerate(lines) if line.startswith("      - name: " + prefix))
    run = next(i for i in range(start, len(lines)) if lines[i] == "        run: |")
    body = []
    for line in lines[run + 1:]:
        if line and not line.startswith("          "):
            break
        body.append(line[10:])
    if not body:
        raise AssertionError("Missing workflow shell: " + prefix)
    return "\n".join(body)


class ReleaseConsumerAnchorTests(unittest.TestCase):
    def test_tip_advance_recovery_and_fail_closed_controls(self):
        with tempfile.TemporaryDirectory(prefix="innodi-release-anchor-") as directory:
            root = Path(directory)
            remote, client = root / "remote", root / "client"
            env = dict(os.environ, GIT_AUTHOR_NAME="Fixture", GIT_COMMITTER_NAME="Fixture",
                       GIT_AUTHOR_EMAIL="fixture@example.invalid", GIT_COMMITTER_EMAIL="fixture@example.invalid")

            def git(where, *args):
                result = subprocess.run(["git", "-C", str(where), "-c", "commit.gpgsign=false", "-c", "tag.gpgsign=false", *args],
                                        env=env, capture_output=True, text=True, timeout=20)
                self.assertEqual(result.returncode, 0, result.stderr)
                return result.stdout.strip()

            git(root, "init", "-q", "-b", "main", str(remote))
            git(remote, "commit", "-q", "--allow-empty", "-m", "candidate")
            candidate = git(remote, "rev-parse", "HEAD")
            git(remote, "tag", "-a", "6.0.0", "-m", "candidate")
            git(root, "clone", "-q", str(remote), str(client))
            env.update(EXPECTED_SHA=candidate, INNODI_REVISION=candidate, DISPATCH_SHA=candidate,
                       INNODI_REPOSITORY_URL=str(remote), VERSION="6.0.1")
            anchor = step_body("Validate remote release anchor")
            consumer = step_body("Confirm exact candidate")

            def check(script, success):
                result = subprocess.run(["bash", "-c", script], cwd=client, env=env,
                                        capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)

            check(anchor, True)  # Untagged initial dispatch is at the main tip.
            check(consumer, True)
            git(remote, "commit", "-q", "--allow-empty", "-m", "next-main")
            next_main = git(remote, "rev-parse", "HEAD")
            # Validated candidate remains eligible after normal main progress.
            with self.subTest(case="preflight-then-fast-forward"):
                check(consumer, True)
            # A new untagged dispatch must still fail at preflight.
            env["DISPATCH_SHA"] = next_main
            with self.subTest(case="new-untagged-old-dispatch"):
                check(anchor, False)
            env["VERSION"] = "6.0.0"
            with self.subTest(case="annotated-tag-recovery"):
                check(anchor, True)
                check(consumer, True)
            git(client, "checkout", "--detach", "origin/main")
            git(client, "commit", "-q", "--allow-empty", "-m", "wrong-checkout")
            with self.subTest(case="wrong-consumer-checkout"):
                check(consumer, False)
            git(client, "checkout", "--detach", candidate)
            git(remote, "checkout", "--orphan", "rewritten")
            git(remote, "commit", "-q", "--allow-empty", "-m", "unrelated")
            git(remote, "update-ref", "refs/heads/main", git(remote, "rev-parse", "HEAD"))
            with self.subTest(case="rewritten-main"):
                check(anchor, False)
                check(consumer, False)


if __name__ == "__main__":
    unittest.main()
