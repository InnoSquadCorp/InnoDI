#!/usr/bin/env python3
"""Repository-local CI selection and fail-closed result evaluation (stdlib only)."""
import argparse
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys

JOBS = ("policy", "fast-tests", "macro-tests", "consumer-contracts", "sanitizers",
        "swift-62-compatibility", "xcode-27-compatibility", "apple-platform-builds",
        "path-identity", "examples", "documentation-contracts", "docc", "remote-consumer")
EXHAUSTIVE = {"macro-tests", "consumer-contracts", "sanitizers", "swift-62-compatibility",
              "xcode-27-compatibility", "apple-platform-builds", "path-identity"}
SHA = re.compile(r"[0-9a-f]{40}")
PR_ACTIONS = {"opened", "synchronize", "reopened", "labeled", "unlabeled", "edited"}


def reuse_policy():
    spec = importlib.util.spec_from_file_location("main_ci_reuse_policy", Path(__file__).with_name("main-ci-reuse-policy.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def reused_jobs(plan, proof):
    reuse = reuse_policy()
    reuse.validate_proof(proof)
    if not proof:
        return set()
    if plan["lane"] != "full" or plan["jobs"] != {job: job != "fast-tests" for job in JOBS}:
        raise ValueError("reuse must preserve every full logical requirement")
    return set(reuse.REUSED_JOBS)


WORKFLOW_IMPACT = {
    "macro-tests.yml": set(JOBS),  # Orchestration changes must prove every branch.
    "examples.yml": {"examples"},
    "docs.yml": {"docc"},
    "docc-validation.yml": {"docc"},
    "remote-consumer-smoke.yml": {"remote-consumer"},
    "release.yml": EXHAUSTIVE | {"fast-tests", "examples", "documentation-contracts", "docc", "remote-consumer"},
    # Manual diagnostics/history are statically checked by policy; these are
    # not calibrated release gates. Do not turn timings into a PR requirement.
    "runtime-trace-diagnostics.yml": set(),
    "cold-build-benchmark.yml": set(),
    "perf-history.yml": set(),
    "dependabot-auto-merge.yml": set(),
    "dependabot-review-notice.yml": set(),
}



def prose_module():
    spec = importlib.util.spec_from_file_location("ci_prose", Path(__file__).with_name("ci_prose.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def apply_prose(plan, root, event, paths):
    if plan["lane"] != "fast" or plan.get("requested"):
        return plan
    pr = event.get("pull_request", {})
    proof = prose_module().inspect(root, pr.get("base", {}).get("sha"), pr.get("head", {}).get("sha"), paths)
    if not proof:
        if paths and all(prose_module().candidate(path) for path in paths):
            # Code fences, file modes, missing blobs, and deletions are not prose evidence.
            return make_plan("pull_request", event, paths + ["__unproven_documentation_full_fallback__"])
        return plan
    plan["prose_only"] = proof
    plan["jobs"] = {job: job == "policy" for job in JOBS}
    if "examples_full" in plan:
        plan["examples_full"] = False
    return plan


def path_impact(path):
    if not isinstance(path, str) or not path or "\x00" in path or "\n" in path:
        raise ValueError("invalid changed path")
    parts = PurePosixPath(path).parts
    if path.startswith("/") or any(p in ("..", ".") for p in parts) or "\\" in path:
        raise ValueError("changed path must be a repository-relative POSIX path")
    if prose_module().RELEASE.search(path):
        return set(JOBS), "release metadata (full fallback)"
    if path in ("Package.swift", "Package.resolved") or path.startswith(".github/actions/"):
        return set(JOBS), "shared package/toolchain"
    if path.startswith(("Sources/", "Plugins/")) and ".docc/" not in path:
        return {"fast-tests", "examples", "documentation-contracts", "docc"}, "source/plugin"
    if path.startswith("Tests/RemoteConsumerSmoke/"):
        return {"fast-tests", "remote-consumer"}, "exact-revision fixture"
    if path == "Tools/materialize-remote-consumer.py":
        return {"remote-consumer"}, "exact-revision consumer tool"
    if path.startswith("Tests/ExternalConsumerFixtures/") or path in (
            "Tests/InnoDIBuildSupportTests/ExternalConsumerContractTests.swift",
            "Tests/InnoDIBuildSupportTests/StrictConcurrencyBuildTests.swift"):
        return {"fast-tests", "consumer-contracts", "swift-62-compatibility",
                "xcode-27-compatibility"}, "clean consumer contract"
    if path.startswith("Tests/InnoDIMigrationCoreTests/"):
        return {"fast-tests", "macro-tests"}, "migration including fresh consumer"
    # The fast lane skips this file's clean consumer build; the coverage gate runs it.
    if path == "Tests/InnoDIMacrosTests/MechanicalFixItTests.swift":
        return {"fast-tests", "macro-tests"}, "fix-it including consumer build"
    if path.startswith("Tests/"):
        return {"fast-tests"}, "test/consumer fixture"
    if path.startswith("Examples/"):
        return {"examples"}, "example"
    if path.startswith(".github/workflows/"):
        name = path.rsplit("/", 1)[1]
        if name in WORKFLOW_IMPACT:
            return WORKFLOW_IMPACT[name], "workflow:" + name
    if path in (".github/dependabot.yml", ".github/actionlint.yaml") or path.startswith((".github/ISSUE_TEMPLATE/", "Tools/tests/")):
        return set(), "policy"
    if path in (".github/PULL_REQUEST_TEMPLATE.md", ".github/CODEOWNERS", "LICENSE", "SECURITY.md"):
        return set(), "public operations"
    if path == ".spi.yml" or path.startswith("Tools/docc/") or path in (
            "Tools/generate-docc.sh", "Tools/package-release-docc.sh") or ".docc/" in path:
        return {"documentation-contracts", "docc"}, "DocC/SPI"
    if path.startswith("Tools/check-docs-") or path == "Tools/check-localized-readme-sync.sh":
        return {"documentation-contracts"}, "documentation checker"
    if path.startswith("Tools/check-ci-") or path in ("Tools/ci-policy.py", "Tools/check-public-operations.py"):
        return set(JOBS), "shared CI policy"
    if path.startswith("Tools/"):
        return set(JOBS), "shared build/release tool"
    if path.startswith("docs/") or (path.endswith(".md") and "/" not in path):
        return {"documentation-contracts"}, "documentation"
    return set(JOBS), "unknown path (full fallback)"


def changed_paths(root, base, head):
    if not SHA.fullmatch(base or "") or not SHA.fullmatch(head or ""):
        raise ValueError("diff anchors must be exact lowercase commit SHAs")
    raw = subprocess.check_output(["git", "-C", str(root), "diff", "--name-status", "-z",
                                   "--find-renames", base + "..." + head])
    tokens = raw.decode("utf-8", errors="strict").split("\x00")
    if tokens[-1] != "":
        raise ValueError("truncated Git changed-file stream")
    tokens.pop()
    paths = []
    while tokens:
        status = tokens.pop(0)
        if not re.fullmatch(r"[ACDMRTUXB][0-9]*", status):
            raise ValueError("unknown Git file status")
        count = 2 if status[0] in "RC" else 1
        if len(tokens) < count:
            raise ValueError("missing changed-file path")
        # Renames/copies must include BOTH old and new paths; deleted files
        # remain in the impact set even though they no longer exist on disk.
        paths.extend(tokens[:count])
        del tokens[:count]
    return paths


def make_plan(event_name, event, paths):
    if not isinstance(event, dict) or not isinstance(paths, list):
        raise ValueError("event and changed paths have invalid types")
    lane = "full"
    if event_name == "pull_request":
        pr = event.get("pull_request", {})
        if event.get("action") not in PR_ACTIONS or not isinstance(pr, dict):
            raise ValueError("unsupported PR event")
        if event["action"] == "edited" and not event.get("changes", {}).get("base"):
            raise ValueError("metadata-only PR edit has no validation plan")
        labels = pr.get("labels")
        if not isinstance(labels, list) or any(not isinstance(x, dict) or not isinstance(x.get("name"), str) for x in labels):
            raise ValueError("missing or malformed PR labels")
        # Match GitHub's case-insensitive native event predicates.
        lane = "release-validation" if any(x["name"].lower() == "release-validation" for x in labels) else "fast"
    elif event_name == "push":
        if event.get("ref") != "refs/heads/main":
            raise ValueError("CI push must target main")
    elif event_name == "merge_group":
        if event.get("action") != "checks_requested":
            raise ValueError("unsupported merge queue event")
    elif event_name != "workflow_dispatch":
        raise ValueError("unsupported CI event")
    selected = {"policy"}
    reasons = []
    for path in paths:
        impact, reason = path_impact(path)
        selected.update(impact)
        reasons.append({"path": path, "reason": reason})
    # An empty/missing diff is never evidence that no verification is needed.
    if lane != "fast" or not paths:
        selected = set(JOBS)
    # Exhaustive runs the same strict serialized suite with fewer skips and
    # every fast API/DAG/report command; the executable superset test guards
    # this relationship against future unique fast checks.
    if "macro-tests" in selected:
        selected.discard("fast-tests")
    return {"schema": 1, "lane": lane, "jobs": {j: j in selected for j in JOBS},
            "examples_full": lane != "fast" or "macro-tests" in selected or any(
                r["reason"] in ("example", "workflow:examples.yml", "unknown path (full fallback)") for r in reasons),
            "changes": reasons}


def product_scope_module():
    spec = importlib.util.spec_from_file_location("product_test_scope", Path(__file__).with_name("ci_product_test_scope.py"))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def apply_product_tests(plan, root, event, paths):
    if plan.get("prose_only") or plan["lane"] != "fast" or plan["jobs"]["macro-tests"]:
        return plan
    proof = product_scope_module().prove(root, event, os.environ)
    if proof is None:
        return plan
    scope = product_scope_module()
    scope.validate(proof, paths)
    return {**plan, "product_test_scope": proof,
            "jobs": {job: job in scope.required_jobs(proof["product"]) for job in JOBS},
            "examples_full": proof["product"] == "InnoDISwiftUI"}


def validate_plan(plan):
    if not isinstance(plan, dict) or (set(plan) - {"prose_only", "product_test_scope"}) != {"schema", "lane", "jobs", "examples_full", "changes"}:
        raise ValueError("missing or unknown plan fields")
    product = plan.get("product_test_scope")
    if "product_test_scope" in plan:
        if "prose_only" in plan or plan.get("lane") != "fast" or not isinstance(plan.get("changes"), list):
            raise ValueError("invalid product-only PR lane")
        scope = product_scope_module()
        scope.validate(product, [change.get("path") for change in plan["changes"] if isinstance(change, dict)])
        if plan.get("jobs") != {job: job in scope.required_jobs(product["product"]) for job in JOBS}:
            raise ValueError("product lane suppresses required scoped/shared contracts")
    prose = plan.get("prose_only")
    if "prose_only" in plan:
        if not isinstance(plan.get("changes"), list):
            raise ValueError("invalid prose changes")
        prose_module().validate(prose, [change.get("path") for change in plan["changes"] if isinstance(change, dict)])
        if plan.get("lane") != "fast" or plan.get("requested") or plan.get("jobs") != {job: job == "policy" for job in JOBS}:
            raise ValueError("prose-only lane must require exactly static policy")
    if type(plan["schema"]) is not int or plan["schema"] != 1 or plan["lane"] not in ("fast", "full", "release-validation"):
        raise ValueError("unsupported plan schema/lane")
    if not isinstance(plan["jobs"], dict) or set(plan["jobs"]) != set(JOBS) or any(type(v) is not bool for v in plan["jobs"].values()):
        raise ValueError("plan must declare every job with a boolean")
    if plan["jobs"]["policy"] is not True or type(plan["examples_full"]) is not bool:
        raise ValueError("policy must always run")
    if not isinstance(plan["changes"], list):
        raise ValueError("invalid change evidence")
    if plan["jobs"]["macro-tests"] and plan["jobs"]["fast-tests"]:
        raise ValueError("exhaustive contracts must replace the duplicate fast lane")
    full = {j: j != "fast-tests" for j in JOBS}
    if plan["lane"] != "fast" and plan["jobs"] != full:
        raise ValueError("full lanes cannot opt out of required contracts")
    if not plan["changes"] and plan["jobs"] != full:
        raise ValueError("empty change evidence requires full validation")
    for change in plan["changes"]:
        if not isinstance(change, dict) or set(change) != {"path", "reason"}:
            raise ValueError("invalid change record")
        impact, reason = path_impact(change["path"])
        if plan["jobs"]["macro-tests"]:
            impact = impact - {"fast-tests"}
        if change["reason"] != reason or (not prose and not product and any(not plan["jobs"][j] for j in impact)):
            raise ValueError("plan suppresses changed-path requirements")
    examples_full = plan["lane"] != "fast" or plan["jobs"]["macro-tests"] or any(
        c["reason"] in ("example", "workflow:examples.yml", "unknown path (full fallback)") for c in plan["changes"])
    if prose:
        examples_full = False
    if product:
        examples_full = product["product"] == "InnoDISwiftUI"
    if plan["examples_full"] != examples_full:
        raise ValueError("plan suppresses extended example requirements")


def evaluate(plan, needs, proof=None, root=None, event=None):
    validate_plan(plan)
    if "prose_only" in plan:
        if root is None or not isinstance(event, dict):
            raise ValueError("prose-only result requires immutable Git revalidation")
        prose_module().revalidate(root, event, plan["prose_only"], [change["path"] for change in plan["changes"]])
    if "product_test_scope" in plan:
        if root is None or not isinstance(event, dict):
            raise ValueError("product-only result requires exact Git/qualification revalidation")
        product_scope_module().revalidate(root, event, os.environ, plan["product_test_scope"], [change["path"] for change in plan["changes"]])
    reused = reused_jobs(plan, proof or {})
    if not isinstance(needs, dict) or set(needs) != set(JOBS) | {"ci-plan"}:
        raise ValueError("missing or unexpected CI result")
    required = {"ci-plan": True, **plan["jobs"]}
    for job, selected in required.items():
        result = needs[job].get("result") if isinstance(needs[job], dict) else None
        expected = "success" if selected and job not in reused else "skipped"
        if result != expected:
            raise ValueError(f"{job}: expected {expected}, got {result!r}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    plan_cmd = sub.add_parser("plan")
    plan_cmd.add_argument("--event", required=True, type=Path)
    plan_cmd.add_argument("--root", type=Path, default=Path("."))
    plan_cmd.add_argument("--output", type=Path, required=True)
    plan_cmd.add_argument("--reuse-proof-json", default=os.environ.get("CI_REUSE", "{}"))
    evaluate_cmd = sub.add_parser("evaluate")
    evaluate_cmd.add_argument("--plan-json", default=os.environ.get("CI_PLAN", ""))
    evaluate_cmd.add_argument("--needs-json", default=os.environ.get("CI_NEEDS", ""))
    evaluate_cmd.add_argument("--reuse-proof-json", default=os.environ.get("CI_REUSE", "{}"))
    strict_cmd = sub.add_parser("require")
    strict_cmd.add_argument("--jobs", nargs="+", required=True)
    strict_cmd.add_argument("--skipped", nargs="*", default=[])
    strict_cmd.add_argument("--needs-json", default=os.environ.get("CI_NEEDS", ""))
    args = parser.parse_args()
    try:
        if args.command == "plan":
            event = json.loads(args.event.read_text())
            event_name = os.environ["GITHUB_EVENT_NAME"]
            paths = []
            if event_name == "pull_request":
                pr = event["pull_request"]
                try:
                    paths = changed_paths(args.root, pr["base"]["sha"], pr["head"]["sha"])
                except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
                    print(f"Changed-file evidence unavailable; selecting full validation: {error}", file=sys.stderr)
                    paths = ["__diff_unavailable_full_fallback__"]
            plan = apply_prose(make_plan(event_name, event, paths), args.root, event, paths)
            plan = apply_product_tests(plan, args.root, event, paths)
            validate_plan(plan)
            proof = json.loads(args.reuse_proof_json)
            reused = reused_jobs(plan, proof)
            if reused and (event_name != "push" or proof["main"] != event.get("after")):
                raise ValueError("reused proof is not for this main push")
            payload = json.dumps(plan, separators=(",", ":"))
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(payload + "\n")
            if "GITHUB_OUTPUT" in os.environ:
                with open(os.environ["GITHUB_OUTPUT"], "a") as stream:
                    stream.write("plan=" + payload + "\n")
                    for job, selected in plan["jobs"].items():
                        # Keep jobs[] as the complete logical contract; only
                        # physical execution is suppressed by explicit proof.
                        stream.write(job + "=" + str(selected and job not in reused).lower() + "\n")
                    stream.write("examples_full=" + str(plan["examples_full"]).lower() + "\n")
            print(json.dumps(plan, indent=2))
        elif args.command == "evaluate":
            proof = json.loads(args.reuse_proof_json)
            reuse = reuse_policy()
            reuse.validate_proof(proof)
            if proof:
                event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
                # Re-read authoritative metadata after the main jobs finish.
                # Lost/raced proof is an aggregate failure, never a green skip.
                reuse.revalidate(proof, event, os.environ)
            plan = json.loads(args.plan_json)
            event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text()) if "prose_only" in plan or "product_test_scope" in plan else None
            evaluate(plan, json.loads(args.needs_json), proof, Path("."), event)
            print("CI Required: every contract has fresh success or revalidated exact-tree PR evidence; no unexplained skips.")
        else:
            needs = json.loads(args.needs_json)
            all_jobs = args.jobs + args.skipped
            if len(set(all_jobs)) != len(all_jobs) or set(needs) != set(all_jobs):
                raise ValueError("missing or unexpected required result")
            for job in args.jobs:
                if not isinstance(needs[job], dict) or needs[job].get("result") != "success":
                    raise ValueError(f"{job}: required result is not success")
            for job in args.skipped:
                if not isinstance(needs[job], dict) or needs[job].get("result") != "skipped":
                    raise ValueError(f"{job}: non-target result must be skipped")
            print("All required validation jobs succeeded.")
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print(f"CI policy rejected: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
