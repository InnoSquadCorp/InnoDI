"""Exercise the checked-in CI conditions without dispatching a workflow."""
from pathlib import Path
import re
import unittest

WORKFLOWS = Path(__file__).resolve().parents[2] / ".github/workflows"


def step(name, workflow="macro-tests.yml"):
    source = (WORKFLOWS / workflow).read_text()
    start = source.index("      - name: " + name + "\n")
    end = source.find("      - name: ", start + 1)
    return source[start:end if end != -1 else None]


class PerformanceWorkflowTests(unittest.TestCase):
    def test_independent_gates_preserve_failure(self):
        # GitHub's default success() would suppress both independent checks
        # after the first failure. Evaluate their actual explicit conditions.
        for workflow, name in [("macro-tests.yml", "Macro Performance Trend"),
                               ("macro-tests.yml", "Runtime Trace Performance Check"),
                               ("release.yml", "Enforce candidate runtime trace performance")]:
            body = step(name, workflow)
            condition = re.search(r"if: \$\{\{ (.+) \}\}", body)
            self.assertIsNotNone(condition, name)
            expression = condition.group(1)
            self.assertEqual(expression, "!cancelled() && steps.macro_performance.outcome != 'skipped'")
            self.assertNotIn("continue-on-error", body.split("run:")[1])
            self.assertNotRegex(body, r"(?m)^\s+continue-on-error:", name)
            for outcome in ["success", "failure", "skipped"]:
                for cancelled in [True, False]:
                    actual = expression.replace("!cancelled()", str(not cancelled)).replace(
                        "steps.macro_performance.outcome", repr(outcome)).replace("&&", "and")
                    self.assertEqual(eval(actual, {"__builtins__": {}}),
                                     not cancelled and outcome != "skipped")
        self.assertNotIn("continue-on-error:", step("Macro Performance Check"))
        self.assertIn("--enforce", step("Macro Performance Check"))
        self.assertIn("always()", step("Upload Runtime Trace Performance Report"))
        self.assertIn("--enforce", step("Enforce macro performance baseline", "release.yml"))
        self.assertIn("always()", step("Upload candidate macro performance report", "release.yml"))


if __name__ == "__main__":
    unittest.main()
