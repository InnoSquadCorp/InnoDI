//
//  InnoDI.swift
//  InnoDI
//

import Foundation

public enum DIScope {
    case shared
    case input
    case transient
}

@attached(member, names: named(init), named(Overrides))
public macro DIContainer(validate: Bool = true, root: Bool = false) = #externalMacro(module: "InnoDIMacros", type: "DIContainerMacro")

@attached(peer)
@attached(accessor)
public macro Provide(
    _ scope: DIScope = .shared,
    _ type: Any.Type? = nil,
    with dependencies: [AnyKeyPath] = [],
    factory: Any? = nil,
    concrete: Bool = false
) = #externalMacro(module: "InnoDIMacros", type: "ProvideMacro")
