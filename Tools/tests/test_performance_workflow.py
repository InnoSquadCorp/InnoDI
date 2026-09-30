"""Exercise the checked-in CI conditions without dispatching a workflow."""
from pathlib import Path
import re
import json
import textwrap
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
    def test_required_isolated_prebuilt_proof_rejects_source_and_missing_metrics(self):
        body = step("Verify isolated primary macro prebuilt", "remote-consumer-smoke.yml")
        self.assertIn('--target consumer --bindings 100 --keep-user-cache', body)
        self.assertIn('git -C "$benchmark_root" rev-parse HEAD', body)
        self.assertIn('== "$INNODI_REVISION"', body)
        condition = next(line.strip() for line in body.splitlines() if line.strip().startswith('[[ "$(jq'))
        with tempfile.TemporaryDirectory() as directory:
            metrics = Path(directory) / 'innodi-isolated-primary.json'
            for mode in ['prebuilt', 'source', 'prebuilt-unavailable', 'not-observed', None]:
                metrics.write_text(json.dumps({'swift_syntax_mode':mode}))
                result = subprocess.run(['bash','-c',condition], env={**os.environ,'RUNNER_TEMP':directory}, capture_output=True)
                self.assertEqual(result.returncode == 0, mode == 'prebuilt')

    def test_isolated_proof_uses_unique_exact_dependency_checkout(self):
        body = step("Verify isolated primary macro prebuilt", "remote-consumer-smoke.yml")
        code = textwrap.dedent(body.split("<<'PY'\n",1)[1].split('\n          PY\n',1)[0])
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            graph = base / 'graph.json'
            good = dict(identity='innodi', path=str(base / '.build/checkouts/InnoDI'))
            for dependencies, ok in [([good],True), ([],False), ([good,good],False),
                                     ([dict(good,path=str(base/'foreign'))],False)]:
                graph.write_text(json.dumps({'dependencies':dependencies}))
                result = subprocess.run(['python3','-c',code,str(graph),directory],
                          env={**os.environ,'INNODI_CONSUMER_IDENTITY':'innodi'},capture_output=True)
                self.assertEqual(result.returncode == 0, ok)

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

    def test_pull_requests_report_while_main_and_dispatch_enforce(self):
        # Evaluate the checked-in mode expressions for every trigger. Only a
        # pull request may downgrade the gates to reports.
        expectations = {
            "Macro Performance Check": ("MACRO_PERFORMANCE_MODE",
                                        {"pull_request": "--report-only", "push": "--enforce",
                                         "merge_group": "--enforce",
                                         "workflow_dispatch": "--enforce"}),
            "Macro Performance Trend": ("TREND_MODE",
                                        {"pull_request": "--report-only", "push": "",
                                         "merge_group": "", "workflow_dispatch": ""}),
        }
        for name, (variable, by_event) in expectations.items():
            body = step(name)
            match = re.search(variable + r": \$\{\{ (.+) \}\}", body)
            self.assertIsNotNone(match, name)
            self.assertNotIn("continue-on-error", body)
            for event, expected in by_event.items():
                actual = eval(
                    match.group(1).replace("github.event_name", repr(event))
                    .replace("&&", "and").replace("||", "or"),
                    {"__builtins__": {}},
                )
                self.assertEqual(actual, expected, (name, event))

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
