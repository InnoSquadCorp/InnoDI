# Trace performance: bounded UUID batching

## Baseline and diagnosis

The `d21cc25` release-validation run [36364377901](https://github.com/InnoSquadCorp/InnoDI/actions/runs/36364377901)
failed enabled tracing at 756.26 ns/event against the unchanged 600 ns budget.
Its other trace budgets passed. A local pass did not close that CI failure.

On 2026-09-28, a macOS 27 Apple Silicon host profiled the enabled owner path
using standalone Swift 6.3.3, the macOS 26.5 SDK, `-O -g -parse-as-library`,
and Xcode 27 Time Profiler. The diagnostic executable repeated the existing
20,000-resolution / 40,000-event workload 2,000 times, creating a fresh buffer
and owner per batch, then snapshotting the buffer. The first launch capture
contained only a dyld sample and was discarded; attaching to the running
executable produced useful 10-second traces. TOC-discovered `time-profile`
samples, rather than guessed table names, supplied the following diagnosis:

- UUID random generation occupied 27.87% inclusive sampled CPU time.
- Event copy and destruction also had substantial cost (10.94% and 11.43%
  inclusive respectively; inclusive weights overlap and must not be added).
- Inlining/ownership-forwarding experiments did not consistently improve
  elapsed time and were discarded.

## Change and compatibility

Each enabled owner lazily obtains 64 raw identifiers (1 KiB) from the OS
`arc4random_buf` facility. Its existing state lock protects refill and slot
consumption. Every returned UUID has the v4 version and RFC variant bits set;
all other bits come from the OS generator. There is no counter-derived ID,
cross-owner pool, unbounded allocation, provider payload, or persisted state.
Non-Darwin platforms retain `UUID()`. Disabled owners still allocate neither
state nor a batch. IDs are diagnostic identifiers, not security credentials.

The primitive is also used by Swift's Apple-platform
[system random generator](https://developer.apple.com/documentation/swift/systemrandomnumbergenerator).
The bit layout follows [RFC 9562 section 5.4](https://www.rfc-editor.org/rfc/rfc9562.html#section-5.4).
Tests cover 1, 63, 64, 65 and 1,025 resolutions per owner, independent owners,
concurrent same-provider resolutions, UUID text round trips, version/variant,
and preserved start/terminal/cache/wait correlations. These finite checks
detect implementation regressions; they are not a mathematical uniqueness proof.

## Measurements and limits

The unchanged release workload, compiled with local Swift 6.3.3, measured
379.94 ns/event from immutable baseline `31f2668` and 280.13 ns/event with
batching. The longer uninstrumented diagnostic measured 36.34 s before and
26.93 s after for 80 million events. Instrumented runs were retained separately;
they must not be compared to uninstrumented elapsed times. Other repository
builds can run on this development machine, so these are improvement evidence,
not a pinned CI calibration or a release verdict.

No thresholds, iteration counts, trace report schema, contention-overlap
requirements, or macro baseline were changed. Final release readiness still
requires all exact-candidate CI gates, including the existing trace gate.
Raw traces, exports, rejected experiments and command logs remain outside the
repository in the review evidence directory.
