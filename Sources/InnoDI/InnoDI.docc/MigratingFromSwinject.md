# Migrating from Swinject

Move Swinject registrations and assemblies into generated InnoDI containers.

## Overview

Swinject registers factories in a `Container` at runtime and resolves them
with `resolve(_:)`, which returns an optional. InnoDI generates the container
initializer instead, so a missing or mistyped dependency fails at compile time
or build time rather than at a force unwrap. Migration moves each registration
into a `@Provide` member and each `r.resolve(...)` call into a named
factory-closure parameter.

InnoDI intentionally has no runtime registration API, no named registrations,
and no weak object scope. Late binding and plugin-style composition remain a
better fit for a runtime container.

## Concept Map

| Swinject | InnoDI |
|---|---|
| `container.register(API.self) { _ in LiveAPI() }` | `@Provide(.shared, factory: LiveAPI()) var api: any API` |
| `.inObjectScope(.container)` | `.shared` |
| `.inObjectScope(.transient)` | `.transient` |
| Default `.graph` scope | `.shared` members of a `.transient` `@SubContainer`, which builds one child per read |
| `.inObjectScope(.weak)` | No equivalent. InnoDI holds strong references. |
| `r.resolve(Dependency.self)!` inside a registration | A named factory-closure parameter such as `{ (dependency: Dependency) in ... }`, checked at compile time |
| `register(_:name:)` | Separate members with distinct names, such as `primaryDatabase` and `cacheDatabase` |
| `register { (r, userID: Int) in ... }` with `resolve(_:argument:)` | `@Input(.assisted)` plus `@AssistedFactory` and `@SubContainerFactory` |
| `Assembly` and `Assembler` | One `@DIContainer` per feature, mounted by its parent with `@SubContainer`. Use `@DIContainerRole(role: ContainerRole.component)` for a feature that another module mounts. |
| `initCompleted` property injection for cycles | Not supported. InnoDI rejects dependency cycles, including cycles through `Lazy` and `Provider`; move shared state into a separate dependency. |
| Re-registering a mock in tests | The generated `Overrides` builder or `withOverrides` |

## Migration Steps

1. Convert one `Assembly` at a time into a `@DIContainer`. Values the assembly
   read from outside, such as configuration, become `@Input` members.
2. Replace each `register` call with a `@Provide` member. Choose the scope from
   the concept map; Swinject's default `.graph` scope has no direct
   equivalent, so decide whether the value should be `.shared` or
   `.transient`.
3. Replace each `r.resolve(...)!` with a factory-closure parameter whose name
   matches the dependency member.
4. Replace named registrations with separately named members, and
   argument-taking registrations with an assisted factory.
5. Break any cycle that relied on `initCompleted`. Attach
   `InnoDIDAGValidationPlugin` to every container target so the build rejects
   new cycles.

Swinject and InnoDI can coexist during the transition. Resolve a value from
the Swinject container at the composition root and pass it into an InnoDI
container as an `@Input`.

## Example

The comments name the Swinject registration each member replaces. The
session container shows the assisted-factory replacement for
`resolve(_:argument:)`.

<!-- innodi:compile -->
```swift
import InnoDI

final class Database {
    let path: String

    init(path: String) {
        self.path = path
    }
}

final class SessionStore {
    let userID: Int
    let database: Database

    init(userID: Int, database: Database) {
        self.userID = userID
        self.database = database
    }
}

@DIContainer
struct SessionContainer {
    @Input(.assisted) var userID: Int
    @Input var database: Database

    @Provide(.shared, factory: { (userID: Int, database: Database) in
        SessionStore(userID: userID, database: database)
    })
    var store: SessionStore

    @AssistedFactory(
        SessionContainer.self,
        static: [\SessionContainer.database],
        assisted: [\SessionContainer.userID]
    )
    struct AssistedFactory {}
}

@DIContainer
struct AppContainer {
    // Swinject: `register(Database.self) { _ in ... }.inObjectScope(.container)`
    @Provide(.shared, factory: Database(path: "app.sqlite"))
    var database: Database

    // Swinject: `register(SessionStore.self) { (r, userID: Int) in ... }`
    @SubContainerFactory(
        SessionContainer.self,
        bindings: [(child: \SessionContainer.database, parent: \Self.database)]
    )
    var session: SessionContainer.AssistedFactory
}

let app = AppContainer()
let session = app.session(userID: 42)
print(session.store.userID, session.store.database === app.database)
```

## See Also

- <doc:MigratingFromFactory>
- <doc:DIContainer>
- <doc:PolicyBoundaries>
