#!/usr/bin/env bash
set -euo pipefail

# CI guard: the build validation plugin emits the global DAG metrics artifact,
# so CI workflows must not disable it. Local iteration can still opt out.

ROOT="${1:-.}"
ROOT="${ROOT%/}"
pattern='INNODI_DISABLE_BUILD_VALIDATION[[:space:]]*(:|=)[[:space:]]*["'\'']?([1]|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss])["'\'']?'

targets=()

add_file_if_present() {
    local file="$1"
    if [[ -f "$file" ]]; then
        targets+=("$file")
    fi
}

if [[ -d "$ROOT/.github/workflows" ]]; then
    while IFS= read -r -d '' file; do
        targets+=("$file")
    done < <(find "$ROOT/.github/workflows" -type f \( -name '*.yml' -o -name '*.yaml' \) -print0)
fi

add_file_if_present "$ROOT/.gitlab-ci.yml"

if [[ -d "$ROOT/.circleci" ]]; then
    while IFS= read -r -d '' file; do
        targets+=("$file")
    done < <(find "$ROOT/.circleci" -type f \( -name '*.yml' -o -name '*.yaml' \) -print0)
fi

if [[ ${#targets[@]} -eq 0 ]]; then
    echo "No CI workflow files found."
    exit 0
fi

failed=0

for file in "${targets[@]}"; do
    line_number=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_number=$((line_number + 1))
        trimmed="${line#"${line%%[![:space:]]*}"}"
        if [[ "$trimmed" == \#* ]]; then
            continue
        fi

        if [[ "$line" =~ $pattern ]]; then
            display_file="${file#"$ROOT"/}"
            echo "::error file=$display_file,line=$line_number::CI workflows must not set INNODI_DISABLE_BUILD_VALIDATION to a truthy value."
            failed=1
        fi
    done < "$file"
done

if [[ $failed -ne 0 ]]; then
    echo "Remove the CI opt-out or limit it to local iteration. See Sources/InnoDI/InnoDI.docc/PluginOptOut.md."
    exit 1
fi

echo "CI workflows keep InnoDI build validation enabled."
