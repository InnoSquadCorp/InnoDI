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
            mainActorEnabled: model.options.mainActor
        )
    }

    /// Generates the full member set: primary init + (if applicable) `Overrides`
    /// struct + convenience init + 4 `withOverrides` effect overloads.
    ///
    /// When the container has no `.shared`/`.transient` members, the overrides
    /// scaffolding is skipped silently — an empty `Overrides` builder would
    /// only add autocomplete noise.
    static func generateAll(for model: DIContainerExpansionModel) -> [DeclSyntax] {
        var decls: [DeclSyntax] = [generateInit(for: model)]

        guard let overridesStruct = makeOverridesStructDecl(model: model) else {
            return decls
        }

        decls.append(overridesStruct)
        decls.append(makeConvenienceInitDecl(model: model))
        decls.append(contentsOf: makeWithOverridesMethods(model: model))
        return decls
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
    mainActorEnabled: Bool
) -> DeclSyntax {
    let modifiers = accessModifiers(accessLevel)
    var params: [FunctionParameterSyntax] = []

    // Phase K: compute the set of members that are the target of at least one
    // soft (Lazy<T>) factory-parameter edge. For these members we emit a
    // local `var _lazyRef_<name>: <Type>? = nil` at the top of init and write
    // through to it immediately after the storage assignment — the Lazy
    // wrapper closures capture the `_lazyRef_` box so they resolve to the
    // fully-initialized value after init returns, without capturing `self`
    // (which would snapshot a struct container).
    let allMembersForSoft = inputMembers + sharedMembers + transientMembers
    let softTargetNames = Set(allMembersForSoft.flatMap(\.softClosureDependencies))
    let softTargetMembers = allMembersForSoft.filter { member in
        softTargetNames.contains(member.name)
            && (member.scope == .shared || member.scope == .input)
    }
    let softTargetNameSet = Set(softTargetMembers.map(\.name))

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

    // Declare one `_LazyCell` reference box per soft-target member. These
    // boxes are `let` bindings wrapping a class instance, so the Lazy
    // wrappers we emit below can read `.value` after init completes — even
    // though factories that capture the box run *before* the target storage
    // is assigned. For struct containers, this avoids the "cannot capture
    // self in init" problem entirely because the box is a local `let`, not
    // a reference to `self`.
    for target in softTargetMembers {
        statements.append(
            CodeBlockItemSyntax(item: .decl(makeLazyCellDecl(name: target.name, type: target.type)))
        )
    }

    for member in inputMembers {
        let storageName = "_storage_\(member.name)"
        statements.append(CodeBlockItemSyntax(item: .expr(assignExpr(targetName: storageName, valueName: member.name))))

        if needsResolvedBindings {
            let resolvedName = "_resolved_\(member.name)"
            let resolvedDecl = letBinding(name: resolvedName, value: member.name)
            statements.append(CodeBlockItemSyntax(item: .decl(resolvedDecl)))
            resolvedValueBindings[member.name] = resolvedName
        }

        if softTargetNameSet.contains(member.name) {
            // _lazyCell_<name>.value = self._storage_<name>
            statements.append(
                CodeBlockItemSyntax(item: .expr(makeLazyCellWriteExpr(name: member.name, storageName: storageName)))
            )
        }
    }

    let inputStorageNames = inputMembers.map { "_storage_\($0.name)" }
    for (index, member) in syncSharedMembers.enumerated() {
        let availableStorageNames = inputStorageNames + syncSharedMembers.prefix(index).map { "_storage_\($0.name)" }
        let factoryExpr = makeFactoryExpr(
            member: member,
            availableNames: availableStorageNames,
            softTargetNameSet: softTargetNameSet
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
            let resolvedDecl = letBinding(name: resolvedName, value: storageName)
            statements.append(CodeBlockItemSyntax(item: .decl(resolvedDecl)))
            resolvedValueBindings[member.name] = resolvedName
        }

        if softTargetNameSet.contains(member.name) {
            statements.append(
                CodeBlockItemSyntax(item: .expr(makeLazyCellWriteExpr(name: member.name, storageName: storageName)))
            )
        }
    }

    for member in asyncSharedMembers {
        let taskName = "_task_\(member.name)"
        let successType = taskSuccessTypeDescription(for: member.type)
        let failureType = member.asyncFactoryIsThrowing ? "Error" : "Never"
        let createExpr = makeAsyncFactoryExpr(
            member: member,
            resolvedValueBindings: resolvedValueBindings,
            taskBindings: taskBindings,
            softTargetNameSet: softTargetNameSet
        )

        let awaited = ExprSyntax(AwaitExprSyntax(expression: createExpr))
        let awaitedFactoryExpr: ExprSyntax = member.asyncFactoryIsThrowing
            ? ExprSyntax(TryExprSyntax(expression: awaited))
            : awaited

        let taskDecl = makeAsyncTaskDecl(
            taskName: taskName,
            overrideName: member.name,
            successType: successType,
            failureType: failureType,
            awaitedFactoryExpr: awaitedFactoryExpr
        )
        statements.append(CodeBlockItemSyntax(item: .decl(taskDecl)))

        let storageName = "_storage_task_\(member.name)"
        statements.append(CodeBlockItemSyntax(item: .expr(assignExpr(targetName: storageName, valueName: taskName))))

        let resolvedTaskName = "_resolved_task_\(member.name)"
        let resolvedTaskDecl = letBinding(name: resolvedTaskName, value: taskName)
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
    softTargetNameSet: Set<String>
) -> ExprSyntax {
    if let factory = member.factory {
        if let closure = factory.as(ClosureExprSyntax.self) {
            let argumentExpressions = closureArgumentExpressions(
                member: member,
                closure: closure,
                availableNames: availableNames,
                softTargetNameSet: softTargetNameSet
            )
            return makeClosureCallExpr(closure: closure, argumentExpressions: argumentExpressions)
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

    fatalError("No factory expression available - validation should have caught this")
}

private func makeAsyncFactoryExpr(
    member: ProvideMemberModel,
    resolvedValueBindings: [String: String],
    taskBindings: [String: AsyncTaskBinding],
    softTargetNameSet: Set<String>
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
        let references = member.closureParameterReferences
        let expressions: [ExprSyntax] = references.map { ref in
            if ref.kind == .soft && softTargetNameSet.contains(ref.name) {
                return makeLazyCellWrapperExpr(name: ref.name)
            }
            return dependencyExpression(
                for: ref.name,
                resolvedValueBindings: resolvedValueBindings,
                taskBindings: taskBindings
            )
        }
        return makeClosureCallExpr(closure: closure, argumentExpressions: expressions)
    }

    return asyncFactory
}

/// Builds one argument expression per closure parameter of `member.factory`.
/// Soft parameters that point at a known soft target are replaced with
/// `Lazy({ _lazyCell_<name>.value! })`; all other parameters fall back to
/// `self._storage_<resolved>` via `resolveClosureParameter`.
private func closureArgumentExpressions(
    member: ProvideMemberModel,
    closure: ClosureExprSyntax,
    availableNames: [String],
    softTargetNameSet: Set<String>
) -> [ExprSyntax] {
    let references = member.closureParameterReferences
    // Shorthand closures or attribute-level mismatches may cause the
    // reference list to be out-of-sync with the AST; fall back to a
    // name-only parse in that case.
    if references.isEmpty {
        let parsed = parseClosureParameterNames(closure)
        return parsed.names.map { name in
            guard let resolvedName = resolveClosureParameter(name: name, availableNames: availableNames) else {
                fatalError("Unresolved closure parameter '\(name)' reached code generation.")
            }
            return makeSelfMemberAccessExpr(name: resolvedName)
        }
    }

    var expressions: [ExprSyntax] = []
    for ref in references {
        if ref.kind == .soft && softTargetNameSet.contains(ref.name) {
            expressions.append(makeLazyCellWrapperExpr(name: ref.name))
            continue
        }
        guard let resolvedName = resolveClosureParameter(name: ref.name, availableNames: availableNames) else {
            fatalError("Unresolved closure parameter '\(ref.name)' reached code generation.")
        }
        expressions.append(makeSelfMemberAccessExpr(name: resolvedName))
    }
    return expressions
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
        // <taskBinding.name>.value
        let valueAccess = MemberAccessExprSyntax(
            base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(taskBinding.name))),
            declName: DeclReferenceExprSyntax(baseName: .identifier("value"))
        )
        let awaited = ExprSyntax(AwaitExprSyntax(expression: ExprSyntax(valueAccess)))
        if taskBinding.isThrowing {
            return ExprSyntax(TryExprSyntax(expression: awaited))
        }
        return awaited
    }

    fatalError("Unresolved async dependency '\(dependencyName)' reached code generation.")
}

private func closureArgumentNames(closure: ClosureExprSyntax, availableNames: [String]) -> [String] {
    let parsedArguments = parseClosureParameterNames(closure)
    var result: [String] = []

    for (index, name) in parsedArguments.names.enumerated() {
        guard let resolvedName = resolveClosureParameter(name: name, availableNames: availableNames) else {
            fatalError("Unresolved closure parameter '\(name)' reached code generation at index \(index).")
        }
        result.append(resolvedName)
    }

    return result
}

private func resolveClosureParameter(name: String, availableNames: [String]) -> String? {
    if availableNames.contains(name) {
        return name
    }

    let nameWithoutPrefix = name.hasPrefix("_storage_") ? String(name.dropFirst(9)) : name

    for availableName in availableNames {
        let availableWithoutPrefix = availableName.hasPrefix("_storage_") ? String(availableName.dropFirst(9)) : availableName
        if availableWithoutPrefix == nameWithoutPrefix {
            return availableName
        }
    }

    return nil
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

    fatalError("Unresolved dependency '\(dependencyName)' reached code generation.")
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

// MARK: - Overrides builder

private func overrideCandidateMembers(_ model: DIContainerExpansionModel) -> [ProvideMemberModel] {
    model.sharedMembers + model.transientMembers
}

private func makeOverridesStructDecl(model: DIContainerExpansionModel) -> DeclSyntax? {
    let candidates = overrideCandidateMembers(model)
    guard !candidates.isEmpty else { return nil }

    let modifiers = accessModifiers(model.accessLevel)
    let memberDecls: [MemberBlockItemSyntax] = candidates.map { member in
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

    let structDecl = StructDeclSyntax(
        modifiers: modifiers,
        name: .identifier("Overrides"),
        memberBlock: MemberBlockSyntax(
            members: MemberBlockItemListSyntax(memberDecls)
        )
    )

    return DeclSyntax(structDecl)
}

private func makeConvenienceInitDecl(model: DIContainerExpansionModel) -> DeclSyntax {
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
            type: member.type,
            ellipsis: nil,
            defaultValue: nil,
            trailingComma: .commaToken()
        )
        params.append(param)
    }

    // Final unnamed trailing closure parameter:
    //   _ applyOverrides: (inout Overrides) -> Void
    let overridesClosureType = TypeSyntax(stringLiteral: "(inout Overrides) -> Void")
    let closureParam = FunctionParameterSyntax(
        firstName: .wildcardToken(),
        secondName: .identifier("applyOverrides"),
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

    // var overrides = Overrides()
    let makeOverrides = VariableDeclSyntax(
        bindingSpecifier: .keyword(.var),
        bindings: PatternBindingListSyntax([
            PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: .identifier("overrides")),
                initializer: InitializerClauseSyntax(
                    value: FunctionCallExprSyntax(
                        calledExpression: DeclReferenceExprSyntax(baseName: .identifier("Overrides")),
                        leftParen: .leftParenToken(),
                        arguments: LabeledExprListSyntax([]),
                        rightParen: .rightParenToken()
                    )
                )
            )
        ])
    )
    statements.append(CodeBlockItemSyntax(item: .decl(DeclSyntax(makeOverrides))))

    // applyOverrides(&overrides)
    let applyCall = FunctionCallExprSyntax(
        calledExpression: DeclReferenceExprSyntax(baseName: .identifier("applyOverrides")),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax([
            LabeledExprSyntax(
                expression: InOutExprSyntax(
                    expression: DeclReferenceExprSyntax(baseName: .identifier("overrides"))
                )
            )
        ]),
        rightParen: .rightParenToken()
    )
    statements.append(CodeBlockItemSyntax(item: .expr(ExprSyntax(applyCall))))

    // self.init(<input args...>, <shared args...>, <transient args...>)
    var callArgs: [LabeledExprSyntax] = []
    let allForwardingMembers = inputMembers + model.sharedMembers + model.transientMembers
    for (index, member) in allForwardingMembers.enumerated() {
        let isLast = index == allForwardingMembers.count - 1
        let valueExpr: ExprSyntax
        if member.scope == .input {
            // Input parameter forwarded from the outer init.
            valueExpr = ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(member.name)))
        } else {
            // shared / transient value pulled out of the overrides builder.
            valueExpr = ExprSyntax(
                MemberAccessExprSyntax(
                    base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("overrides"))),
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

private func makeWithOverridesMethods(model: DIContainerExpansionModel) -> [DeclSyntax] {
    let candidates = overrideCandidateMembers(model)
    guard !candidates.isEmpty else { return [] }

    return [
        makeWithOverridesMethod(model: model, isAsync: false, isThrowing: false),
        makeWithOverridesMethod(model: model, isAsync: false, isThrowing: true),
        makeWithOverridesMethod(model: model, isAsync: true, isThrowing: false),
        makeWithOverridesMethod(model: model, isAsync: true, isThrowing: true),
    ]
}

private func makeWithOverridesMethod(
    model: DIContainerExpansionModel,
    isAsync: Bool,
    isThrowing: Bool
) -> DeclSyntax {
    let accessModifiers = accessModifiers(model.accessLevel)
    var modifiers = accessModifiers
    modifiers.append(DeclModifierSyntax(name: .keyword(.static)))

    let inputMembers = model.inputMembers
    var params: [FunctionParameterSyntax] = []

    for member in inputMembers {
        let param = FunctionParameterSyntax(
            firstName: .identifier(member.name),
            secondName: nil,
            colon: .colonToken(),
            type: member.type,
            ellipsis: nil,
            defaultValue: nil,
            trailingComma: .commaToken()
        )
        params.append(param)
    }

    let applyOverridesParam = FunctionParameterSyntax(
        firstName: .wildcardToken(),
        secondName: .identifier("applyOverrides"),
        colon: .colonToken(),
        type: TypeSyntax(stringLiteral: "(inout Overrides) -> Void"),
        ellipsis: nil,
        defaultValue: nil,
        trailingComma: .commaToken()
    )
    params.append(applyOverridesParam)

    // operation: (Self) [async] [throws] -> T
    var operationTypeDescription = "(Self) "
    if isAsync { operationTypeDescription += "async " }
    if isThrowing { operationTypeDescription += "throws " }
    operationTypeDescription += "-> T"
    let operationParam = FunctionParameterSyntax(
        firstName: .identifier("operation"),
        secondName: nil,
        colon: .colonToken(),
        type: TypeSyntax(stringLiteral: operationTypeDescription),
        ellipsis: nil,
        defaultValue: nil,
        trailingComma: nil
    )
    params.append(operationParam)

    // <T>
    let genericParameterClause = GenericParameterClauseSyntax(
        leftAngle: .leftAngleToken(),
        parameters: GenericParameterListSyntax([
            GenericParameterSyntax(name: .identifier("T"))
        ]),
        rightAngle: .rightAngleToken()
    )

    // `async throws` effects
    var effectSpecifiers: FunctionEffectSpecifiersSyntax? = nil
    if isAsync || isThrowing {
        effectSpecifiers = FunctionEffectSpecifiersSyntax(
            asyncSpecifier: isAsync ? .keyword(.async) : nil,
            throwsClause: isThrowing
                ? ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws))
                : nil
        )
    }

    let returnClause = ReturnClauseSyntax(
        arrow: .arrowToken(),
        type: TypeSyntax(stringLiteral: "T")
    )

    let signature = FunctionSignatureSyntax(
        parameterClause: FunctionParameterClauseSyntax(parameters: FunctionParameterListSyntax(params)),
        effectSpecifiers: effectSpecifiers,
        returnClause: returnClause
    )

    // Body: let container = Self(<inputs...>, applyOverrides)
    //       return [try] [await] operation(container)
    var statements: [CodeBlockItemSyntax] = []

    var callArgs: [LabeledExprSyntax] = []
    for member in inputMembers {
        callArgs.append(
            LabeledExprSyntax(
                label: .identifier(member.name),
                colon: .colonToken(),
                expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(member.name))),
                trailingComma: .commaToken()
            )
        )
    }
    callArgs.append(
        LabeledExprSyntax(
            expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("applyOverrides")))
        )
    )

    let selfCall = FunctionCallExprSyntax(
        calledExpression: ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.Self))),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax(callArgs),
        rightParen: .rightParenToken()
    )

    let containerDecl = VariableDeclSyntax(
        bindingSpecifier: .keyword(.let),
        bindings: PatternBindingListSyntax([
            PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: .identifier("container")),
                initializer: InitializerClauseSyntax(value: selfCall)
            )
        ])
    )
    statements.append(CodeBlockItemSyntax(item: .decl(DeclSyntax(containerDecl))))

    let operationCall = FunctionCallExprSyntax(
        calledExpression: DeclReferenceExprSyntax(baseName: .identifier("operation")),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax([
            LabeledExprSyntax(expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("container"))))
        ]),
        rightParen: .rightParenToken()
    )
    var returnExpr: ExprSyntax = ExprSyntax(operationCall)
    if isAsync {
        returnExpr = ExprSyntax(AwaitExprSyntax(expression: returnExpr))
    }
    if isThrowing {
        returnExpr = ExprSyntax(TryExprSyntax(expression: returnExpr))
    }

    let returnStmt = ReturnStmtSyntax(expression: returnExpr)
    statements.append(CodeBlockItemSyntax(item: .stmt(StmtSyntax(returnStmt))))

    let funcDecl = FunctionDeclSyntax(
        attributes: model.options.mainActor ? mainActorAttributeList() : AttributeListSyntax([]),
        modifiers: modifiers,
        name: .identifier("withOverrides"),
        genericParameterClause: genericParameterClause,
        signature: signature,
        body: CodeBlockSyntax(statements: CodeBlockItemListSyntax(statements))
    )

    return DeclSyntax(funcDecl)
}
