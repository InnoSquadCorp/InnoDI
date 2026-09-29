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
waiting reader with ``DIAsyncScopeError/closed(providerID:)``, and makes later
reads throw the same error. An overridden provider closes the same way, so a
test that overrides it observes the production contract. The provider ID is
the member name. Closing is idempotent. Container copies share their providers, so closing any copy closes
them for every copy. Closing does not reach sub-containers.

An eager asynchronous consumer still starts during initialization, so it
constructs every on-demand provider it depends on at that time.

Choose a `.transient` provider with `asyncFactory:` when every read should
construct a fresh value. Inject a ``DIAsyncScope`` as an `@Input` when
construction also needs explicit preparation or retry.

## See Also

- ``Provide(_:_:with:initialization:effect:collection:factory:asyncFactory:)``
- ``DIScope``
- <doc:Validation>
