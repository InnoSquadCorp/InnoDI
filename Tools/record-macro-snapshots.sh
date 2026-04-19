#!/usr/bin/env bash
set -euo pipefail

# Records (or re-records) macro expansion snapshot files used by
# `assertMacroExpansionSnapshot` in Tests/InnoDIMacrosTests/.
#
# Snapshot location:
#   Tests/InnoDIMacrosTests/__Snapshots__/<TestFile>/<snapshotName>.swift
#
# Run after changing macro expansion output on purpose. The script sets
# INNODI_RECORD_SNAPSHOTS=1, which makes the snapshot helper write the
# current expansion to disk instead of comparing. On first record the
# helper also reports an Issue so the run surfaces the change; re-run
# without the env var to verify.
#
# Usage:
#   Tools/record-macro-snapshots.sh             # record/refresh every snapshot
#   Tools/record-macro-snapshots.sh <filter>    # forward filter to swift test

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

FILTER="${1:-InnoDIMacrosTests}"

echo "Recording macro snapshots with filter: ${FILTER}"
echo "(INNODI_RECORD_SNAPSHOTS=1 — snapshot files will be (re)written.)"
echo

set +e
INNODI_RECORD_SNAPSHOTS=1 swift test --filter "${FILTER}"
test_exit_code=$?
set -e

echo
echo "Snapshot recording complete. Review the diff and re-run tests without"
echo "INNODI_RECORD_SNAPSHOTS to verify the new snapshots compare cleanly:"
echo
echo "    swift test --filter ${FILTER}"

exit "${test_exit_code}"
