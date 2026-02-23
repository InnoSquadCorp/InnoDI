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

@attached(member, names: named(init))
/// Marks a type as an InnoDI container and synthesizes initialization/validation behavior.
///
/// - Parameters:
///   - validate: Enables container-level compile-time validation.
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
