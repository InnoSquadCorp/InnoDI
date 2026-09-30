"""Exercise the checked-in CI conditions without dispatching a workflow."""
from pathlib import Path
import re
import os
import subprocess
import tempfile
import unittest

WORKFLOWS = Path(__file__).resolve().parents[2] / ".github/workflows"


def step(name, workflow="macro-tests.yml"):
    source = (WORKFLOWS / workflow).read_text()
    start = source.index("      - name: " + name + "\n")
    end = source.find("      - name: ", start + 1)
    return source[start:end if end != -1 else None]


class PerformanceWorkflowTests(unittest.TestCase):
    def test_optional_cold_benchmark_preserves_primary_prebuilt_contract(self):
        source = (WORKFLOWS / "cold-build-benchmark.yml").read_text()
        triggers = source.split("on:\n", 1)[1].split("\npermissions:", 1)[0]
        self.assertEqual(re.findall(r"^  ([a-z_]+):", triggers, re.MULTILINE), ["schedule", "workflow_dispatch"])
        primary = source.split("          - scenario: consumer-xcode-26.6", 1)[1].split("    steps:", 1)[0]
        self.assertIn('xcode: "26.6"', primary)
        self.assertIn("expected_swift_syntax_mode: prebuilt", primary)
        self.assertIn("fail-fast: false", source)
        self.assertIn("Verify expected SwiftSyntax mode", source)
        self.assertIn("actual=\"$(jq -r '.swift_syntax_mode'", source)
        self.assertIn("if-no-files-found: error", source)
        self.assertNotIn("continue-on-error:", source)
        history = (WORKFLOWS / "perf-history.yml").read_text()
        self.assertIn("on:\n  workflow_dispatch:", history)
        self.assertNotIn("  pull_request:", history)

    def test_independent_gates_preserve_failure(self):
        # GitHub's default success() would suppress both independent checks
        # after the first failure. Evaluate their actual explicit conditions.
        for workflow, name in [("macro-tests.yml", "Macro Performance Trend")]:
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
        self.assertIn("--enforce", step("Enforce macro performance baseline", "release.yml"))
        self.assertIn("always()", step("Upload candidate macro performance report", "release.yml"))

    def test_trace_is_not_an_automatic_or_release_gate(self):
        for filename in ["macro-tests.yml", "release.yml"]:
            source = (WORKFLOWS / filename).read_text()
            self.assertNotIn("Tools/measure-runtime-trace-performance.sh", source)
            self.assertNotIn("uses: ./.github/workflows/runtime-trace-diagnostics.yml", source)
        source = (WORKFLOWS / "runtime-trace-diagnostics.yml").read_text()
        triggers = source.split("on:\n", 1)[1].split("\npermissions:", 1)[0]
        self.assertEqual(re.findall(r"^  ([a-z_]+):", triggers, re.MULTILINE), ["workflow_dispatch"])
        self.assertNotIn("workflow_call:", source)
        self.assertIn("  contents: read\n", source)
        self.assertNotRegex(source, r"(?m)^\s+\S+: write\s*$")
        self.assertIn("timeout-minutes: 15", source)
        checkout = step("Checkout exact diagnostic revision", "runtime-trace-diagnostics.yml")
        self.assertIn("ref: ${{ inputs.commit_sha }}", checkout)
        self.assertIn("persist-credentials: false", checkout)
        measure = step("Measure trace diagnostics", "runtime-trace-diagnostics.yml")
        self.assertIn("INNODI_RUNTIME_TRACE_EXPECTED_SHA: ${{ inputs.commit_sha }}", measure)
        self.assertIn("INNODI_RUNTIME_TRACE_REPORT: build/runtime-trace-performance-report.json", measure)
        self.assertIn("run: Tools/measure-runtime-trace-performance.sh\n", measure)
        self.assertNotRegex(measure, r"(?m)^\s+(continue-on-error|if):")
        self.assertNotIn("||", measure.split("run:", 1)[1])
        upload = step("Upload raw trace diagnostics", "runtime-trace-diagnostics.yml")
        self.assertIn("always()", upload)
        self.assertIn("hashFiles('build/runtime-trace-performance-report.json') != ''", upload)
        self.assertIn("name: runtime-trace-diagnostics-${{ inputs.commit_sha }}", upload)
        self.assertIn("path: build/runtime-trace-performance-report.json", upload)
        self.assertIn("if-no-files-found: error", upload)

    def test_diagnostic_revision_validation_executes(self):
        body = step("Validate diagnostic revision", "runtime-trace-diagnostics.yml")
        script = body.split("run: |\n", 1)[1]
        for value, expected in [("a" * 40, 0), ("main", 1), ("A" * 40, 1), ("a" * 39, 1),
                                ("a" * 40 + "\n", 1), ("$(exit 42)", 1)]:
            result = subprocess.run(["bash", "-c", script], env={**os.environ, "CANDIDATE_SHA": value},
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, expected, result.stderr)

    def test_diagnostic_summary_never_promotes_invalid_or_missing_measurements(self):
        body = step("Explain diagnostic outcome", "runtime-trace-diagnostics.yml")
        self.assertIn("if: ${{ always() }}", body)
        self.assertIn("TRACE_OUTCOME: ${{ steps.trace.outcome }}", body)
        script = body.split("run: |\n", 1)[1]
        for outcome in ["success", "failure", "cancelled", "skipped", ""]:
            with tempfile.TemporaryDirectory(prefix="innodi-trace-summary-") as directory:
                summary = Path(directory) / "summary.md"
                result = subprocess.run(["bash", "-c", script],
                                        env={**os.environ, "TRACE_OUTCOME": outcome,
                                             "GITHUB_STEP_SUMMARY": str(summary)},
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                text = summary.read_text()
                self.assertIn("not a release gate or a trace performance guarantee", text)
                if outcome == "success":
                    self.assertIn("reference budgets only", text)
                else:
                    self.assertIn("Do not count this as a performance pass", text)
                    self.assertNotIn("satisfied", text)
                if outcome == "failure":
                    self.assertIn("Diagnostic rejected", text)
                elif outcome != "success":
                    self.assertIn("No completed diagnostic measurement", text)


if __name__ == "__main__":
    unittest.main()
