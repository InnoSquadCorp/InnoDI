#!/usr/bin/env bash
# CI guard: every local destination referenced by tracked Markdown must exist.

set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT_DIR="$SCRIPT_ROOT"
SCAN_MODE="tracked"

usage() {
    cat <<'EOF'
Usage: Tools/check-docs-local-links.sh [--root <path>]

Checks local Markdown link and image destinations. With --root, Markdown files
are discovered recursively so the command can validate an isolated fixture.
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
            SCAN_MODE="recursive"
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

python3 - "$ROOT_DIR" "$SCAN_MODE" <<'PY'
from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote


root = Path(sys.argv[1]).resolve()
scan_mode = sys.argv[2]

if not root.is_dir():
    print(f"Documentation root is not a directory: {root}", file=sys.stderr)
    raise SystemExit(2)


def markdown_files() -> list[Path]:
    if scan_mode == "tracked":
        result = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-z", "--", "*.md"],
            check=True,
            stdout=subprocess.PIPE,
        )
        return [
            root / os.fsdecode(path)
            for path in result.stdout.split(b"\0")
            if path
        ]

    ignored_directories = {".build", ".git"}
    return sorted(
        path
        for path in root.rglob("*.md")
        if ignored_directories.isdisjoint(path.relative_to(root).parts)
    )


def mask_inline_code(line: str) -> str:
    characters = list(line)
    index = 0
    while index < len(line):
        if line[index] != "`":
            index += 1
            continue
        run_length = 1
        while index + run_length < len(line) and line[index + run_length] == "`":
            run_length += 1
        closing = line.find("`" * run_length, index + run_length)
        if closing == -1:
            index += run_length
            continue
        for masked_index in range(index, closing + run_length):
            characters[masked_index] = " "
        index = closing + run_length
    return "".join(characters)


def inline_destinations(line: str) -> list[str]:
    destinations: list[str] = []
    search_from = 0
    while True:
        marker = line.find("](", search_from)
        if marker == -1:
            return destinations
        if line.rfind("[", 0, marker) == -1:
            search_from = marker + 2
            continue

        index = marker + 2
        depth = 1
        escaped = False
        while index < len(line):
            character = line[index]
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == "(":
                depth += 1
            elif character == ")":
                depth -= 1
                if depth == 0:
                    destinations.append(line[marker + 2:index])
                    search_from = index + 1
                    break
            index += 1
        else:
            return destinations


def destination_path(raw_destination: str) -> str | None:
    destination = raw_destination.strip()
    if not destination:
        return None
    if destination.startswith("<"):
        closing = destination.find(">", 1)
        if closing == -1:
            return None
        destination = destination[1:closing]
    else:
        match = re.match(r"(?:\\.|[^\s])+", destination)
        if match is None:
            return None
        destination = match.group(0)

    destination = re.sub(r"\\([\\ ()])", r"\1", destination)
    destination = unquote(destination)
    if (
        not destination
        or destination.startswith("#")
        or destination.startswith("//")
        or re.match(r"^[A-Za-z][A-Za-z0-9+.-]*:", destination)
    ):
        return None

    return re.split(r"[?#]", destination, maxsplit=1)[0]


reference_definition = re.compile(r"^\s{0,3}\[[^]]+\]:\s*(.+?)\s*$")
fence_opening = re.compile(r"^\s{0,3}(`{3,}|~{3,})")
failures: list[tuple[str, int, str]] = []
checked_links = 0
documentation_files = markdown_files()

for markdown_path in documentation_files:
    try:
        contents = markdown_path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        relative_path = markdown_path.relative_to(root).as_posix()
        failures.append((relative_path, 1, f"unreadable Markdown file ({error})"))
        continue

    active_fence_character: str | None = None
    active_fence_length = 0
    relative_path = markdown_path.relative_to(root).as_posix()

    for line_number, original_line in enumerate(contents.splitlines(), start=1):
        fence = fence_opening.match(original_line)
        if fence is not None:
            marker = fence.group(1)
            marker_character = marker[0]
            if active_fence_character is None:
                active_fence_character = marker_character
                active_fence_length = len(marker)
                continue
            if (
                marker_character == active_fence_character
                and len(marker) >= active_fence_length
            ):
                active_fence_character = None
                active_fence_length = 0
                continue
        if active_fence_character is not None:
            continue

        line = mask_inline_code(original_line)
        destinations = inline_destinations(line)
        definition = reference_definition.match(line)
        if definition is not None:
            destinations.append(definition.group(1))

        for raw_destination in destinations:
            local_path = destination_path(raw_destination)
            if local_path is None or local_path == "":
                continue
            checked_links += 1
            if local_path.startswith("/"):
                resolved = root / local_path.lstrip("/")
            else:
                resolved = markdown_path.parent / local_path
            if not resolved.exists():
                failures.append((relative_path, line_number, local_path))

if failures:
    for relative_path, line_number, detail in sorted(failures):
        print(
            f"{relative_path}:{line_number}: missing local documentation target: {detail}",
            file=sys.stderr,
        )
    raise SystemExit(1)

print(
    f"Checked {checked_links} local documentation link(s) "
    f"across {len(documentation_files)} Markdown file(s)."
)
PY
