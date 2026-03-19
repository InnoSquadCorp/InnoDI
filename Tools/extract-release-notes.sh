#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <tag>" >&2
  exit 1
fi

tag="$1"
changelog="CHANGELOG.md"

if [[ ! -f "$changelog" ]]; then
  echo "missing $changelog" >&2
  exit 1
fi

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
  ' "$changelog"
)"

if [[ -z "${notes//[$' \t\r\n']/}" ]]; then
  echo "no release notes found for tag $tag in $changelog" >&2
  exit 1
fi

printf '%s\n' "$notes"
