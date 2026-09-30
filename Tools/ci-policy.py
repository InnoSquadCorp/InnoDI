#!/usr/bin/env python3
"""Repository-local CI selection and fail-closed result evaluation (stdlib only)."""
import argparse
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys

JOBS = ("policy", "fast-tests", "macro-tests", "sanitizers", "swift-62-compatibility",
        "xcode-27-compatibility", "apple-platform-builds", "path-identity", "examples",
        "documentation-contracts", "docc", "remote-consumer")
EXHAUSTIVE = {"macro-tests", "sanitizers", "swift-62-compatibility", "xcode-27-compatibility",
              "apple-platform-builds", "path-identity"}
SHA = re.compile(r"[0-9a-f]{40}")
PR_ACTIONS = {"opened", "synchronize", "reopened", "labeled", "unlabeled", "ready_for_review"}
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
}


def path_impact(path):
    if not isinstance(path, str) or not path or "\x00" in path or "\n" in path:
        raise ValueError("invalid changed path")
    parts = PurePosixPath(path).parts
    if path.startswith("/") or any(p in ("..", ".") for p in parts) or "\\" in path:
        raise ValueError("changed path must be a repository-relative POSIX path")
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
        return {"fast-tests", "swift-62-compatibility", "xcode-27-compatibility"}, "clean consumer contract"
    if path.startswith("Tests/InnoDIMigrationCoreTests/"):
        return {"fast-tests", "macro-tests"}, "migration including fresh consumer"
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
        labels = pr.get("labels")
        if not isinstance(labels, list) or any(not isinstance(x, dict) or not isinstance(x.get("name"), str) for x in labels):
            raise ValueError("missing or malformed PR labels")
        lane = "release-validation" if any(x["name"] == "release-validation" for x in labels) else "fast"
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
    return {"schema": 1, "lane": lane, "jobs": {j: j in selected for j in JOBS},
            "examples_full": lane != "fast" or "macro-tests" in selected or any(
                r["reason"] in ("example", "workflow:examples.yml", "unknown path (full fallback)") for r in reasons),
            "changes": reasons}


def validate_plan(plan):
    if not isinstance(plan, dict) or set(plan) != {"schema", "lane", "jobs", "examples_full", "changes"}:
        raise ValueError("missing or unknown plan fields")
    if type(plan["schema"]) is not int or plan["schema"] != 1 or plan["lane"] not in ("fast", "full", "release-validation"):
        raise ValueError("unsupported plan schema/lane")
    if not isinstance(plan["jobs"], dict) or set(plan["jobs"]) != set(JOBS) or any(type(v) is not bool for v in plan["jobs"].values()):
        raise ValueError("plan must declare every job with a boolean")
    if plan["jobs"]["policy"] is not True or type(plan["examples_full"]) is not bool:
        raise ValueError("policy must always run")
    if not isinstance(plan["changes"], list):
        raise ValueError("invalid change evidence")
    if plan["lane"] != "fast" and not all(plan["jobs"].values()):
        raise ValueError("full lanes cannot opt out of required jobs")
    if not plan["changes"] and not all(plan["jobs"].values()):
        raise ValueError("empty change evidence requires full validation")
    for change in plan["changes"]:
        if not isinstance(change, dict) or set(change) != {"path", "reason"}:
            raise ValueError("invalid change record")
        impact, reason = path_impact(change["path"])
        if change["reason"] != reason or any(not plan["jobs"][j] for j in impact):
            raise ValueError("plan suppresses changed-path requirements")
    examples_full = plan["lane"] != "fast" or plan["jobs"]["macro-tests"] or any(
        c["reason"] in ("example", "workflow:examples.yml", "unknown path (full fallback)") for c in plan["changes"])
    if plan["examples_full"] != examples_full:
        raise ValueError("plan suppresses extended example requirements")


def evaluate(plan, needs):
    validate_plan(plan)
    if not isinstance(needs, dict) or set(needs) != set(JOBS) | {"ci-plan"}:
        raise ValueError("missing or unexpected CI result")
    required = {"ci-plan": True, **plan["jobs"]}
    for job, selected in required.items():
        result = needs[job].get("result") if isinstance(needs[job], dict) else None
        expected = "success" if selected else "skipped"
        if result != expected:
            raise ValueError(f"{job}: expected {expected}, got {result!r}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    plan_cmd = sub.add_parser("plan")
    plan_cmd.add_argument("--event", required=True, type=Path)
    plan_cmd.add_argument("--root", type=Path, default=Path("."))
    plan_cmd.add_argument("--output", type=Path, required=True)
    evaluate_cmd = sub.add_parser("evaluate")
    evaluate_cmd.add_argument("--plan-json", default=os.environ.get("CI_PLAN", ""))
    evaluate_cmd.add_argument("--needs-json", default=os.environ.get("CI_NEEDS", ""))
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
                paths = changed_paths(args.root, pr["base"]["sha"], pr["head"]["sha"])
            plan = make_plan(event_name, event, paths)
            validate_plan(plan)
            payload = json.dumps(plan, separators=(",", ":"))
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(payload + "\n")
            if "GITHUB_OUTPUT" in os.environ:
                with open(os.environ["GITHUB_OUTPUT"], "a") as stream:
                    stream.write("plan=" + payload + "\n")
                    for job, selected in plan["jobs"].items():
                        stream.write(job + "=" + str(selected).lower() + "\n")
                    stream.write("examples_full=" + str(plan["examples_full"]).lower() + "\n")
            print(json.dumps(plan, indent=2))
        elif args.command == "evaluate":
            evaluate(json.loads(args.plan_json), json.loads(args.needs_json))
            print("CI Required: every planned job succeeded; only declared non-targets skipped.")
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
