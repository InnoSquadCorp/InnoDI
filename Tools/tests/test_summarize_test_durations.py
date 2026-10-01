"""Keep the CI test-duration summary deterministic and non-failing."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Tools" / "summarize-test-durations.py"

SAMPLE_LOG = "\n".join(
    [
        "Build complete! (51.12s)",
        '◇ Suite "Fast suite" started.',
        '✔ Suite "Fast suite" passed after 0.004 seconds.',
        '\U00101059  Suite "Strict concurrency build integration" passed after 822.449 seconds.',
        '\x1b[1;32m✔\x1b[0m Suite "External SwiftPM consumer contracts" passed after 592.526 seconds.',
        '✘ Suite "Broken | suite" failed after 3.5 seconds with 2 issues.',
        '✔ Test "not a suite" passed after 900.0 seconds.',
        "✘ Test run with 1258 tests in 111 suites failed after 1460.420 seconds with 2 issues.",
    ]
)


class SummarizeTestDurationsTests(unittest.TestCase):
    def run_script(self, text, *arguments):
        with tempfile.TemporaryDirectory(prefix="innodi-durations-") as directory:
            log = Path(directory, "test-output.log")
            log.write_text(text, encoding="utf-8")
            return subprocess.run(
                ["python3", "-B", str(SCRIPT), str(log), *arguments],
                capture_output=True,
                text=True,
                timeout=30,
            )

    def test_ranks_suites_by_duration_and_ignores_individual_tests(self):
        result = self.run_script(SAMPLE_LOG, "--title", "Slowest suites", "--top", "3")
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        self.assertEqual(lines[0], "### Slowest suites")
        self.assertIn("- 1258 tests in 111 suites failed after 1460.4 seconds.", lines)
        rows = [line for line in lines if line.startswith("| ") and not line.startswith("| Rank")]
        self.assertEqual(
            rows,
            [
                "| 1 | Strict concurrency build integration | passed | 822.4 |",
                "| 2 | External SwiftPM consumer contracts | passed | 592.5 |",
                "| 3 | Broken \\| suite | failed | 3.5 |",
            ],
        )
        self.assertNotIn("not a suite", result.stdout)

    def test_log_without_results_reports_a_notice_and_succeeds(self):
        result = self.run_script("Build complete!\nerror: compile failed\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("No Swift Testing results were found", result.stdout)

    def test_missing_log_is_reported_without_failing_the_job(self):
        result = subprocess.run(
            ["python3", "-B", str(SCRIPT), str(ROOT / "build" / "missing-test-output.log")],
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("could not be read", result.stdout)

    def test_top_must_be_positive(self):
        result = self.run_script(SAMPLE_LOG, "--top", "0")
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
