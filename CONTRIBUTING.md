# Contributing to InnoDI

Thanks for contributing.

## Before Opening a PR

Please keep these checks green:

```bash
swift test
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
(cd Examples/SwiftUIExample && swift build && swift test)
(cd Examples/PreviewInjectionExample && swift build && swift test)
swift run InnoDI-DependencyGraph --root . --validate-dag
Tools/generate-docc.sh
```

## Documentation Contract

If behavior changes, update the docs in the same change.

Canonical sources:

- `README.md`
- `Sources/InnoDI/InnoDI.docc/*.md`
- `RELEASING.md`
- `ROADMAP.md`

Localized mirrors:

- `README.ko.md`
- `README.es.md`
- `README.de.md`
- `README.zh-Hans.md`
- `README.ja.md`
- `README.ru.md`
- `Sources/InnoDI/InnoDI.docc/*.lproj/*.md`

Keep the English docs authoritative, then mirror the same structure and meaning
into localized README and DocC files.

The generated DocC archive currently builds from the English base catalog, so
localized DocC files are maintained as source mirrors in the repository.

`Tools/check-localized-readme-sync.sh` runs in strict mode on every PR and
release: a swift fence count or H2 header count drift between the English
canonical and any localized README fails the build. When you add or remove an
H2 in `README.md`, mirror the change into all six localized files in the same
PR. The script accepts `INNODI_README_SYNC_STRICT=0` only as an explicit
soft-rollout window for canonical restructures.

## Code Coverage

The PR workflow runs `swift test --enable-code-coverage` once and feeds the
profile data into `Tools/collect-coverage.sh`, which exports a per-module
rollup. The rollup appears in the workflow run's step summary and is
uploaded as an `actions/upload-artifact` artifact named `coverage`. Locally:

```sh
swift test --enable-code-coverage
Tools/collect-coverage.sh
# → coverage/lcov.info, coverage/report.txt, coverage/summary.json, coverage/summary.md
```

Coverage is informational: it surfaces unexpected per-module drops without
gating merges on a threshold. Tests, examples, swift-syntax, and the
`.build` cache are excluded so the report tracks the library surface, not
fixtures or third-party code.

## Macro Performance Trend

`Tools/measure-macro-performance.sh --enforce` continues to compare each
PR against the pinned baseline JSON in
`Tools/macro-performance-baseline.json`. Alongside that, the PR pipeline
also runs `Tools/check-performance-trend.sh`, which compares the current
measurement against the rolling median of the last entries on the
`perf-history` branch. The dual gate is intentional: the pinned baseline
catches single-PR regressions, while the trend gate catches gradual
creep that under-threshold PRs accumulate over time.

The `Perf History` workflow runs on every push to `main` and uses
`Tools/append-performance-history.sh` to append one
`history/macro-performance/<UTC date>-<short sha>.json` entry to the
`perf-history` branch, then rebuilds `history/index.json`. The trend
script reads only that index — locally you do not need to checkout
`perf-history` yourself; the script fetches it and is a no-op when the
branch is empty or unreachable.

Tunables for the trend gate (set as environment variables):

- `INNODI_TREND_WINDOW` (default 7) — trailing entries used for the
  median.
- `INNODI_TREND_THRESHOLD_PCT` (default 10) — fail above this delta.
- `INNODI_TREND_MIN_SAMPLES` (default 5) — below this the gate just
  reports.
- `INNODI_TREND_REQUIRE_SAME_TOOLCHAIN` (default 1) — drop history
  entries that used a different `swift_version` than the current run.

When a Swift toolchain bump moves the absolute number, refresh
`Tools/macro-performance-baseline.json` with
`Tools/measure-macro-performance.sh --update-baseline` and let the trend
gate's same-toolchain filter fall through naturally.

## PR Expectations

- Keep changes scoped and explain user-facing behavior changes.
- Add or update tests for validation, diagnostics, graph output, SwiftUI helpers, or examples when behavior changes.
- If release notes, upgrade guidance, artifact naming, or schema expectations change, update `RELEASING.md` in the same change.
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
