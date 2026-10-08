# Product test consumers

These two test-only packages reuse the original `InnoDISwiftUITests` and
`InnoDITestingTests` directories through relative symlinks. Each depends on the
unchanged root product. The intended SwiftPM build includes that product's real dependencies,
including macros and resources, without compiling unrelated root test targets.
The root manifest, full test discovery, compiler fixtures, release commands,
and default `swift test` behavior remain unchanged.

Only single-product SwiftUI or Testing changes may use these packages. Shared,
mixed, plugin, CLI, Migration, and Doctor changes require full tests. Internal
CLI/Migration tests cannot be treated as consumer tests: they import private
targets and use source-file paths to locate repository and consumer fixtures.

## Qualification on the existing Apple CI runner

Resolve the root and both packages with the selected CI toolchain. Resolution
evidence collection may happen before locks are tracked. Do not invent pins or
claim that static Python tests compiled Swift.

```sh
xcrun swift package resolve
xcrun swift package --package-path Tools/CIProductTests/InnoDISwiftUI resolve
xcrun swift package --package-path Tools/CIProductTests/InnoDITesting resolve
python3 -B Tools/ci_product_tests.py inspect --root . --output build/product-test-evidence
```

After the existing full-package test command succeeds, capture unfiltered
discovery from that same build, retaining its compiler flags:

```sh
xcrun swift test --skip-build --list-tests --no-parallel \
  -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors \
  > build/product-test-evidence/full-list.txt
```

Qualify each product. This command compiles and executes the entire standalone
test package with strict concurrency and warnings as errors, obtains its real
unfiltered test discovery, and checks exact parity with the corresponding root
test target. Failure never emits a success qualification.

```sh
python3 -B Tools/ci_product_tests.py qualify --root . --product InnoDISwiftUI \
  --full-list build/product-test-evidence/full-list.txt \
  --full-api-contract build/public-api-current.json \
  --output build/product-test-evidence/InnoDISwiftUI-qualification.json
python3 -B Tools/ci_product_tests.py qualify --root . --product InnoDITesting \
  --full-list build/product-test-evidence/full-list.txt \
  --full-api-contract build/public-api-current.json \
  --output build/product-test-evidence/InnoDITesting-qualification.json
```

Qualification must follow the existing successful full public API check, which
produces `build/public-api-current.json`. It builds each consumer in a new,
empty scratch directory and compares the native SwiftPM compiler-command
inventory and actual `.swiftmodule` outputs with the exact product dependency
closure. Raw descriptions are saved beside the qualification under
`<product>-build-evidence/`; an unknown build backend or descriptor schema
cannot qualify. This currently targets the native SwiftPM backend on the
existing Xcode 26.6 runner, not the separate Swift Build backend.

The same fresh product module is extracted with `swift-symbolgraph-extract`.
`ci_product_api.py` reuses the unchanged full API checker's semantic normalizer,
including extension graphs and compiler-derived aliases. Qualification
requires exact equality with both the selected graph in the full current
contract and the selected baseline graph. Raw API graphs remain in the build
evidence directory. The helper takes target/SDK flags from the actual compile
description and cross-checks the binary path using the consumer package's
`swift build --show-bin-path`.

Review the actual generated root/consumer locks, semantic dumps, descriptions,
discovery, execution, and API-equivalence evidence. Only then commit each package's lock and
`qualification.json`. Qualification binds the toolchain, root/consumer
manifests and locks, helpers, original API checker/baseline, and every test-source byte. Updating one of those
inputs requires a fresh qualification. Changes to the tested product's Swift
implementation may reuse the qualification and run all qualified tests again.

The qualification also binds exact Xcode version/build, macOS SDK version/build,
macOS product version, and runner architecture. Those identities are captured
before and after qualification and must remain equal. The record contains no
runner-specific absolute paths. Runtime `prepare()` recaptures them and rejects
any difference or unknown output. Static validation checks the complete
versioned record without invoking Apple tools. A hosted runner image update
therefore requires fresh qualification even if `swift --version` is unchanged.

## Execution adapter contract

`ci_product_tests.prepare(root, product, temporary, check_output=...)` returns
`test_arguments` for `swift test` only after checking committed qualification
and lock files plus live SwiftPM dump/describe equivalence. Preserve the
existing caller's strict diagnostic, serialization, filter and skip flags.
Missing or stale evidence during planning selects the original full test command. Once a scoped plan has omitted unrelated jobs, any live toolchain/manifest mismatch fails that job; it cannot silently turn into success under a different plan. A missing qualification is not a successful skipped job. The CI adapter owns exact event admission and required-job receipts.

`verify_qualification(root, product, check_output=...)` is a separate,
compiler-free verifier for CI Plan and CI Required. It returns the committed
qualification digest and recorded toolchain, never test commands. A successful
static check does not replace `prepare()` and cannot independently authorize
execution or skipping a job.

After a qualified scoped test run, check the current selected API using the
same scratch directory (SCOPED_SCRATCH_PATH is the scratch value in the successful test receipt):

```sh
python3 -B Tools/ci_product_api.py --root . --product InnoDISwiftUI \
  --scratch "$SCOPED_SCRATCH_PATH" \
  --output build/selected-api.json
```

This never invokes an unscoped package build or changes the original public API
checker's default behavior. A changed selected API fails its baseline check.

The semantic comparison includes all test-target fields and package language,
platform, and tools settings. New unmodeled fields fail closed. Source inventory
checks confirm that SwiftPM sees every original test file. Source path, bundle,
filesystem, process, resource, and fixture assumptions require additional
review before these packages can accept such tests.
