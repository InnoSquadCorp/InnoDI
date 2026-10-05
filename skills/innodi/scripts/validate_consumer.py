#!/usr/bin/env python3
"""Build an isolated copy of the exact-release consumer and record real evidence."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scratch-path", type=Path, help="External SwiftPM build/cache directory; retained after the run")
    args = parser.parse_args()
    skill = Path(__file__).resolve().parents[1]
    scratch = (args.scratch_path or Path(tempfile.mkdtemp(prefix="innodi-skill-"))).resolve()
    if scratch == skill or skill in scratch.parents:
        parser.error("Choose a scratch directory outside the skill so installed assets stay unchanged")
    scratch.mkdir(parents=True, exist_ok=True)
    runs = scratch / "skill-runs"
    runs.mkdir(exist_ok=True)
    run_dir = Path(tempfile.mkdtemp(prefix="run-", dir=runs))
    evidence_file = run_dir / "evidence.json"
    evidence = {"status": "running", "started_at": datetime.now(timezone.utc).isoformat(), "commands": [], "run_directory": str(run_dir)}

    def command(label, argv):
        log = run_dir / (label + ".log")
        entry = {"argv": [str(value) for value in argv], "log": str(log)}
        evidence["commands"].append(entry)
        with log.open("w") as stream:
            result = subprocess.run(entry["argv"], stdout=stream, stderr=subprocess.STDOUT, check=False)
        entry["exit_code"] = result.returncode
        if result.returncode:
            raise RuntimeError(f"{label} failed ({result.returncode}); see {log}")
        return log.read_text(errors="replace").strip()

    def check(condition, message):
        if not condition:
            raise RuntimeError(message)

    def flatten(node):
        yield node
        for dependency in node.get("dependencies", []):
            yield from flatten(dependency)

    try:
        check(sys.platform == "darwin", "This fixture requires an Apple Swift development host")
        support = json.loads((skill / "references/support.json").read_text())
        evidence["swift"] = command("swift-version", ["swift", "--version"])
        evidence["xcode"] = command("xcode-version", ["xcodebuild", "-version"])
        source = skill / "assets/consumer"
        evidence["source_sha256"] = {
            str(path.relative_to(source)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(source.rglob("*"))
            if path.is_file() and path.suffix in (".swift", ".resolved")
            and not {".build", ".swiftpm"}.intersection(path.relative_to(source).parts)
        }
        package = run_dir / "consumer"
        shutil.copytree(source, package, ignore=shutil.ignore_patterns(".build", ".swiftpm", ".DS_Store"))
        options = ["--package-path", package, "--scratch-path", scratch]
        command("resolve", ["swift", "package", *options, "resolve"])
        pins = {pin["identity"]: pin for pin in json.loads((package / "Package.resolved").read_text())["pins"]}
        graph_text = command("dependency-graph", ["swift", "package", *options, "show-dependencies", "--format", "json"])
        graph = {node["identity"]: node for node in flatten(json.loads(graph_text))}
        expected = {"innodi": support, "swift-syntax": support["swift_syntax"]}
        check(set(pins) == set(expected), "Unexpected dependency pins; review the fixture's dependency graph")
        check(set(graph) == set(expected) | {"consumer"}, "Unexpected package in active dependency graph")
        evidence["dependencies"] = {}
        for identity, baseline in expected.items():
            pin, node = pins[identity], graph[identity]
            check(pin["kind"] == "remoteSourceControl", f"{identity} is not a remote release pin")
            check(pin["location"] == baseline["repository"], f"{identity} source location changed")
            check(pin["state"] == {"revision": baseline["revision"], "version": baseline["version"]}, f"{identity} lock pin differs from support record")
            check(node["url"] == baseline["repository"] and node["version"] == baseline["version"], f"{identity} active graph differs from lock pin")
            checkout = Path(node["path"]).resolve()
            check((scratch / "checkouts").resolve() in checkout.parents, f"{identity} resolved outside managed checkouts; possible local override")
            head = command(identity + "-head", ["git", "-C", checkout, "rev-parse", "HEAD"])
            check(head == baseline["revision"], f"{identity} checkout revision differs from release")
            status = command(identity + "-status", ["git", "-C", checkout, "status", "--porcelain", "--untracked-files=all"])
            check(not status, f"{identity} checkout has local modifications")
            evidence["dependencies"][identity] = {"version": node["version"], "revision": head, "checkout": str(checkout), "clean": True}
        command("swift-test", ["swift", "test", *options, "--no-parallel", "-Xswiftc", "-strict-concurrency=complete", "-Xswiftc", "-warnings-as-errors"])
        evidence["status"] = "passed"
    except (OSError, RuntimeError, ValueError, KeyError) as error:
        evidence["status"] = "failed"
        evidence["error"] = str(error)
    finally:
        evidence["finished_at"] = datetime.now(timezone.utc).isoformat()
        evidence_file.write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps({"status": evidence["status"], "evidence": str(evidence_file), "error": evidence.get("error")}, indent=2))
    return 0 if evidence["status"] == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())
