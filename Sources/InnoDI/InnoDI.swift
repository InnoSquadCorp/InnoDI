//
//  InnoDI.swift
//  InnoDI
//

import Foundation

public enum DIScope {
    case shared
    case input
}

@attached(member, names: named(init), named(Overrides))
public macro DIContainer(validate: Bool = true, root: Bool = false) = #externalMacro(module: "InnoDIMacros", type: "DIContainerMacro")

@attached(accessor)
public macro Provide(_ scope: DIScope = .shared, factory: Any? = nil) = #externalMacro(module: "InnoDIMacros", type: "ProvideMacro")
