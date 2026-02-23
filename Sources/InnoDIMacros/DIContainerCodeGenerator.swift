import SwiftSyntax
import SwiftSyntaxBuilder

struct DIContainerCodeGenerator {
    static func generateInit(for model: DIContainerExpansionModel) -> DeclSyntax {
        makeInitDecl(
            sharedMembers: model.sharedMembers,
            syncSharedMembers: model.syncSharedMembers,
            asyncSharedMembers: model.asyncSharedMembers,
            inputMembers: model.inputMembers,
            transientMembers: model.transientMembers,
            accessLevel: model.accessLevel,
            validateEnabled: model.options.validate,
            mainActorEnabled: model.options.mainActor
        )
    }
}

private struct AsyncTaskBinding {
    let name: String
    let isThrowing: Bool
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

private func makeInitDecl(
    sharedMembers: [ProvideMemberModel],
    syncSharedMembers: [ProvideMemberModel],
    asyncSharedMembers: [ProvideMemberModel],
    inputMembers: [ProvideMemberModel],
    transientMembers: [ProvideMemberModel],
    accessLevel: String?,
    validateEnabled: Bool,
    mainActorEnabled: Bool
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
            type: optionalParameterType(for: member.type),
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
            type: optionalParameterType(for: member.type),
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
    var resolvedValueBindings: [String: String] = [:]
    var taskBindings: [String: AsyncTaskBinding] = [:]
    let needsResolvedBindings = !asyncSharedMembers.isEmpty

    for member in inputMembers {
        let storageName = "_storage_\(member.name)"
        statements.append(CodeBlockItemSyntax(item: .expr(assignExpr(targetName: storageName, valueName: member.name))))

        if needsResolvedBindings {
            let resolvedName = "_resolved_\(member.name)"
            let resolvedDecl: DeclSyntax = "let \(raw: resolvedName) = \(raw: member.name)"
            statements.append(CodeBlockItemSyntax(item: .decl(resolvedDecl)))
            resolvedValueBindings[member.name] = resolvedName
        }
    }

    let inputStorageNames = inputMembers.map { "_storage_\($0.name)" }
    for (index, member) in syncSharedMembers.enumerated() {
        let availableStorageNames = inputStorageNames + syncSharedMembers.prefix(index).map { "_storage_\($0.name)" }
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

        if needsResolvedBindings {
            let resolvedName = "_resolved_\(member.name)"
            let resolvedDecl: DeclSyntax = "let \(raw: resolvedName) = \(raw: storageName)"
            statements.append(CodeBlockItemSyntax(item: .decl(resolvedDecl)))
            resolvedValueBindings[member.name] = resolvedName
        }
    }

    for member in asyncSharedMembers {
        let taskName = "_task_\(member.name)"
        let successType = taskSuccessTypeDescription(for: member.type)
        let failureType = member.asyncFactoryIsThrowing ? "Error" : "Never"
        let createExpr = makeAsyncFactoryExpr(
            member: member,
            resolvedValueBindings: resolvedValueBindings,
            taskBindings: taskBindings
        )
        let factoryCall = createExpr.trimmedDescription
        let awaitedFactoryCall = member.asyncFactoryIsThrowing
            ? "try await \(factoryCall)"
            : "await \(factoryCall)"

        let taskDecl: DeclSyntax = """
        let \(raw: taskName) = Task<\(raw: successType), \(raw: failureType)> {
            if let override = \(raw: member.name) { return override }
            return \(raw: awaitedFactoryCall)
        }
        """
        statements.append(CodeBlockItemSyntax(item: .decl(taskDecl)))

        let storageName = "_storage_task_\(member.name)"
        statements.append(CodeBlockItemSyntax(item: .expr(assignExpr(targetName: storageName, valueName: taskName))))

        let resolvedTaskName = "_resolved_task_\(member.name)"
        let resolvedTaskDecl: DeclSyntax = "let \(raw: resolvedTaskName) = \(raw: taskName)"
        statements.append(CodeBlockItemSyntax(item: .decl(resolvedTaskDecl)))
        taskBindings[member.name] = AsyncTaskBinding(name: resolvedTaskName, isThrowing: member.asyncFactoryIsThrowing)
    }

    for member in transientMembers {
        let overrideName = "_override_\(member.name)"
        statements.append(CodeBlockItemSyntax(item: .expr(assignExpr(targetName: overrideName, valueName: member.name))))
    }

    let initDecl = InitializerDeclSyntax(
        attributes: mainActorEnabled ? mainActorAttributeList() : AttributeListSyntax([]),
        modifiers: modifiers,
        signature: signature,
        body: CodeBlockSyntax(statements: CodeBlockItemListSyntax(statements))
    )

    return DeclSyntax(initDecl)
}

private func optionalParameterType(for type: TypeSyntax) -> TypeSyntax {
    let trimmed = type.trimmedDescription

    if trimmed.hasPrefix("any ") || trimmed.hasPrefix("some ") || trimmed.contains("&") {
        return TypeSyntax(stringLiteral: "(\(trimmed))?")
    }

    return TypeSyntax(stringLiteral: "\(trimmed)?")
}

private func makeFactoryExpr(
    member: ProvideMemberModel,
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
        for dep in member.withDependencies {
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

private func makeAsyncFactoryExpr(
    member: ProvideMemberModel,
    resolvedValueBindings: [String: String],
    taskBindings: [String: AsyncTaskBinding]
) -> ExprSyntax {
    guard let asyncFactory = member.asyncFactory else {
        return ExprSyntax(
            FunctionCallExprSyntax(
                calledExpression: DeclReferenceExprSyntax(baseName: .identifier("fatalError")),
                leftParen: .leftParenToken(),
                arguments: LabeledExprListSyntax([
                    LabeledExprSyntax(expression: ExprSyntax(StringLiteralExprSyntax(content: "Missing async factory for shared dependency '\(member.name)'.")))
                ]),
                rightParen: .rightParenToken()
            )
        )
    }

    if let closure = asyncFactory.as(ClosureExprSyntax.self) {
        let parsedArguments = parseClosureParameterNames(closure)
        let expressions = parsedArguments.names.map { dependencyExpression(for: $0, resolvedValueBindings: resolvedValueBindings, taskBindings: taskBindings) }
        return makeClosureCallExpr(closure: closure, argumentExpressions: expressions)
    }

    return asyncFactory
}

private func dependencyExpression(
    for dependencyName: String,
    resolvedValueBindings: [String: String],
    taskBindings: [String: AsyncTaskBinding]
) -> ExprSyntax {
    if let resolvedName = resolvedValueBindings[dependencyName] {
        return ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(resolvedName)))
    }

    if let taskBinding = taskBindings[dependencyName] {
        if taskBinding.isThrowing {
            return ExprSyntax("\(raw: "try await \(taskBinding.name).value")")
        }
        return ExprSyntax("\(raw: "await \(taskBinding.name).value")")
    }

    return ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(dependencyName)))
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

    for availableName in availableNames where availableName.hasPrefix("_storage_") {
        let nameWithoutPrefix = String(availableName.dropFirst(9))
        if nameWithoutPrefix == dependencyName {
            return availableName
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

private func taskSuccessTypeDescription(for type: TypeSyntax) -> String {
    let description = type.trimmedDescription
    if description.hasPrefix("any ") || description.hasPrefix("some ") || description.contains("&") {
        return "(\(description))"
    }
    return description
}

private func mainActorAttributeList() -> AttributeListSyntax {
    AttributeListSyntax([
        AttributeListSyntax.Element(
            AttributeSyntax(
                attributeName: IdentifierTypeSyntax(name: .identifier("MainActor"))
            )
        )
    ])
}
