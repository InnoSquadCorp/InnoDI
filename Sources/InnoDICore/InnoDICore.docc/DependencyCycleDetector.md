# Dependency Cycle Detector

Iterative DFS over an adjacency list with a configurable depth cap.

## Overview

`detectDependencyCycles(adjacency:depthLimit:)` is the primitive that
powers both the per-container macro validator and the global DAG CLI.
It returns every distinct elementary cycle in the graph, keyed by the
lexicographically smallest rotation of the cycle core — so callers get
a stable, deduplicated list across runs.

### Determinism

Neighbors are sorted before traversal; start nodes are sorted too. This
is the property that keeps diagnostic output and snapshot tests stable
when the input adjacency comes from a dictionary whose iteration order
is not defined.

### Safety

The implementation uses an explicit frame stack rather than Swift's
native call stack, so adversarially deep graphs cannot overflow. A
configurable `depthLimit` (default: 4096) abandons any branch that
exceeds it, returning no cycles for that branch rather than crashing.
That default is well above realistic DI depths; lowering it is useful
primarily in tests that exercise the fallback.

### Canonical rotation

Elementary cycles in a dependency graph never repeat a node, so the
smallest-node anchor produces the unique canonical rotation in O(n).
A tie-breaking path is retained for the rare degenerate case where two
nodes share an id — it keeps canonicalization idempotent even there.

## Topics

### Public API

- `detectDependencyCycles(adjacency:depthLimit:)`
