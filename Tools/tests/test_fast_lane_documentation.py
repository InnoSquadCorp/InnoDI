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
        # CONTRIBUTING presents its test command as the PR fast lane, so a
        # skip added to one side must appear on the other. The block is found
        # by its command, not by the wording around it.
        blocks = re.findall(r"```bash\n(.*?)```", (ROOT / "CONTRIBUTING.md").read_text(), re.S)
        commands = [block for block in blocks if "swift test" in block and "--skip" in block]
        self.assertEqual(len(commands), 1, "CONTRIBUTING documents one fast-lane test command")
        documented = commands[0]
        self.assertGreaterEqual(len(skipped(job)), 1)
        self.assertEqual(skipped(documented), skipped(job))
        for flag in ("--no-parallel", "-strict-concurrency=complete", "-warnings-as-errors"):
            self.assertIn(flag, job)
            self.assertIn(flag, documented)


if __name__ == "__main__":
    unittest.main()
