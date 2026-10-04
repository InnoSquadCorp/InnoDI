# Provide

`@Provide` declares a container member and its construction strategy.

InnoDI 6.0 supports `@Provide` only on a direct, plain, stored instance `var` in
the same supported `struct` that carries `@DIContainer`. `let`, computed or
observed properties, `lazy`, `weak`, `unowned`, `static`/`class`, standalone,
and indirectly nested uses are rejected. InnoDI owns the generated provider
accessor; never attach `_InnoDIProvideAccessor(recovery:)` manually.

Provider declarations also use a closed attribute and access-control surface.
Property wrappers, conditional or unknown attributes, setter access modifiers
such as `private(set)`, and global-actor attributes are rejected. Besides
`@Provide` itself, no source-written property-level attribute is supported.
This prohibition includes `@MainActor`; use `@DIContainerRole(role: ContainerRole.local, mainActor: true)` for
actor isolation.
Isolation attributes InnoDI generates on the provider declaration and accessor
are internal compiler support. A complete `@Provide` member declaration inside
`#if` is rejected with
`provide.conditional-declaration-unsupported`; keep the declaration
unconditional and branch inside its factory or injected implementation.

Attach exactly one `@Provide` to each property. Duplicate attributes fail with
`provide.duplicate-attribute`. The explicit property type cannot be an opaque
`some Protocol` or an implicitly unwrapped optional `T!`; migrate to
`any Protocol`, or to explicit `T` / `T?`, respectively. A deliberately forged
combination of the compiler-support accessor with another property wrapper can
also receive Swift structural diagnostics in addition to InnoDI's misuse
diagnostic.

## Declaration

```swift
@Provide(
    _ scope: DIScope = .shared,
    _ type: Any.Type? = nil,
    with dependencies: [AnyKeyPath] = [],
    initialization: DIInitialization = .eager,
    effect: DIProviderEffect = .none,
    factory: Any? = nil,
    asyncFactory: Any? = nil
)
```

`effect:` is explicit test/preview metadata, not inferred behavior. Mark a live
network, persistence, process, device, or similarly observable provider as
`.sideEffect`. Its generated `Overrides` builder then exposes the requirement
to opt-in `InnoDITesting` validation. The default `.none` means “not classified
as requiring a strict override”; it does not prove that an opaque factory is
pure. Production construction never enables strict validation automatically.

## Input Values and Escaping Functions

Generated `@Input` initializer parameters are eager values of the declared
type `T`. Swift evaluates each argument before the initializer call, so
`try makeValue()` and `await makeValue()` remain valid argument expressions.
Directly spelled non-optional function types are detected automatically and
emitted as escaping parameters. If a non-optional function type is hidden
behind a typealias, declare `@Input(escaping: true)`.

`escaping:` must be a literal Boolean and is valid only for `@Input`. The opt-in
rejects obvious nonfunction and optional-function type shapes with stable
InnoDI diagnostics. Identifier and member types are accepted conservatively
because an attached macro cannot resolve arbitrary aliases; Swift may add its
own diagnostic if such an alias does not actually resolve to a non-optional
function type.

## Construction Modes

- `factory`: synchronous construction expression or root closure literal
- `asyncFactory`: asynchronous construction closure
- `Type.self`, optionally with `with:`: synchronous construction/autowiring
- property initializer: synchronous opaque construction

For `.shared` and `.transient`, choose exactly one mode. `@Input` chooses none
and also rejects `with:`.

## Sibling Edge Contract

Sibling DI edges use a closed, reviewable syntax:

- A root `factory:` or `asyncFactory:` closure literal declares one edge for
  each named parameter. Parameters in nested closures and arbitrary identifier
  references do not add edges.
- `Type.self` construction declares edges from a literal `with:` array. Every
  entry must use exactly the canonical direct-member spelling `\Self.member`,
  for example `with: [\Self.config]`; `with: []` is also valid. Named container,
  module-qualified, and typealias roots are rejected, as are nested components,
  optional chaining, subscripts, and computed elements. All targets must use
  synchronous construction.
- A non-closure `factory:` expression or property initializer is an opaque,
  zero-edge construction source. It must not reference sibling container
  members. Rewrite sibling wiring as root closure parameters. If construction
  intentionally has no DI edge, call a qualified global/static symbol.

## Rules

- `factory:`, `asyncFactory:`, `Type.self`, and a property initializer are
  mutually exclusive construction sources.
- `@Input` does not allow any construction source or `with:`.
- `.shared` and `.transient` require exactly one construction source.
- `with:` is allowed only with `Type.self` construction and synchronous
  providers.
- `asyncFactory` is supported for `.shared` and `.transient` and must be an
  `async` closure.
- The declared property type determines storage shape: a concrete nominal type
  uses concrete storage, while `any Protocol` uses existential storage.
- Name resolution for factory parameters and `with:` dependencies is strict by
  member name.

## Provider Effect Compatibility

Factory effects are explicit and are not inferred from dependencies. Use
`asyncFactory:` for an asynchronous consumer and spell `async throws` on the
closure when it consumes a throwing asynchronous provider. InnoDI validates
effect compatibility on every explicit sibling edge even when its container
uses `validateDAG: false`.

| Provider | sync consumer | `async` consumer | `async throws` consumer |
|---|---:|---:|---:|
| sync | allowed | allowed | allowed |
| `async` | rejected | allowed | allowed |
| `async throws` | rejected | rejected | allowed |
| `async` or `async throws`, `.onDemand` | rejected | rejected | allowed |

A read of an asynchronous on-demand provider can observe reader cancellation or
a closed provider, so it always has the `async throws` consumer effect.

`Lazy<T>` and `Provider<T>` remain synchronous deferred wrappers. Both reject
targets constructed by `asyncFactory:`. `with:`, `@Multibinding` contributors,
and `@SubContainer` child inputs also require synchronous parent members.

## Typed Synchronous Prewarming (7.0 Candidate)

A container with synchronous `.shared` providers using
`initialization: .onDemand` generates a nested `_InnoDIPrewarmProvider: Sendable` enum.
Its cases use those providers' names, so selections are checked by Swift:

```swift
@DIContainer
struct FeatureContainer {
    @Provide(.shared, initialization: .onDemand, factory: Metrics())
    var metrics: Metrics
    @Provide(.shared, initialization: .onDemand, factory: Analytics())
    var analytics: Analytics
}

let container = FeatureContainer()
container.prewarm(.metrics)
container.prewarm(.analytics, .metrics)

// An empty selection is a nonthrowing no-op.
container.prewarm()
```

The typed method is synchronous, nonthrowing, and returns no value. An empty
selection does nothing. Each selection dispatches directly to its provider in
argument order. The 7.0 candidate replaces the key-path overload.
Repeated selections and container copies reuse the existing shared cache.
Unselected providers stay lazy unless a selected factory needs them.

Inputs, eager providers, asynchronous providers, and transient providers have no
cases. A selection from another container has a different Swift type. The enum
is selection-only: it does not expose `get`, `resolve`, registration, or a runtime
registry. A token is `Sendable`; its provider's value need not be. Generated
prewarming methods preserve the container's main-actor isolation, and ordinary
synchronous containers keep value access on the caller.

The enum and typed method follow the container's access level, like its generated
initializer and `Overrides`. Cases expose construction names even when the
corresponding getters are less visible; selecting a case does not expose the
value. For an explicit annotation, spell
`FeatureContainer._InnoDIPrewarmProvider`. Contextual `.metrics` calls avoid that
longer compiler-owned name.

The `_InnoDI` prefix is already reserved for generated support. Authored direct
container declarations using it receive `container.reserved-name-prefix`.
No `PrewarmProvider` alias is generated, so ordinary global or nested payload
types with that name keep their meaning. The fixed prefixed spelling is an
explicit usability tradeoff, not a claim of universally collision-proof naming;
do not author names in the compiler-owned namespace. This API is included in
the unreleased 7.0 candidate; public API baseline review and supported Apple
toolchain qualification remain pending.

## Asynchronous Shared Lifetime

A `.shared` provider constructed by `asyncFactory:` is eager by default. It
starts an unstructured construction task while the container initializer runs,
before any read. Reads await that one task. The container never cancels it:
cancelling a reader does not cancel construction, and releasing the container
does not cancel work that has already started.

Each read of a `.transient` `@SubContainer` builds a fresh child container, so
every read starts that child's eager asynchronous `.shared` providers again.

Add `initialization: .onDemand` to construct the value on its first read
instead:

<!-- innodi:compile -->
```swift
import InnoDI

struct APIClient: Sendable {}

struct Session: Sendable {
    static func open(client: APIClient) async throws -> Session { Session() }
}

@DIContainer
struct AppContainer {
    @Input var client: APIClient

    @Provide(.shared, initialization: .onDemand, asyncFactory: { (client: APIClient) async throws in
        try await Session.open(client: client)
    })
    var session: Session
}

func run(_ container: AppContainer) async throws {
    let session = try await container.session
    _ = session
    await container.closeAsyncProviders()
}
```

- The initializer starts nothing. The first read starts one construction task,
  and concurrent reads wait for it.
- Cancelling a reader cancels only that reader's wait. Construction continues
  for the other readers.
- The accessor is `get async throws` even when the factory does not throw.
- A value or a failure is cached for the lifetime of the provider, as with an
  eager provider.
- An override value completes the provider at initialization. The factory
  never runs.
- The value type and every dependency the factory captures must be
  `Sendable`. A main-actor container runs the factory on the main actor
  instead, so its captures follow main-actor rules.

A container with at least one asynchronous on-demand provider also gains
`closeAsyncProviders()`. Closing cancels in-flight construction, resumes every
waiting reader with ``DIAsyncScopeError/closed(providerID:)``, releases the
value, and makes later reads throw the same error. A construction that has not
begun never starts the factory; a factory already running observes
cancellation, and a value it returns anyway is discarded. An overridden
provider closes the same way and releases its value, so a test that overrides
it observes the production contract. The provider ID is
the member name. Closing is idempotent. Container copies share their providers, so closing any copy closes
them for every copy. Closing does not reach sub-containers.

An eager asynchronous consumer still starts during initialization, so it
constructs every on-demand provider it depends on at that time.

Choose a `.transient` provider with `asyncFactory:` when every read should
construct a fresh value. Inject a ``DIAsyncScope`` as an `@Input` when
that transient use case needs a custom lifecycle adapter. For supported shared
graphs, `generateOwned: true` adds typed preparation, retry and explicit close;
see <doc:OwnedContainers>.

## See Also

- ``Provide(_:_:with:initialization:effect:collection:factory:asyncFactory:)``
- ``DIScope``
- <doc:Validation>

### Migrating prewarm selections

Replace `try container.prewarm(\FeatureContainer.metrics)` with
`container.prewarm(.metrics)` and remove `try` from empty calls. A codemod can
rewrite simple literal key paths once their receiver/container identity is
resolved, but arbitrary `PartialKeyPath` variables and generic key-path APIs do
not convert automatically. Store the concrete container's generated token type,
or redesign the generic adapter around an explicit warming closure. Unsupported
providers now fail at compilation instead of throwing `DIPrewarmError` at runtime.
There is no reflection-based conversion or fallback key-path resolver.
`InnoDI-Migrate` does not rewrite prewarm calls; apply this migration by hand.
`DIPrewarmError` remains declared for compatibility.
