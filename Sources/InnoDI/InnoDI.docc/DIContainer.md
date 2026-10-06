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
@DIContainer(
    validateDAG: Bool = true,
    initializationOrder: String = ContainerInitializationOrder.declaration,
    generateOwned: Bool = false
)
@DIContainerRole(
    role: String,
    mainActor: Bool = false,
    validateDAG: Bool = true,
    initializationOrder: String = ContainerInitializationOrder.declaration,
    generateOwned: Bool = false
)
```

## Generated Surface

`@DIContainer` synthesizes:

- a primary `init(...)`
- a nested `Overrides` type
- a convenience `init(<inputs...>, _ applyOverrides: ...)`
- four `withOverrides` effect overloads

For a container with neither explicit `@MainActor` nor `mainActor: true`, the generated `async` and
`async throws` `withOverrides` methods and their operation closure types are
`nonisolated(nonsending)`. They retain the caller's actor executor, so arbitrary
non-`Sendable` container and closure values do not cross an isolation boundary.
The synchronous overloads are unchanged. With explicit `@MainActor` or
`mainActor: true` on `@DIContainerRole`, every `withOverrides` overload and
operation closure remains on MainActor.

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

## Targets with default MainActor isolation

A syntactic macro does not receive the target's implicit default actor setting.
When using `.defaultIsolation(MainActor.self)` or the corresponding compiler
flag, spell the container's boundary explicitly: `@MainActor @DIContainer`,
`@DIContainerRole(role: ContainerRole.local, mainActor: true)`, or
`@DIContainer nonisolated struct Services` for a caller-isolated container.
This also applies to `generateOwned: true` and async `withOverrides`.

Leaving the container implicitly MainActor currently makes its generated
nonisolated async helpers call an isolated initializer. The compiler rejects
that shape; provider-level `nonisolated(nonsending)` does not repair this
container-construction boundary. An explicit actor declaration is the supported
workaround, not automatic detection of the build setting.

## Parameters

- `role`: Required by `@DIContainerRole`. Use `ContainerRole.local` for an
  explicit local boundary, `.component` for a cross-module mount contract, or
  `.root` for the hierarchy and graph-reachability entry point.
- `validateDAG`: Enables global DAG validation plus the macro's local
  graph-derived checks. When set to `false`, global DAG and local availability checks
  are skipped, but local ownership-cycle validation, declaration validation and
  effect compatibility on explicit sibling edges remain active.
- `mainActor`: Available on `@DIContainerRole`; applies `@MainActor` isolation to dependency accessors, every
  generated initializer, `Overrides`, the `applyOverrides` function types used
  by convenience initializers, `withOverrides`, child overrides, and component
  mounting, assisted factories, all four `withOverrides` operation closures, and feature-root
  helpers. A source-written `@MainActor` on the container selects the same policy.
  With `ContainerRole.component`, the generated `<Container>Dependencies`
  protocol and `init(dependencies:_:)` receive the same isolation, and the
  component conforms to the dedicated
  `_InnoDIMainActorComponentMountable` protocol. Components with neither the annotation nor the option
  continue to use `_InnoDIComponentMountable`. Keep non-`Sendable` generated
  values on the main actor by using an `@MainActor` caller or constructing and
  consuming them inside `MainActor.run`. A direct `await` is appropriate for an
  isolated operation that returns a `Sendable` result, not for carrying the
  container itself off actor.

## Opt-in Dependency Ordering

The default `ContainerInitializationOrder.declaration` preserves the existing
construction rules. Select `ContainerInitializationOrder.dependency` to wire
acyclic shared providers without moving their declarations above their users.
Only these named tokens, optionally qualified with `InnoDI.`, are accepted;
string literals, variables, and shorthand `.dependency` are not supported.

```swift
@DIContainer(initializationOrder: ContainerInitializationOrder.dependency)
struct AppContainer {
    @Provide(.shared, factory: { (configuration: Configuration) in
        Client(configuration: configuration)
    }) var client: Client
    @Provide(.shared, factory: Configuration()) var configuration: Configuration
}
```

The macro orders synchronous shared construction first, then asynchronous
shared handle creation. Within each stage, a hard dependency precedes its
consumer; among ready providers the earliest source declaration wins. Already
valid declaration-ordered containers retain their construction order. Inputs,
initializer argument order, override fields and child mounting stay unchanged.

This is an explicit behavior choice: a forward dependency can move observable
factory side effects. Review initialization traces when adopting it; no factory
is assumed pure. Async completion order is still determined by execution, and
independent tasks are not serialized. On-demand providers remain on-demand;
ordering their capture/cell setup does not prewarm unused services.

`Lazy` and `Provider` edges remain deferred, but still count for ownership-cycle
validation. Cycles remain errors, including with `validateDAG: false`. The opt-in
does not permit a sync factory to consume async work, a shared hard edge to a
transient provider, or a provider to depend on a child container. It does not
change close, cancellation, retry, or container-copy lifetime contracts.

Existing containers need no migration. Adoption adds one argument; do not
mechanically reorder declarations or change the default across an app without
reviewing side effects. This API was introduced in 7.0;
use the documentation tagged for your installed version.

## See Also

- <doc:Validation>
- <doc:Provide>
