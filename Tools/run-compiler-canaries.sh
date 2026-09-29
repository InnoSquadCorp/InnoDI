#!/usr/bin/env bash
# Informational compiler canaries.
#
# Each directory under Tests/CompilerCanaries is a fixture package whose files
# carry a `.fixture` suffix, so repository-wide Swift scans never see them.
# The script materializes every canary into a temporary directory, builds and
# runs it with the active toolchain, and reports one result per canary:
#
#   compiled        the canary built and ran
#   compiler-crash  the compiler crashed while building the canary
#   failed          the build or run failed without a compiler crash
#
# A canary result never fails the job. The script exits non-zero only when it
# is invoked incorrectly. Build logs are kept under build/compiler-canaries.
#
# Usage:
#   Tools/run-compiler-canaries.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ $# -ne 0 ]]; then
    echo "usage: Tools/run-compiler-canaries.sh" >&2
    exit 2
fi

CANARY_ROOT="$ROOT_DIR/Tests/CompilerCanaries"
LOG_DIR="$ROOT_DIR/build/compiler-canaries"
mkdir -p "$LOG_DIR"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

toolchain="$(swift --version 2>&1 | head -n 1)"

describe() {
    local canary="$1" result="$2"
    case "$canary:$result" in
        enum-role-macro:compiled)
            echo "Enum-typed arguments on a multi-role attached macro compile and run." ;;
        enum-role-macro:compiler-crash)
            echo "The compiler still crashes on enum-typed multi-role macro arguments; keep the string-backed ContainerRole token." ;;
        *:failed)
            echo "The canary failed without a compiler crash; inspect its build log." ;;
        *)
            echo "See Tests/CompilerCanaries/$canary." ;;
    esac
}

rows=()
shopt -s nullglob
for canary_dir in "$CANARY_ROOT"/*/; do
    canary="$(basename "$canary_dir")"
    package_dir="$WORK_DIR/$canary"
    while IFS= read -r -d '' fixture; do
        relative="${fixture#"$canary_dir"}"
        destination="$package_dir/${relative%.fixture}"
        mkdir -p "$(dirname "$destination")"
        cp "$fixture" "$destination"
    done < <(find "$canary_dir" -type f -name '*.fixture' -print0)

    log="$LOG_DIR/$canary.log"
    result="compiled"
    if ! swift build --package-path "$package_dir" >"$log" 2>&1; then
        if grep -qE 'Stack dump:|PLEASE submit a bug report|failed due to signal|Segmentation fault' "$log"; then
            result="compiler-crash"
        else
            result="failed"
        fi
    elif ! swift run --skip-build --package-path "$package_dir" >>"$log" 2>&1; then
        result="failed"
    elif ! grep -q 'canary compiled' "$log"; then
        result="failed"
    fi
    rows+=("| \`$canary\` | $result | $(describe "$canary" "$result") |")
    echo "$canary: $result (log: ${log#"$ROOT_DIR"/})" >&2
done

summary="$(
    echo "### Compiler canaries (informational)"
    echo
    echo "Toolchain: \`$toolchain\`"
    echo
    if [[ ${#rows[@]} -eq 0 ]]; then
        echo "No compiler canaries were found."
    else
        echo "| Canary | Result | Meaning |"
        echo "|---|---|---|"
        printf '%s\n' "${rows[@]}"
        echo
        echo "A canary result does not fail this job."
    fi
)"

printf '%s\n' "$summary"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf '%s\n' "$summary" >> "$GITHUB_STEP_SUMMARY"
fi
