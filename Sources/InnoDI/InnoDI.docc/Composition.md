# Assisted Factories and Collections

Use explicit composition when children need call-time inputs or modules export
ordered contributions. These APIs are part of the current 7.0.1 surface; no
runtime registration or implicit module discovery is involved.

## Choose a Composition Boundary

- `@SubContainer`: a fixed child with inputs supplied by its parent
- `@SubContainerFactory`: a parent-owned factory for children with assisted inputs
- `@Multibinding`: a typed array of synchronous sibling dependencies
- Collection value/provider types: explicitly compose exported module outputs

Attach the validation plugin to every declaring target. Keep source-visible
factory declarations in the child so another file or module can name them.

## Assisted Child Inputs

Ordinary `@Input` values are captured by the child factory. `@Input(.assisted)`
values are arguments supplied when calling it. Declare an empty nested
`AssistedFactory` with the matching macro and explicit static/assisted lists.

<!-- innodi:compile -->
```swift
import InnoDI

struct Repository {}

@DIContainer
struct SessionContainer {
    @Input var repository: Repository
    @Input(.assisted) var sessionID: Int

    @AssistedFactory(
        SessionContainer.self,
        static: [\SessionContainer.repository],
        assisted: [\SessionContainer.sessionID]
    )
    struct AssistedFactory {}
}

@DIContainer
struct AppContainer {
    @Input var repository: Repository

    @SubContainerFactory(
        SessionContainer.self,
        bindings: [(child: \SessionContainer.repository, parent: \Self.repository)]
    )
    var session: SessionContainer.AssistedFactory
}

let app = AppContainer(repository: Repository())
let first = app.session(sessionID: 1)
let second = app.session(sessionID: 2)
precondition(first.sessionID == 1 && second.sessionID == 2)
```

The parent `bindings:` list must bind every ordinary child input exactly once
and must not bind assisted inputs. Parent paths use canonical `\Self.member`;
child paths name that child's input. Each factory call creates a child;
`.shared` providers inside it belong to that new child. Static parent values
can still be shared between children. Resolving static bindings can eagerly
read a parent's on-demand provider when the factory itself is constructed.

For a child in another module, use `@DIContainerRole(role: ContainerRole.component)`
and expose the child, its inputs, and nested factory at the required access
level. See the repository's cross-module external consumer fixture rather
than relying on an internal same-file example for access control.

This factory does not automatically establish an owned async lifecycle. See
<doc:OwnedContainers> and <doc:SwiftUIPreviewHelper> for owned scopes and
identity-based hosts; check their supported shapes before combining features.

## Ordered and Keyed Values

`@Multibinding` preserves contributor order. Contributors must be synchronous,
direct managed members assignable to the declared array element type. Swift's
generated array checks assignability, including concrete values contributing
to an existential array. An empty `[]` is an explicit empty contribution.

<!-- innodi:compile -->
```swift
import InnoDI

protocol Service { var name: String { get } }
struct AuthService: Service { let name = "auth" }
struct LogService: Service { let name = "log" }

@DIContainer
struct AppContainer {
    @Provide(.shared, factory: AuthService()) var auth: AuthService
    @Provide(.transient, factory: LogService()) var log: LogService
    @Multibinding([\Self.auth, \Self.log]) var services: [any Service]
}

let app = AppContainer()
precondition(app.services.map(\.name) == ["auth", "log"])

let first = DICollectionGroup([1, 2])
let second = DICollectionGroup([3])
precondition(Array(DICollectionGroup.compose([first, second])) == [1, 2, 3])

let keyed = try DIKeyedCollection<String, Int>([
    .init(key: "auth", value: 1),
    .init(key: "log", value: 2),
])
precondition(keyed[key: "auth"] == 1)
```

Reading a multibinding reads each contributor through its accessor, preserving
its lifetime and overrides. The collection itself also has an override slot.
`DICollectionGroup.compose` concatenates named groups in caller order.
`DIKeyedCollection` preserves entry order and returns an optional value for a
key. Construction and composition throw `DIKeyedCollectionDuplicateError` for
duplicate keys; no value silently replaces an earlier contribution.

## Deferred Collections and Graph Metadata

`DIProviderCollection` stores synchronous closures and resolves only the
selected index. `DIKeyedProviderCollection` resolves a selected key, or exposes
an entry whose `callAsFunction()` resolves it. Repeated reads invoke the
closure again; the closure's target determines caching. Iterating an entire
provider collection can resolve every selected element. Provider collections
are not a promise of async support or `Sendable` conformance.

Runtime composition and graph metadata are separate. Factory-built collections
can supply `@Provide(collection:)` with `.ordered`, `.keyed`, `.providers`, or
`.keyedProviders`. Metadata uses literal canonical direct-member key paths;
keyed entries use `.init(key: "id", contributor: \Self.member)`. It describes
the declared graph but does not inspect or rewrite factory bodies. Keep the
actual construction and declared metadata aligned. Explicit empty metadata
is different from omitting metadata. Schema-v6 graph diffs include order,
keys, contributor identity and lifetime; use <doc:DAGValidation> to review them.

## Next Steps

- <doc:Tutorial-05-SubContainer>: fixed child wiring and child overrides
- <doc:Provide>: construction, effects and synchronous deferred wrappers
- <doc:OwnedContainers>: preparation, readiness and explicit cleanup
- <doc:MigrationGuide>: older vocabulary and removed prototype APIs
- <doc:DocumentationGuide>: complete task-based navigation
