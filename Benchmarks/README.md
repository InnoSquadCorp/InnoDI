# Benchmarks

This directory contains performance benchmark scaffolding for InnoDI.

## Scenarios

- `10` dependencies
- `50` dependencies
- `100` dependencies
- `250` dependencies

## Run

```bash
Benchmarks/run-compile-bench.sh
Benchmarks/run-runtime-bench.sh
Benchmarks/compare.sh
```

## Output

Results are written as JSON:

- `Benchmarks/results/compile.json`
- `Benchmarks/results/runtime.json`
- `Benchmarks/results/compare.json`

## Notes

- InnoDI measurements are active.
- Needle/SafeDI entries are scaffolded as non-blocking comparison slots and marked `skipped` until scenario generators are added.
