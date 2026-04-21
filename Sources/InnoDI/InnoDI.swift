//
//  InnoDI.swift
//  InnoDI
//

/// Dependency lifecycle scopes used by `@Provide`.
public enum DIScope {
    /// A shared dependency initialized once per container instance.
    case shared
    /// An externally provided dependency supplied through container initialization.
    case input
    /// A dependency that is created every time it is accessed.
    case transient
}

@attached(member, names: named(init), named(Overrides), named(withOverrides))
/// Marks a type as an InnoDI container and synthesizes initialization/validation behavior.
///
/// - Parameters:
///   - validate: Reserved compatibility flag. Core construction invariants remain enforced regardless of this value.
///   - root: Marks this container as a root for dependency graph rendering.
///   - validateDAG: Includes this container in global/local DAG validation.
///   - mainActor: Isolates generated container API on the main actor.
public macro DIContainer(
    validate: Bool = true,
    root: Bool = false,
    validateDAG: Bool = true,
    mainActor: Bool = false
) = #externalMacro(module: "InnoDIMacros", type: "DIContainerMacro")

@attached(peer, names: prefixed(_storage_), prefixed(_storage_task_), prefixed(_override_))
@attached(accessor)
/// Declares a dependency member inside a `@DIContainer`.
///
/// - Parameters:
///   - scope: Dependency lifecycle scope.
///   - type: Optional concrete type expression used with `with` autowiring.
///   - dependencies: Key-path dependencies for `type`-based construction.
///   - factory: Synchronous factory expression.
///   - asyncFactory: Asynchronous factory closure expression.
///   - concrete: Explicit opt-in for concrete-type storage.
public macro Provide(
    _ scope: DIScope = .shared,
    _ type: Any.Type? = nil,
    with dependencies: [AnyKeyPath] = [],
    factory: Any? = nil,
    asyncFactory: Any? = nil,
    concrete: Bool = false
) = #externalMacro(module: "InnoDIMacros", type: "ProvideMacro")

/// A lazy reference to another container-managed dependency, used to break
/// otherwise-valid dependency cycles without restructuring.
///
/// When a factory parameter is declared `Lazy<T>`, InnoDI classifies the
/// resulting DAG edge as a *soft edge*: the dependency is resolved on demand
/// at call time rather than during container initialization, and the edge is
/// omitted from cycle detection. This lets authors express real
/// mutually-referential graphs like ViewModel↔Coordinator without the macro
/// rejecting the container.
///
/// ```swift
/// @DIContainer
/// struct AppContainer {
///     // Declare the soft-target side first. `a`'s factory only consumes
///     // the already-initialized `b` via a Lazy wrapper, so `a` compiles
///     // cleanly even though `b` references `a` in turn.
///     @Provide(.shared, factory: { (b: Lazy<CoordinatorB>) in CoordinatorA(b: b) })
///     var a: CoordinatorA
///
///     @Provide(.shared, factory: { (a: CoordinatorA) in CoordinatorB(a: a) })
///     var b: CoordinatorB
/// }
/// ```
///
/// `Lazy<T>` is invoked with `callAsFunction()`, so call sites read `b()` to
/// resolve the underlying dependency. It does not cache the resolved value —
/// the container's own `.shared` / `.transient` semantics continue to govern
/// the target's lifecycle. Do not call the wrapper inside the factory body
/// itself; only store it for later use, or the backing cell will not yet be
/// populated. `Lazy<T>` remains synchronous, so it cannot target `.shared`
/// members provided by `asyncFactory`.
///
/// ### Detection
/// The macro recognizes `Lazy` by its written identifier at the factory
/// parameter site (either `Lazy<T>` or `<Module>.Lazy<T>`). A `typealias`
/// that renames `Lazy` cannot be detected and will be treated as an ordinary
/// hard edge — use the canonical name at factory-parameter sites. If your
/// module also defines `Lazy<T>`, prefer spelling the wrapper as
/// `InnoDI.Lazy<T>` so the generated code preserves that qualification.
public struct Lazy<T> {
    @usableFromInline
    let resolver: () -> T

    /// Creates a lazy reference that invokes `resolver` on every access.
    @inlinable
    public init(_ resolver: @escaping () -> T) {
        self.resolver = resolver
    }

    /// Resolves the underlying dependency. Equivalent to `callAsFunction`.
    @inlinable
    public func callAsFunction() -> T {
        resolver()
    }
}

/// A factory handle that re-enters a `.transient` accessor on every call.
/// Use `Provider<T>` when a factory parameter needs repeated access to a
/// transient dependency without retaining the owning container.
///
/// When a factory parameter is declared `Provider<T>`, InnoDI classifies the
/// resulting DAG edge as a *provider edge*: like `Lazy<T>`, it is excluded
/// from cycle detection, but the validator additionally requires the target
/// member to have `.transient` scope so that `.callAsFunction()` semantics
/// stay aligned with transient re-entry. Live containers typically produce a
/// new instance on each call, but test overrides may still return a stored
/// value. `.shared` and `.input` targets are rejected with
/// `provide.provider-non-transient-target`.
///
/// ```swift
/// @DIContainer
/// struct AppContainer {
///     @Provide(.input) var config: Config
///
///     @Provide(.transient, factory: { (config: Config) in
///         Request(config: config)
///     })
///     var request: Request
///
///     @Provide(.shared, factory: { (requests: Provider<Request>) in
///         RequestLogger(requests: requests)
///     })
///     var logger: RequestLogger
/// }
///
/// final class RequestLogger {
///     let requests: Provider<Request>
///     init(requests: Provider<Request>) { self.requests = requests }
///     func logNew() {
///         let request = requests() // re-enters `.transient`; overrides may reuse a stored value
///         _ = request
///     }
/// }
/// ```
///
/// `Provider<T>` is invoked with `callAsFunction()`, mirroring `Lazy<T>`'s
/// call-site ergonomics. Unlike `Lazy<T>`, it does not cache by itself —
/// each invocation re-enters the container's transient accessor, so live
/// containers typically build a new instance while overrides may return a
/// stored value. Do not call the wrapper inside a `.shared` factory or
/// `asyncFactory` body itself; store it or pass it downstream first, then
/// invoke it only after the container has finished initializing. InnoDI diagnoses direct `provider()` /
/// `provider.callAsFunction()` use inside shared construction, but indirect
/// eager calls routed through helper APIs can still fail if they resolve too
/// early.
///
/// ### Detection
/// The macro recognizes `Provider` by its written identifier at the factory
/// parameter site (either `Provider<T>` or `<Module>.Provider<T>`). A
/// `typealias` that renames `Provider` cannot be detected, matching the
/// `Lazy<T>` limitation. If your module also defines `Provider<T>`, prefer
/// spelling the wrapper as `InnoDI.Provider<T>` so the generated code
/// preserves that qualification.
public struct Provider<T> {
    @usableFromInline
    let resolver: () -> T

    /// Creates a provider handle that invokes `resolver` on every access.
    @inlinable
    public init(_ resolver: @escaping () -> T) {
        self.resolver = resolver
    }

    /// Re-enters the underlying transient resolver. Live containers typically
    /// build a new instance; override-backed tests may return a stored value.
    /// Equivalent to `callAsFunction()`.
    @inlinable
    public func callAsFunction() -> T {
        resolver()
    }
}

/// Internal reference cell used by macro-generated init bodies to hand a
/// `Lazy<T>` wrapper to a factory whose soft-edge target has not yet been
/// assigned. The code generator:
///
/// 1. declares a local `let _lazyCell_<name> = _LazyCell<Type>()` at the top
///    of the synthesized init,
/// 2. passes `Lazy({ _lazyCell_<name>.resolve() })` to any soft factory
///    parameter, and
/// 3. either stores the concrete shared/input value or assigns a transient
///    resolver after the target accessor becomes available.
///
/// Users should not reach for this type directly — it is public only so that
/// macro output can reference it from arbitrary modules.
public final class _LazyCell<T>: @unchecked Sendable {
    public var value: T?
    public var resolver: (() -> T)?

    public init() {}

    public func resolve() -> T {
        if let value {
            return value
        }
        if let resolver {
            return resolver()
        }
        fatalError("_LazyCell resolved before the dependency was initialized.")
    }
}

/// Lifetime policy for a `@SubContainer`-owned child container.
///
/// - `shared`: The parent constructs and stores a single child instance
///   during parent initialization. All subsequent reads of the
///   sub-container property return the same instance — useful for
///   coordinator-like children whose internal `.shared` graph must remain
///   stable across views.
/// - `transient`: Every read of the sub-container property builds a fresh
///   child container with the current parent state. Useful for per-screen or
///   per-request scopes where the child has no identity of its own and only
///   acts as a wiring namespace.
///
/// Unlike `DIScope`, this enum intentionally excludes `.input`: a
/// sub-container is always owned by its parent and cannot be supplied from
/// the outside through the primary init — tests inject a replacement via the
/// generated `Overrides` builder instead.
public enum SubContainerScope {
    case shared
    case transient
}

/// Declares that a property owns a child `@DIContainer` whose `.input` members
/// should be wired automatically from the parent container's members.
///
/// ```swift
/// @DIContainer(root: true)
/// struct AppContainer {
///     @Provide(.input) var config: AppConfig
///     @Provide(.shared, factory: APIClient()) var apiClient: any APIClientProtocol
///
///     // `FeatureContainer.init(config:apiClient:)` is called automatically
///     // with parent members whose names match `config` / `apiClient`.
///     @SubContainer(scope: .shared)
///     var feature: FeatureContainer
/// }
/// ```
///
/// ### Parameters
/// - `scope`: Must be stated explicitly (`.shared` or `.transient`). There is
///   no default because the two lifetimes have very different runtime
///   implications (cached vs fresh), and forcing the author to pick makes the
///   intent visible at every declaration site.
/// - `with`: Optional keypath list used to re-map parent members when their
///   names do not match the child's `.input` parameter names. Each
///   `\.parentMember` keypath is passed positionally to the child init, so
///   the order must match the child's `.input` declaration order.
///
/// ### Wiring
/// The macro emits a parent-side property whose getter (for `.transient`) or
/// cached storage (for `.shared`) exposes a child built via
/// `Child(config: self.config, apiClient: self.apiClient, …)`. When `with:`
/// is empty the macro assumes each child `.input` parameter label matches a
/// parent member name. When `with:` is provided, the listed parent members
/// replace the auto-matched ones positionally. Any mismatch surfaces as a
/// regular Swift compile error from the child's synthesized init — the macro
/// does not pretend to verify the child's parameter list cross-file.
///
/// ### Overrides
/// `@DIContainer` extends its nested `Overrides` struct with two optional
/// slots per `@SubContainer` member:
///
/// - `var <name>: <ChildContainer>? = nil` — replaces the child entirely
///   (e.g. `overrides.feature = MockFeatureContainer(...)`).
/// - `var <name>Overrides: ((inout <ChildContainer>.Overrides) -> Void)? = nil`
///   — forwards a trailing-closure override block to the child's own
///   convenience init (`overrides.featureOverrides = { $0.store = Mock() }`).
///
/// Both slots are mutually exclusive: if the direct replacement is provided
/// it wins; otherwise the chain closure (if any) is forwarded. The second
/// slot requires the child to have its own `Overrides` builder — see the
/// README caveat for input-only children.
@attached(peer, names: prefixed(_storage_sub_), prefixed(_override_sub_), prefixed(_override_sub_apply_), prefixed(_innoDISubBuild_))
@attached(accessor)
public macro SubContainer(
    scope: SubContainerScope,
    with dependencies: [AnyKeyPath] = []
) = #externalMacro(module: "InnoDIMacros", type: "SubContainerMacro")
