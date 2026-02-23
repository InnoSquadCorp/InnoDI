//
//  Parsing.swift
//  InnoDICore
//

import SwiftSyntax

/// Scope for a `@Provide` declaration.
public enum ProvideScope: String {
    /// Shared singleton-like instance in a container.
    case shared
    /// Input value passed from outside the container.
    case input
    /// New instance created on each access.
    case transient
}

/// Parsed arguments extracted from a single `@Provide` attribute.
public struct ProvideArguments {
    /// Parsed scope value (`.shared`, `.input`, `.transient`) when available.
    public let scope: ProvideScope?
    /// Raw textual scope name.
    public let scopeName: String?
    /// Factory expression passed via `factory:`.
    public let factoryExpr: ExprSyntax?
    /// Asynchronous factory expression passed via `asyncFactory:`.
    public let asyncFactoryExpr: ExprSyntax?
    /// Whether the async factory closure is throwing.
    public let asyncFactoryIsThrowing: Bool
    /// Whether concrete opt-in (`concrete: true`) was explicitly requested.
    public let concrete: Bool
    /// Explicit type expression passed as positional `Type.self`.
    public let typeExpr: ExprSyntax?
    /// Dependency key-path names passed via `with:`.
    public let dependencies: [String]

    /// Creates a parsed `@Provide` argument model.
    ///
    /// - Parameters:
    ///   - scope: Parsed scope value.
    ///   - scopeName: Raw scope name text.
    ///   - factoryExpr: Parsed factory expression.
    ///   - asyncFactoryExpr: Parsed async factory expression.
    ///   - asyncFactoryIsThrowing: Whether the async factory closure throws.
    ///   - concrete: Explicit concrete opt-in value.
    ///   - typeExpr: Positional type expression.
    ///   - dependencies: Parsed dependency names from `with:`.
    public init(
        scope: ProvideScope?,
        scopeName: String?,
        factoryExpr: ExprSyntax?,
        asyncFactoryExpr: ExprSyntax? = nil,
        asyncFactoryIsThrowing: Bool = false,
        concrete: Bool = false,
        typeExpr: ExprSyntax? = nil,
        dependencies: [String] = []
    ) {
        self.scope = scope
        self.scopeName = scopeName
        self.factoryExpr = factoryExpr
        self.asyncFactoryExpr = asyncFactoryExpr
        self.asyncFactoryIsThrowing = asyncFactoryIsThrowing
        self.concrete = concrete
        self.typeExpr = typeExpr
        self.dependencies = dependencies
    }
}

/// Parsed arguments extracted from a single `@DIContainer` attribute.
public struct DIContainerAttributeInfo {
    /// Whether compile-time validation is enabled for the container.
    public let validate: Bool
    /// Whether the container should be marked as graph root.
    public let root: Bool
    /// Whether DAG validation is enabled for this container.
    public let validateDAG: Bool
    /// Whether generated API is isolated to the main actor.
    public let mainActor: Bool

    /// Creates a parsed `@DIContainer` attribute model.
    ///
    /// - Parameters:
    ///   - validate: Validation flag.
    ///   - root: Root flag.
    ///   - validateDAG: DAG validation flag.
    ///   - mainActor: Main actor isolation flag.
    public init(validate: Bool, root: Bool, validateDAG: Bool, mainActor: Bool) {
        self.validate = validate
        self.root = root
        self.validateDAG = validateDAG
        self.mainActor = mainActor
    }
}

/// Finds the first attribute whose base name matches `name`.
///
/// - Parameters:
///   - name: Attribute base name (for example, `"Provide"`).
///   - attributes: Attribute list to search.
/// - Returns: Matching `AttributeSyntax` when found; otherwise `nil`.
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
    var asyncFactoryExpr: ExprSyntax?
    var asyncFactoryIsThrowing = false
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
                if label == "asyncFactory" {
                    asyncFactoryExpr = argument.expression
                    if let closure = argument.expression.as(ClosureExprSyntax.self) {
                        asyncFactoryIsThrowing = closure.signature?.description.contains("throws") == true
                    }
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

    return ProvideArguments(
        scope: scope,
        scopeName: scopeName,
        factoryExpr: factoryExpr,
        asyncFactoryExpr: asyncFactoryExpr,
        asyncFactoryIsThrowing: asyncFactoryIsThrowing,
        concrete: concrete,
        typeExpr: typeExpr,
        dependencies: dependencies
    )
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
    var validateDAG = true
    var mainActor = false

    if let arguments = attr.arguments?.as(LabeledExprListSyntax.self) {
        for argument in arguments {
            guard let label = argument.label?.text else { continue }
            if label == "validate", let value = parseBoolLiteral(argument.expression) {
                validate = value
            }
            if label == "root", let value = parseBoolLiteral(argument.expression) {
                root = value
            }
            if label == "validateDAG", let value = parseBoolLiteral(argument.expression) {
                validateDAG = value
            }
            if label == "mainActor", let value = parseBoolLiteral(argument.expression) {
                mainActor = value
            }
        }
    }

    return DIContainerAttributeInfo(validate: validate, root: root, validateDAG: validateDAG, mainActor: mainActor)
}
