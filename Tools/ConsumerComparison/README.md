# Capability-matched consumer experiment

Status: the local runtime and native-effect scenarios have executed. Results
and limitations are in `docs/reviews/macro-first-results.ko.md`; no universal
competitive ranking is implied.

Entrypoints:
- `generate-consumers.py OUT PINNED_COMPETITORS` creates the graph lanes; export
  actual InnoDI AST first via `ConsumerComparisonExportTests` and the
  `INNODI_COMPARISON_EXPORT` environment variable, for each compared revision.
- `measure-consumers.py CONSUMERS OUT` runs existing release binaries serially,
  validates before timing and after debug stripping, and records hashes/raw data.
- `audit-boundaries.py CONSUMERS OUT_JSON` reads actual SwiftBuild task stores,
  compile/link commands and module source lists (requires Python msgpack).
- `measure-final-macro.py BASELINE_RUNNER CANDIDATE_RUNNER OUT` uses a fixed
  15-paired-block/30-sample protocol and whole-block resampling for composite-v2.
- `measure-prewarm.py CONSUMERS OUT` isolates old/typed generated dispatch while
  both lanes link the SAME baseline runtime package; builds before serial timing.
- `validate-effect-overrides.sh PINNED_DEPENDENCIES MACRO_PLUGIN PORTABLE_RUNTIME OUT`
  runs idiomatic swift-dependencies context and InnoDI explicit-passing scenarios.
  This is correctness/DX evidence, not a timed equivalent-lifetime comparison.

The official Needle generator build was attempted on the Linux VM without source
edits and failed in its upstream Objective-C Foundation bridge. Its runtime-only
lane remains explicitly manual and does not qualify generated wiring UX.

Pinned inputs: InnoDI baseline `6725e08`; Factory `3.4.1`; swift-dependencies
`1.17.1`; Needle `v0.25.1`; Swinject `2.10.0`. Capture actual revision hashes,
compiler, compiler flags, OS, CPU, cache state, binary sizes and raw samples.

The first lane is a 20-node synchronous shared/on-demand chain. Every program
uses the same `Node` and counter implementation. Before timing it must prove:

- no service construction before first access;
- exactly 20 constructions for the first leaf access;
- repeated access has the same identity and no additional construction;
- independent roots have separate services and counters;
- dependency IDs and checksum match, including an override variant.

Time cold graph construction + first resolution + release, first resolution
after root setup, and warm leaf access separately. Cold lifecycle resolves the
leaf inside the timed loop so unused root construction cannot be eliminated.
Use an identical noinline resolution boundary and observable checksum in all
programs. Report lifetime and access scope differences; do not substitute weak
shared scopes for retained container scopes. Library build/resolution time is
separate from the benchmark executable. Cold download is not cold compilation.

InnoDI's Linux lane uses actual macro and accessor AST output with unchanged
portable production runtime files. This does not build the full Apple product,
so its selective-runtime build cost is not a whole-package comparison. Its
Apple full package, SwiftUI and supported-toolchain qualification remain unrun.
Needle generator qualification must be distinguished from its runtime module;
handwritten provider-registration code is not counted as generated or validated.

A second idiomatic effect/override lane is required for swift-dependencies;
this library is not assumed to be a whole-object graph ownership system. Async
owner prepare/cancel/retry/close comparisons require equivalent adapters and
are unsupported until those adapters and their costs are explicitly included.

No source edits, unchecked concurrency relaxations, or platform-contract changes
to a competitor are allowed merely to make the experiment run on Linux.

The serial control uses ordinary Swift lazy properties, and is not a concurrent
cache comparator. Measurements report batch-mean per-operation time: p95 of
batch means is not individual-call p95. The shared managed VM is not a pinned
release runner. Alternate library ordering and retain every raw process result.
