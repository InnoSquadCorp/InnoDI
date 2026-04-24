# ``InnoDICore``

Shared parsing, graph modeling, and cycle-detection primitives that the
InnoDI macro implementations and build-time validator depend on.

## Overview

`InnoDICore` is deliberately low-level: no SwiftSyntax macro plumbing, no
filesystem I/O, no configuration layer. It exposes the data model and
algorithms that sit between raw source (parsed to SwiftSyntax) and the
two downstream consumers:

- **InnoDIMacros** — attached-macro implementations that expand
  `@DIContainer`, `@Provide`, `@SubContainer`, etc.
- **InnoDIBuildSupport** and **InnoDI-DependencyGraph** — the
  build-plugin coordinator and CLI that perform global DAG validation
  and rendering.

Third-party tools (alternative renderers, editor integrations, lint
rules) can depend on `InnoDICore` to reuse the same graph model and
cycle detector without pulling in the full macro stack.

## Topics

### Graph Model

- <doc:DependencyGraphCore>

### Cycle Detection

- <doc:DependencyCycleDetector>

### Semantic Resolution

- <doc:SemanticResolution>

### Parsing Helpers

The closure-parameter parser that powers `@Provide` soft/provider edge
detection lives in `Parsing.swift` (`parseClosureParameterNames`,
`DependencyKind`). It treats written syntax as the source of truth; it
does not follow `typealias` chains across files. Consumers that want to
detect aliased `Lazy<T>` / `Provider<T>` should use the macro-side
`DILazyProviderAliasCheck` facility instead.
