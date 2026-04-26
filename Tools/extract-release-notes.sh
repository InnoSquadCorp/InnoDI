#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <tag>" >&2
  exit 1
fi

tag="$1"
release_doc="RELEASING.md"

if [[ ! -f "$release_doc" ]]; then
  echo "missing $release_doc" >&2
  exit 1
fi

awk_status=0
notes="$(
  awk -v tag="$tag" '
    $0 == "## " tag { found = 1; next }
    found && /^## / { exit }
    found { print }
    END {
      if (!found) {
        exit 2
      }
    }
  ' "$release_doc"
)" || awk_status=$?

if [[ $awk_status -eq 2 ]]; then
  echo "no release notes found for tag $tag in $release_doc" >&2
  exit 1
elif [[ $awk_status -ne 0 ]]; then
  exit "$awk_status"
fi

if [[ -z "${notes//[$' \t\r\n']/}" ]]; then
  echo "no release notes found for tag $tag in $release_doc" >&2
  exit 1
fi

printf '%s\n' "$notes"
