//
//  InnoDI.swift
//  InnoDI
//

/// Dependency lifecycle scopes used by `@Provide`.
public enum DIScope {
    /// A shared dependency initialized once per container instance.
    case shared
    /// A dependency that is created every time it is accessed.
    case transient
}

/// Determines when an `@Input` value is supplied.
public enum DIInputKind {
    /// Supplied by the container's synthesized initializer.
    case container
    /// Supplied later by an assisted child-container factory call.
    case assisted
}

/// Selects when a shared provider creates its value.
public enum DIInitialization {
    /// Construct the value while the container initializer runs.
    case eager
    /// Construct the value on first access and cache it in a copy-shared cell.
    case onDemand
}

/// Raised when generated prewarming receives a key path that does not name an
/// on-demand shared provider on that container.
public enum DIPrewarmError: Error, Equatable, Sendable {
    case unsupportedProvider
}

/// Source tokens for declaring how a container participates in the application hierarchy.
///
/// The tokens are strings because Swift 6.2.3 crashes while matching a public
/// enum value passed to a multi-role attached macro. `@DIContainerRole`
/// validates that callers use one of these named tokens.
public enum ContainerRole {
    /// A container used only inside its declaring feature or module.
    public static let local = "local"
    /// A mountable feature boundary with a generated dependency contract.
    public static let component = "component"
    /// The root of strict hierarchy validation and graph reachability.
    public static let root = "root"
}

/// Compiler support used by generated invariant paths. Application code must
/// not call this function directly.
@_documentation(visibility: internal)
@inline(never)
public func _innoDITrap<T>(_ message: String) -> T {
    fatalError(message)
}

@attached(memberAttribute)
@attached(member, names: named(init), named(Overrides), named(withOverrides), arbitrary)
/// Marks a supported non-generic struct as an InnoDI container and synthesizes
/// initialization, overrides, and validation behavior.
///
/// - Parameter validateDAG: Enables global DAG validation plus the macro's
///   graph-derived local checks for this container. When set to `false`, global
///   DAG validation and local cycle checks are skipped, but declaration
///   diagnostics and effect compatibility on explicit sibling edges still apply.
///
/// The generated `async` and
/// `async throws` `withOverrides` methods and their operation closure types use
/// `nonisolated(nonsending)`. They retain the caller's actor executor, so an
/// arbitrary non-`Sendable` container and closure do not cross an isolation
/// boundary. Use `@DIContainerRole(role: ContainerRole.local, mainActor: true)`
/// when every generated API must be isolated to the main actor.
///
/// > Important: `validateDAG: false` is a narrow opt-out from the global
/// > DAG and local cycle gates. Treat it as a temporary fixture rather than
/// > a release-quality flag — production builds should keep the default. See
/// > <doc:DAGValidation> for the configuration-aware enforcement pattern.
/// > Every PR runs `Tools/report-validate-dag-escape-hatches.sh`, which
/// > lists every `@DIContainer(...validateDAG: false...)` site and any
/// > active `INNODI_DISABLE_BUILD_VALIDATION` environment override in the
/// > workflow's step summary so reviewers can audit escape-hatch creep
/// > without a separate gate.
///
/// > Important: InnoDI 6.0 supports only effectively non-generic structs at
/// > file scope or nested in non-generic nominal declarations. Neither the
/// > struct nor an enclosing nominal declaration may introduce generic
/// > parameters or a generic `where` clause. Classes, actors, enums, protocols,
/// > extension declarations, structs inside extensions, and structs in
/// > executable scopes such as functions, closures, accessors, or switch cases
/// > are rejected. Move runtime or type-specific state behind injected protocol
/// > dependencies or `@Input` values.
/// > Current Swift toolchains omit accessor ancestry from attached-macro
/// > context for a type inside a computed-property body. Attach the
/// > build-validation plugin to every container target so its full-source
/// > preflight enforces this edge case. Without it, companion macros stacked on
/// > an accessor-local container can emit secondary compiler or macro errors.
public macro DIContainer(
    validateDAG: Bool = true
) = #externalMacro(module: "InnoDIMacros", type: "DIContainerMacro")

@attached(memberAttribute)
@attached(member, names: named(init), named(Overrides), named(withOverrides), arbitrary)
@attached(peer, names: suffixed(Dependencies))
@attached(
    extension,
    conformances: _InnoDIComponentMountable, _InnoDIMainActorComponentMountable,
        DIHierarchyRootMarker,
    names: named(_InnoDIComponentDependencies), named(_InnoDIComponentOverrides)
)
/// Declares the explicit 6.0 hierarchy role for a container. Use the `.local`
/// token for an actor-isolated local container, `.component` for a mountable
/// feature boundary, and `.root` for the rooted validation entry point.
public macro DIContainerRole(
    role: String,
    mainActor: Bool = false,
    validateDAG: Bool = true
) = #externalMacro(module: "InnoDIMacros", type: "DIContainerRoleMacro")

@attached(member, names: named(init), named(callAsFunction), arbitrary)
/// Completes a source-visible child-owned assisted factory.
///
/// Declare an empty nested `AssistedFactory` inside a container that has at
/// least one `@Input(.assisted)` member. Keeping the nested type declaration
/// in source makes it visible to parents in another file of the same target;
/// the container and factory macros cooperatively supply its static-input
/// storage, initializer, and typed call while preserving source input order.
public macro AssistedFactory(
    _ child: Any.Type,
    static staticInputs: [AnyKeyPath],
    assisted assistedInputs: [AnyKeyPath]
) = #externalMacro(
    module: "InnoDIMacros",
    type: "AssistedFactoryMacro"
)

@_documentation(visibility: internal)
@attached(member, names: arbitrary)
/// Compiler support carrying child-input metadata from `@DIContainer` to its
/// nested `@AssistedFactory`. Application code must not attach this macro.
public macro _InnoDIAssistedFactoryMetadata(
    order: [String],
    escaping: [String],
    mainActor: Bool
) = #externalMacro(
    module: "InnoDIMacros",
    type: "InnoDIAssistedFactoryMetadataMacro"
)

@attached(peer, names: prefixed(_storage_), prefixed(_storage_task_), prefixed(_override_))
/// Declares a dependency on a direct, plain, stored instance `var` in the same
/// supported struct annotated with `@DIContainer`. `let`, computed or observed
/// properties, `lazy`, `weak`, `unowned`, `static`/`class`, standalone, and
/// indirectly nested uses are unsupported and fail closed at compile time.
/// Provider accessors are synthesized and owned by InnoDI; application code
/// must not attach ``_InnoDIProvideAccessor(recovery:)`` manually.
/// Property wrappers, conditional or unknown attributes, setter access
/// modifiers such as `private(set)`, and global-actor attributes are
/// unsupported. Besides `@Provide` itself, no source-written property-level
/// attribute is accepted. This prohibition includes `@MainActor`; use
/// `@DIContainerRole(role: ContainerRole.local, mainActor: true)` for actor isolation. Any isolation
/// attributes InnoDI generates on provider declarations and accessors are
/// internal compiler support. A complete provider declaration inside `#if` is
/// also unsupported; keep it unconditional and branch inside the factory or
/// injected implementation.
/// Attach exactly one `@Provide` to each property; duplicate provider
/// attributes are rejected. Provider properties and root factory dependency
/// parameters must use unescaped identifiers and unique effective names;
/// backtick-escaped spellings are rejected before generated storage or lookup
/// tables are emitted. The explicit property type must not be opaque
/// (`some Protocol`) or implicitly unwrapped (`T!`). Use an existential
/// `any Protocol`, or explicit `T` / `T?`, respectively. A deliberately forged
/// property-wrapper combination involving the compiler-support accessor can
/// also receive Swift structural diagnostics in addition to InnoDI's misuse
/// diagnostic.
/// The declared property type is the single source of truth for generated
/// storage: `ConcreteType` produces concrete storage, while `any Protocol`
/// produces existential storage.
///
/// Sibling DI edges use a closed syntax. They come only from named parameters
/// on the root `factory:` or `asyncFactory:` closure literal, or from `type`
/// construction paired with a literal `with:` key-path array. Every entry must
/// use exactly the canonical direct-member spelling `\Self.member`, such as
/// `[\Self.config]`; `[]` is also valid. Named container, module-qualified, and
/// typealias roots are unsupported, as are nested components, optional
/// chaining, subscripts, and computed elements. Every `with:` target must use
/// synchronous construction. Non-closure `factory:` expressions and property
/// initializers are opaque zero-edge construction sources and must not
/// reference sibling container members. Use root closure parameters for DI
/// wiring, or a qualified global/static construction symbol when no sibling
/// edge is intended.
///
/// A `.shared` or `.transient` provider declares exactly one construction
/// source: `factory:`, `asyncFactory:`, `Type.self`, or a property initializer.
/// - Parameters:
///   - scope: Dependency lifecycle scope. `.shared` and `.transient` require
///     exactly one construction source.
///   - type: Optional `Type.self` construction source. This is the only source
///     that accepts `with` autowiring.
///   - dependencies: A literal array containing only canonical direct-member
///     `\Self.member` key paths for `type`-based construction, or an empty
///     array. Every referenced provider must be synchronous.
///   - initialization: `.eager` preserves the default initialization-time
///     construction. `.onDemand` is available for synchronous `.shared`
///     providers and constructs once on first access. Value-type container
///     copies share the same cache cell; separately initialized containers do
///     not. Passing an override bypasses the original factory.
///   - factory: Synchronous factory expression. Only a root closure literal's
///     named parameters declare sibling DI edges; other expressions are opaque.
///   - asyncFactory: Explicit `async` or `async throws` factory closure for
///     `.shared` and `.transient` dependencies. Consumers must declare every
///     effect required by their providers; InnoDI does not infer effects, and
///     validates them even when the container uses `validateDAG: false`.
public macro Provide(
    _ scope: DIScope = .shared,
    _ type: Any.Type? = nil,
    with dependencies: [AnyKeyPath] = [],
    initialization: DIInitialization = .eager,
    factory: Any? = nil,
    asyncFactory: Any? = nil
) = #externalMacro(module: "InnoDIMacros", type: "ProvideMacro")

@attached(
    peer,
    names: prefixed(_storage_), prefixed(_storage_task_),
        prefixed(_override_), prefixed(_InnoDIInputType_)
)
/// Declares a required external value using the 6.0 input vocabulary.
///
/// Container inputs are synthesized initializer parameters. Assisted inputs are
/// retained in the normalized graph model and are consumed by an assisted
/// factory rather than by a parent container's static binding contract.
public macro Input(
    _ kind: DIInputKind = .container,
    escaping: Bool = false
) = #externalMacro(module: "InnoDIMacros", type: "ProvideMacro")

@attached(peer, names: prefixed(_override_))
/// Declares a deterministic, injectable collection of direct dependencies.
///
/// Contributors must be synchronous direct managed members assignable to the
/// collection element type. The generated array is a compiler-typed witness,
/// so concrete implementations can contribute to existential arrays. Literal
/// `\Self.member` key-path order is preserved; `[]` explicitly declares an
/// empty contribution. Reading the collection resolves each contributor
/// through its own accessor, retaining shared/transient lifetime and override
/// behavior; the collection itself can also be overridden for tests.
public macro Multibinding(
    _ contributors: [AnyKeyPath]
) = #externalMacro(module: "InnoDIMacros", type: "ProvideMacro")

@attached(peer, names: prefixed(_storage_), prefixed(_storage_task_), prefixed(_override_))
/// Owns a child container's assisted factory in its parent graph.
///
/// `bindings:` must bind every ordinary child `@Input` exactly once and must
/// not bind `@Input(.assisted)` values. Assisted values remain named arguments
/// of the child-owned factory's `callAsFunction` method.
public macro SubContainerFactory(
    _ child: Any.Type,
    bindings: [(child: AnyKeyPath, parent: AnyKeyPath)]
) = #externalMacro(module: "InnoDIMacros", type: "ProvideMacro")

/// Internal accessor and storage owner synthesized for direct provider members
/// by `@DIContainer`. Application code must not attach this macro manually.
@_documentation(visibility: internal)
@attached(accessor)
@attached(peer, names: prefixed(_storage_), prefixed(_storage_task_), prefixed(_override_))
public macro _InnoDIProvideAccessor(
    recovery: Bool
) = #externalMacro(module: "InnoDIMacros", type: "InnoDIProvideAccessorMacro")

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
/// populated. InnoDI diagnoses direct `lazy()` / `lazy.callAsFunction()` /
/// `lazy.resolver()` calls inside `.shared` construction; indirect eager calls
/// routed through helper APIs remain a policy boundary you should review
/// manually. `Lazy<T>` remains synchronous, so it cannot target `.shared` or
/// `.transient` members provided by `asyncFactory`.
///
/// `Lazy<T>` is intentionally a non-`Sendable` deferred handle. The wrapper
/// keeps evaluation on the container's original isolation domain, so actor
/// boundary transport is not supported even when `T: Sendable`.
///
/// ### Detection
/// The macro recognizes `Lazy` by its written identifier at the factory
/// parameter site (either `Lazy<T>` or `<Module>.Lazy<T>`). A `typealias`
/// that renames `Lazy` cannot be detected and will be treated as an ordinary
/// hard edge — use the canonical name at factory-parameter sites. If your
/// module also defines `Lazy<T>`, prefer spelling the wrapper as
/// `InnoDI.Lazy<T>` so the generated code preserves that qualification.
///
/// > Warning: Detection inside the macro plugin is by canonical
/// > identifier only. A typealias to `Lazy<T>` in the same file emits a
/// > warning; cross-file aliases the macro itself cannot see. Run
/// > `swift run InnoDI-DeferredAliasScan --root .` (the PR pipeline runs
/// > this on every build and uploads the JSON report) to enumerate
/// > cross-file aliases workspace-wide. A renamed alias the scanner
/// > flags silently behaves as a hard edge and disables cycle escape —
/// > prefer the canonical `Lazy<T>` or `InnoDI.Lazy<T>` spelling at
/// > every factory parameter site.
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
/// transient dependency without retaining the owning container. The generated
/// handle retains only the dependency and override context required to rebuild
/// `T`; it remains usable after the container value itself goes out of scope.
/// Releasing the last copied handle releases that detached context.
///
/// When a factory parameter is declared `Provider<T>`, InnoDI classifies the
/// resulting DAG edge as a *provider edge*: like `Lazy<T>`, it is excluded
/// from cycle detection, but the validator additionally requires the target
/// member to have `.transient` scope so that `.callAsFunction()` semantics
/// stay aligned with transient re-entry. Live containers typically produce a
/// new instance on each call, but test overrides may still return a stored
/// value. `.shared` and `@Input` targets are rejected with
/// `provide.provider-non-transient-target`.
/// Async transient targets are also rejected because `Provider<T>` is a
/// synchronous handle; use an explicitly async factory abstraction instead.
///
/// ```swift
/// @DIContainer
/// struct AppContainer {
///     @Input var config: Config
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
/// `Provider<T>` is intentionally a non-`Sendable` deferred handle. Provider
/// re-entry happens on the container's original isolation domain, so actor
/// boundary transport is not supported even when `T: Sendable`.
///
/// ### Detection
/// The macro recognizes `Provider` by its written identifier at the factory
/// parameter site (either `Provider<T>` or `<Module>.Provider<T>`). A
/// `typealias` that renames `Provider` cannot be detected, matching the
/// `Lazy<T>` limitation. If your module also defines `Provider<T>`, prefer
/// spelling the wrapper as `InnoDI.Provider<T>` so the generated code
/// preserves that qualification.
///
/// > Warning: Detection inside the macro plugin is by canonical
/// > identifier only. A typealias to `Provider<T>` in the same file emits
/// > a warning; cross-file aliases the macro itself cannot see. Run
/// > `swift run InnoDI-DeferredAliasScan --root .` (the PR pipeline runs
/// > this on every build and uploads the JSON report) to enumerate
/// > cross-file aliases workspace-wide. A renamed alias the scanner
/// > flags silently behaves as a hard edge with re-entry semantics lost
/// > — prefer the canonical `Provider<T>` or `InnoDI.Provider<T>`
/// > spelling at every factory parameter site.
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
/// A sub-container is always owned by its parent and cannot be declared with
/// `@Input` or supplied through the primary initializer. Tests inject a
/// replacement through the generated `Overrides` builder instead.
public enum SubContainerScope {
    /// Parent constructs and stores the child during parent initialization,
    /// then reuses that same instance on every access. Use for coordinator-
    /// like children whose internal `.shared` graph should remain stable.
    case shared
    /// Parent builds a fresh child on every property read. Use for screen- or
    /// request-scoped children that should not retain identity between reads.
    case transient
}

/// Declares a SwiftUI feature root view that should be exposed through a
/// parent container's `@SubContainer` member.
///
/// Use this value with `@SubContainer(featureRoots:)` when a child container
/// needs multiple root helpers or an explicit helper alias.
///
/// ```swift
/// @SubContainer(
///     scope: .shared,
///     featureRoots: [
///         FeatureRoot(DashboardRootView.self),
///         FeatureRoot(DashboardShellView.self, as: "dashboardShell")
///     ]
/// )
/// var dashboard: DashboardContainer
/// ```
///
/// The generated helpers instantiate each root view through
/// `RootView(container: <subContainer>)`.
public struct FeatureRoot {
    public let rootView: Any.Type
    public let alias: String?

    public init(_ rootView: Any.Type, as alias: String? = nil) {
        self.rootView = rootView
        self.alias = alias
    }
}

/// Declares that a property owns a child `@DIContainer` whose `@Input` members
/// are wired from the parent container's members.
///
/// ```swift
/// @DIContainerRole(role: ContainerRole.root)
/// struct AppContainer {
///     @Input var config: AppConfig
///     @Provide(.shared, factory: APIClient()) var apiClient: any APIClientProtocol
///
///     // Explicit same-name wiring calls
///     // `FeatureContainer.init(config:apiClient:)`.
///     @SubContainer(scope: .shared, with: [\.config, \.apiClient])
///     var feature: FeatureContainer
/// }
/// ```
///
/// ### Parameters
/// - `scope`: Must be stated explicitly (`.shared` or `.transient`). There is
///   no default because the two lifetimes have very different runtime
///   implications (cached vs fresh), and forcing the author to pick makes the
///   intent visible at every declaration site.
/// - `with`: Optional keypath list used to restrict or reorder which same-name
///   parent members are forwarded to the child. Each `\.parentMember` keypath
///   is passed with the same label on the child side. This must be a literal
///   array the macro can read, for example `with: [\.config]` or `with: []`.
/// - `bindings`: Optional explicit remapping tuples used when child `@Input`
///   labels differ from the parent member names. Each tuple spells
///   `(child: \.childInput, parent: \.parentMember)`. List tuples in the
///   child's `@Input` declaration order; the build validator reports the first
///   out-of-order child key path before Swift diagnoses the generated call.
/// - `featureRoot`: Optional SwiftUI root view type. When provided, the
///   parent container receives `<propertyName>RootView()`, which calls
///   `RootView(container: <propertyName>)`. Targets that import
///   `InnoDISwiftUI` also receive an identity-taking overload backed by
///   `DIContainerHost`; use that overload for route, document, and window
///   ownership so transient children are created only after mount and reused
///   across redraws. The zero-argument helper remains source-compatible.
/// - `featureRoots`: Optional list of SwiftUI root view declarations. Use
///   `FeatureRoot(View.self)` for the default helper or
///   `FeatureRoot(View.self, as: "alias")` for `aliasRootView()`.
///
/// `with` and `bindings` are mutually exclusive wiring forms: choose `with`
/// for same-name subset/reorder shorthand, or use `bindings` for rename-aware
/// explicit wiring.
///
/// ### Wiring
/// The macro emits a parent-side property whose getter (for `.transient`) or
/// cached storage (for `.shared`) exposes a child built via
/// `Child(config: self.config, apiClient: self.apiClient, …)`. With no
/// explicit wiring, the macro only applies same-name implicit wiring when the
/// parent has zero or one `@Provide` candidate; if multiple parent members
/// exist, InnoDI emits `sub.auto-wiring-ambiguous` and requires `with` or
/// `bindings`. When `with:` is provided, the listed parent members replace
/// the implicit set but keep their same-name labels; an empty list is an
/// explicit empty subset and generates `Child()`.
/// Runtime variables or computed array elements are not evaluated by the macro.
/// When `bindings:` is provided, each tuple rewrites the child label explicitly
/// while reading from the selected parent member. Child-input and declaration
/// order verification is handled conservatively by the build-support validator
/// across the complete visible source graph.
/// The property name must be an unescaped Swift identifier. Backtick-escaped
/// names are rejected because child storage, override slots, and SwiftUI helper
/// identities are derived from that spelling.
/// Declare exactly one `@SubContainer` on a direct, plain, stored instance
/// `var` in its supported parent `@DIContainer`, outside `#if`. InnoDI attaches
/// the hidden `_InnoDISubContainerAccessor` support; application code must not.
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
/// it wins; otherwise the chain closure (if any) is forwarded. Input-only
/// child containers synthesize an empty nested `Overrides` type, so chain
/// closures compile and execute as no-ops until the child gains overrideable
/// members.
///
/// > Note: `with:` and `bindings:` are the supported wiring forms. The
/// > legacy string-literal `withNames:` parameter was removed in 4.2 — use
/// > `with: [\.member]` for same-name forwarding or `bindings: [(child:
/// > \.x, parent: \.y)]` for explicit relabeling. See <doc:MigrationGuide>
/// > for the rationale and a stacked-peer-macro recipe.
@attached(peer)
public macro SubContainer(
    scope: SubContainerScope,
    with dependencies: [AnyKeyPath] = [],
    bindings: [(child: AnyKeyPath, parent: AnyKeyPath)] = [],
    featureRoot: Any.Type? = nil,
    featureRoots: [FeatureRoot] = []
) = #externalMacro(module: "InnoDIMacros", type: "SubContainerMacro")

/// Internal accessor and storage owner synthesized for direct child-container
/// members by `@DIContainer`. Application code must not attach this macro.
@_documentation(visibility: internal)
@attached(accessor)
@attached(peer, names: prefixed(_storage_sub_), prefixed(_override_sub_), prefixed(_override_sub_apply_), prefixed(_innoDISubBuild_))
public macro _InnoDISubContainerAccessor(
    recovery: Bool
) = #externalMacro(module: "InnoDIMacros", type: "InnoDISubContainerAccessorMacro")

/// Marker protocol synthesized for a component-role container.
///
/// Conforming containers expose a dependency-contract type plus an overrides
/// builder shape that other modules can mount through `@SubContainer` while
/// build validation enforces rooted hierarchy rules.
///
/// The protocol itself remains nonisolated so ordinary components do not
/// acquire actor requirements. A component role whose `@DIContainerRole`
/// opts into `mainActor: true` conforms to ``_InnoDIMainActorComponentMountable``
/// instead.
///
/// > Important: This protocol is an InnoDI implementation detail synthesized
/// > for a component-role container. The leading underscore marks it as SPI-in-spirit;
/// > application code should not conform to it manually.
@_documentation(visibility: internal)
public protocol _InnoDIComponentMountable {
    associatedtype _InnoDIComponentDependencies
    associatedtype _InnoDIComponentOverrides

    init(
        dependencies: _InnoDIComponentDependencies,
        _ applyOverrides: (inout _InnoDIComponentOverrides) -> Void
    )
}

/// Main-actor-isolated mounting marker synthesized when a component-role
/// container declares `mainActor: true`.
///
/// This protocol intentionally remains separate from
/// ``_InnoDIComponentMountable`` because actor isolation is part of a
/// function type. A plain override closure requirement cannot be witnessed by
/// an initializer whose closure is `@MainActor` without weakening the
/// generated API's concurrency contract.
///
/// > Important: This is an InnoDI implementation detail. Application code
/// > should not conform to it manually.
@_documentation(visibility: internal)
@MainActor
public protocol _InnoDIMainActorComponentMountable {
    associatedtype _InnoDIComponentDependencies
    associatedtype _InnoDIComponentOverrides

    init(
        dependencies: _InnoDIComponentDependencies,
        _ applyOverrides: @MainActor (inout _InnoDIComponentOverrides) -> Void
    )
}

/// Marker protocol synthesized by
/// `@DIContainerRole(role: ContainerRole.root)`.
///
/// The build-support hierarchy validator only enforces rooted component rules
/// for workspaces that declare at least one root container with this marker.
public protocol DIHierarchyRootMarker {}

/// Experimental — synthesizes a call-recording mock peer for a protocol.
///
/// `@GenerateMock` is the RFC 0001 entry point. Attach it to a protocol
/// declaration to have InnoDI emit a `Mock` peer with stubbed return
/// values, recorded call lists, and protocol conformance. The 6.0 candidate
/// supports top-level protocols, overload-qualified helper names, typed
/// throws, `@MainActor` protocols, and lock-backed `Sendable` protocols.
/// `Sendable` mock consumers also add the `InnoDITesting` product, which owns
/// the concurrency-safe storage and interaction validation helpers. Generic
/// method requirements continue to use erased handlers on non-`Sendable`
/// protocols.
/// The `Overrides` builder bundling option remains planned (see
/// `bundleWithOverrides:`).
///
/// Track RFC 0001 (`docs/rfcs/0001-macro-mock-generation.md`) for the
/// rollout schedule. Adoption remains opt-in through InnoDI 6.0; the macro
/// reaches GA only after RFC 0001's dedicated promotion criteria pass, and
/// the generated shape may evolve until then.
///
/// > Important: this surface is experimental. The attribute name is
/// > stable, but generated symbol shape (mock helper names, storage
/// > suffixes, override slot names) is **not** SemVer-frozen until GA.
/// > See [ROADMAP — Experimental Features &
/// > Promotion Criteria](https://github.com/InnoSquadCorp/InnoDI/blob/main/ROADMAP.md#experimental-features--promotion-criteria)
/// > for the registry of experimental surfaces, the pipeline phases, and
/// > the gates a feature must clear before promotion.
@attached(peer, names: suffixed(Mock))
public macro GenerateMock() = #externalMacro(module: "InnoDIMacros", type: "GenerateMockMacro")
