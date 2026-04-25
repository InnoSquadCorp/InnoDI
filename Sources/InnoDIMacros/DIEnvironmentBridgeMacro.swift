//
//  DIEnvironmentBridgeMacro.swift
//  InnoDIMacros
//
//  `@DIEnvironmentBridge` drives SwiftUI environment wiring: a container
//  type declares member → environment key-path mappings, and the macro
//  synthesizes a `ViewModifier` that reads those members and injects them
//  into the SwiftUI environment. This file holds the macro conformances
//  (member + extension) plus the validation and codegen helpers specific
//  to the bridge.
//

import InnoDICore
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct DIEnvironmentBridgeMacro {}

extension DIEnvironmentBridgeMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try expansion(of: node, providingMembersOf: declaration, in: context)
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let nominalType = nominalTypeSyntax(for: declaration) else {
            return []
        }

        let validation = validateEnvironmentBridge(
            attribute: node,
            declaration: declaration,
            context: context,
            emitDiagnostics: true
        )
        guard let mappings = validation.mappings else {
            return []
        }

        let accessLevel = accessLevelModifiers(for: declaration.modifiers)
        let modifierDecl = makeEnvironmentBridgeModifierDecl(
            accessLevel: accessLevel,
            containerType: nominalType,
            mappings: mappings
        )
        let bridgeMethodDecl = makeEnvironmentBridgeHelperDecl(accessLevel: accessLevel)

        return [DeclSyntax(modifierDecl), DeclSyntax(bridgeMethodDecl)]
    }
}

extension DIEnvironmentBridgeMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let validation = validateEnvironmentBridge(
            attribute: node,
            declaration: declaration,
            context: context,
            emitDiagnostics: false
        )
        guard validation.mappings != nil else {
            return []
        }

        return [
            try ExtensionDeclSyntax("extension \(type): DIEnvironmentBridging {}")
        ]
    }
}

// MARK: - Validation model

private struct EnvironmentBridgeMappingInfo {
    let memberName: String
    let environmentKeyPath: ExprSyntax
}

private struct EnvironmentBridgeValidationResult {
    let mappings: [EnvironmentBridgeMappingInfo]?
}

private func validateEnvironmentBridge(
    attribute: AttributeSyntax,
    declaration: some DeclGroupSyntax,
    context: some MacroExpansionContext,
    emitDiagnostics: Bool
) -> EnvironmentBridgeValidationResult {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
          let firstArgument = arguments.first,
          let arrayExpr = firstArgument.expression.as(ArrayExprSyntax.self) else {
        if emitDiagnostics {
            context.diagnose(
                Diagnostic(
                    node: Syntax(attribute),
                    message: SimpleDiagnostic.swiftUIEnvironmentBridgeInvalidArguments()
                )
            )
        }
        return EnvironmentBridgeValidationResult(mappings: nil)
    }

    let memberNames = Set(containerMemberNames(in: declaration))
    var seenMembers: Set<String> = []
    var mappings: [EnvironmentBridgeMappingInfo] = []
    var hadErrors = false

    for element in arrayExpr.elements {
        guard let tupleExpr = element.expression.as(TupleExprSyntax.self) else {
            if emitDiagnostics {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(element.expression),
                        message: SimpleDiagnostic.swiftUIEnvironmentBridgeInvalidKeyPath(label: "member")
                    )
                )
            }
            hadErrors = true
            continue
        }

        var memberName: String?
        var environmentKeyPath: ExprSyntax?

        for tupleElement in tupleExpr.elements {
            guard let label = tupleElement.label?.text else {
                continue
            }

            switch label {
            case "member":
                guard let parsedMemberName = stringLiteralValue(tupleElement.expression) else {
                    if emitDiagnostics {
                        context.diagnose(
                            Diagnostic(
                                node: Syntax(tupleElement.expression),
                                message: SimpleDiagnostic.swiftUIEnvironmentBridgeInvalidKeyPath(label: "member")
                            )
                        )
                    }
                    hadErrors = true
                    continue
                }
                memberName = parsedMemberName
            case "environment":
                guard let keyPath = tupleElement.expression.as(KeyPathExprSyntax.self) else {
                    if emitDiagnostics {
                        context.diagnose(
                            Diagnostic(
                                node: Syntax(tupleElement.expression),
                                message: SimpleDiagnostic.swiftUIEnvironmentBridgeInvalidKeyPath(label: "environment")
                            )
                        )
                    }
                    hadErrors = true
                    continue
                }
                environmentKeyPath = ExprSyntax(keyPath)
            default:
                continue
            }
        }

        guard let memberName, let environmentKeyPath else {
            hadErrors = true
            continue
        }

        guard memberNames.contains(memberName) else {
            if emitDiagnostics {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(element.expression),
                        message: SimpleDiagnostic.swiftUIEnvironmentBridgeUnknownMember(memberName: memberName)
                    )
                )
            }
            hadErrors = true
            continue
        }

        guard seenMembers.insert(memberName).inserted else {
            if emitDiagnostics {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(element.expression),
                        message: SimpleDiagnostic.swiftUIEnvironmentBridgeDuplicateMember(memberName: memberName)
                    )
                )
            }
            hadErrors = true
            continue
        }

        mappings.append(
            EnvironmentBridgeMappingInfo(
                memberName: memberName,
                environmentKeyPath: environmentKeyPath
            )
        )
    }

    return EnvironmentBridgeValidationResult(mappings: hadErrors ? nil : mappings)
}

// MARK: - Code generation

private func makeEnvironmentBridgeModifierDecl(
    accessLevel: DeclModifierListSyntax,
    containerType: TypeSyntax,
    mappings: [EnvironmentBridgeMappingInfo]
) -> StructDeclSyntax {
    let containerDecl = VariableDeclSyntax(
        bindingSpecifier: .keyword(.let),
        bindings: PatternBindingListSyntax([
            PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: .identifier("container")),
                typeAnnotation: TypeAnnotationSyntax(type: containerType)
            )
        ])
    )
    let bodyDecl = FunctionDeclSyntax(
        modifiers: accessLevel,
        name: .identifier("body"),
        signature: FunctionSignatureSyntax(
            parameterClause: FunctionParameterClauseSyntax(
                parameters: FunctionParameterListSyntax([
                    FunctionParameterSyntax(
                        firstName: .identifier("content"),
                        colon: .colonToken(),
                        type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Content")))
                    )
                ])
            ),
            returnClause: ReturnClauseSyntax(type: TypeSyntax(stringLiteral: "some SwiftUI.View"))
        ),
        body: CodeBlockSyntax(
            statements: CodeBlockItemListSyntax([
                CodeBlockItemSyntax(
                    item: .stmt(
                        StmtSyntax(
                            ExpressionStmtSyntax(
                                expression: makeEnvironmentBridgeBodyExpr(mappings: mappings)
                            )
                        )
                    )
                )
            ])
        )
    )

    return StructDeclSyntax(
        modifiers: accessLevel,
        name: .identifier("_InnoDIEnvironmentBridgeModifier"),
        inheritanceClause: InheritanceClauseSyntax(
            inheritedTypes: InheritedTypeListSyntax([
                InheritedTypeSyntax(type: TypeSyntax(stringLiteral: "SwiftUI.ViewModifier"))
            ])
        ),
        memberBlock: MemberBlockSyntax(
            members: MemberBlockItemListSyntax([
                MemberBlockItemSyntax(decl: DeclSyntax(containerDecl)),
                MemberBlockItemSyntax(decl: DeclSyntax(bodyDecl)),
            ])
        )
    )
}

private func makeEnvironmentBridgeHelperDecl(
    accessLevel: DeclModifierListSyntax
) -> FunctionDeclSyntax {
    let modifierType = TypeSyntax(IdentifierTypeSyntax(name: .identifier("_InnoDIEnvironmentBridgeModifier")))
    let callExpr = ExprSyntax(
        FunctionCallExprSyntax(
            calledExpression: ExprSyntax(
                DeclReferenceExprSyntax(baseName: .identifier("_InnoDIEnvironmentBridgeModifier"))
            ),
            leftParen: .leftParenToken(),
            arguments: LabeledExprListSyntax([
                LabeledExprSyntax(
                    label: .identifier("container"),
                    colon: .colonToken(),
                    expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.self)))
                )
            ]),
            rightParen: .rightParenToken()
        )
    )

    return FunctionDeclSyntax(
        attributes: AttributeListSyntax([
            .attribute(
                AttributeSyntax(attributeName: IdentifierTypeSyntax(name: .identifier("MainActor")))
            )
        ]),
        modifiers: accessLevel,
        name: .identifier("_innodiEnvironmentBridgeModifier"),
        signature: FunctionSignatureSyntax(
            parameterClause: FunctionParameterClauseSyntax(parameters: []),
            returnClause: ReturnClauseSyntax(type: modifierType)
        ),
        body: CodeBlockSyntax(
            statements: CodeBlockItemListSyntax([
                CodeBlockItemSyntax(
                    item: .stmt(StmtSyntax(ExpressionStmtSyntax(expression: callExpr)))
                )
            ])
        )
    )
}

private func makeEnvironmentBridgeBodyExpr(
    mappings: [EnvironmentBridgeMappingInfo]
) -> ExprSyntax {
    mappings.reduce(
        ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("content")))
    ) { partialResult, mapping in
        let memberAccess = ExprSyntax(
            MemberAccessExprSyntax(
                base: partialResult,
                declName: DeclReferenceExprSyntax(baseName: .identifier("environment"))
            )
        )
        let containerMember = ExprSyntax(
            MemberAccessExprSyntax(
                base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("container"))),
                declName: DeclReferenceExprSyntax(baseName: .identifier(mapping.memberName))
            )
        )

        return ExprSyntax(
            FunctionCallExprSyntax(
                calledExpression: memberAccess,
                leftParen: .leftParenToken(),
                arguments: LabeledExprListSyntax([
                    LabeledExprSyntax(
                        expression: mapping.environmentKeyPath,
                        trailingComma: .commaToken()
                    ),
                    LabeledExprSyntax(expression: containerMember),
                ]),
                rightParen: .rightParenToken()
            )
        )
    }
}
