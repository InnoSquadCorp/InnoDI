# Dependency Graph Core

The vocabulary types every InnoDI graph consumer shares.

## Overview

A dependency graph is expressed as two flat collections:

- **Nodes** — one `DependencyGraphNode` per container type. Each carries
  a stable `id` (semantic path), a human-friendly `displayName`, a flag
  for whether the container is the hierarchy root, and the names of the
  ordinary input members the parent must provide and a separate
  `assistedInputs` list supplied at child-factory call time.
- **Edges** — one `DependencyGraphEdge` per wiring. Edges carry the
  source/target node IDs, an optional label (usually the member name
  that created the edge), and semantic flags that describe the edge's
  semantics:

  - `isSoft` — `Lazy<T>` parameter. Excluded from cycle detection, rendered
    dashed.
  - `isProvider` — `Provider<T>` parameter. Excluded from cycle detection,
    rendered with a dotted glyph.
  - `isOwnership` — parent-owned `@SubContainer`. Participates in cycle
    detection (child construction happens during parent init) and is
    classified as `EdgeKind.ownership` by renderers so they can emphasize
    the relationship with their own label or style.
  - `isAssistedFactoryOwnership` — parent-owned child factory. It remains a
    hard ownership edge but serializes as `assistedFactoryOwnership` so tools
    can distinguish runtime-input child creation from a fixed child.
  - `isContribution` — ordered `@Multibinding` contributor metadata. The
    owning container is both endpoint; `contributor` and `order` identify the
    collection element. Contribution annotations are excluded from cycles.

Normal factory parameters land on the default (all three booleans
false) and behave as hard dependency edges.

## Building an adjacency list for cycle detection

`buildCycleDetectionAdjacency(nodes:edges:)` returns a dictionary
suitable for ``detectDependencyCycles(adjacency:depthLimit:)``. The
helper intentionally drops soft and provider edges so the cycle detector
sees only the hard-edged core — matching the macro-level per-container
validator's DFS.

Ordered contribution annotations are also dropped: they describe collection
membership within one container rather than a container construction edge.

Ownership edges stay hard even when a merged edge still carries deferred
flags from upstream callers: the parent constructs the child eagerly, so
ownership always participates in cycle analysis.
