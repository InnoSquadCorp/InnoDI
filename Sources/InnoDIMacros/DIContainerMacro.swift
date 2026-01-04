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
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try expansion(of: attribute, providingMembersOf: decl, in: context)
    }

    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf decl: some DeclGroupSyntax,
        in context: some MacroExpansionContext
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
        let transientMembers = provideMembers.filter { $0.scope == .transient }

        var generated: [DeclSyntax] = []

        // No more Overrides struct
        
        generated.append(makeInitDecl(
            sharedMembers: sharedMembers,
            inputMembers: inputMembers,
            transientMembers: transientMembers,
            accessLevel: accessLevel
        ))

        return generated
    }
}

private struct ProvideMember {
    let name: String
    let type: TypeSyntax
    let scope: ProvideScope
    let factory: ExprSyntax?
    let typeExpr: ExprSyntax?
    let dependencies: [String]
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

        if scope == .shared && parseResult.factoryExpr == nil && parseResult.typeExpr == nil {
            context.diagnose(Diagnostic(node: Syntax(attribute), message: SimpleDiagnostic("@Provide(.shared) requires factory: <expr> or type: Type.self.")))
            hadErrors = true
        }

        if scope == .transient && parseResult.factoryExpr == nil && parseResult.typeExpr == nil {
            context.diagnose(Diagnostic(node: Syntax(attribute), message: SimpleDiagnostic("@Provide(.transient) requires factory: <expr> or type: Type.self.")))
            hadErrors = true
        }

        if scope == .input && (parseResult.factoryExpr != nil || parseResult.typeExpr != nil) {
            context.diagnose(Diagnostic(node: Syntax(attribute), message: SimpleDiagnostic("@Provide(.input) should not include a factory or type.")))
            hadErrors = true
        }

        result.append(
            ProvideMember(
                name: identifier.identifier.text,
                type: typeAnnotation.type,
                scope: scope,
                factory: parseResult.factoryExpr,
                typeExpr: parseResult.typeExpr,
                dependencies: parseResult.dependencies,
                syntax: Syntax(varDecl)
            )
        )
    }

    return result
}

private func makeInitDecl(
    sharedMembers: [ProvideMember],
    inputMembers: [ProvideMember],
    transientMembers: [ProvideMember],
    accessLevel: String?
) -> DeclSyntax {
    let modifiers = accessModifiers(accessLevel)
    var params: [FunctionParameterSyntax] = []

    // 1. Input members (Required)
    for (index, member) in inputMembers.enumerated() {
        let isLast = index == inputMembers.count - 1 && sharedMembers.isEmpty && transientMembers.isEmpty
        let param = FunctionParameterSyntax(
            firstName: .identifier(member.name),
            secondName: nil,
            colon: .colonToken(),
            type: member.type,
            ellipsis: nil,
            defaultValue: nil,
            trailingComma: isLast ? nil : .commaToken()
        )
        params.append(param)
    }
    
    // 2. Shared members (Optional override)
    for (index, member) in sharedMembers.enumerated() {
        let isLast = index == sharedMembers.count - 1 && transientMembers.isEmpty
        let param = FunctionParameterSyntax(
            firstName: .identifier(member.name),
            secondName: nil,
            colon: .colonToken(),
            type: TypeSyntax(OptionalTypeSyntax(wrappedType: member.type)), // Optional for override
            ellipsis: nil,
            defaultValue: InitializerClauseSyntax(value: NilLiteralExprSyntax()), // default nil
            trailingComma: isLast ? nil : .commaToken()
        )
        params.append(param)
    }
    
    // 3. Transient members (Optional override)
    for (index, member) in transientMembers.enumerated() {
        let isLast = index == transientMembers.count - 1
        let param = FunctionParameterSyntax(
            firstName: .identifier(member.name),
            secondName: nil,
            colon: .colonToken(),
            type: TypeSyntax(OptionalTypeSyntax(wrappedType: member.type)), // Optional for override
            ellipsis: nil,
            defaultValue: InitializerClauseSyntax(value: NilLiteralExprSyntax()), // default nil
            trailingComma: isLast ? nil : .commaToken()
        )
        params.append(param)
    }

    let signature = FunctionSignatureSyntax(
        parameterClause: FunctionParameterClauseSyntax(parameters: FunctionParameterListSyntax(params))
    )

    var statements: [CodeBlockItemSyntax] = []

    // Assignments
    
    // Input: self.name = name
    for member in inputMembers {
        statements.append(CodeBlockItemSyntax(item: .expr(assignExpr(targetName: member.name, valueName: member.name))))
    }

    // Shared:
    // let _name = name ?? Factory(...)
    // self.name = _name
    let inputNames = inputMembers.map { $0.name }
    for (index, member) in sharedMembers.enumerated() {
        // let name = TokenSyntax.identifier(member.name) // Unused
        let availableNames = inputNames + sharedMembers.prefix(index).map { $0.name }
        
        let factoryExpr = makeFactoryExpr(member: member, availableNames: availableNames)
        
        let initializerExpr = ExprSyntax(
            InfixOperatorExprSyntax(
                leftOperand: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(member.name))), // Parameter name
                operator: BinaryOperatorExprSyntax(operator: .binaryOperator("??")),
                rightOperand: factoryExpr
            )
        )
        
        // let _name = ...
        let tempName = "_\(member.name)"
        let binding = PatternBindingSyntax(
            pattern: IdentifierPatternSyntax(identifier: .identifier(tempName)),
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
        
        // self.name = _name
        statements.append(CodeBlockItemSyntax(item: .expr(assignExpr(targetName: member.name, valueName: tempName))))
    }
    
    // Transient:
    // self._override_name = name
    for member in transientMembers {
        let overrideName = "_override_\(member.name)"
        statements.append(CodeBlockItemSyntax(item: .expr(assignExpr(targetName: overrideName, valueName: member.name))))
    }

    let initDecl = InitializerDeclSyntax(
        modifiers: modifiers,
        signature: signature,
        body: CodeBlockSyntax(statements: CodeBlockItemListSyntax(statements))
    )

    return DeclSyntax(initDecl)
}

private func makeFactoryExpr(member: ProvideMember, availableNames: [String]) -> ExprSyntax {
    if let factory = member.factory {
        if let closure = factory.as(ClosureExprSyntax.self) {
             let argumentNames = closureArgumentNames(closure: closure, availableNames: availableNames)
             return ExprSyntax(callClosureExpr(closure: closure, argumentNames: argumentNames))
        }
        return factory
    }
    
    if let typeExpr = member.typeExpr {
        var args: [LabeledExprSyntax] = []
        for dep in member.dependencies {
            args.append(LabeledExprSyntax(
                label: .identifier(dep),
                colon: .colonToken(),
                expression: ExprSyntax(MemberAccessExprSyntax(
                    base: DeclReferenceExprSyntax(baseName: .keyword(.self)),
                    declName: DeclReferenceExprSyntax(baseName: .identifier(dep))
                ))
            ))
        }
        
        let call = FunctionCallExprSyntax(
            calledExpression: typeExpr,
            leftParen: .leftParenToken(),
            arguments: LabeledExprListSyntax(args),
            rightParen: .rightParenToken()
        )
        return ExprSyntax(call)
    }

    // Should be unreachable due to validation
    return ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("nil")))
}

private func closureArgumentNames(closure: ClosureExprSyntax, availableNames: [String]) -> [String] {
    guard let signature = closure.signature,
          let parameterClause = signature.parameterClause else {
        return []
    }

    var result: [String] = []

    switch parameterClause {
    case .simpleInput(let shorthandParameters):
        for (index, param) in shorthandParameters.enumerated() {
            result.append(matchClosureParameter(name: param.name.text, index: index, availableNames: availableNames))
        }
    case .parameterClause(let parameterClause):
        for (index, param) in parameterClause.parameters.enumerated() {
            let name = param.secondName?.text ?? param.firstName.text
            result.append(matchClosureParameter(name: name, index: index, availableNames: availableNames))
        }
    }

    return result
}

private func matchClosureParameter(name: String, index: Int, availableNames: [String]) -> String {
    if availableNames.contains(name) {
        return name
    }

    if index < availableNames.count {
        return availableNames[index]
    }

    return name
}

private func callClosureExpr(closure: ClosureExprSyntax, argumentNames: [String]) -> ExprSyntax {
    var arguments: [LabeledExprSyntax] = []

    for (index, name) in argumentNames.enumerated() {
        let isLast = index == argumentNames.count - 1
        let expr = ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(name)))
        let argument = LabeledExprSyntax(
            label: nil,
            colon: nil,
            expression: expr,
            trailingComma: isLast ? nil : .commaToken()
        )
        arguments.append(argument)
    }

    let call = FunctionCallExprSyntax(
        calledExpression: ExprSyntax(closure),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax(arguments),
        rightParen: .rightParenToken()
    )

    return ExprSyntax(call)
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
