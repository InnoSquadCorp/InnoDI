//
//  Parsing.swift
//  InnoDICore
//

import SwiftSyntax

public enum ProvideScope: String {
    case shared
    case input
}

public struct ProvideArguments {
    public let scope: ProvideScope?
    public let scopeName: String?
    public let isDefaultScope: Bool
    public let factoryExpr: ExprSyntax?

    public init(scope: ProvideScope?, scopeName: String?, isDefaultScope: Bool, factoryExpr: ExprSyntax?) {
        self.scope = scope
        self.scopeName = scopeName
        self.isDefaultScope = isDefaultScope
        self.factoryExpr = factoryExpr
    }
}

public struct ProvideAttributeInfo {
    public let hasProvide: Bool
    public let scope: ProvideScope?
    public let scopeName: String?
    public let factoryExpr: ExprSyntax?

    public init(hasProvide: Bool, scope: ProvideScope?, scopeName: String?, factoryExpr: ExprSyntax?) {
        self.hasProvide = hasProvide
        self.scope = scope
        self.scopeName = scopeName
        self.factoryExpr = factoryExpr
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

    if let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) {
        for argument in arguments {
            if let label = argument.label?.text, label == "factory" {
                factoryExpr = argument.expression
                continue
            }

            if let memberAccess = argument.expression.as(MemberAccessExprSyntax.self) {
                let name = memberAccess.declName.baseName.text
                scopeName = name
                scope = ProvideScope(rawValue: name)
            }
        }
    }

    if scopeName == nil {
        scopeName = ProvideScope.shared.rawValue
        scope = .shared
        return ProvideArguments(scope: scope, scopeName: scopeName, isDefaultScope: true, factoryExpr: factoryExpr)
    }

    return ProvideArguments(scope: scope, scopeName: scopeName, isDefaultScope: false, factoryExpr: factoryExpr)
}

public func parseProvideAttribute(_ attributes: AttributeListSyntax?) -> ProvideAttributeInfo {
    guard let attribute = findAttribute(named: "Provide", in: attributes) else {
        return ProvideAttributeInfo(hasProvide: false, scope: nil, scopeName: nil, factoryExpr: nil)
    }

    let args = parseProvideArguments(attribute)
    return ProvideAttributeInfo(
        hasProvide: true,
        scope: args.scope,
        scopeName: args.scopeName,
        factoryExpr: args.factoryExpr
    )
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
