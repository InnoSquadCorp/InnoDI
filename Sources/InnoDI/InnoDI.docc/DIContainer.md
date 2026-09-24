# DIContainer

`@DIContainer` marks a supported, effectively non-generic struct at file scope
or in a non-generic nominal declaration as an InnoDI container and synthesizes
the container API surface.

InnoDI 6.0 requires both the struct and every enclosing nominal declaration to
omit generic parameters and generic `where` clauses. Classes, actors, enums,
protocols, extension declarations, structs declared inside extensions, and
structs in executable scopes such as functions, closures, accessors, or switch
cases are rejected. The same boundary applies to `@DIContainerRole`. Move
runtime or type-specific state behind injected protocol dependencies or
`@Input` values.

An explicitly `private` container is also rejected because sibling containers
cannot access its generated mount surface. Use `fileprivate` for file-local
mounting, or put a default-access container inside a private namespace.

## Declaration

```swift
@DIContainer(validateDAG: Bool = true)
@DIContainerRole(role: String, mainActor: Bool = false, validateDAG: Bool = true)
```

## Generated Surface

`@DIContainer` synthesizes:

- a primary `init(...)`
- a nested `Overrides` type
- a convenience `init(<inputs...>, _ applyOverrides: ...)`
- four `withOverrides` effect overloads

For a plain `@DIContainer` or a role container without `mainActor: true`, the generated `async` and
`async throws` `withOverrides` methods and their operation closure types are
`nonisolated(nonsending)`. They retain the caller's actor executor, so arbitrary
non-`Sendable` container and closure values do not cross an isolation boundary.
The synchronous overloads are unchanged. With `mainActor: true` on
`@DIContainerRole`, every `withOverrides` overload and operation closure
remains `@MainActor`.

Every supported container, including one with no managed members, synthesizes
the complete overrides scaffolding. A user-declared nested `Overrides` type is
unsupported in InnoDI 6.0 and emits `container.overrides-name-conflict`; rename
it so the macro can own the mountable override ABI.

The macro also emits the reserved compiler-support alias
`_InnoDIMountOverrides = Overrides` for generated parent mounting code. Do not
declare or reference that underscored name directly.

Every stored instance member must use `@Provide` or `@SubContainer`.
Computed and type properties remain available. This lets the synthesized
initializer own all stored state and prevents memberwise-initializer ABI drift.

Every `@Provide` member must be a direct, plain, stored instance `var` in this
struct. InnoDI rejects `let`, computed/observed properties, storage modifiers
such as `lazy`, `weak`, and `unowned`, type properties, standalone providers,
and providers below an intervening declaration. Generated provider accessors
are internal compiler support and must not be attached manually.

The container graph reads sibling edges only from named parameters on root
`factory:`/`asyncFactory:` closure literals and from `Type.self` with literal
`with:` key paths. Non-closure factories and property initializers are opaque
zero-edge sources; they must not reference sibling members. Effect
compatibility on explicit edges is mandatory even with `validateDAG: false`.

## Parameters

- `role`: Required by `@DIContainerRole`. Use `ContainerRole.local` for an
  explicit local boundary, `.component` for a cross-module mount contract, or
  `.root` for the hierarchy and graph-reachability entry point.
- `validateDAG`: Enables global DAG validation plus the macro's local
  graph-derived checks. When set to `false`, global DAG and local cycle checks
  are skipped, but declaration validation and effect compatibility on explicit
  sibling edges still remain active.
- `mainActor`: Available on `@DIContainerRole`; applies `@MainActor` isolation to dependency accessors, every
  generated initializer, `Overrides`, the `applyOverrides` function types used
  by convenience initializers, `withOverrides`, child overrides, and component
  mounting, all four `withOverrides` operation closures, and feature-root
  helpers. With `ContainerRole.component`, the generated `<Container>Dependencies`
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
