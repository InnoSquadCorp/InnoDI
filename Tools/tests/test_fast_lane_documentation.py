"""The documented local fast lane matches the checked-in PR fast lane."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def skipped(text):
    return re.findall(r"--skip '([^']+)'", text)


class FastLaneDocumentationTests(unittest.TestCase):
    def test_contributing_command_skips_exactly_what_the_fast_lane_skips(self):
        workflow = (ROOT / ".github/workflows/macro-tests.yml").read_text()
        job = workflow.split("\n  fast-tests:\n", 1)[1].split("\n  macro-tests:\n", 1)[0]
        # CONTRIBUTING introduces the command as "exactly as the PR fast lane
        # runs it", so a skip added to one side must appear on the other.
        documented = (ROOT / "CONTRIBUTING.md").read_text().split("```bash\n", 1)[1].split("```", 1)[0]
        self.assertIn("exactly as the PR fast lane runs it", documented)
        self.assertGreaterEqual(len(skipped(job)), 1)
        self.assertEqual(skipped(documented), skipped(job))
        for flag in ("--no-parallel", "-strict-concurrency=complete", "-warnings-as-errors"):
            self.assertIn(flag, job)
            self.assertIn(flag, documented)


if __name__ == "__main__":
    unittest.main()
