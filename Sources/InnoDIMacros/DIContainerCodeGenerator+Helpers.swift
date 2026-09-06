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

/// Wraps a precedence-sensitive expression in an explicit single-element
/// parenthesized AST. Factory expressions are embedded inside override `??`
/// expressions, where `try` and operator sequences are otherwise rejected or
/// can be reassociated by the parser. Primary expressions remain unchanged so
/// generated source keeps its stable spelling.
internal func parenthesizedExpr(_ expression: ExprSyntax) -> ExprSyntax {
    let requiresParentheses = expression.is(TryExprSyntax.self)
        || expression.is(TernaryExprSyntax.self)
        || expression.is(SequenceExprSyntax.self)

    guard requiresParentheses else { return expression }

    return ExprSyntax(
        TupleExprSyntax(
            leftParen: .leftParenToken(),
            elements: LabeledExprListSyntax([
                LabeledExprSyntax(expression: expression)
            ]),
            rightParen: .rightParenToken()
        )
    )
}

/// Builds `<optional> ?? <fallback>` nil-coalescing expression.
internal func nilCoalescingExpr(optionalName: String, fallback: ExprSyntax) -> ExprSyntax {
    ExprSyntax(
        InfixOperatorExprSyntax(
            leftOperand: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(optionalName))),
            operator: BinaryOperatorExprSyntax(
                operator: .binaryOperator(
                    "??",
                    leadingTrivia: .space,
                    trailingTrivia: .space
                )
            ),
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
    if description.hasPrefix("any ")
        || description.hasPrefix("some ")
        || description.contains("&")
        || description.contains("->") {
        return "(\(description))"
    }
    return description
}

/// Builds a `@MainActor` attribute list for generated declarations that belong
/// to a container's opted-in main-actor isolation domain.
internal func mainActorAttribute() -> AttributeSyntax {
    AttributeSyntax(
        attributeName: TypeSyntax(stringLiteral: "_Concurrency.MainActor")
    )
}

/// Builds the override-application closure type shared by container,
/// component, and sub-container code generation. Main-actor containers must
/// carry isolation on the function type itself; isolating only the receiving
/// initializer is not enough for closure bodies that mutate `Overrides`.
internal func overrideApplyClosureType(
    overridesTypeDescription: String = "Overrides",
    isMainActor: Bool,
    isOptional: Bool = false
) -> TypeSyntax {
    let actorPrefix = isMainActor ? "@_Concurrency.MainActor " : ""
    let closure = "\(actorPrefix)(inout \(overridesTypeDescription)) -> Void"
    return TypeSyntax(
        stringLiteral: isOptional ? "(\(closure))?" : closure
    )
}

internal func mainActorAttributeList() -> AttributeListSyntax {
    AttributeListSyntax([
        AttributeListSyntax.Element(
            mainActorAttribute()
        )
    ])
}

/// Wraps a Swift type in an optional spelling, parenthesizing `any`/`some`/
/// composed (`&`) forms so the emitted `<type>?` stays parseable.
internal func optionalParameterType(for type: TypeSyntax) -> TypeSyntax {
    let trimmed = type.trimmedDescription

    if trimmed.hasPrefix("any ")
        || trimmed.hasPrefix("some ")
        || trimmed.contains("&")
        || trimmed.contains("->") {
        return TypeSyntax(stringLiteral: "(\(trimmed))?")
    }

    return TypeSyntax(stringLiteral: "\(trimmed)?")
}

/// Function parameters are nonescaping by default, including when the
/// function type is hidden behind a typealias. Direct function spellings are
/// detectable from syntax; cross-file aliases use `escaping: true` because an
/// attached macro has no type-resolution API.
internal func inputParameterType(for member: ProvideMemberModel) -> TypeSyntax {
    guard member.escapingInput || isDirectNonOptionalFunctionType(member.type) else {
        return member.type
    }
    return TypeSyntax(stringLiteral: "@escaping \(member.type.trimmedDescription)")
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

extension DeclSyntax {
    /// Prepends a `// MARK: ...` line comment to this declaration's leading
    /// trivia so that macro expansions render with section dividers in the
    /// generated source.
    internal func prependingMARK(_ comment: String) -> DeclSyntax {
        let markTrivia: Trivia = [
            .newlines(1),
            .lineComment(comment),
            .newlines(1),
        ]
        return self.with(\.leadingTrivia, markTrivia + self.leadingTrivia)
    }
}
