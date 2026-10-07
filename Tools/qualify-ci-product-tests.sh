#!/usr/bin/env bash
set -euo pipefail
# Reuse a successful full root test build and full API contract. This script
# never replaces those gates or accepts a source-authored success record.
evidence="${RUNNER_TEMP:?}/ci-test-qualification"
mkdir -p "$evidence"
xcrun swift test --skip-build --list-tests --no-parallel -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors > "$evidence/full-list.txt"
python3 -B Tools/collect_ci_resolution_evidence.py --unit SampleApp --include-product-tests --output "$evidence/resolution"
python3 -B Tools/ci_product_tests.py inspect --root . --output "$evidence/manifests"
python3 -B Tools/ci_product_tests.py qualify --root . --product InnoDISwiftUI --full-list "$evidence/full-list.txt" --full-api-contract build/public-api-current.json --output "$evidence/InnoDISwiftUI-qualification.json"
python3 -B Tools/ci_product_tests.py qualify --root . --product InnoDITesting --full-list "$evidence/full-list.txt" --full-api-contract build/public-api-current.json --output "$evidence/InnoDITesting-qualification.json"
