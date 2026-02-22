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

        let containerOptions = parseDIContainerAttribute(decl.attributes) ?? DIContainerAttributeInfo(validate: true, root: false)
        let accessLevel = containerAccessLevel(for: decl)
        var hadErrors = false
        let provideMembers = collectProvideMembers(
            in: decl,
            context: context,
            validateEnabled: containerOptions.validate,
            hadErrors: &hadErrors
        )

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
            accessLevel: accessLevel,
            validateEnabled: containerOptions.validate
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
    let initializer: ExprSyntax?
    let dependencies: [String]
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
    validateEnabled: Bool,
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
            context.diagnose(Diagnostic(node: Syntax(varDecl), message: SimpleDiagnostic.provideSingleBinding()))
            hadErrors = true
            continue
        }

        guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
            context.diagnose(Diagnostic(node: Syntax(binding), message: SimpleDiagnostic.provideNamedPropertyRequired()))
            hadErrors = true
            continue
        }

        guard let typeAnnotation = binding.typeAnnotation else {
            context.diagnose(Diagnostic(node: Syntax(binding), message: SimpleDiagnostic.provideExplicitTypeRequired()))
            hadErrors = true
            continue
        }

        let parseResult = parseProvideArguments(attribute)
        guard let scope = parseResult.scope else {
            if let name = parseResult.scopeName {
                context.diagnose(Diagnostic(node: Syntax(attribute), message: SimpleDiagnostic.provideUnknownScope(name)))
            }
            hadErrors = true
            continue
        }

        let initializerExpr = binding.initializer?.value
        let hasFactory = parseResult.factoryExpr != nil || parseResult.typeExpr != nil || initializerExpr != nil

        if scope == .shared && !hasFactory && validateEnabled {
            context.diagnose(Diagnostic(node: Syntax(attribute), message: SimpleDiagnostic.provideSharedFactoryRequired()))
            hadErrors = true
        }

        if scope == .transient && !hasFactory && validateEnabled {
            context.diagnose(Diagnostic(node: Syntax(attribute), message: SimpleDiagnostic.provideTransientFactoryRequired()))
            hadErrors = true
        }

        if scope == .input && (parseResult.factoryExpr != nil || parseResult.typeExpr != nil || initializerExpr != nil) {
            context.diagnose(Diagnostic(node: Syntax(attribute), message: SimpleDiagnostic.provideInputInvalidConfiguration()))
            hadErrors = true
        }

        if scope != .input && !parseResult.concrete && requiresConcreteOptIn(type: typeAnnotation.type) {
            context.diagnose(
                Diagnostic(
                    node: Syntax(attribute),
                    message: SimpleDiagnostic.provideConcreteOptInRequired(
                        name: identifier.identifier.text,
                        typeDescription: typeAnnotation.type.trimmedDescription
                    )
                )
            )
            hadErrors = true
        }

        result.append(
            ProvideMember(
                name: identifier.identifier.text,
                type: typeAnnotation.type,
                scope: scope,
                factory: parseResult.factoryExpr,
                typeExpr: parseResult.typeExpr,
                initializer: initializerExpr,
                dependencies: parseResult.dependencies
            )
        )
    }

    return result
}

private func makeInitDecl(
    sharedMembers: [ProvideMember],
    inputMembers: [ProvideMember],
    transientMembers: [ProvideMember],
    accessLevel: String?,
    validateEnabled: Bool
) -> DeclSyntax {
    let modifiers = accessModifiers(accessLevel)
    var params: [FunctionParameterSyntax] = []

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
    
    for (index, member) in sharedMembers.enumerated() {
        let isLast = index == sharedMembers.count - 1 && transientMembers.isEmpty
        let param = FunctionParameterSyntax(
            firstName: .identifier(member.name),
            secondName: nil,
            colon: .colonToken(),
            type: TypeSyntax(OptionalTypeSyntax(wrappedType: member.type.trimmed)),
            ellipsis: nil,
            defaultValue: InitializerClauseSyntax(value: NilLiteralExprSyntax()),
            trailingComma: isLast ? nil : .commaToken()
        )
        params.append(param)
    }
    
    for (index, member) in transientMembers.enumerated() {
        let isLast = index == transientMembers.count - 1
        let param = FunctionParameterSyntax(
            firstName: .identifier(member.name),
            secondName: nil,
            colon: .colonToken(),
            type: TypeSyntax(OptionalTypeSyntax(wrappedType: member.type.trimmed)),
            ellipsis: nil,
            defaultValue: InitializerClauseSyntax(value: NilLiteralExprSyntax()),
            trailingComma: isLast ? nil : .commaToken()
        )
        params.append(param)
    }

    let signature = FunctionSignatureSyntax(
        parameterClause: FunctionParameterClauseSyntax(parameters: FunctionParameterListSyntax(params))
    )

    var statements: [CodeBlockItemSyntax] = []

    for member in inputMembers {
        let storageName = "_storage_\(member.name)"
        statements.append(CodeBlockItemSyntax(item: .expr(assignExpr(targetName: storageName, valueName: member.name))))
    }

    let inputStorageNames = inputMembers.map { "_storage_\($0.name)" }
    for (index, member) in sharedMembers.enumerated() {
        let availableStorageNames = inputStorageNames + sharedMembers.prefix(index).map { "_storage_\($0.name)" }
        let factoryExpr = makeFactoryExpr(
            member: member,
            availableNames: availableStorageNames,
            allowMissingFactoryFallback: !validateEnabled
        )
        
        let initializerExpr = ExprSyntax(
            InfixOperatorExprSyntax(
                leftOperand: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(member.name))),
                operator: BinaryOperatorExprSyntax(operator: .binaryOperator("??")),
                rightOperand: factoryExpr
            )
        )
        
        let storageName = "_storage_\(member.name)"
        statements.append(CodeBlockItemSyntax(item: .expr(assignExprWithValue(targetName: storageName, value: initializerExpr))))
    }
    
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

private func makeFactoryExpr(
    member: ProvideMember,
    availableNames: [String],
    allowMissingFactoryFallback: Bool
) -> ExprSyntax {
    if let factory = member.factory {
        if let closure = factory.as(ClosureExprSyntax.self) {
            let argumentNames = closureArgumentNames(closure: closure, availableNames: availableNames)
            return makeClosureCallExpr(closure: closure, argumentNames: argumentNames)
        }
        return factory
    }

    if let initializer = member.initializer {
        return initializer
    }

    if let typeExpr = member.typeExpr {
        var args: [LabeledExprSyntax] = []
        for dep in member.dependencies {
            let storageName = mapDependencyNameToStorageName(dep, availableNames: availableNames)
            args.append(LabeledExprSyntax(
                label: .identifier(dep),
                colon: .colonToken(),
                expression: makeSelfMemberAccessExpr(name: storageName)
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

    if allowMissingFactoryFallback {
        return ExprSyntax(
            FunctionCallExprSyntax(
                calledExpression: DeclReferenceExprSyntax(baseName: .identifier("fatalError")),
                leftParen: .leftParenToken(),
                arguments: LabeledExprListSyntax([
                    LabeledExprSyntax(
                        expression: ExprSyntax(
                            StringLiteralExprSyntax(
                                content: "Missing factory for shared dependency '\(member.name)'."
                            )
                        )
                    )
                ]),
                rightParen: .rightParenToken()
            )
        )
    }

    fatalError("No factory expression available - validation should have caught this")
}

private func requiresConcreteOptIn(type: TypeSyntax) -> Bool {
    let normalized = normalizedConcreteCheckType(type)

    if normalized.is(SomeOrAnyTypeSyntax.self) || normalized.is(CompositionTypeSyntax.self) {
        return false
    }

    if let identifier = normalized.as(IdentifierTypeSyntax.self) {
        return !isExistentialIdentifier(identifier.name.text)
    }

    if let member = normalized.as(MemberTypeSyntax.self) {
        return !isExistentialIdentifier(member.name.text)
    }

    return true
}

private func normalizedConcreteCheckType(_ type: TypeSyntax) -> TypeSyntax {
    if let optional = type.as(OptionalTypeSyntax.self) {
        return normalizedConcreteCheckType(optional.wrappedType)
    }

    if let implicitlyUnwrapped = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
        return normalizedConcreteCheckType(implicitlyUnwrapped.wrappedType)
    }

    if let attributed = type.as(AttributedTypeSyntax.self) {
        return normalizedConcreteCheckType(attributed.baseType)
    }

    if let tuple = type.as(TupleTypeSyntax.self),
       tuple.elements.count == 1,
       let first = tuple.elements.first,
       first.firstName == nil,
       first.secondName == nil {
        return normalizedConcreteCheckType(first.type)
    }

    if let identifier = type.as(IdentifierTypeSyntax.self),
       identifier.name.text == "Optional",
       let wrapped = identifier.genericArgumentClause?.arguments.first?.argument,
       let wrappedType = wrapped.as(TypeSyntax.self) {
        return normalizedConcreteCheckType(wrappedType)
    }

    return type
}

private func isExistentialIdentifier(_ name: String) -> Bool {
    name == "Any" || name == "AnyObject"
}

private func closureArgumentNames(closure: ClosureExprSyntax, availableNames: [String]) -> [String] {
    let parsedArguments = parseClosureParameterNames(closure)
    var result: [String] = []

    for (index, name) in parsedArguments.names.enumerated() {
        result.append(matchClosureParameter(name: name, index: index, availableNames: availableNames))
    }

    return result
}

private func matchClosureParameter(name: String, index: Int, availableNames: [String]) -> String {
    if availableNames.contains(name) {
        return name
    }

    let nameWithoutPrefix = name.hasPrefix("_storage_") ? String(name.dropFirst(9)) : name

    for (i, availableName) in availableNames.enumerated() {
        let availableWithoutPrefix = availableName.hasPrefix("_storage_") ? String(availableName.dropFirst(9)) : availableName
        if availableWithoutPrefix == nameWithoutPrefix {
            return availableNames[i]
        }
    }

    if index < availableNames.count {
        return availableNames[index]
    }

    return name
}

private func mapDependencyNameToStorageName(_ dependencyName: String, availableNames: [String]) -> String {
    if availableNames.contains(dependencyName) {
        return dependencyName
    }

    for availableName in availableNames {
        if availableName.hasPrefix("_storage_") {
            let nameWithoutPrefix = String(availableName.dropFirst(9))
            if nameWithoutPrefix == dependencyName {
                return availableName
            }
        }
    }

    return dependencyName
}

private func assignExpr(targetName: String, valueName: String) -> ExprSyntax {
    let valueExpr = ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(valueName)))
    let assignment = InfixOperatorExprSyntax(
        leftOperand: makeSelfMemberAccessExpr(name: targetName),
        operator: AssignmentExprSyntax(),
        rightOperand: valueExpr
    )
    return ExprSyntax(assignment)
}

private func assignExprWithValue(targetName: String, value: ExprSyntax) -> ExprSyntax {
    let assignment = InfixOperatorExprSyntax(
        leftOperand: makeSelfMemberAccessExpr(name: targetName),
        operator: AssignmentExprSyntax(),
        rightOperand: value
    )
    return ExprSyntax(assignment)
}
