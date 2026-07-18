import SwiftSyntax
import SwiftSyntaxBuilder

struct EnvironmentBridgeShadowSafeTypeNames {
    let container: String
    let values: [String]
}

func makeEnvironmentBridgeModifierDecl(
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
                        type: TypeSyntax(stringLiteral: "Self.Content")
                    )
                ])
            ),
            returnClause: ReturnClauseSyntax(
                type: TypeSyntax(stringLiteral: "some SwiftUI.View")
            )
        ),
        body: CodeBlockSyntax(
            statements: CodeBlockItemListSyntax([
                CodeBlockItemSyntax(
                    item: .stmt(
                        StmtSyntax(
                            ExpressionStmtSyntax(
                                expression: makeEnvironmentBridgeBodyExpr(
                                    mappings: mappings
                                )
                            )
                        )
                    )
                )
            ])
        )
    )

    return StructDeclSyntax(
        modifiers: accessLevel,
        name: .identifier(environmentBridgeModifierTypeName),
        inheritanceClause: InheritanceClauseSyntax(
            inheritedTypes: InheritedTypeListSyntax([
                InheritedTypeSyntax(
                    type: TypeSyntax(stringLiteral: "SwiftUI.ViewModifier")
                )
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

/// A bridge target or one of its generic parameters may legally have the same
/// name as its generated nested modifier. In that case unqualified generated
/// type references resolve to the source binder instead of the nested type.
/// Generic container/value storage plus key paths preserves normal deferred
/// member reads without spelling the shadowed target type in nested storage.
func makeShadowSafeEnvironmentBridgeModifierDecl(
    accessLevel: DeclModifierListSyntax,
    typeNames: EnvironmentBridgeShadowSafeTypeNames
) -> StructDeclSyntax {
    let genericParameterNames = [typeNames.container] + typeNames.values
    let genericParameterClause = GenericParameterClauseSyntax(
        leftAngle: .leftAngleToken(),
        parameters: GenericParameterListSyntax(
            genericParameterNames.enumerated().map { index, name in
                GenericParameterSyntax(
                    name: .identifier(name),
                    trailingComma: index == genericParameterNames.count - 1
                        ? nil
                        : .commaToken()
                )
            }
        ),
        rightAngle: .rightAngleToken()
    )

    var members: [MemberBlockItemSyntax] = [
        MemberBlockItemSyntax(
            decl: DeclSyntax(
                makeEnvironmentBridgeStoredProperty(
                    name: "container",
                    type: TypeSyntax(
                        IdentifierTypeSyntax(
                            name: .identifier(typeNames.container)
                        )
                    )
                )
            )
        )
    ]
    for index in typeNames.values.indices {
        let valueTypeName = typeNames.values[index]
        members.append(
            MemberBlockItemSyntax(
                decl: DeclSyntax(
                    makeEnvironmentBridgeStoredProperty(
                        name: "member\(index)",
                        type: TypeSyntax(
                            stringLiteral: "Swift.KeyPath<\(typeNames.container), \(valueTypeName)>"
                        )
                    )
                )
            )
        )
        members.append(
            MemberBlockItemSyntax(
                decl: DeclSyntax(
                    makeEnvironmentBridgeStoredProperty(
                        name: "environment\(index)",
                        type: TypeSyntax(
                            stringLiteral: "Swift.WritableKeyPath<SwiftUI.EnvironmentValues, \(valueTypeName)>"
                        )
                    )
                )
            )
        )
    }

    let bodyDecl = FunctionDeclSyntax(
        modifiers: accessLevel,
        name: .identifier("body"),
        signature: FunctionSignatureSyntax(
            parameterClause: FunctionParameterClauseSyntax(
                parameters: FunctionParameterListSyntax([
                    FunctionParameterSyntax(
                        firstName: .identifier("content"),
                        colon: .colonToken(),
                        type: TypeSyntax(stringLiteral: "Self.Content")
                    )
                ])
            ),
            returnClause: ReturnClauseSyntax(
                type: TypeSyntax(stringLiteral: "some SwiftUI.View")
            )
        ),
        body: CodeBlockSyntax(
            statements: CodeBlockItemListSyntax([
                CodeBlockItemSyntax(
                    item: .stmt(
                        StmtSyntax(
                            ExpressionStmtSyntax(
                                expression: makeShadowSafeEnvironmentBridgeBodyExpr(
                                    mappingCount: typeNames.values.count
                                )
                            )
                        )
                    )
                )
            ])
        )
    )
    members.append(MemberBlockItemSyntax(decl: DeclSyntax(bodyDecl)))

    return StructDeclSyntax(
        modifiers: accessLevel,
        name: .identifier(environmentBridgeModifierTypeName),
        genericParameterClause: genericParameterClause,
        inheritanceClause: InheritanceClauseSyntax(
            inheritedTypes: InheritedTypeListSyntax([
                InheritedTypeSyntax(
                    type: TypeSyntax(stringLiteral: "SwiftUI.ViewModifier")
                )
            ])
        ),
        memberBlock: MemberBlockSyntax(
            members: MemberBlockItemListSyntax(members)
        )
    )
}

func makeEnvironmentBridgeShadowSafeTypeNames(
    mappingCount: Int,
    excluding visibleGenericParameterNames: Set<String>
) -> EnvironmentBridgeShadowSafeTypeNames {
    var usedNames = visibleGenericParameterNames

    func allocate(_ base: String) -> String {
        var candidate = base
        var suffix = 0
        while usedNames.contains(candidate) {
            suffix += 1
            candidate = "\(base)_\(suffix)"
        }
        usedNames.insert(candidate)
        return candidate
    }

    return EnvironmentBridgeShadowSafeTypeNames(
        container: allocate("_InnoDIContainer"),
        values: (0..<mappingCount).map { index in
            allocate("_InnoDIValue\(index)")
        }
    )
}

private func makeEnvironmentBridgeStoredProperty(
    name: String,
    type: TypeSyntax
) -> VariableDeclSyntax {
    VariableDeclSyntax(
        bindingSpecifier: .keyword(.let),
        bindings: PatternBindingListSyntax([
            PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: .identifier(name)),
                typeAnnotation: TypeAnnotationSyntax(type: type)
            )
        ])
    )
}

func makeEnvironmentBridgeHelperDecl(
    accessLevel: DeclModifierListSyntax
) -> FunctionDeclSyntax {
    let modifierType = TypeSyntax(
        IdentifierTypeSyntax(name: .identifier(environmentBridgeModifierTypeName))
    )
    let callExpr = ExprSyntax(
        FunctionCallExprSyntax(
            calledExpression: ExprSyntax(
                MemberAccessExprSyntax(
                    base: ExprSyntax(
                        DeclReferenceExprSyntax(baseName: .keyword(.Self))
                    ),
                    declName: DeclReferenceExprSyntax(
                        baseName: .identifier(environmentBridgeModifierTypeName)
                    )
                )
            ),
            leftParen: .leftParenToken(),
            arguments: LabeledExprListSyntax([
                LabeledExprSyntax(
                    label: .identifier("container"),
                    colon: .colonToken(),
                    expression: ExprSyntax(
                        DeclReferenceExprSyntax(baseName: .keyword(.self))
                    )
                )
            ]),
            rightParen: .rightParenToken()
        )
    )

    return FunctionDeclSyntax(
        attributes: AttributeListSyntax([
            .attribute(
                AttributeSyntax(
                    attributeName: TypeSyntax(
                        stringLiteral: "_Concurrency.MainActor"
                    )
                )
            )
        ]),
        modifiers: accessLevel,
        name: .identifier(environmentBridgeHelperName),
        signature: FunctionSignatureSyntax(
            parameterClause: FunctionParameterClauseSyntax(parameters: []),
            returnClause: ReturnClauseSyntax(type: modifierType)
        ),
        body: CodeBlockSyntax(
            statements: CodeBlockItemListSyntax([
                CodeBlockItemSyntax(
                    item: .stmt(
                        StmtSyntax(ExpressionStmtSyntax(expression: callExpr))
                    )
                )
            ])
        )
    )
}

func makeShadowSafeEnvironmentBridgeHelperDecl(
    accessLevel: DeclModifierListSyntax,
    mappings: [EnvironmentBridgeMappingInfo]
) -> FunctionDeclSyntax {
    var arguments: [LabeledExprSyntax] = [
        LabeledExprSyntax(
            label: .identifier("container"),
            colon: .colonToken(),
            expression: ExprSyntax(
                DeclReferenceExprSyntax(baseName: .keyword(.self))
            ),
            trailingComma: mappings.isEmpty ? nil : .commaToken()
        )
    ]
    for (index, mapping) in mappings.enumerated() {
        arguments.append(
            LabeledExprSyntax(
                label: .identifier("member\(index)"),
                colon: .colonToken(),
                expression: ExprSyntax(
                    stringLiteral: "\\Self.\(mapping.memberName)"
                ),
                trailingComma: .commaToken()
            )
        )
        arguments.append(
            LabeledExprSyntax(
                label: .identifier("environment\(index)"),
                colon: .colonToken(),
                expression: ExprSyntax(mapping.environmentKeyPath),
                trailingComma: index == mappings.count - 1
                    ? nil
                    : .commaToken()
            )
        )
    }

    let callExpr = ExprSyntax(
        FunctionCallExprSyntax(
            calledExpression: ExprSyntax(
                MemberAccessExprSyntax(
                    base: ExprSyntax(
                        DeclReferenceExprSyntax(baseName: .keyword(.Self))
                    ),
                    declName: DeclReferenceExprSyntax(
                        baseName: .identifier(environmentBridgeModifierTypeName)
                    )
                )
            ),
            leftParen: .leftParenToken(),
            arguments: LabeledExprListSyntax(arguments),
            rightParen: .rightParenToken()
        )
    )

    return FunctionDeclSyntax(
        attributes: AttributeListSyntax([
            .attribute(
                AttributeSyntax(
                    attributeName: TypeSyntax(
                        stringLiteral: "_Concurrency.MainActor"
                    )
                )
            )
        ]),
        modifiers: accessLevel,
        name: .identifier(environmentBridgeHelperName),
        signature: FunctionSignatureSyntax(
            parameterClause: FunctionParameterClauseSyntax(parameters: []),
            returnClause: ReturnClauseSyntax(
                type: TypeSyntax(stringLiteral: "some SwiftUI.ViewModifier")
            )
        ),
        body: CodeBlockSyntax(
            statements: CodeBlockItemListSyntax([
                CodeBlockItemSyntax(
                    item: .stmt(
                        StmtSyntax(ExpressionStmtSyntax(expression: callExpr))
                    )
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
                declName: DeclReferenceExprSyntax(
                    baseName: .identifier("environment")
                )
            )
        )
        let containerMember = ExprSyntax(
            MemberAccessExprSyntax(
                base: ExprSyntax(
                    DeclReferenceExprSyntax(baseName: .identifier("container"))
                ),
                declName: DeclReferenceExprSyntax(
                    baseName: .identifier(mapping.memberName)
                )
            )
        )

        return ExprSyntax(
            FunctionCallExprSyntax(
                calledExpression: memberAccess,
                leftParen: .leftParenToken(),
                arguments: LabeledExprListSyntax([
                    LabeledExprSyntax(
                        expression: ExprSyntax(mapping.environmentKeyPath),
                        trailingComma: .commaToken()
                    ),
                    LabeledExprSyntax(expression: containerMember),
                ]),
                rightParen: .rightParenToken()
            )
        )
    }
}

private func makeShadowSafeEnvironmentBridgeBodyExpr(
    mappingCount: Int
) -> ExprSyntax {
    (0..<mappingCount).reduce(
        ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("content")))
    ) { partialResult, index in
        let memberAccess = ExprSyntax(
            MemberAccessExprSyntax(
                base: partialResult,
                declName: DeclReferenceExprSyntax(
                    baseName: .identifier("environment")
                )
            )
        )
        return ExprSyntax(
            FunctionCallExprSyntax(
                calledExpression: memberAccess,
                leftParen: .leftParenToken(),
                arguments: LabeledExprListSyntax([
                    LabeledExprSyntax(
                        expression: ExprSyntax(
                            DeclReferenceExprSyntax(
                                baseName: .identifier("environment\(index)")
                            )
                        ),
                        trailingComma: .commaToken()
                    ),
                    LabeledExprSyntax(
                        expression: ExprSyntax(
                            stringLiteral: "container[keyPath: member\(index)]"
                        )
                    ),
                ]),
                rightParen: .rightParenToken()
            )
        )
    }
}
