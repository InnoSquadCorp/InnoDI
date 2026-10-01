"""Execute changed-path selection, Git diff, and fail-closed negative controls."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("ci_policy", ROOT / "Tools/ci-policy.py")
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)


def pr(labels=(), action="opened"):
    return {"action": action, "pull_request": {"labels": [{"name": x} for x in labels]}}


def results(plan):
    return {"ci-plan": {"result": "success"}, **{
        job: {"result": "success" if selected else "skipped"}
        for job, selected in plan["jobs"].items()}}


class SelectionTests(unittest.TestCase):
    def test_impact_matrix(self):
        cases = [
            (["README.md"], {"policy", "documentation-contracts"}),
            ([".github/dependabot.yml"], {"policy"}),
            ([".spi.yml"], {"policy", "documentation-contracts", "docc"}),
            (["Sources/InnoDI/InnoDI.docc/MigrationGuide.md"], {"policy", "documentation-contracts", "docc"}),
            ([".github/workflows/examples.yml"], {"policy", "examples"}),
            ([".github/workflows/docs.yml"], {"policy", "docc"}),
            ([".github/workflows/remote-consumer-smoke.yml"], {"policy", "remote-consumer"}),
            (["Tests/ExternalConsumerFixtures/fail/invalid/Package.swift.fixture"], {"policy", "fast-tests", "consumer-contracts", "swift-62-compatibility", "xcode-27-compatibility"}),
            (["Tests/InnoDIBuildSupportTests/ExternalConsumerContractTests.swift"], {"policy", "fast-tests", "consumer-contracts", "swift-62-compatibility", "xcode-27-compatibility"}),
            (["Tests/InnoDIMacrosTests/MechanicalFixItTests.swift"], {"policy", "fast-tests", "macro-tests"}),
            (["Tests/InnoDIMacrosTests/DIContainerMacroTests.swift"], {"policy", "fast-tests"}),
            (["Tools/materialize-remote-consumer.py"], {"policy", "remote-consumer"}),
            ([".github/workflows/runtime-trace-diagnostics.yml"], {"policy"}),
            ([".github/workflows/dependabot-auto-merge.yml"], {"policy"}),
            ([".github/workflows/dependabot-review-notice.yml"], {"policy"}),
            (["Sources/InnoDIMacros/ContainerMacro.swift"], {"policy", "fast-tests", "examples", "documentation-contracts", "docc"}),
            (["Tools/run-coverage-gate.sh"], set(policy.JOBS)),
            (["Package.swift"], set(policy.JOBS)),
            ([".github/actions/select-xcode/action.yml"], set(policy.JOBS)),
            (["future/new-script"], set(policy.JOBS)),
            ([".github/workflows/future.yml"], set(policy.JOBS)),
            ([], set(policy.JOBS)),
        ]
        for paths, expected in cases:
            with self.subTest(paths=paths):
                plan = policy.make_plan("pull_request", pr(), paths)
                policy.validate_plan(plan)
                self.assertEqual({j for j, selected in plan["jobs"].items() if selected}, expected)

    def test_every_pr_lifecycle_and_label_transition(self):
        for action in policy.PR_ACTIONS:
            for labels in ([], ["dependencies"], ["release-validation"]):
                plan = policy.make_plan("pull_request", pr(labels, action), [".github/dependabot.yml"])
                expected = set(policy.JOBS) if "release-validation" in labels else {"policy"}
                self.assertEqual({j for j, selected in plan["jobs"].items() if selected}, expected)
                policy.evaluate(plan, results(plan))

    def test_main_queue_dispatch_keep_full_level(self):
        for name, event in [("push", {"ref": "refs/heads/main"}),
                            ("merge_group", {"action": "checks_requested"}),
                            ("workflow_dispatch", {})]:
            plan = policy.make_plan(name, event, [".github/dependabot.yml"])
            self.assertTrue(all(plan["jobs"].values()))
            self.assertTrue(plan["examples_full"])

    def test_bad_inputs_fail_instead_of_emitting_an_empty_plan(self):
        for name, event, paths in [("pull_request", {}, []),
                                   ("pull_request", {"action": "opened", "pull_request": {}}, []),
                                   ("pull_request", pr(), None),
                                   ("push", {"ref": "refs/heads/topic"}, []),
                                   ("merge_group", {"action": "destroyed"}, []),
                                   ("pull_request_target", pr(), [])]:
            with self.assertRaises(ValueError):
                policy.make_plan(name, event, paths)
        for path in ["../Package.swift", "/Package.swift", "x/../../README.md", "a\nvalue=false", "a\x00b", "a\\b", "", None]:
            with self.assertRaises(ValueError):
                policy.make_plan("pull_request", pr(), [path])

    def test_real_git_deleted_and_renamed_paths_and_missing_anchor(self):
        with tempfile.TemporaryDirectory(prefix="innodi-ci-diff-") as directory:
            root = Path(directory)
            env = dict(os.environ, GIT_AUTHOR_NAME="Fixture", GIT_COMMITTER_NAME="Fixture",
                       GIT_AUTHOR_EMAIL="fixture@example.invalid", GIT_COMMITTER_EMAIL="fixture@example.invalid")
            def git(*args):
                return subprocess.check_output(["git", "-C", directory, "-c", "commit.gpgsign=false", *args], env=env, text=True).strip()
            git("init", "-q", "-b", "main")
            (root / "Sources").mkdir()
            (root / "Sources/deleted.swift").write_text("struct Deleted {}\n")
            (root / "Sources/renamed.swift").write_text("struct Renamed {}\n" * 20)
            git("add", ".")
            git("commit", "-qm", "base")
            base = git("rev-parse", "HEAD")
            (root / "Sources/deleted.swift").unlink()
            (root / "Sources/renamed.swift").rename(root / "renamed.md")
            git("add", "-A")
            git("commit", "-qm", "delete and rename source to docs")
            head = git("rev-parse", "HEAD")
            paths = policy.changed_paths(root, base, head)
            self.assertEqual(set(paths), {"Sources/deleted.swift", "Sources/renamed.swift", "renamed.md"})
            plan = policy.make_plan("pull_request", pr(), paths)
            self.assertTrue(plan["jobs"]["fast-tests"])
            self.assertTrue(plan["jobs"]["documentation-contracts"])
            event = pr(action="synchronize")
            event["pull_request"].update(base={"sha": base}, head={"sha": head})
            event_file, output, github_output = root / "event.json", root / "plan.json", root / "github-output"
            event_file.write_text(json.dumps(event))
            cmd = ["python3", str(ROOT / "Tools/ci-policy.py"), "plan", "--event", str(event_file), "--root", directory, "--output", str(output)]
            proc = subprocess.run(cmd, env={**env, "GITHUB_EVENT_NAME": "pull_request", "GITHUB_OUTPUT": str(github_output)}, capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            policy.evaluate(json.loads(output.read_text()), results(plan))
            output.unlink()
            event["pull_request"]["head"]["sha"] = "1" * 40
            event_file.write_text(json.dumps(event))
            proc = subprocess.run(cmd, env={**env, "GITHUB_EVENT_NAME": "pull_request"}, capture_output=True, text=True)
            self.assertNotEqual(proc.returncode, 0)
            self.assertFalse(output.exists())


class RequiredTests(unittest.TestCase):
    def test_all_results_reject_failure_cancel_missing_and_wrong_skip(self):
        plan = policy.make_plan("pull_request", pr(), ["README.md"])
        policy.evaluate(plan, results(plan))
        for job in ("ci-plan", *policy.JOBS):
            expected = results(plan)[job]["result"]
            for status in ["failure", "cancelled", "timed_out", "neutral", "", None,
                           "skipped" if expected == "success" else "success"]:
                needs = results(plan)
                needs[job]["result"] = status
                with self.subTest(job=job, status=status), self.assertRaises(ValueError):
                    policy.evaluate(plan, needs)
            needs = results(plan)
            del needs[job]
            with self.assertRaises(ValueError):
                policy.evaluate(plan, needs)

    def test_plan_tampering_and_incomplete_evidence_fail_closed(self):
        original = policy.make_plan("pull_request", pr(), ["Package.swift"])
        mutations = [lambda p: p["jobs"].pop("sanitizers"),
                     lambda p: p["jobs"].update(sanitizers=False),
                     lambda p: p["jobs"].update(policy=False),
                     lambda p: p["jobs"].update(policy="true"),
                     lambda p: p.update(schema=2),
                     lambda p: p.update(schema=True),
                     lambda p: p.update(lane="unrecognized"),
                     lambda p: p.update(examples_full=False),
                     lambda p: p["changes"][0].update(reason="documentation")]
        for mutate in mutations:
            plan = copy.deepcopy(original)
            mutate(plan)
            with self.assertRaises(ValueError):
                policy.evaluate(plan, results(plan))
        for value in ["", "{}", "null", "{invalid", json.dumps({**original, "unknown": True})]:
            proc = subprocess.run(["python3", str(ROOT / "Tools/ci-policy.py"), "evaluate"],
                                  env={**os.environ, "CI_PLAN": value, "CI_NEEDS": json.dumps(results(original))}, capture_output=True)
            self.assertNotEqual(proc.returncode, 0)

    def test_matrix_or_reusable_child_failure_and_unexpected_skip_reject(self):
        for result in ["failure", "cancelled", "skipped", "success"]:
            needs = {"release-compatibility": {"result": result}}
            proc = subprocess.run(["python3", str(ROOT / "Tools/ci-policy.py"), "require", "--jobs", "release-compatibility"],
                                  env={**os.environ, "CI_NEEDS": json.dumps(needs)}, capture_output=True)
            self.assertEqual(proc.returncode == 0, result == "success")
        needs = {"sample-app": {"result": "success"}, "swiftui-example": {"result": "skipped"},
                 "preview-injection-example": {"result": "skipped"}}
        command = ["python3", str(ROOT / "Tools/ci-policy.py"), "require", "--jobs", "sample-app", "--skipped", "swiftui-example", "preview-injection-example"]
        proc = subprocess.run(command, env={**os.environ, "CI_NEEDS": json.dumps(needs)}, capture_output=True)
        self.assertEqual(proc.returncode, 0)
        needs["swiftui-example"]["result"] = "failure"
        proc = subprocess.run(command, env={**os.environ, "CI_NEEDS": json.dumps(needs)}, capture_output=True)
        self.assertNotEqual(proc.returncode, 0)

    def test_workflows_bind_plan_needs_and_candidate_publication(self):
        source = (ROOT / ".github/workflows/macro-tests.yml").read_text()
        import re
        all_jobs = set(re.findall(r"^  ([A-Za-z0-9_-]+):$", source.split("\njobs:\n", 1)[1], re.MULTILINE))
        self.assertEqual(all_jobs, set(policy.JOBS) | {"ci-plan", "ci-required", "append-perf-history"})
        self.assertNotIn("    paths:", source)
        self.assertIn("  merge_group:\n    types: [checks_requested]", source)
        aggregate = source.split("  ci-required:\n", 1)[1].split("  append-perf-history:\n", 1)[0]
        self.assertIn("if: ${{ always() }}", aggregate)
        for job in policy.JOBS:
            self.assertIn("      - " + job + "\n", aggregate)
            if job != "policy":
                self.assertIn(f"if: needs.ci-plan.outputs.{job} == 'true'", source)
        release = (ROOT / ".github/workflows/release.yml").read_text()
        self.assertIn("      publish:\n", release)
        self.assertIn("        default: false\n        type: boolean", release)
        for job in ("stage-release", "exact-tag-consumer", "publish-release"):
            self.assertIn(f"  {job}:\n    if: inputs.publish\n", release)
        self.assertIn("      - candidate-required\n", release)
        self.assertIn("environment: release", release)
        self.assertIn("fail-fast: false", release)
        self.assertIn("scenario: xcode-27", release)
        for name in ("macro-tests.yml", "examples.yml", "docc-validation.yml", "remote-consumer-smoke.yml"):
            text = (ROOT / ".github/workflows" / name).read_text()
            self.assertNotIn("pull_request_target", text)
            self.assertNotIn("secrets.", text)
            self.assertNotIn("continue-on-error:", text)
        docs = (ROOT / ".github/workflows/docs.yml").read_text()
        self.assertIn("github.event.workflow_run.event == 'push'", docs)
        self.assertIn("github.event.workflow_run.head_branch == 'main'", docs)
        self.assertNotIn("actions/checkout@", docs)
        self.assertIn("EXPECTED_SHA: ${{ github.event.workflow_run.head_sha }}", docs)
        self.assertIn('if [[ "$EXPECTED_SHA" != "$remote_main" ]]', docs)
        self.assertIn("github.event.merge_group.head_ref ||", source)
        self.assertIn(" || github.ref }}", source)
        remote = (ROOT / ".github/workflows/remote-consumer-smoke.yml").read_text()
        self.assertIn("            Tools\n", remote)
        self.assertNotIn("            Tools/materialize-remote-consumer.py\n", remote)

    def test_pages_rejects_stale_missing_and_unreadable_main_before_deploy(self):
        source = (ROOT / ".github/workflows/docs.yml").read_text()
        step = source.split("      - name: Reject stale main documentation\n", 1)[1].split("      - name: Deploy to GitHub Pages", 1)[0]
        script = step.split("        run: |\n", 1)[1]
        with tempfile.TemporaryDirectory(prefix="innodi-pages-gate-") as directory:
            git = Path(directory) / "git"
            git.write_text('#!/bin/sh\n[ "$FIXTURE_GIT_FAIL" = 1 ] && exit 128\nprintf "%s refs/heads/main\\n" "$FIXTURE_REMOTE_SHA"\n')
            git.chmod(0o755)
            for expected, remote, failed, success in [("a" * 40, "a" * 40, "0", True),
                                                       ("a" * 40, "b" * 40, "0", False),
                                                       ("a" * 40, "", "0", False),
                                                       ("", "", "0", False),
                                                       ("a" * 40, "a" * 40, "1", False)]:
                result = subprocess.run(["bash", "-c", script], env={**os.environ,
                    "PATH": directory + ":" + os.environ["PATH"], "EXPECTED_SHA": expected,
                    "REPOSITORY": "InnoSquadCorp/InnoDI", "FIXTURE_REMOTE_SHA": remote,
                    "FIXTURE_GIT_FAIL": failed}, capture_output=True, text=True)
                self.assertEqual(result.returncode == 0, success, result.stderr)


if __name__ == "__main__":
    unittest.main()
