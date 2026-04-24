# Dependency Graph Core

The vocabulary types every InnoDI graph consumer shares.

## Overview

A dependency graph is expressed as two flat collections:

- **Nodes** — one `DependencyGraphNode` per container type. Each carries
  a stable `id` (semantic path), a human-friendly `displayName`, a flag
  for whether the container is the hierarchy root, and the names of the
  `.input` members the parent must provide.
- **Edges** — one `DependencyGraphEdge` per wiring. Edges carry the
  source/target node IDs, an optional label (usually the member name
  that created the edge), and three booleans that describe the edge's
  semantics:

  - `isSoft` — `Lazy<T>` parameter. Excluded from cycle detection, rendered
    dashed.
  - `isProvider` — `Provider<T>` parameter. Excluded from cycle detection,
    rendered with a dotted glyph.
  - `isOwnership` — parent-owned `@SubContainer`. Participates in cycle
    detection (child construction happens during parent init) and is
    rendered with the `owns` label to emphasize the relationship.

Normal factory parameters land on the default (all three booleans
false) and behave as hard dependency edges.

## Building an adjacency list for cycle detection

`buildCycleDetectionAdjacency(nodes:edges:)` returns a dictionary
suitable for ``detectDependencyCycles(adjacency:depthLimit:)``. The
helper intentionally drops soft and provider edges so the cycle detector
sees only the hard-edged core — matching the macro-level per-container
validator's DFS.

Ownership edges stay hard even when a merged edge still carries deferred
flags from upstream callers: the parent constructs the child eagerly, so
ownership always participates in cycle analysis.
