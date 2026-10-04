# Transient child resolver capture regression

## Cause and change

At baseline `b2a89f53b6f1674d2853da5707e9061c3e5ab15d`, the peer
builder for an ordinary transient child was explicitly `@Sendable () -> Child`.
After deferred resolver cells correctly lost unchecked Sendable conformance,
that builder could no longer capture its initialization-local cell. A minimal
actual-plugin consumer reproduced the same compiler diagnostic as Apple CI.
This is an explicit generated type requirement, not a package-level
`InferSendableFromCaptures` setting.

`subContainerBuildClosurePeerDecl` now emits an ordinary `() -> Child` for an
ordinary container. The MainActor-specific function type remains
`@_Concurrency.MainActor @Sendable () -> Child`. Source-written MainActor
containers also retain their enclosing actor isolation. No cell Sendable
conformance, transfer wrapper, binding order, async startup, or resolver body
changed.

## Contract checks

The new actual-plugin `TransientChildren.swift.fixture` covers automatic,
`with:`, and `bindings:` wiring under ordinary and MainActor isolation. Inputs
and child storage intentionally use mutable, non-Sendable reference types.
The executable verifies input identity, fresh child storage on every read,
child overrides, direct replacement precedence, and weak input release. The
source-written MainActor parent explicitly conforms to Sendable.

Two negative consumers verify that an ordinary parent cannot escape through
an `@Sendable` closure and that a MainActor child's accessor cannot be called
from a nonisolated function. Existing deferred-cell negatives remain compiler
errors, while safe asynchronous and exclusively transferred resolver controls
still execute successfully.

An ordinary parent explicitly declaring Sendable remains rejected before and
after this change: its existing `_override_sub_apply_child` stored closure is
non-Sendable even when the input and child themselves conform to Sendable.
The patch does not attempt to introduce a new cross-actor ordinary-container
contract or require all child inputs/results to be Sendable.

## Verification

All commands use Swift 6 language mode, complete strict concurrency, and
warnings as errors. The plugin is compiled from the candidate macro sources
against source-built SwiftSyntax 604.0.0; runtime tests use real generated code.

| Check | Result |
| --- | --- |
| Minimal synchronous transient child, baseline plugin | Reproduces the CI capture error |
| Same minimal source, candidate plugin | Compiles and runs |
| New six-shape positive consumer, Swift 6.2/6.3/6.4 | Compiles and runs on all three |
| New Sendable and actor escape negatives, Swift 6.2/6.3/6.4 | Intended compiler diagnostics on all three |
| Existing SubContainerRuntimeTests and EagerAsyncLifetimeTests | 20 tests pass |
| Focused container, sub-container, isolation and async-parent macro tests | 106 tests pass; no snapshot changes |
| Full owned portable plugin validator, Swift 6.4 | Passes, including 35 intended diagnostic checks |
| Safe deferred async consumer, Swift 6.2/6.3/6.4 | Compiles and runs on all three |

This is Linux actual-plugin verification. It does not qualify Apple-only
`AsyncSharedCell` execution or replace the full Apple package/coverage CI run.
Exact-head Apple CI remains required before release qualification.

The separate baseline and candidate executables, source copies, commands,
source/tool hashes, diagnostics, and results are retained in the task evidence
under `transient-child-capture-v1`; no prior plugin artifact was overwritten.

- Baseline plugin SHA-256: `bffc09c0f9c15c6c4638dcdd87c7155d9e2da59afebddaab5263c042d8a3a9de`
- Candidate plugin SHA-256: `f0d57530426bad9d1fa136c972f194c5931153bdc3ebeb5a3f53ebad8f12780d`
