//
//  DIContainerMacro.swift
//  InnoDIMacros
//

import InnoDICore
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct DIContainerMacro: MemberMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf decl: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try expansion(of: attribute, providingMembersOf: decl, in: context)
    }

    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf decl: some DeclGroupSyntax,
        in context: MacroExpansionContext
    ) throws -> [DeclSyntax] {
        if hasUserDefinedInit(in: decl) {
            return []
        }

        let accessLevel = containerAccessLevel(for: decl)
        var hadErrors = false
        let provideMembers = collectProvideMembers(in: decl, context: context, hadErrors: &hadErrors)

        if hadErrors || provideMembers.isEmpty {
            return []
        }

        let sharedMembers = provideMembers.filter { $0.scope == .shared }
        let inputMembers = provideMembers.filter { $0.scope == .input }

        var generated: [DeclSyntax] = []

        if !sharedMembers.isEmpty {
            generated.append(makeOverridesStruct(sharedMembers: sharedMembers, accessLevel: accessLevel))
        }

        generated.append(makeInitDecl(sharedMembers: sharedMembers, inputMembers: inputMembers, accessLevel: accessLevel))

        return generated
    }
}

private struct ProvideMember {
    let name: String
    let type: TypeSyntax
    let scope: ProvideScope
    let factory: ExprSyntax?
    let syntax: Syntax
}

private func hasUserDefinedInit(in decl: some DeclGroupSyntax) -> Bool {
    decl.memberBlock.members.contains { member in
        member.decl.is(InitializerDeclSyntax.self)
    }
}

private func containerAccessLevel(for decl: some DeclGroupSyntax) -> String? {
    let modifiers = decl.modifiers
    if modifiers.isEmpty {
        return nil
    }
    for modifier in modifiers {
        switch modifier.name.text {
        case "public", "open":
            return "public"
        case "internal", "fileprivate", "private":
            return modifier.name.text
        default:
            continue
        }
    }
    return nil
}

private func accessModifiers(_ accessLevel: String?) -> DeclModifierListSyntax {
    guard let accessLevel else { return DeclModifierListSyntax([]) }
    let token: TokenSyntax
    switch accessLevel {
    case "public": token = .keyword(.public)
    case "internal": token = .keyword(.internal)
    case "fileprivate": token = .keyword(.fileprivate)
    case "private": token = .keyword(.private)
    default: return DeclModifierListSyntax([])
    }
    let modifier = DeclModifierSyntax(name: token)
    return DeclModifierListSyntax([modifier])
}

private func collectProvideMembers(
    in decl: some DeclGroupSyntax,
    context: MacroExpansionContext,
    hadErrors: inout Bool
) -> [ProvideMember] {
    var result: [ProvideMember] = []

    for member in decl.memberBlock.members {
        guard let varDecl = member.decl.as(VariableDeclSyntax.self) else {
            continue
        }

        if varDecl.modifiers.contains(where: { $0.name.text == "static" }) {
            continue
        }

        guard let attribute = findAttribute(named: "Provide", in: varDecl.attributes) else {
            continue
        }

        guard varDecl.bindings.count == 1, let binding = varDecl.bindings.first else {
            context.diagnose(Diagnostic(node: Syntax(varDecl), message: SimpleDiagnostic("@Provide supports a single variable binding.")))
            hadErrors = true
            continue
        }

        guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
            context.diagnose(Diagnostic(node: Syntax(binding), message: SimpleDiagnostic("@Provide requires a named property.")))
            hadErrors = true
            continue
        }

        guard let typeAnnotation = binding.typeAnnotation else {
            context.diagnose(Diagnostic(node: Syntax(binding), message: SimpleDiagnostic("@Provide requires an explicit type.")))
            hadErrors = true
            continue
        }

        if binding.initializer != nil {
            context.diagnose(Diagnostic(node: Syntax(binding), message: SimpleDiagnostic("Remove property initializer and pass a factory in @Provide(...).")))
            hadErrors = true
        }

        let parseResult = parseProvideArguments(attribute)
        guard let scope = parseResult.scope else {
            if let name = parseResult.scopeName {
                context.diagnose(Diagnostic(node: Syntax(attribute), message: SimpleDiagnostic("Unknown @Provide scope: \(name).")))
            }
            hadErrors = true
            continue
        }

        if scope == .shared && parseResult.factoryExpr == nil {
            context.diagnose(Diagnostic(node: Syntax(attribute), message: SimpleDiagnostic("@Provide(.shared) requires factory: <expr>.")))
            hadErrors = true
        }

        if scope == .input && parseResult.factoryExpr != nil {
            context.diagnose(Diagnostic(node: Syntax(attribute), message: SimpleDiagnostic("@Provide(.input) should not include a factory.")))
            hadErrors = true
        }

        result.append(
            ProvideMember(
                name: identifier.identifier.text,
                type: typeAnnotation.type,
                scope: scope,
                factory: parseResult.factoryExpr,
                syntax: Syntax(varDecl)
            )
        )
    }

    return result
}

private func makeOverridesStruct(sharedMembers: [ProvideMember], accessLevel: String?) -> DeclSyntax {
    let modifiers = accessModifiers(accessLevel)
    var members: [MemberBlockItemSyntax] = []

    for member in sharedMembers {
        let name = TokenSyntax.identifier(member.name)
        let optionalType = TypeSyntax(OptionalTypeSyntax(wrappedType: member.type))
        let binding = PatternBindingSyntax(
            pattern: IdentifierPatternSyntax(identifier: name),
            typeAnnotation: TypeAnnotationSyntax(type: optionalType),
            initializer: nil,
            accessorBlock: nil,
            trailingComma: nil
        )
        let varDecl = VariableDeclSyntax(
            modifiers: modifiers,
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax([binding])
        )
        members.append(MemberBlockItemSyntax(decl: DeclSyntax(varDecl)))
    }

    let initDecl = InitializerDeclSyntax(
        modifiers: modifiers,
        signature: FunctionSignatureSyntax(parameterClause: FunctionParameterClauseSyntax(parameters: FunctionParameterListSyntax([]))),
        body: CodeBlockSyntax(statements: CodeBlockItemListSyntax([]))
    )
    members.append(MemberBlockItemSyntax(decl: DeclSyntax(initDecl)))

    let structDecl = StructDeclSyntax(
        modifiers: modifiers,
        name: .identifier("Overrides"),
        memberBlock: MemberBlockSyntax(members: MemberBlockItemListSyntax(members))
    )

    return DeclSyntax(structDecl)
}

private func makeInitDecl(
    sharedMembers: [ProvideMember],
    inputMembers: [ProvideMember],
    accessLevel: String?
) -> DeclSyntax {
    let modifiers = accessModifiers(accessLevel)
    var params: [FunctionParameterSyntax] = []

    if !sharedMembers.isEmpty {
        let overridesType = TypeSyntax(IdentifierTypeSyntax(name: .identifier("Overrides")))
        let defaultValue = InitializerClauseSyntax(value: dotInitExpr())
        let overridesParam = FunctionParameterSyntax(
            firstName: .identifier("overrides"),
            secondName: nil,
            colon: .colonToken(),
            type: overridesType,
            ellipsis: nil,
            defaultValue: defaultValue,
            trailingComma: nil
        )
        params.append(overridesParam)
    }

    for member in inputMembers {
        let param = FunctionParameterSyntax(
            firstName: .identifier(member.name),
            secondName: nil,
            colon: .colonToken(),
            type: member.type,
            ellipsis: nil,
            defaultValue: nil,
            trailingComma: nil
        )
        params.append(param)
    }

    let signature = FunctionSignatureSyntax(
        parameterClause: FunctionParameterClauseSyntax(parameters: FunctionParameterListSyntax(params))
    )

    var statements: [CodeBlockItemSyntax] = []

    for member in sharedMembers {
        let name = TokenSyntax.identifier(member.name)
        let factoryExpr = member.factory ?? ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("nil")))
        let initializerExpr = ExprSyntax(
            InfixOperatorExprSyntax(
                leftOperand: overridesMemberExpr(name: member.name),
                operator: BinaryOperatorExprSyntax(operator: .binaryOperator("??")),
                rightOperand: factoryExpr
            )
        )
        let binding = PatternBindingSyntax(
            pattern: IdentifierPatternSyntax(identifier: name),
            typeAnnotation: nil,
            initializer: InitializerClauseSyntax(value: initializerExpr),
            accessorBlock: nil,
            trailingComma: nil
        )
        let letDecl = VariableDeclSyntax(
            modifiers: DeclModifierListSyntax([]),
            bindingSpecifier: .keyword(.let),
            bindings: PatternBindingListSyntax([binding])
        )
        statements.append(CodeBlockItemSyntax(item: .decl(DeclSyntax(letDecl))))
    }

    for member in inputMembers {
        statements.append(CodeBlockItemSyntax(item: .expr(assignExpr(targetName: member.name, valueName: member.name))))
    }

    for member in sharedMembers {
        statements.append(CodeBlockItemSyntax(item: .expr(assignExpr(targetName: member.name, valueName: member.name))))
    }

    let initDecl = InitializerDeclSyntax(
        modifiers: modifiers,
        signature: signature,
        body: CodeBlockSyntax(statements: CodeBlockItemListSyntax(statements))
    )

    return DeclSyntax(initDecl)
}

private func dotInitExpr() -> ExprSyntax {
    let initDecl = DeclReferenceExprSyntax(baseName: .identifier("init"))
    let memberAccess = MemberAccessExprSyntax(base: ExprSyntax?.none, declName: initDecl)
    let call = FunctionCallExprSyntax(
        calledExpression: memberAccess,
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax([]),
        rightParen: .rightParenToken()
    )
    return ExprSyntax(call)
}

private func overridesMemberExpr(name: String) -> ExprSyntax {
    let base = DeclReferenceExprSyntax(baseName: .identifier("overrides"))
    let memberAccess = MemberAccessExprSyntax(
        base: ExprSyntax(base),
        declName: DeclReferenceExprSyntax(baseName: .identifier(name))
    )
    return ExprSyntax(memberAccess)
}

private func selfMemberExpr(name: String) -> ExprSyntax {
    let base = DeclReferenceExprSyntax(baseName: .keyword(.self))
    let memberAccess = MemberAccessExprSyntax(
        base: ExprSyntax(base),
        declName: DeclReferenceExprSyntax(baseName: .identifier(name))
    )
    return ExprSyntax(memberAccess)
}

private func assignExpr(targetName: String, valueName: String) -> ExprSyntax {
    let valueExpr = ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(valueName)))
    let assignment = InfixOperatorExprSyntax(
        leftOperand: selfMemberExpr(name: targetName),
        operator: AssignmentExprSyntax(),
        rightOperand: valueExpr
    )
    return ExprSyntax(assignment)
}
