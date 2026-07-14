# DIContainer

`@DIContainer` marks a supported, effectively non-generic struct at file scope
or in a non-generic nominal declaration as an InnoDI container and synthesizes
the container API surface.

InnoDI 5.0 requires both the struct and every enclosing nominal declaration to
omit generic parameters and generic `where` clauses. Classes, actors, enums,
protocols, extension declarations, structs declared inside extensions, and
structs in executable scopes such as functions, closures, accessors, or switch
cases are rejected. The same boundary applies when `@DIComponent` is stacked
on the container. Move runtime or type-specific state behind injected protocol
dependencies or `@Provide(.input)` values.

## Declaration

```swift
@DIContainer(root: Bool = false, validateDAG: Bool = true, mainActor: Bool = false)
```

## Generated Surface

`@DIContainer` synthesizes:

- a primary `init(...)`
- a nested `Overrides` type
- a convenience `init(<inputs...>, _ applyOverrides: ...)`
- four `withOverrides` effect overloads

Every supported container synthesizes the overrides scaffolding unless the
user already declares a nested `Overrides` type.

## Parameters

- `root`: Graph-render entry flag only. When at least one root exists, Mermaid,
  DOT, and ASCII output is pruned to the union of root-reachable nodes and
  edges.
- `validateDAG`: Enables global DAG validation plus the macro's local cycle and
  closure/`with:` graph-derived checks. When set to `false`, those checks are
  skipped, but raw-expression `factory:` and initializer references plus
  structural diagnostics still remain active.
- `mainActor`: Applies `@MainActor` isolation to dependency accessors, every
  generated initializer, `Overrides`, the `applyOverrides` function types used
  by convenience initializers, `withOverrides`, child overrides, and component
  mounting, all four `withOverrides` operation closures, and feature-root
  helpers. With `@DIComponent`, the generated `<Container>Dependencies`
  protocol and `init(dependencies:_:)` receive the same isolation, and the
  component conforms to the dedicated
  `_InnoDIMainActorComponentMountable` protocol. Components without the option
  continue to use `_InnoDIComponentMountable`. Keep non-`Sendable` generated
  values on the main actor by using an `@MainActor` caller or constructing and
  consuming them inside `MainActor.run`. A direct `await` is appropriate for an
  isolated operation that returns a `Sendable` result, not for carrying the
  container itself off actor.

## See Also

- <doc:Validation>
- <doc:Provide>
