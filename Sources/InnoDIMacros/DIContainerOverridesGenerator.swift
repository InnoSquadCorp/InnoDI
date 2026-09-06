//
//  DIContainerOverridesGenerator.swift
//  InnoDIMacros
//
//  Emits the nested `struct Overrides` builder plus the trailing-closure
//  convenience init that forwards named overrides into the primary init.
//  Each `@SubContainer` member adds two extra slots (`<name>` direct
//  replacement + `<name>Overrides` chained closure). Splitting these into a
//  dedicated file keeps the primary init body focused on storage/factory
//  wiring.
//

import SwiftSyntax
import SwiftSyntaxBuilder

internal let innoDIMountOverridesTypeName = "_InnoDIMountOverrides"

// MARK: - Overrides builder

internal func overrideCandidateMembers(_ model: DIContainerExpansionModel) -> [ProvideMemberModel] {
    model.sharedMembers + model.transientMembers
}

internal func makeOverridesStructDecl(model: DIContainerExpansionModel) -> DeclSyntax {
    let candidates = overrideCandidateMembers(model)
    let effectCandidates = candidates.filter {
        $0.operationalEffect == .sideEffect
    }
    let subs = model.subContainerMembers

    let modifiers = accessModifiers(model.accessLevel)
    var memberDecls: [MemberBlockItemSyntax] = candidates.map { member in
        let variableDecl = VariableDeclSyntax(
            modifiers: modifiers,
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier(member.name)),
                    typeAnnotation: TypeAnnotationSyntax(type: optionalParameterType(for: member.type)),
                    initializer: InitializerClauseSyntax(value: NilLiteralExprSyntax())
                )
            ])
        )
        return MemberBlockItemSyntax(decl: variableDecl)
    }

    // Each `@SubContainer` member gains two slots on Overrides —
    // `<name>` for full replacement, `<name>Overrides` for a closure that
    // forwards into the child's own convenience init. Both default to nil so
    // tests only touch the slots they actually need.
    for member in subs {
        let directSlot = VariableDeclSyntax(
            modifiers: modifiers,
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier(member.name)),
                    typeAnnotation: TypeAnnotationSyntax(type: optionalParameterType(for: member.type)),
                    initializer: InitializerClauseSyntax(value: NilLiteralExprSyntax())
                )
            ])
        )
        memberDecls.append(MemberBlockItemSyntax(decl: directSlot))

        let applyType = overrideApplyClosureType(
            overridesTypeDescription: "\(member.type.trimmedDescription).\(innoDIMountOverridesTypeName)",
            isMainActor: model.options.mainActor,
            isOptional: true
        )
        let applySlot = VariableDeclSyntax(
            modifiers: modifiers,
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier(member.overrideClosureName)),
                    typeAnnotation: TypeAnnotationSyntax(type: applyType),
                    initializer: InitializerClauseSyntax(value: NilLiteralExprSyntax())
                )
            ])
        )
        memberDecls.append(MemberBlockItemSyntax(decl: applySlot))
    }

    if !effectCandidates.isEmpty {
        let accessPrefix = model.accessLevel.map { "\($0) " } ?? ""
        let requirements = effectCandidates.map {
            "InnoDI.DIProviderEffectRequirement(providerName: \"\($0.name)\", effect: .sideEffect)"
        }.joined(separator: ", ")
        let checks = effectCandidates.map { member in
            """
                    if self.\(member.name) == nil {
                        missing.append(
                            InnoDI.DIProviderEffectRequirement(
                                providerName: "\(member.name)",
                                effect: .sideEffect
                            )
                        )
                    }
            """
        }.joined(separator: "\n")

        memberDecls.append(
            MemberBlockItemSyntax(
                decl: DeclSyntax(
                    stringLiteral: "\(accessPrefix)static let requiredEffectOverrides: [InnoDI.DIProviderEffectRequirement] = [\(requirements)]"
                )
            )
        )
        memberDecls.append(
            MemberBlockItemSyntax(
                decl: DeclSyntax(
                    stringLiteral: """
                    \(accessPrefix)var missingEffectOverrides: [InnoDI.DIProviderEffectRequirement] {
                        var missing: [InnoDI.DIProviderEffectRequirement] = []
                    \(checks)
                        return missing
                    }
                    """
                )
            )
        )
    }

    let inheritanceClause: InheritanceClauseSyntax? = effectCandidates.isEmpty
        ? nil
        : InheritanceClauseSyntax(
            inheritedTypes: InheritedTypeListSyntax([
                InheritedTypeSyntax(
                    type: TypeSyntax(
                        stringLiteral: model.options.mainActor
                            ? "InnoDI.DIMainActorOverrideEffectValidating"
                            : "InnoDI.DIOverrideEffectValidating"
                    )
                )
            ])
        )

    let structDecl = StructDeclSyntax(
        attributes: model.options.mainActor ? mainActorAttributeList() : AttributeListSyntax([]),
        modifiers: modifiers,
        name: .identifier("Overrides"),
        inheritanceClause: inheritanceClause,
        memberBlock: MemberBlockSyntax(
            members: MemberBlockItemListSyntax(memberDecls)
        )
    )

    return DeclSyntax(structDecl)
}

/// Stable child-mount ABI used by parent `@SubContainer` code. Valid
/// containers alias the source-facing builder so parent code no longer
/// depends directly on a user-collidable nested name.
internal func makeMountOverridesAliasDecl(
    model: DIContainerExpansionModel
) -> DeclSyntax {
    DeclSyntax(
        TypeAliasDeclSyntax(
            modifiers: accessModifiers(model.accessLevel),
            name: .identifier(innoDIMountOverridesTypeName),
            initializer: TypeInitializerClauseSyntax(
                value: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Overrides")))
            )
        )
    )
}

/// A diagnostic-only mount type for a container whose user declaration
/// collided with `Overrides`. It keeps parent expansion type-checkable without
/// exposing or specializing the conflicting declaration.
internal func makeOverridesConflictMountTypeDecl(
    model: DIContainerExpansionModel
) -> DeclSyntax {
    DeclSyntax(
        StructDeclSyntax(
            attributes: model.options.mainActor
                ? mainActorAttributeList()
                : AttributeListSyntax([]),
            modifiers: accessModifiers(model.accessLevel),
            name: .identifier(innoDIMountOverridesTypeName),
            memberBlock: MemberBlockSyntax(
                members: MemberBlockItemListSyntax([])
            )
        )
    )
}

internal func makeConvenienceInitDecl(model: DIContainerExpansionModel) -> DeclSyntax {
    let modifiers = accessModifiers(model.accessLevel)
    let inputMembers = model.inputMembers
    var params: [FunctionParameterSyntax] = []

    for member in inputMembers {
        // All input params have a trailing comma because the closure param
        // always follows them.
        let param = FunctionParameterSyntax(
            firstName: .identifier(member.name),
            secondName: nil,
            colon: .colonToken(),
            type: inputParameterType(for: member),
            ellipsis: nil,
            defaultValue: nil,
            trailingComma: .commaToken()
        )
        params.append(param)
    }

    // Final unnamed trailing closure parameter. Main-actor containers carry
    // isolation on the closure type as well as on the initializer:
    //   _ _innoDIApplyOverrides: [@MainActor] (inout Overrides) -> Void
    let overridesClosureType = overrideApplyClosureType(
        isMainActor: model.options.mainActor
    )
    let closureParam = FunctionParameterSyntax(
        firstName: .wildcardToken(),
        secondName: .identifier("_innoDIApplyOverrides"),
        colon: .colonToken(),
        type: overridesClosureType,
        ellipsis: nil,
        defaultValue: nil,
        trailingComma: nil
    )
    params.append(closureParam)

    let signature = FunctionSignatureSyntax(
        parameterClause: FunctionParameterClauseSyntax(parameters: FunctionParameterListSyntax(params))
    )

    var statements: [CodeBlockItemSyntax] = []

    // var _innoDIOverrides = Overrides()
    let makeOverrides = VariableDeclSyntax(
        bindingSpecifier: .keyword(.var),
        bindings: PatternBindingListSyntax([
            PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: .identifier("_innoDIOverrides")),
                initializer: InitializerClauseSyntax(
                    value: FunctionCallExprSyntax(
                        calledExpression: MemberAccessExprSyntax(
                            base: DeclReferenceExprSyntax(baseName: .keyword(.Self)),
                            declName: DeclReferenceExprSyntax(baseName: .identifier("Overrides"))
                        ),
                        leftParen: .leftParenToken(),
                        arguments: LabeledExprListSyntax([]),
                        rightParen: .rightParenToken()
                    )
                )
            )
        ])
    )
    statements.append(CodeBlockItemSyntax(item: .decl(DeclSyntax(makeOverrides))))

    // _innoDIApplyOverrides(&_innoDIOverrides)
    let applyCall = FunctionCallExprSyntax(
        calledExpression: DeclReferenceExprSyntax(baseName: .identifier("_innoDIApplyOverrides")),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax([
            LabeledExprSyntax(
                expression: InOutExprSyntax(
                    expression: DeclReferenceExprSyntax(baseName: .identifier("_innoDIOverrides"))
                )
            )
        ]),
        rightParen: .rightParenToken()
    )
    statements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(applyCall))))

    // self.init(<input args...>, <shared args...>, <transient args...>,
    //           <subContainer direct args...>, <subContainerOverrides args...>)
    var callArgs: [LabeledExprSyntax] = []
    let allForwardingMembers = inputMembers + model.sharedMembers + model.transientMembers
    let subForwardingPairs: [(label: String, source: String)] = model.subContainerMembers.flatMap { sub in
        // Each sub-container contributes two forwarded args: direct
        // replacement (`overrides.<name>`) and the chained closure
        // (`overrides.<name>Overrides`).
        [
            (sub.name, sub.name),
            (sub.overrideClosureName, sub.overrideClosureName)
        ]
    }
    let totalArgCount = allForwardingMembers.count + subForwardingPairs.count

    for (index, member) in allForwardingMembers.enumerated() {
        let isLast = index == allForwardingMembers.count - 1 && subForwardingPairs.isEmpty
        let valueExpr: ExprSyntax
        if member.scope == .input {
            // Input parameter forwarded from the outer init.
            valueExpr = ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(member.name)))
        } else {
            // shared / transient value pulled out of the overrides builder.
            valueExpr = ExprSyntax(
                MemberAccessExprSyntax(
                    base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("_innoDIOverrides"))),
                    declName: DeclReferenceExprSyntax(baseName: .identifier(member.name))
                )
            )
        }

        callArgs.append(
            LabeledExprSyntax(
                label: .identifier(member.name),
                colon: .colonToken(),
                expression: valueExpr,
                trailingComma: isLast ? nil : .commaToken()
            )
        )
    }

    for (index, pair) in subForwardingPairs.enumerated() {
        let runningIndex = allForwardingMembers.count + index
        let isLast = runningIndex == totalArgCount - 1
        let valueExpr = ExprSyntax(
            MemberAccessExprSyntax(
                base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("_innoDIOverrides"))),
                declName: DeclReferenceExprSyntax(baseName: .identifier(pair.source))
            )
        )
        callArgs.append(
            LabeledExprSyntax(
                label: .identifier(pair.label),
                colon: .colonToken(),
                expression: valueExpr,
                trailingComma: isLast ? nil : .commaToken()
            )
        )
    }

    let selfInitCall = FunctionCallExprSyntax(
        calledExpression: ExprSyntax(
            MemberAccessExprSyntax(
                base: ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.self))),
                declName: DeclReferenceExprSyntax(baseName: .keyword(.`init`))
            )
        ),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax(callArgs),
        rightParen: .rightParenToken()
    )
    statements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(selfInitCall))))

    let initDecl = InitializerDeclSyntax(
        attributes: model.options.mainActor ? mainActorAttributeList() : AttributeListSyntax([]),
        modifiers: modifiers,
        signature: signature,
        body: CodeBlockSyntax(statements: CodeBlockItemListSyntax(statements))
    )

    return DeclSyntax(initDecl)
}

/// Emits only the source shape that a parent `@SubContainer` needs to type
/// check after a user-defined nested `Overrides` declaration has already made
/// the child container invalid. The primary InnoDI error keeps this
/// initializer unreachable; the nonreturning body prevents secondary stored
/// property and `extra argument in call` diagnostics from obscuring it.
internal func makeOverridesConflictRecoveryInitDecl(
    model: DIContainerExpansionModel
) -> DeclSyntax {
    let modifiers = accessModifiers(model.accessLevel)
    var params: [FunctionParameterSyntax] = model.inputMembers.map { member in
        FunctionParameterSyntax(
            firstName: .identifier(member.name),
            secondName: nil,
            colon: .colonToken(),
            type: inputParameterType(for: member),
            ellipsis: nil,
            defaultValue: nil,
            trailingComma: .commaToken()
        )
    }
    params.append(
        FunctionParameterSyntax(
            firstName: .wildcardToken(),
            secondName: .identifier("_innoDIApplyOverrides"),
            colon: .colonToken(),
            type: overrideApplyClosureType(
                overridesTypeDescription: innoDIMountOverridesTypeName,
                isMainActor: model.options.mainActor
            ),
            ellipsis: nil,
            defaultValue: nil,
            trailingComma: nil
        )
    )

    let loop: CodeBlockItemSyntax = "while true {}"
    return DeclSyntax(
        InitializerDeclSyntax(
            attributes: model.options.mainActor
                ? mainActorAttributeList()
                : AttributeListSyntax([]),
            modifiers: modifiers,
            signature: FunctionSignatureSyntax(
                parameterClause: FunctionParameterClauseSyntax(
                    parameters: FunctionParameterListSyntax(params)
                )
            ),
            body: CodeBlockSyntax(
                statements: CodeBlockItemListSyntax([loop])
            )
        )
    )
}
