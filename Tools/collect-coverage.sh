#!/usr/bin/env bash
set -euo pipefail

# Tools/collect-coverage.sh
#
# Aggregates code-coverage data from a `swift test --enable-code-coverage`
# run. Produces:
#   coverage/lcov.info     — full-package lcov for upload to Codecov-style tools
#   coverage/report.txt    — `xcrun llvm-cov report` plain-text summary
#   coverage/summary.json  — per-module rollup (files, lines, line %, function %)
#   coverage/summary.md    — Markdown table of the same rollup, suitable for
#                            posting as a PR comment
#
# Tests, examples, the `.build` cache, and external dependencies (e.g.
# swift-syntax) are excluded so the reported coverage tracks the library
# surface, not snapshot fixtures or third-party code.
#
# CI publishes these artifacts and then runs `check-coverage-floor.py` so
# package/module regressions fail independently of artifact generation.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -n "${INNODI_COVERAGE_BUILD_DIR:-}" ]]; then
    BUILD_DIR="$INNODI_COVERAGE_BUILD_DIR"
else
    ARCH=$(uname -m)
    case "$ARCH" in
        arm64) ARCH_DIR="arm64-apple-macosx";;
        x86_64) ARCH_DIR="x86_64-apple-macosx";;
        *) echo "::error::unsupported architecture '$ARCH' for coverage collection" >&2; exit 1;;
    esac
    BUILD_DIR=".build/$ARCH_DIR/debug"
fi
PROFDATA="$BUILD_DIR/codecov/default.profdata"
XCTEST_BUNDLE="$BUILD_DIR/InnoDIPackageTests.xctest"

if [[ ! -f "$PROFDATA" ]]; then
    echo "::error::missing $PROFDATA — run 'swift test --enable-code-coverage' first" >&2
    exit 1
fi
if [[ ! -d "$XCTEST_BUNDLE" ]]; then
    echo "::error::missing $XCTEST_BUNDLE" >&2
    exit 1
fi

BINARY="$XCTEST_BUNDLE/Contents/MacOS/$(basename "$XCTEST_BUNDLE" .xctest)"
if [[ ! -x "$BINARY" ]]; then
    echo "::error::xctest binary not executable: $BINARY" >&2
    exit 1
fi

OUT_DIR="${INNODI_COVERAGE_DIR:-coverage}"
mkdir -p "$OUT_DIR"

# Filter: keep only first-party Sources/<module>/... files.
IGNORE_REGEX='(Tests/|Examples/|\.build/|/usr/|swift-syntax|/CommandLineToolSupport/|checkouts/)'

echo "Exporting lcov to $OUT_DIR/lcov.info"
xcrun llvm-cov export "$BINARY" \
    -instr-profile="$PROFDATA" \
    --ignore-filename-regex="$IGNORE_REGEX" \
    --format=lcov > "$OUT_DIR/lcov.info"

echo "Writing human-readable report to $OUT_DIR/report.txt"
xcrun llvm-cov report "$BINARY" \
    -instr-profile="$PROFDATA" \
    --ignore-filename-regex="$IGNORE_REGEX" \
    > "$OUT_DIR/report.txt"

echo "Computing per-module rollup"
JSON_TMP="$OUT_DIR/.llvm-cov-export.json"
xcrun llvm-cov export "$BINARY" \
    -instr-profile="$PROFDATA" \
    --ignore-filename-regex="$IGNORE_REGEX" \
    --format=text > "$JSON_TMP"

INNODI_COVERAGE_JSON="$JSON_TMP" OUT_DIR="$OUT_DIR" python3 - <<'PY'
import json, os, re

with open(os.environ["INNODI_COVERAGE_JSON"]) as fh:
    data = json.load(fh)
out_dir = os.environ["OUT_DIR"]

modules: dict[str, dict] = {}
total_files = 0
package_lines_covered = 0
package_lines_total = 0
package_functions_covered = 0
package_functions_total = 0

for entry in data.get("data", []):
    for filedata in entry.get("files", []):
        path = filedata.get("filename", "")
        m = re.search(r"/Sources/([^/]+)/", path)
        if not m:
            continue
        module = m.group(1)
        summary = filedata["summary"]
        bucket = modules.setdefault(module, {
            "files": 0,
            "lines_covered": 0,
            "lines_total": 0,
            "functions_covered": 0,
            "functions_total": 0,
        })
        bucket["files"] += 1
        bucket["lines_covered"] += summary["lines"]["covered"]
        bucket["lines_total"] += summary["lines"]["count"]
        bucket["functions_covered"] += summary["functions"]["covered"]
        bucket["functions_total"] += summary["functions"]["count"]
        total_files += 1
        package_lines_covered += summary["lines"]["covered"]
        package_lines_total += summary["lines"]["count"]
        package_functions_covered += summary["functions"]["covered"]
        package_functions_total += summary["functions"]["count"]

def pct(num: int, denom: int) -> float:
    return round(100.0 * num / denom, 2) if denom else 0.0

result_modules = []
for module in sorted(modules):
    bucket = modules[module]
    result_modules.append({
        "name": module,
        "files": bucket["files"],
        "linesCovered": bucket["lines_covered"],
        "linesTotal": bucket["lines_total"],
        "linePercent": pct(bucket["lines_covered"], bucket["lines_total"]),
        "functionsCovered": bucket["functions_covered"],
        "functionsTotal": bucket["functions_total"],
        "functionPercent": pct(bucket["functions_covered"], bucket["functions_total"]),
    })

result = {
    "totalFiles": total_files,
    "package": {
        "linesCovered": package_lines_covered,
        "linesTotal": package_lines_total,
        "linePercent": pct(package_lines_covered, package_lines_total),
        "functionsCovered": package_functions_covered,
        "functionsTotal": package_functions_total,
        "functionPercent": pct(package_functions_covered, package_functions_total),
    },
    "modules": result_modules,
}

with open(os.path.join(out_dir, "summary.json"), "w") as fh:
    json.dump(result, fh, indent=2)
    fh.write("\n")

with open(os.path.join(out_dir, "summary.md"), "w") as fh:
    fh.write("### InnoDI test coverage (macOS, strict-concurrency suite)\n\n")
    fh.write(
        f"**Package totals:** {result['package']['linesCovered']}/"
        f"{result['package']['linesTotal']} lines "
        f"({result['package']['linePercent']:.1f}%), "
        f"{result['package']['functionsCovered']}/"
        f"{result['package']['functionsTotal']} functions "
        f"({result['package']['functionPercent']:.1f}%).\n\n"
    )
    fh.write("| Module | Files | Lines covered | Line % | Function % |\n")
    fh.write("|---|---:|---:|---:|---:|\n")
    for module in result_modules:
        fh.write(
            f"| `{module['name']}` | {module['files']} | "
            f"{module['linesCovered']}/{module['linesTotal']} | "
            f"{module['linePercent']:.1f}% | {module['functionPercent']:.1f}% |\n"
        )
    fh.write(
        "\n_Tests, examples, swift-syntax, and other dependencies are excluded._ "
        "Checked-in package and module floors gate main and releases.\n"
    )

print(f"Per-module rollup: {len(result_modules)} modules, {total_files} files")
PY

rm -f "$JSON_TMP"

echo "Coverage artifacts written to $OUT_DIR/"
ls -la "$OUT_DIR"
