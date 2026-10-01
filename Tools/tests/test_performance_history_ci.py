"""Exercise writer admission, exact current-run artifact and checkout guards."""
import itertools
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SHA = "a" * 40


def writer():
    return (ROOT / ".github/workflows/macro-tests.yml").read_text().split("  append-perf-history:\n", 1)[1]


def guard_scripts(script):
    # A conditional function caller makes Bash ignore errexit even when the
    # function sets -e. Guards must explicitly reject rather than depend on
    # version-specific handling of failed [[ compound commands (macOS Bash).
    return (script, "guard() {\n" + script + "\n}\nif guard; then exit 0; else exit $?; fi\n")


class HistoryWriterTests(unittest.TestCase):
    def test_actual_condition_requires_all_success_and_never_runs_after_cancellation(self):
        expression = " ".join(writer().split("    if: >-\n", 1)[1].split("    needs:\n", 1)[0].split())
        self.assertIn("always()", expression)  # No implicit success() over skipped ancestors.
        self.assertIn("!cancelled()", expression)
        def allowed(results, *, event="push", ref="refs/heads/main", post_merge="", cancelled=False, ancestor_skipped=False):
            values = {"github.event_name": event, "github.ref": ref,
                      "needs.ci-plan.outputs.post_merge": post_merge,
                      **{f"needs.{name}.result": value for name, value in zip(("ci-plan", "ci-required", "macro-tests"), results)}}
            actual = expression
            for key, value in values.items(): actual = actual.replace(key, repr(value))
            actual = actual.replace("always()", "True").replace("!cancelled()", str(not cancelled))
            actual = actual.replace("&&", " and ").replace("||", " or ")
            # GitHub's default status gate only applies without a status function.
            default = True if "always()" in expression else not ancestor_skipped
            return default and eval(actual, {"__builtins__": {}})
        success = ("success",) * 3
        for results in itertools.product(("success", "failure", "cancelled", "skipped", ""), repeat=3):
            with self.subTest(results=results):
                self.assertEqual(allowed(results, ancestor_skipped=True), results == success)
                self.assertFalse(allowed(results, cancelled=True))
        for event, ref, post_merge, expected in [
                ("push", "refs/heads/main", "", True),
                ("pull_request", "refs/heads/main", "true", False),
                ("merge_group", "refs/heads/main", "true", False),
                ("push", "refs/heads/topic", "true", False),
                ("workflow_dispatch", "refs/heads/main", "", False),
                ("workflow_dispatch", "refs/heads/main", "false", False),
                ("workflow_dispatch", "refs/heads/main", "true", True)]:
            with self.subTest(event=event, ref=ref, post_merge=post_merge):
                self.assertEqual(allowed(success, event=event, ref=ref, post_merge=post_merge, ancestor_skipped=True), expected)

    def test_only_this_runs_exact_fresh_report_is_downloaded(self):
        source = writer()
        download = source.split("      - name: Download validated macro performance report\n", 1)[1].split("      - name:", 1)[0]
        arguments = [line.strip() for line in download.split("        with:\n", 1)[1].splitlines()]
        self.assertEqual(arguments, ["name: macro-performance-report", "path: build/performance"])
        self.assertIn("needs.macro-tests.result == 'success'", source)
        self.assertIn("INNODI_PERF_EXPECTED_SHA: ${{ github.sha }}", source)
        self.assertIn("--report build/performance/macro-performance-report.json", source)
        self.assertLess(source.index("Verify performance history source context"), source.index("Download validated macro performance report"))
        self.assertNotIn("continue-on-error:", source)

    def test_context_guard_rejects_foreign_repo_ref_and_mismatched_checkout(self):
        step = writer().split("      - name: Verify performance history source context\n", 1)[1].split("      - name:", 1)[0]
        script = step.split("        run: |\n", 1)[1]
        with tempfile.TemporaryDirectory(prefix="innodi-history-context-") as directory:
            git = Path(directory) / "git"
            git.write_text('#!/bin/sh\nprintf "%s\\n" "$FIXTURE_HEAD"\nexit "${FIXTURE_GIT_EXIT:-0}"\n')
            git.chmod(0o755)
            valid = {"PATH": directory + ":" + os.environ["PATH"], "GITHUB_REPOSITORY": "InnoSquadCorp/InnoDI",
                     "GITHUB_REF": "refs/heads/main", "GITHUB_SHA": SHA, "FIXTURE_HEAD": SHA}
            cases = [{}, {"GITHUB_REPOSITORY": "foreign/repo"}, {"GITHUB_REF": "refs/pull/49/merge"},
                     {"GITHUB_SHA": ""}, {"GITHUB_SHA": "main"}, {"FIXTURE_HEAD": "b" * 40}, {"FIXTURE_GIT_EXIT": "1"}]
            for change in cases:
                for command in guard_scripts(script):
                    result = subprocess.run(["bash", "-c", command], env={**valid, **change}, capture_output=True)
                    self.assertEqual(result.returncode == 0, not change, (change, result.stderr))

    def test_append_rechecks_report_context_before_adding_commit_or_writing_history(self):
        script = (ROOT / "Tools/append-performance-history.sh").read_text()
        start = script.index('current_sha=$(git rev-parse HEAD)')
        end = script.index('short_sha=$(git rev-parse --short=12 HEAD)', start)
        guard = script[start:end]
        self.assertLess(script.index('python3 Tools/validate-macro-performance-report.py'), start)
        self.assertLess(end, script.index('data["commit"] = os.environ["COMMIT_SHA"]'))
        self.assertLess(end, script.index('git fetch origin "$PERF_BRANCH"'))
        with tempfile.TemporaryDirectory(prefix="innodi-history-recheck-") as directory:
            git = Path(directory) / "git"
            git.write_text('#!/bin/sh\nprintf "%s\\n" "$FIXTURE_HEAD"\nexit "${FIXTURE_GIT_EXIT:-0}"\n')
            git.chmod(0o755)
            valid = {"PATH": directory + ":" + os.environ["PATH"], "INNODI_PERF_EXPECTED_SHA": SHA,
                     "GITHUB_SHA": SHA, "FIXTURE_HEAD": SHA, "GITHUB_REPOSITORY": "InnoSquadCorp/InnoDI",
                     "GITHUB_REF": "refs/heads/main"}
            for change in [{}, {"FIXTURE_HEAD": "b" * 40}, {"GITHUB_SHA": "b" * 40},
                           {"GITHUB_REPOSITORY": "fork/repo"}, {"GITHUB_REF": "refs/heads/topic"},
                           {"INNODI_PERF_EXPECTED_SHA": "main"}, {"FIXTURE_GIT_EXIT": "1"}]:
                for command in guard_scripts("set -euo pipefail\n" + guard):
                    result = subprocess.run(["bash", "-c", command], env={**valid, **change}, capture_output=True)
                    self.assertEqual(result.returncode == 0, not change, (change, result.stderr))


if __name__ == "__main__":
    unittest.main()
