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

`InnoDICore` is an internal target of the InnoDI package, not a package
product, so code outside the package cannot depend on it. The graph model,
`buildCycleDetectionAdjacency`, and the semantic resolver are declared
`package`, and nothing in this module carries a source-compatibility
promise. A tool outside the package reads the graph through
`InnoDI-DependencyGraph`, whose JSON output is the versioned contract.

## Topics

### Graph Model

- <doc:DependencyGraphCore>

### Cycle Detection

- <doc:DependencyCycleDetector>

### Semantic Resolution

- <doc:SemanticResolution>

### Macro-Side Parsing Helpers

The closure-parameter parser that powers `@Provide` soft/provider edge
detection lives in the `InnoDIMacros` target:
`ClosureSyntaxHelpers.swift` defines `parseClosureParameterNames`, and
`DIContainerModel.swift` defines `DependencyKind`. It treats written syntax
as the source of truth; it does not follow `typealias` chains across files.
The macro-side alias check in `DILazyProviderAliasCheck.swift` is internal
to that target and sees only the source the macro is expanded with, which in
a real build excludes file-scope aliases. The build plugin's
`deferred-alias.workspace-finding` warning and the `InnoDI-DeferredAliasScan`
target report aliased `Lazy<T>` / `Provider<T>` across the validated sources.
