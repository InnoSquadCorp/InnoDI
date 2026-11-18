# Contributing to InnoDI

Thanks for contributing.

## Before Opening a PR

The always-present CI Plan selects checks by changed paths and CI Required
rejects failure, cancellation, missing results, and unexpected skips. See the
[CI and public operations contract](docs/automation-policy.md) for the selection
matrix, dependency updates, and publication boundary. Local results do not
establish remote CI success. The following commands cover a source PR:

```bash
# Test suite, exactly as the PR fast lane runs it (the skipped suites are
# clean-build consumer contracts that remain exhaustive main gates)
swift test --no-parallel \
  -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors \
  --skip 'InnoDIBuildSupportTests.PublicAPIContractTests/compilerDefaultArgumentContract' \
  --skip 'InnoDIBuildSupportTests.(ExternalConsumerContractTests|StrictConcurrencyBuildTests)' \
  --skip 'InnoDIMigrationCoreTests.InnoDIMigrationCoreTests/publicExecutableRunsFromFreshConsumer' \
  --skip 'InnoDIMacrosTests.MechanicalFixItTests/uniqueBindingRepairBuildsAndGraphs'

# Macro synthesis and CI policy guards
Tools/check-no-fatalerror-in-macros.sh
Tools/check-ci-validation-opt-out.sh
Tools/check-ci-action-pins.sh

# Documentation contracts
Tools/check-docs-code-blocks.sh
Tools/check-docs-local-links.sh
Tools/check-localized-readme-sync.sh

# Public API contract and global DAG validation
Tools/check-public-api.py
swift run InnoDI-DependencyGraph --root . --validate-dag

# DocC (selected for package/source/catalog/SPI/DocC workflow changes)
Tools/generate-docc.sh

# The example project the PR gate builds
(cd Examples/SampleApp && swift build && swift test && swift run SampleApp)
```

Pushes to `main` additionally run the unskipped `swift test` suite, the
`SwiftUIExample` and `PreviewInjectionExample` builds, the five-platform
build matrix, and the remote-consumer smoke test. Running those locally is
optional; do it when your change touches build support, packaging, or the
examples.

External-consumer contracts keep compatible dependency products in
`.build/external-consumer-contracts` so pass, fail, signature, CLI, fix-it, and
macro-only strict-concurrency fixtures do not rebuild SwiftSyntax from scratch. SwiftPM still rebuilds each disposable
consumer root and separates macro-prebuilt from plugin-source graphs. Use
`swift package clean` for a cold run, or set `INNODI_EXTERNAL_SCRATCH_PATH` to
an isolated absolute path when comparing clean-build timings.

The compile-pass and compile-fail fixture loops build one fixture at a time.
On a workstation with spare cores, `INNODI_EXTERNAL_FIXTURE_LANES=<2...8>`
builds them in that many concurrent lanes. Lane 0 keeps the scratch path
above; each further lane uses a sibling such as `pass-lane1` with its own copy
of the dependency products, so the first run of a lane builds SwiftSyntax and
InnoDI again and every later InnoDI source change rebuilds InnoDI once per
lane. CI leaves the variable unset.

## Documentation Contract

If behavior changes, update the docs in the same change.

Canonical sources:

- `README.md`
- `Sources/InnoDI/InnoDI.docc/*.md`
- `RELEASING.md`
- `ROADMAP.md`

Localized mirror:

- `README.ko.md`
- `Sources/InnoDI/InnoDI.docc/ko.lproj/*.md`

Keep the English docs authoritative, then mirror the same structure and meaning
into the Korean README and DocC files. The Japanese, Simplified Chinese,
German, Spanish, and Russian READMEs are concise current-release guides,
not full translations of the reference. Keep all five guides current together;
preserve the guide-version and section markers used by the parity gate. Their
`*.lproj` folders still contain historical 6.0.0 DocC notices. Do not present
those notices as current translated API documentation.

The generated DocC archive currently builds from the English base catalog, so
localized DocC files are maintained as source mirrors in the repository.

`Tools/check-localized-readme-sync.sh` runs in strict mode whenever CI Plan
selects the documentation contracts and in every release: a swift fence count
or H2 header count drift between the English canonical and the Korean README,
or between an English DocC article and its `ko.lproj` counterpart, fails the
build, as do an English DocC article without a `ko.lproj` counterpart and a
concise guide that loses its current version, required section, installation,
critical API token, canonical link, or historical link. The frozen `*.lproj`
folders are not compared. Passing structural checks does not prove translation
accuracy: review meaning, particularly readiness, cancellation, isolation and
platform limitations, in every changed locale. When you add a DocC article, or add
or remove an H2 or a Swift example in `README.md` or a DocC article, mirror
the change into the Korean file in the same PR. The script accepts
`INNODI_README_SYNC_STRICT=0` only as an explicit soft-rollout window for
canonical restructures.

## Code Coverage

The exhaustive lane on `main` and the Release Gate run
`Tools/run-coverage-gate.sh`: one strict `swift test --enable-code-coverage`
pass whose profile data `Tools/collect-coverage.sh` exports as a per-module
rollup. The rollup appears in the workflow run's step summary and is uploaded
as an `actions/upload-artifact` artifact named `coverage`, and
`Tools/check-coverage-floor.py` fails the gate when a module falls below its
floor in `Tools/coverage-floor.json`. Locally:

```sh
Tools/run-coverage-gate.sh
# → coverage/lcov.info, coverage/report.txt, coverage/summary.json, coverage/summary.md
```

The pass skips the external consumer and strict-concurrency build contracts.
They build fixture packages in separate, non-instrumented Swift processes and
used to take most of the pass; the exhaustive lane runs them in its own job
beside the gate, and the Release Gate runs them for every release toolchain.
Tests, examples, swift-syntax, and the `.build` cache are excluded from the
report so it tracks the library surface, not fixtures or third-party code.

## Macro Performance Trend

`Tools/measure-macro-performance.sh --enforce` compares every validated
`main` revision against the pinned baseline JSON in
`Tools/macro-performance-baseline.json`. Alongside that, the `main` pipeline
runs `Tools/check-paired-macro-performance.py`. It builds the released commit
pinned in `Tools/macro-performance-paired-baseline.json` beside the candidate,
gives both the candidate's benchmark source, alternates the two benchmark
processes in paired blocks on the same machine, and fails when the median
per-block ratio of their fastest samples exceeds the 20% budget. Because the
baseline is a released commit, the comparison also covers creep that
under-threshold PRs accumulate over a release train. A baseline that cannot be
fetched or does not build the candidate's benchmark is reported as
insufficient evidence, not as a pass. An enforcing run fails on it, and
`--report-only` prints a warning.

`Tools/check-performance-trend.sh` compares the current measurement against
the rolling median of the last entries on the `perf-history` branch. It is a
report on every event. Those entries come from different hosted runners, and
the fastest sample for unchanged code has differed by more than the 20% budget
between them, so the comparison cannot distinguish a runner from a regression.

To run the paired comparison locally:

```sh
python3 -B Tools/check-paired-macro-performance.py --report-only
# → build/paired-macro-performance-report.json
```

`--baseline-commit <rev>` compares against another revision for an experiment.
The checked-in baseline moves only to a released commit, in a reviewed change.

Each run removes the report left by an earlier run before it starts, so a run
that fails before it writes a report leaves none. The report names the
candidate by `candidate.commit`, `candidate.dirty` and `candidate.tree`.
`dirty` is `true` when the tree had uncommitted or untracked changes once the
candidate was built. Such a tree is measured, not rejected, and its report is
not a measurement of the commit alone. `tree` is the git tree id of the
content that was built: the tree a commit of every tracked change and every
untracked file would record. For a clean tree it equals
`git rev-parse <commit>^{tree}`, and two different uncommitted edits at one
commit get two different ids. Computing it writes nothing to your index,
working tree or object store, and it is `null` when git cannot compute it.
Files that `.gitignore` excludes are build products, not sources, and count
toward neither field.

Source PRs use a separate 30-minute fast lane selected by CI Plan. It keeps all in-process unit,
macro-expansion, graph, runtime, migration, documentation, public-API, and DAG
contracts, but defers contracts that spawn clean external SwiftPM builds to
`main`. PRs build one representative example; the two extended examples run
on `main`, their weekly schedule, and manual dispatch. The exhaustive lane also
retains coverage, Swift 6.2 compatibility, Apple-platform builds, path-identity
checks, and performance tracking, and runs the external consumer contracts in
a job beside the coverage gate. This split changes feedback latency, not
release coverage.

The gated Ubuntu history job in `CI` runs after successful pushes to `main` and uses
`Tools/append-performance-history.sh` to append one
`history/macro-performance/<UTC date>-<short sha>.json` entry to the
`perf-history` branch, then rebuilds `history/index.json`. The trend
script reads only that index — locally you do not need to checkout
`perf-history` yourself; the script fetches it and is a no-op when the
branch is empty or unreachable.

Tunables for the trend report (set as environment variables):

- `INNODI_TREND_WINDOW` (default 7) — trailing entries used for the
  median.
- `INNODI_TREND_THRESHOLD_PCT` (default 20) — report a regression above
  this delta.
- `INNODI_TREND_MIN_SAMPLES` (default 5) — below this the comparison is
  skipped as insufficient history.
- `INNODI_TREND_REQUIRE_SAME_TOOLCHAIN` (default 1) — drop history
  entries that used a different `swift_version` than the current run.

When a Swift toolchain bump moves the absolute number, refresh
`Tools/macro-performance-baseline.json` with
`Tools/measure-macro-performance.sh --update-baseline` and let the trend
report's same-toolchain filter fall through naturally.

## Governance

`/.github/CODEOWNERS` is the single source of truth for review routing.
Every path is currently owned by the maintainer (`@ethan-is`); the
per-area sections of CODEOWNERS exist so a future owner taking on one
subsystem (macros, build support, SwiftUI integration, workspace
analysis, examples, docs, CI) is a one-line change rather than a
restructure. The most-specific path match wins.

GitHub auto-assigns the matching code owner as a reviewer when a PR
touches a path. Branch protection should enforce the CODEOWNERS review
requirement on `main` so the routing translates to a hard gate; this
repository's protection rules are configured externally and are not
part of this file.

## PR Expectations

- Keep changes scoped and explain user-facing behavior changes.
- Add or update tests for validation, diagnostics, graph output, SwiftUI helpers, or examples when behavior changes.
- If release notes or upgrade guidance change, update `CHANGELOG.md` in the same change. If artifact naming or schema expectations change, update `RELEASING.md`.
- Prefer `SwiftSyntaxBuilder` over string-built AST when changing macro generation.

## Code Style Conventions

InnoDI does not enforce code style through an automated formatter. The
repository follows these whitespace conventions consistently across both
`Sources/` and `Tests/`; new contributions should match what neighboring
files already do:

- Swift tools version `6.2`.
- Indent with 4 spaces; no tabs.
- LF line endings.
- No trailing semicolons; no trailing whitespace.
- Spaces around binary operators and after commas; no spaces inside
  `..<` or `...` ranges.
- Imports grouped with `@testable` imports trailing.
- `self.` only inside initializers; rely on Swift's default elsewhere.
- Use `some Protocol` / `any Protocol` deliberately — the macro and
  validator pipelines treat them as distinct, and changing one to the
  other can shift diagnostics or graph edges.

Stylistic decisions that are not in this list (line wrapping, doc
comment placement, redundant-`Sendable` conformances on non-public
types, generic parameter syntax) are deliberately left to author
judgment. Macro fixtures and validator pipelines often have a reason
for their current shape; do not reformat unrelated code in a behavior
PR.

## Issues and Discussions

- Use issues for reproducible bugs, missing diagnostics, or feature requests.
- Include sample containers, diagnostics, or CLI output when reporting graph or validation problems.
