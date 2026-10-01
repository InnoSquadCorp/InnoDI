#!/usr/bin/env python3
"""Exact-toolchain CI cache identity and observable restore/product reuse (stdlib)."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

PROFILES = ("shared-source", "dag-plugin-source")
EXPECTATIONS = ("pass", "fail", "signature")


def digest(value):
    if not value:
        raise ValueError("empty cache fingerprint input")
    return hashlib.sha256(value.encode()).hexdigest()


def fingerprint(manifest, swift, xcode, system, architecture, contract):
    values = dict(manifest=manifest, swift=swift, xcode=xcode, system=system,
                  architecture=architecture, contract=contract)
    if any(not isinstance(v, str) or not v.strip() for v in values.values()):
        raise ValueError("missing manifest, compiler, Xcode, OS, architecture or profile contract")
    pins = re.findall(r'\.package\(url:\s*"([^"\n]+)",\s*exact:\s*"([^"\n]+)"\)', manifest)
    if not pins or len(pins) != len(re.findall(r"\.package\(", manifest)):
        raise ValueError("cache requires explicit exact pins for every package dependency")
    compiler = re.search(r"Apple Swift version (6\.[234])(?:\.|\s)", swift)
    if not compiler or not re.search(r"^Xcode [0-9]+(?:\.[0-9]+)*\nBuild version \S+", xcode):
        raise ValueError("unsupported or incomplete Apple compiler/Xcode identity")
    profile = "dag-plugin-source" if compiler[1] == "6.4" else "shared-source"
    # Never restore across compiler builds, SDK/Xcode builds, OS images, CPU
    # architectures, package pins or scratch-profile implementation revisions.
    payload = json.dumps({**values, "pins": pins, "schema": 2}, sort_keys=True)
    identity = digest(payload)
    return {"dependency-key": "swiftpm-deps-v2-mirrors-prebuilts-" + identity,
            "consumer-key": "innodi-external-consumers-v2-" + profile + "-" + digest(payload + profile),
            "consumer-profile": profile,
            "consumer-paths": [".build/external-consumer-contracts/" + profile + "/" + e for e in EXPECTATIONS],
            "identity": values, "pins": pins}


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def products(root, profile):
    if profile not in PROFILES:
        raise ValueError("unsupported consumer cache profile")
    result = {}
    for expectation in EXPECTATIONS:
        path = root / ".build/external-consumer-contracts" / profile / expectation
        for file in path.rglob("*"):
            # These are dependency build products; never call a cache hit proof
            # that a clean consumer or the current InnoDI sources were tested.
            if file.is_file() and file.suffix in (".o", ".swiftmodule") and any(
                    p.startswith(("SwiftSyntax", "SwiftParser", "SwiftDiagnostics", "SwiftBasicFormat")) for p in file.parts):
                stat = file.stat()
                result[str(file.relative_to(root))] = [stat.st_size, stat.st_mtime_ns]
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("fingerprint", "restored", "report"))
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--state", type=Path, default=Path("build/ci-cache.json"))
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        if args.command == "fingerprint":
            for path in ("Package.swift", "Tests/InnoDIBuildSupportTests/ExternalConsumerContractTests.swift"):
                subprocess.check_output(["git", "-C", str(root), "ls-files", "--error-unmatch", "--", path])
            data = fingerprint((root / "Package.swift").read_text(), command("swift", "--version"),
                command("xcodebuild", "-version"), command("sw_vers", "-productVersion") + " / " + command("sw_vers", "-buildVersion"),
                command("uname", "-m"), (root / "Tests/InnoDIBuildSupportTests/ExternalConsumerContractTests.swift").read_text())
            data["started"] = time.time()
            args.state.parent.mkdir(parents=True, exist_ok=True)
            args.state.write_text(json.dumps(data, indent=2) + "\n")
            with open(os.environ["GITHUB_OUTPUT"], "a") as output:
                for key in ("dependency-key", "consumer-key", "consumer-profile"):
                    output.write(key + "=" + data[key] + "\n")
                output.write("consumer-paths<<CACHE_PATHS\n" + "\n".join(data["consumer-paths"]) + "\nCACHE_PATHS\n")
            print(json.dumps({k: v for k, v in data.items() if k != "identity"}, indent=2))
        else:
            data = json.loads(args.state.read_text())
            current = products(root, data["consumer-profile"])
            if args.command == "restored":
                data.update(restored=current, restore_seconds=round(time.time() - data["started"], 3),
                            dependency_hit=os.environ.get("DEPENDENCY_CACHE_HIT", ""),
                            consumer_hit=os.environ.get("CONSUMER_CACHE_HIT", "not-requested"), build_started=time.time())
                args.state.write_text(json.dumps(data, indent=2) + "\n")
                print("Restored dependency products:", len(current))
            else:
                before = data["restored"]
                report = {"dependency_key": data["dependency-key"], "consumer_key": data["consumer-key"],
                          "consumer_profile": data["consumer-profile"], "dependency_cache_hit": data["dependency_hit"],
                          "consumer_cache_hit": data["consumer_hit"], "restore_elapsed_seconds": data["restore_seconds"],
                          "validation_elapsed_seconds": round(time.time() - data["build_started"], 3),
                          "restored_products": len(before), "products_after": len(current),
                          "restored_products_unchanged": sum(current.get(k) == v for k, v in before.items())}
                print(json.dumps(report, indent=2))
                if os.environ.get("GITHUB_STEP_SUMMARY"):
                    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
                        summary.write("\n### CI cache observations\n\n")
                        for key, value in report.items():
                            summary.write(f"- {key}: {value}\n")
                        summary.write("\nUnchanged dependency-product size/mtime is reuse evidence, not a substitute for fresh consumer assertions. Elapsed times include the steps between observations; compare hosted step/suite durations separately. No speedup percentage is inferred.\n")
        return 0
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print("CI cache rejected: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
