//
//  DIContainerCodeGenerator+Helpers.swift
//  InnoDIMacros
//
//  Small expression/syntax helpers shared across the primary-init code
//  generator, the factory expression builder, and the dependency resolver.
//  These are pure AST utilities with no knowledge of the expansion model.
//

import SwiftSyntax
import SwiftSyntaxBuilder

/// Builds `<optional> ?? <fallback>` nil-coalescing expression.
internal func nilCoalescingExpr(optionalName: String, fallback: ExprSyntax) -> ExprSyntax {
    ExprSyntax(
        InfixOperatorExprSyntax(
            leftOperand: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(optionalName))),
            operator: BinaryOperatorExprSyntax(operator: .binaryOperator("??")),
            rightOperand: fallback
        )
    )
}

/// Builds `self.<targetName> = <valueName>` assignment.
internal func assignExpr(targetName: String, valueName: String) -> ExprSyntax {
    let valueExpr = ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(valueName)))
    let assignment = InfixOperatorExprSyntax(
        leftOperand: makeSelfMemberAccessExpr(name: targetName),
        operator: AssignmentExprSyntax(),
        rightOperand: valueExpr
    )
    return ExprSyntax(assignment)
}

/// Builds `self.<targetName> = <value>` assignment with an arbitrary expression.
internal func assignExprWithValue(targetName: String, value: ExprSyntax) -> ExprSyntax {
    let assignment = InfixOperatorExprSyntax(
        leftOperand: makeSelfMemberAccessExpr(name: targetName),
        operator: AssignmentExprSyntax(),
        rightOperand: value
    )
    return ExprSyntax(assignment)
}

/// Normalizes a Swift type description for use as a `Task<Success, Failure>`
/// success parameter. Wraps `any`/`some`/composed (`&`) spellings in
/// parentheses so the emitted generic argument stays parseable.
internal func taskSuccessTypeDescription(for type: TypeSyntax) -> String {
    let description = type.trimmedDescription
    if description.hasPrefix("any ") || description.hasPrefix("some ") || description.contains("&") {
        return "(\(description))"
    }
    return description
}

/// Builds a `@MainActor` attribute list used to annotate the synthesized
/// init when the container opts into main-actor isolation.
internal func mainActorAttributeList() -> AttributeListSyntax {
    AttributeListSyntax([
        AttributeListSyntax.Element(
            AttributeSyntax(
                attributeName: IdentifierTypeSyntax(name: .identifier("MainActor"))
            )
        )
    ])
}

/// Wraps a Swift type in an optional spelling, parenthesizing `any`/`some`/
/// composed (`&`) forms so the emitted `<type>?` stays parseable.
internal func optionalParameterType(for type: TypeSyntax) -> TypeSyntax {
    let trimmed = type.trimmedDescription

    if trimmed.hasPrefix("any ") || trimmed.hasPrefix("some ") || trimmed.contains("&") {
        return TypeSyntax(stringLiteral: "(\(trimmed))?")
    }

    return TypeSyntax(stringLiteral: "\(trimmed)?")
}

/// Maps the container's declared access level to the modifier list applied
/// to synthesized init / Overrides / withOverrides members.
internal func accessModifiers(_ accessLevel: String?) -> DeclModifierListSyntax {
    guard let accessLevel else { return DeclModifierListSyntax([]) }
    let token: TokenSyntax
    switch accessLevel {
    case "public": token = .keyword(.public)
    case "package": token = .keyword(.package)
    case "internal": token = .keyword(.internal)
    case "fileprivate": token = .keyword(.fileprivate)
    case "private": token = .keyword(.private)
    default: return DeclModifierListSyntax([])
    }
    let modifier = DeclModifierSyntax(name: token)
    return DeclModifierListSyntax([modifier])
}
