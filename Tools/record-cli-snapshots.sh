#!/usr/bin/env bash
set -euo pipefail

# Records (or re-records) CLI renderer snapshot files used by
# `assertTextSnapshot` in Tests/InnoDIDependencyGraphCLITests/.
#
# Snapshot location:
#   Tests/InnoDIDependencyGraphCLITests/__Snapshots__/<TestFile>/<snapshotName>.txt
#
# Run after changing any of the Mermaid / DOT / ASCII renderer output on
# purpose. The script sets INNODI_RECORD_SNAPSHOTS=1, which makes the
# snapshot helper write the current stdout to disk instead of comparing.
# On first record the helper also reports an Issue so the run surfaces the
# change; re-run without the env var to verify.
#
# Usage:
#   Tools/record-cli-snapshots.sh             # record/refresh every snapshot
#   Tools/record-cli-snapshots.sh <filter>    # forward filter to swift test

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

FILTER="${1:-InnoDIDependencyGraphCLITests.GraphRendererSnapshotTests}"

echo "Recording CLI renderer snapshots with filter: ${FILTER}"
echo "(INNODI_RECORD_SNAPSHOTS=1 — snapshot files will be (re)written.)"
echo

INNODI_RECORD_SNAPSHOTS=1 swift test --filter "${FILTER}"

echo
echo "Snapshot recording complete. Review the diff and re-run tests without"
echo "INNODI_RECORD_SNAPSHOTS to verify the new snapshots compare cleanly:"
echo
echo "    swift test --filter ${FILTER}"
