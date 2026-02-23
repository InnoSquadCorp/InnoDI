//
//  InnoDI.swift
//  InnoDI
//

public enum DIScope {
    case shared
    case input
    case transient
}

@attached(member, names: named(init))
public macro DIContainer(validate: Bool = true, root: Bool = false, validateDAG: Bool = true) = #externalMacro(module: "InnoDIMacros", type: "DIContainerMacro")

@attached(peer, names: prefixed(_storage_), prefixed(_override_))
@attached(accessor)
public macro Provide(
    _ scope: DIScope = .shared,
    _ type: Any.Type? = nil,
    with dependencies: [AnyKeyPath] = [],
    factory: Any? = nil,
    concrete: Bool = false
) = #externalMacro(module: "InnoDIMacros", type: "ProvideMacro")
