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
    factory: Any? = nil,
    asyncFactory: Any? = nil
)
```

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

`Lazy<T>` and `Provider<T>` remain synchronous deferred wrappers. Both reject
targets constructed by `asyncFactory:`.

## See Also

- ``Provide(_:_:with:initialization:factory:asyncFactory:)``
- ``DIScope``
- <doc:Validation>
