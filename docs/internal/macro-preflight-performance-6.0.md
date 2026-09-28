# Macro recovery preflight performance

## Trigger and scope

Candidate `115e3f0dec968256edfffadca562b4eee4378709`, Macro Tests run
[36371632099](https://github.com/InnoSquadCorp/InnoDI/actions/runs/36371632099),
failed the composite-v2 gate: minimum 307.590 ms against the unchanged
227.409 ms baseline and 20% limit (272.8908 ms). Trace performance passed.
All thirty macro samples are preserved in that run's artifact. This failure
is not dismissed as runner noise or repaired by replacing calibration data.

The only intervening macro-source change concerned checked on-demand captures;
the representative fixture does not use that path. The reports alone do not
establish the cause of the timing difference from the preceding passing run.
Profiling instead identified a concrete, independently avoidable cost.

## Evidence and implementation

An attached Instruments 27 Time Profiler captured ten seconds of the actual
composite benchmark on local Swift 6.4 / macOS 27, using its Debug configuration.
This intentionally profiles the failing gate's configuration, not optimized
Release consumer latency. Each before/after run used the unchanged v2 fixture,
80 warmups and 80 samples; these diagnostic timings do not recalibrate CI.

The child member-attribute role parsed and validated the parent, then generated
its entire initializer, overrides and feature-root syntax only to discard it.
`subContainerMemberValidationRecovery` accounted for 7.67% inclusive sampled
CPU weight. After the change this was 1.48%; full `generateAll` fell from 13.82%
to 7.43%. These are sampled proportions, not additive wall-clock durations.
Local sampled-run minima were 223.828 → 206.483 ms; means were 230.736 →
215.666 ms. All samples, including profiler perturbations, remain retained.

Recovery now uses the same initializer planner and throwing factory/dependency
builders with a lazy nonthrowing statement buffer. Invalid models still run
the exact invariant checks. No cache, process-global model retention or new
concurrency boundary is introduced. Nonthrowing overrides and feature-root
emission is omitted in this check-only path. Each of the four override methods
now carries its own MARK label, removing the possibility of parallel label and
method arrays getting out of sync. Normal emitted syntax stays unchanged.

## Validation and limits

- Seven invalid codegen models compare preflight errors with full emission:
  missing factory, hard/soft/provider/async/typed-wiring missing dependencies,
  and a reachable detached-transient cycle.
- Five valid models compare emission before/after preflight, including
  on-demand async chains and transient children. The four overloads remain.
- Explicit `validateDAG: false` recovery retains its documented fallback.
- Existing snapshots, diagnostics and compiler contracts remain required.
- The first new test run exposed fixture/assertion mistakes (unformatted AST
  substring checks and noncanonical typed wiring), not product failures; those
  controls were corrected before accepting the parity result.
- Raw traces stay outside Git: Instruments records local environment metadata.
- The benchmark fixture, sample policy, compiler pin, baseline and tolerance
  are unchanged. Only a fresh candidate-bound pinned-CI run can close the gate.
  Local improvement does not establish the cause of the earlier CI variance.
