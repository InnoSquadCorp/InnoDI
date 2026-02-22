//
//  Parsing.swift
//  InnoDICore
//

import SwiftSyntax

public enum ProvideScope: String {
    case shared
    case input
    case transient
}

public struct ProvideArguments {
    public let scope: ProvideScope?
    public let scopeName: String?
    public let factoryExpr: ExprSyntax?
    public let concrete: Bool
    public let typeExpr: ExprSyntax?
    public let dependencies: [String]

    public init(scope: ProvideScope?, scopeName: String?, factoryExpr: ExprSyntax?, concrete: Bool = false, typeExpr: ExprSyntax? = nil, dependencies: [String] = []) {
        self.scope = scope
        self.scopeName = scopeName
        self.factoryExpr = factoryExpr
        self.concrete = concrete
        self.typeExpr = typeExpr
        self.dependencies = dependencies
    }
}

public struct DIContainerAttributeInfo {
    public let validate: Bool
    public let root: Bool

    public init(validate: Bool, root: Bool) {
        self.validate = validate
        self.root = root
    }
}

public func findAttribute(named name: String, in attributes: AttributeListSyntax?) -> AttributeSyntax? {
    guard let attributes else { return nil }
    for attribute in attributes {
        guard let attr = attribute.as(AttributeSyntax.self) else { continue }
        guard let identifier = attr.attributeName.as(IdentifierTypeSyntax.self) else { continue }
        if identifier.name.text == name {
            return attr
        }
    }
    return nil
}

public func parseProvideArguments(_ attribute: AttributeSyntax) -> ProvideArguments {
    var scopeName: String?
    var scope: ProvideScope?
    var factoryExpr: ExprSyntax?
    var concrete: Bool = false
    var typeExpr: ExprSyntax?
    var dependencies: [String] = []

    if let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) {
        for argument in arguments {
            if let label = argument.label?.text {
                if label == "factory" {
                    factoryExpr = argument.expression
                    continue
                }
                if label == "concrete" {
                    if let value = parseBoolLiteral(argument.expression) {
                        concrete = value
                    }
                    continue
                }
                if label == "with" {
                    if let arrayExpr = argument.expression.as(ArrayExprSyntax.self) {
                        for element in arrayExpr.elements {
                            // \.config, \.logger (KeyPathExprSyntax)
                            if let keyPath = element.expression.as(KeyPathExprSyntax.self),
                               let property = keyPath.components.last?.component.as(KeyPathPropertyComponentSyntax.self)?.declName.baseName.text {
                                dependencies.append(property)
                            }
                        }
                    }
                    continue
                }
            } else {
                // Positional arguments
                if let memberAccess = argument.expression.as(MemberAccessExprSyntax.self),
                   memberAccess.declName.baseName.text == "self" {
                    // Type argument (e.g., APIClient.self)
                    typeExpr = memberAccess.base
                    continue
                }
                
                if let memberAccess = argument.expression.as(MemberAccessExprSyntax.self) {
                     let name = memberAccess.declName.baseName.text
                     if let s = ProvideScope(rawValue: name) {
                         scopeName = name
                         scope = s
                     }
                }
            }
        }
    }

    if scopeName == nil {
        scopeName = ProvideScope.shared.rawValue
        scope = .shared
    }

    return ProvideArguments(scope: scope, scopeName: scopeName, factoryExpr: factoryExpr, concrete: concrete, typeExpr: typeExpr, dependencies: dependencies)
}

public func parseProvideAttribute(_ attributes: AttributeListSyntax?) -> ProvideArguments? {
    guard let attribute = findAttribute(named: "Provide", in: attributes) else {
        return nil
    }
    return parseProvideArguments(attribute)
}

public func parseBoolLiteral(_ expr: ExprSyntax) -> Bool? {
    if let literal = expr.as(BooleanLiteralExprSyntax.self) {
        return literal.literal.text == "true"
    }
    if let reference = expr.as(DeclReferenceExprSyntax.self) {
        if reference.baseName.text == "true" { return true }
        if reference.baseName.text == "false" { return false }
    }
    return nil
}

public func parseDIContainerAttribute(_ attributes: AttributeListSyntax?) -> DIContainerAttributeInfo? {
    guard let attr = findAttribute(named: "DIContainer", in: attributes) else { return nil }

    var validate = true
    var root = false

    if let arguments = attr.arguments?.as(LabeledExprListSyntax.self) {
        for argument in arguments {
            guard let label = argument.label?.text else { continue }
            if label == "validate", let value = parseBoolLiteral(argument.expression) {
                validate = value
            }
            if label == "root", let value = parseBoolLiteral(argument.expression) {
                root = value
            }
        }
    }

    return DIContainerAttributeInfo(validate: validate, root: root)
}
