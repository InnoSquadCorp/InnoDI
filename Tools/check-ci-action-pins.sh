#!/usr/bin/env bash
# CI guard: external actions are immutable and checkout credentials are scoped.

set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT_DIR="$SCRIPT_ROOT"

usage() {
    cat <<'EOF'
Usage: Tools/check-ci-action-pins.sh [--root <path>]

Checks workflow permissions, full-SHA external action pins, and checkout
credential persistence. Only the reviewed performance-history writer jobs may
persist checkout credentials.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)
            if [[ $# -lt 2 ]]; then
                echo "--root requires a path" >&2
                exit 2
            fi
            ROOT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

python3 - "$ROOT_DIR" <<'PY'
from __future__ import annotations

from pathlib import Path
import re
import sys


root = Path(sys.argv[1]).resolve()
workflow_directory = root / ".github" / "workflows"
action_directory = root / ".github" / "actions"

if not workflow_directory.is_dir():
    print(f"Workflow directory does not exist: {workflow_directory}", file=sys.stderr)
    raise SystemExit(2)

workflow_files = sorted(
    path
    for suffix in ("*.yml", "*.yaml")
    for path in workflow_directory.glob(suffix)
)
action_files: list[Path] = []
if action_directory.is_dir():
    for name in ("action.yml", "action.yaml"):
        action_files.extend(action_directory.rglob(name))
    action_files.sort()

if not workflow_files:
    print(f"No workflow files found under {workflow_directory}", file=sys.stderr)
    raise SystemExit(2)

uses_pattern = re.compile(r"^\s*(?:-\s*)?uses:\s*(.+?)\s*$")
permission_entry_pattern = re.compile(r"^\s{2}([a-z-]+):\s*([a-z-]+)\s*$")
job_pattern = re.compile(r"^\s{2}([A-Za-z0-9_-]+):\s*$")
job_permission_entry_pattern = re.compile(
    r"^\s{6}([a-z-]+):\s*([a-z-]+)\s*$"
)
full_sha_pattern = re.compile(r"^[0-9a-f]{40}$")
checkout_prefix = "actions/checkout@"
failures: list[tuple[str, int, str]] = []
external_action_count = 0


def relative(path: Path) -> str:
    return path.relative_to(root).as_posix()


def top_level_permissions(lines: list[str]) -> dict[str, str] | None:
    for index, line in enumerate(lines):
        if line != "permissions:":
            continue
        permissions: dict[str, str] = {}
        for candidate in lines[index + 1:]:
            if candidate and not candidate.startswith((" ", "\t", "#")):
                break
            entry = permission_entry_pattern.match(candidate)
            if entry is not None:
                permissions[entry.group(1)] = entry.group(2)
        return permissions
    return None


for workflow_path in workflow_files:
    lines = workflow_path.read_text(encoding="utf-8").splitlines()
    permissions = top_level_permissions(lines)
    expected_permissions = {"contents": "read"}
    if permissions != expected_permissions:
        failures.append(
            (
                relative(workflow_path),
                1,
                "top-level permissions must be exactly "
                + ", ".join(
                    f"{key}: {value}"
                    for key, value in expected_permissions.items()
                ),
            )
        )

    expected_job_permissions: dict[str, dict[str, str]] = {}
    if workflow_path.name == "docs.yml":
        expected_job_permissions = {
            "deploy-pages": {"pages": "write", "id-token": "write"},
        }
    elif workflow_path.name == "release.yml":
        expected_job_permissions = {
            "recovery-state": {"contents": "read"},
            "release-gate": {"contents": "read"},
            "release-compatibility": {"contents": "read"},
            "exact-revision-consumer": {"contents": "read"},
            "publish-release": {"contents": "write"},
        }
    elif workflow_path.name == "macro-tests.yml":
        expected_job_permissions = {
            "append-perf-history": {"contents": "write"},
        }
    elif workflow_path.name == "perf-history.yml":
        expected_job_permissions = {
            "append-perf-history": {"contents": "write"},
        }

    current_job: str | None = None
    actual_job_permissions: dict[str, dict[str, str]] = {}
    in_jobs = False
    for index, line in enumerate(lines):
        if line == "jobs:":
            in_jobs = True
            continue
        if not in_jobs:
            continue
        if line and not line.startswith((" ", "\t", "#")):
            break
        job = job_pattern.match(line)
        if job is not None:
            current_job = job.group(1)
            continue
        if not line.startswith("    permissions:"):
            continue
        if current_job is None or line != "    permissions:":
            failures.append(
                (
                    relative(workflow_path),
                    index + 1,
                    "job permissions must use an explicit scoped mapping",
                )
            )
            continue

        job_permissions: dict[str, str] = {}
        for candidate in lines[index + 1:]:
            if candidate and len(candidate) - len(candidate.lstrip()) <= 4:
                break
            entry = job_permission_entry_pattern.match(candidate)
            if entry is not None:
                job_permissions[entry.group(1)] = entry.group(2)
        actual_job_permissions[current_job] = job_permissions

    if actual_job_permissions != expected_job_permissions:
        failures.append(
            (
                relative(workflow_path),
                1,
                "job-level permissions differ from the reviewed least-privilege map",
            )
        )

for source_path in workflow_files + action_files:
    lines = source_path.read_text(encoding="utf-8").splitlines()
    current_job: str | None = None
    in_jobs = False
    for index, line in enumerate(lines):
        if line == "jobs:":
            in_jobs = True
            continue
        if in_jobs:
            if line and not line.startswith((" ", "\t", "#")):
                in_jobs = False
                current_job = None
            else:
                job = job_pattern.match(line)
                if job is not None:
                    current_job = job.group(1)

        match = uses_pattern.match(line)
        if match is None:
            continue
        action = match.group(1).split("#", maxsplit=1)[0].strip().strip("\"'")
        if action.startswith("./"):
            continue

        external_action_count += 1
        if "@" not in action:
            failures.append(
                (relative(source_path), index + 1, f"external action has no revision: {action}")
            )
            continue
        _, revision = action.rsplit("@", maxsplit=1)
        if full_sha_pattern.fullmatch(revision) is None:
            failures.append(
                (
                    relative(source_path),
                    index + 1,
                    f"external action revision is not a full lowercase commit SHA: {action}",
                )
            )

        if not action.startswith(checkout_prefix):
            continue

        uses_indent = len(line) - len(line.lstrip())
        step_indent = max(0, uses_indent - 2)
        persistence_values: list[str] = []
        for candidate in lines[index + 1:]:
            candidate_indent = len(candidate) - len(candidate.lstrip())
            if (
                candidate.strip().startswith("- ")
                and candidate_indent <= step_indent
            ):
                break
            persistence = re.match(
                r"^\s*persist-credentials:\s*(true|false)\s*$",
                candidate,
            )
            if persistence is not None:
                persistence_values.append(persistence.group(1))

        credential_writers = {
            ("macro-tests.yml", "append-perf-history"),
            ("perf-history.yml", "append-perf-history"),
        }
        expected_persistence = (
            "true"
            if (source_path.name, current_job) in credential_writers
            else "false"
        )
        if persistence_values != [expected_persistence]:
            failures.append(
                (
                    relative(source_path),
                    index + 1,
                    "checkout must set exactly one "
                    f"persist-credentials: {expected_persistence}",
                )
            )

if failures:
    for path, line, message in sorted(failures):
        print(f"{path}:{line}: {message}", file=sys.stderr)
    raise SystemExit(1)

print(
    f"Checked {external_action_count} pinned external action use(s) "
    f"across {len(workflow_files)} workflow file(s)."
)
PY
