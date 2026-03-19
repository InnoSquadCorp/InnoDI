# Benchmarks

This directory contains performance benchmark scaffolding for InnoDI.

## Presets

- `local`: default exploratory runs with broader iteration counts
- `ci`: lower-noise, lower-cost preset intended for regression gating in CI

## Run

```bash
Benchmarks/run-compile-bench.sh
Benchmarks/run-runtime-bench.sh
Benchmarks/run-validation-bench.sh --preset ci
Benchmarks/compare.sh --preset ci
```

Update the validation baseline only after an intentional performance change:

```bash
Benchmarks/compare.sh --preset ci --update-validation-baseline
```

## Outputs

Core benchmark outputs:

- `Benchmarks/results/compile.json`
- `Benchmarks/results/runtime.json`
- `Benchmarks/results/validation.json`
- `Benchmarks/results/compare.json`

Validation regression outputs:

- `Benchmarks/validation-performance-baseline.json`
- `Benchmarks/results/validation-compare.json`
- `Benchmarks/results/validation-compare.md`

## Validation Benchmark Contract

Validation benchmarks track:

- graph scan wall time
- coordinator cold-run wall time
- coordinator warm cache-hit wall time
- cache reason distribution summary

`compare.sh` uses the validation baseline and threshold to decide pass/fail:

- baseline within threshold: exit `0`
- threshold exceeded: exit non-zero and list offending metrics
- baseline update mode: refreshes the tracked validation baseline without gating

## Notes

- InnoDI measurements are active.
- Needle/SafeDI entries are scaffolded as non-blocking comparison slots and marked `skipped` until scenario generators are added.
- Validation benchmarks split graph scan, coordinator cold run, coordinator warm cache hit, and cache invalidation scenarios.
- Result and baseline JSON files are versioned schemas; update them intentionally and document schema changes in the release process.
