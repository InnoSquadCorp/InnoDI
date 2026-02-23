import SwiftSyntax

enum ProvideScope: String {
    case shared
    case input
    case transient
}

struct ProvideArguments {
    let scope: ProvideScope?
    let scopeName: String?
    let factoryExpr: ExprSyntax?
    let concrete: Bool
    let typeExpr: ExprSyntax?
    let dependencies: [String]
}

struct DIContainerAttributeInfo {
    let validate: Bool
    let root: Bool
    let validateDAG: Bool
}

func findAttribute(named name: String, in attributes: AttributeListSyntax?) -> AttributeSyntax? {
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

func parseProvideArguments(_ attribute: AttributeSyntax) -> ProvideArguments {
    var scopeName: String?
    var scope: ProvideScope?
    var factoryExpr: ExprSyntax?
    var concrete = false
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
                            if let keyPath = element.expression.as(KeyPathExprSyntax.self),
                               let property = keyPath.components.last?.component.as(KeyPathPropertyComponentSyntax.self)?.declName.baseName.text {
                                dependencies.append(property)
                            }
                        }
                    }
                    continue
                }
            } else {
                if let memberAccess = argument.expression.as(MemberAccessExprSyntax.self),
                   memberAccess.declName.baseName.text == "self" {
                    typeExpr = memberAccess.base
                    continue
                }

                if let memberAccess = argument.expression.as(MemberAccessExprSyntax.self) {
                    let name = memberAccess.declName.baseName.text
                    if let parsedScope = ProvideScope(rawValue: name) {
                        scopeName = name
                        scope = parsedScope
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
        concrete: concrete,
        typeExpr: typeExpr,
        dependencies: dependencies
    )
}

func parseBoolLiteral(_ expr: ExprSyntax) -> Bool? {
    if let literal = expr.as(BooleanLiteralExprSyntax.self) {
        return literal.literal.text == "true"
    }
    if let reference = expr.as(DeclReferenceExprSyntax.self) {
        if reference.baseName.text == "true" { return true }
        if reference.baseName.text == "false" { return false }
    }
    return nil
}

func parseDIContainerAttribute(_ attributes: AttributeListSyntax?) -> DIContainerAttributeInfo? {
    guard let attr = findAttribute(named: "DIContainer", in: attributes) else { return nil }

    var validate = true
    var root = false
    var validateDAG = true

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
        }
    }

    return DIContainerAttributeInfo(validate: validate, root: root, validateDAG: validateDAG)
}
