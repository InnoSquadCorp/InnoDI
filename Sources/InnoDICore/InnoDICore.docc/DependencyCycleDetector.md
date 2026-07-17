# Dependency Cycle Detector

Iterative DFS over an adjacency list with a configurable depth cap.

## Overview

`analyzeDependencyCycles(adjacency:depthLimit:)` powers both the
per-container macro validator and the global DAG CLI. It returns a
deterministic set of DFS cycle witnesses plus a `truncatedByDepthLimit`
flag. Each witness is rotated to the lexicographically smallest form so
callers get stable, deduplicated diagnostics across runs. The older
`detectDependencyCycles(adjacency:depthLimit:)` API remains as a
cycle-list-only convenience wrapper.

The witness list is deliberately non-exhaustive. A directed graph can
contain exponentially many elementary cycles, while DAG validation only
needs one valid witness to reject a cyclic graph. When analysis is not
truncated, an empty witness list proves the graph is acyclic and a
non-empty list proves it is cyclic.

### Determinism

Neighbors are sorted before traversal; start nodes are sorted too. This
is the property that keeps diagnostic output and snapshot tests stable
when the input adjacency comes from a dictionary whose iteration order
is not defined.

### Safety

The implementation uses an explicit frame stack rather than Swift's
native call stack, so adversarially deep graphs cannot overflow. A
configurable `depthLimit` (default: 4096) abandons any branch that
exceeds it and marks the richer result as truncated rather than silently
passing validation. That default is well above realistic DI depths;
lowering it is useful primarily in tests that exercise the fallback.

### Canonical rotation

Cycle witnesses never repeat an internal node, so the smallest-node
anchor produces the unique canonical rotation in O(n).
A tie-breaking path is retained for the rare degenerate case where two
nodes share an id — it keeps canonicalization idempotent even there.

## Topics

### Public API

- `analyzeDependencyCycles(adjacency:depthLimit:)`
- `detectDependencyCycles(adjacency:depthLimit:)`
