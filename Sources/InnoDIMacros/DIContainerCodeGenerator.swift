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
            subContainerMembers: model.subContainerMembers,
            accessLevel: model.accessLevel,
            mainActorEnabled: model.options.mainActor
        )
    }

    /// Generates the full member set: primary init + (if applicable) `Overrides`
    /// struct + convenience init + 4 `withOverrides` effect overloads.
    ///
    /// All `@DIContainer` types synthesize the overrides scaffolding unless a
    /// user-defined nested `Overrides` type suppresses generation. Input-only
    /// containers now receive an empty builder so parents can always forward
    /// `@SubContainer` override closures into child containers.
    static func generateAll(for model: DIContainerExpansionModel) -> [DeclSyntax] {
        var decls: [DeclSyntax] = [generateInit(for: model)]

        // Phase M: `.transient` sub-containers are backed by a stored
        // builder closure that `@SubContainer.PeerMacro` emits; the init
        // assigns that closure using a `_lazySelf` snapshot so it can
        // reach parent members on every invocation. The closure logic is
        // generated inline by `makeSubContainerInitStatements` — no extra
        // member-level decls are needed here.

        decls.append(makeOverridesStructDecl(model: model))
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
    subContainerMembers: [SubContainerMemberModel],
    accessLevel: String?,
    mainActorEnabled: Bool
) -> DeclSyntax {
    let modifiers = accessModifiers(accessLevel)
    var params: [FunctionParameterSyntax] = []

    // Phase K / Phase L: only deferred wrappers that are consumed from the
    // synthesized init (`.shared` / `asyncFactory`) need `_LazyCell` storage.
    // Transient accessors emit `Lazy({ self.<name> })` / `Provider({ self.<name> })`
    // directly and therefore do not need init-time boxes or late resolver
    // bindings.
    let initTimeDeferredSourceMembers = sharedMembers
    let initTimeDeferredTargetNames = Set(
        initTimeDeferredSourceMembers.flatMap { $0.softClosureDependencies + $0.providerClosureDependencies }
    )
    let allPossibleDeferredTargets = inputMembers + sharedMembers + transientMembers
    let deferredTargetMembers = allPossibleDeferredTargets.filter { member in
        initTimeDeferredTargetNames.contains(member.name)
            && member.supportsLazySoftTarget
    }
    let deferredTargetNameSet = Set(deferredTargetMembers.map(\.name))

    for (index, member) in inputMembers.enumerated() {
        let isLast = index == inputMembers.count - 1
            && sharedMembers.isEmpty
            && transientMembers.isEmpty
            && subContainerMembers.isEmpty
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
        let isLast = index == sharedMembers.count - 1
            && transientMembers.isEmpty
            && subContainerMembers.isEmpty
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
            && subContainerMembers.isEmpty
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

    // Phase M: two parameters per `@SubContainer` member — a direct
    // replacement (`<name>: Child? = nil`) and a trailing-closure override
    // block forwarded into the child's own convenience init
    // (`<name>Overrides: ((inout Child.Overrides) -> Void)? = nil`). Both
    // default to `nil` so existing call sites stay unchanged; the Overrides
    // builder threads named values in via the convenience init.
    for (index, member) in subContainerMembers.enumerated() {
        let isLastMember = index == subContainerMembers.count - 1
        let directType = optionalParameterType(for: member.type)
        let childTypeDescription = member.type.trimmedDescription
        let applyTypeSyntax = TypeSyntax(stringLiteral: "((inout \(childTypeDescription).Overrides) -> Void)?")

        let directParam = FunctionParameterSyntax(
            firstName: .identifier(member.name),
            secondName: nil,
            colon: .colonToken(),
            type: directType,
            ellipsis: nil,
            defaultValue: InitializerClauseSyntax(value: NilLiteralExprSyntax()),
            trailingComma: .commaToken()
        )
        params.append(directParam)

        let applyParam = FunctionParameterSyntax(
            firstName: .identifier(member.overrideClosureName),
            secondName: nil,
            colon: .colonToken(),
            type: applyTypeSyntax,
            ellipsis: nil,
            defaultValue: InitializerClauseSyntax(value: NilLiteralExprSyntax()),
            trailingComma: isLastMember ? nil : .commaToken()
        )
        params.append(applyParam)
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
    for target in deferredTargetMembers {
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

        if deferredTargetNameSet.contains(member.name) {
            // _lazyCell_<name>.store(self._storage_<name>)
            statements.append(
                CodeBlockItemSyntax(item: .expr(makeLazyCellStoreExpr(name: member.name, storageName: storageName)))
            )
        }
    }

    let inputStorageNames = inputMembers.map { "_storage_\($0.name)" }
    for (index, member) in syncSharedMembers.enumerated() {
        let availableStorageNames = inputStorageNames + syncSharedMembers.prefix(index).map { "_storage_\($0.name)" }
        let factoryExpr = makeFactoryExpr(
            member: member,
            availableNames: availableStorageNames,
            deferredTargetNameSet: deferredTargetNameSet
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

        if deferredTargetNameSet.contains(member.name) {
            statements.append(
                CodeBlockItemSyntax(item: .expr(makeLazyCellStoreExpr(name: member.name, storageName: storageName)))
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
            deferredTargetNameSet: deferredTargetNameSet
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

        taskBindings[member.name] = AsyncTaskBinding(name: taskName, isThrowing: member.asyncFactoryIsThrowing)
    }

    for member in transientMembers {
        let overrideName = "_override_\(member.name)"
        statements.append(CodeBlockItemSyntax(item: .expr(assignExpr(targetName: overrideName, valueName: member.name))))
    }

    let transientDeferredTargetMembers = transientMembers.filter { deferredTargetNameSet.contains($0.name) }
    if !transientDeferredTargetMembers.isEmpty {
        statements.append(
            CodeBlockItemSyntax(item: .decl(letBinding(name: "_lazySelf", value: "self")))
        )
        for member in transientDeferredTargetMembers {
            statements.append(
                CodeBlockItemSyntax(
                    item: .expr(
                        makeLazyCellBindExpr(
                            name: member.name,
                            accessorName: member.name,
                            baseName: "_lazySelf"
                        )
                    )
                )
            )
        }
    }

    // Phase M: sub-container storage.
    //
    // `.shared` children are built (or replaced by an override) exactly
    // once here and assigned to `_storage_sub_<name>`.
    //
    // `.transient` children capture a closure in `_innoDISubBuild_<name>`
    // (a `private let` peer emitted by `@SubContainer.PeerMacro`). The
    // closure captures a `_lazySelfForSub` snapshot so it can read parent
    // accessors as a fully-constructed value type — value-type copies of
    // `self` are cheap and reflect the stable parent state.
    let autoWireParentMemberNames = (inputMembers + sharedMembers + transientMembers).map(\.name)
    let hasTransientSubContainer = subContainerMembers.contains(where: { $0.scope == .transient })
    for member in subContainerMembers {
        statements.append(contentsOf: makeSubContainerInitStatements(
            member: member,
            autoWireParentMemberNames: autoWireParentMemberNames
        ))
    }
    if hasTransientSubContainer {
        for member in subContainerMembers where member.scope == .transient {
            statements.append(
                CodeBlockItemSyntax(
                    item: .decl(
                        makeDeferredCellDecl(
                            cellName: "_subBuildCell_\(member.name)",
                            type: member.type
                        )
                    )
                )
            )
            let assignBuildClosure: CodeBlockItemSyntax = """
                self._innoDISubBuild_\(raw: member.name) = {
                    _subBuildCell_\(raw: member.name).resolve()
                }
                """
            statements.append(assignBuildClosure)
        }

        // Snapshot `self` once, *after* every other stored property is
        // assigned, so the closures we bind below can safely read parent
        // accessors. The override wedges for every sub-container member
        // and builder closures are assigned by the loop above, so `self`
        // is fully initialized.
        statements.append(
            CodeBlockItemSyntax(item: .decl(letBinding(name: "_lazySelfForSub", value: "self")))
        )
        for member in subContainerMembers where member.scope == .transient {
            let childTypeDesc = member.type.trimmedDescription
            let selectedArguments = resolvedSubContainerArguments(
                member: member,
                autoWireParentMemberNames: autoWireParentMemberNames
            )
            let baseInitializer = subContainerInitializerExpr(
                childType: member.type,
                argumentMappings: selectedArguments,
                parentMemberBaseName: "_lazySelfForSub",
                parentMemberPrefix: ""
            )
            let overrideInitializer = subContainerInitializerExpr(
                childType: member.type,
                argumentMappings: selectedArguments,
                trailingOverrideExpression: ExprSyntax(
                    DeclReferenceExprSyntax(baseName: .identifier("apply"))
                ),
                parentMemberBaseName: "_lazySelfForSub",
                parentMemberPrefix: ""
            )
            let assignStmt: CodeBlockItemSyntax = """
                _subBuildCell_\(raw: member.name).bindResolver { () -> \(raw: childTypeDesc) in
                    if let direct = _lazySelfForSub._override_sub_\(raw: member.name) {
                        return direct
                    }
                    if let apply = _lazySelfForSub._override_sub_apply_\(raw: member.name) {
                        return \(overrideInitializer)
                    }
                    return \(baseInitializer)
                }
                """
            statements.append(assignStmt)
        }
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
    deferredTargetNameSet: Set<String>
) -> ExprSyntax {
    if let factory = member.factory {
        if let closure = factory.as(ClosureExprSyntax.self) {
            let argumentExpressions = closureArgumentExpressions(
                member: member,
                closure: closure,
                availableNames: availableNames,
                deferredTargetNameSet: deferredTargetNameSet
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
    deferredTargetNameSet: Set<String>
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
            if ref.kind == .soft {
                guard deferredTargetNameSet.contains(ref.name),
                      let calleeDescription = ref.lazyWrapperCalleeDescription else {
                    fatalError("Unsupported soft dependency '\(ref.name)' reached async code generation.")
                }
                return makeLazyCellWrapperExpr(name: ref.name, calleeDescription: calleeDescription)
            }
            if ref.kind == .provider {
                guard deferredTargetNameSet.contains(ref.name),
                      let calleeDescription = ref.providerWrapperCalleeDescription else {
                    fatalError("Unsupported provider dependency '\(ref.name)' reached async code generation.")
                }
                return makeProviderCellWrapperExpr(name: ref.name, calleeDescription: calleeDescription)
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
    deferredTargetNameSet: Set<String>
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
        if ref.kind == .soft {
            guard deferredTargetNameSet.contains(ref.name),
                  let calleeDescription = ref.lazyWrapperCalleeDescription else {
                fatalError("Unsupported soft dependency '\(ref.name)' reached code generation.")
            }
            expressions.append(makeLazyCellWrapperExpr(name: ref.name, calleeDescription: calleeDescription))
            continue
        }
        if ref.kind == .provider {
            guard deferredTargetNameSet.contains(ref.name),
                  let calleeDescription = ref.providerWrapperCalleeDescription else {
                fatalError("Unsupported provider dependency '\(ref.name)' reached code generation.")
            }
            expressions.append(makeProviderCellWrapperExpr(name: ref.name, calleeDescription: calleeDescription))
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

private func makeOverridesStructDecl(model: DIContainerExpansionModel) -> DeclSyntax {
    let candidates = overrideCandidateMembers(model)
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

    // Phase M: each `@SubContainer` member gains two slots on Overrides —
    // `<name>` for full replacement, `<name>Overrides` for a closure that
    // forwards into the child's own convenience init. Both default to nil so
    // tests only touch the slots they actually need.
    for member in subs {
        let childTypeDesc = member.type.trimmedDescription
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

        let applyType = TypeSyntax(stringLiteral: "((inout \(childTypeDesc).Overrides) -> Void)?")
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

    for (index, pair) in subForwardingPairs.enumerated() {
        let runningIndex = allForwardingMembers.count + index
        let isLast = runningIndex == totalArgCount - 1
        let valueExpr = ExprSyntax(
            MemberAccessExprSyntax(
                base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("overrides"))),
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

private func makeWithOverridesMethods(model: DIContainerExpansionModel) -> [DeclSyntax] {
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

// MARK: - Sub-container init / build helpers (Phase M)

/// Emits the init-time statements for a single `@SubContainer` member:
///
/// - `.shared`: builds the child (or accepts the override replacement) once
///   and assigns `_storage_sub_<name>`. The direct replacement wins; the
///   `<name>Overrides` trailing-closure block is forwarded to the child's
///   own convenience init when present.
/// - `.transient`: only the override wedges are captured; actual construction
///   happens lazily inside the stored `_innoDISubBuild_<name>` closure on
///   every accessor read.
///
/// `autoWireParentMemberNames` is the ordered list of parent `@Provide`
/// member names (input/shared/transient) that the call site forwards by
/// default. When the user wrote `with: [\.a, \.b]` on the attribute, that
/// list replaces the default — Swift's compile-time label check surfaces
/// mismatches with the child's `.input` parameter names.
private func makeSubContainerInitStatements(
    member: SubContainerMemberModel,
    autoWireParentMemberNames: [String]
) -> [CodeBlockItemSyntax] {
    let selectedArguments = resolvedSubContainerArguments(
        member: member,
        autoWireParentMemberNames: autoWireParentMemberNames
    )

    var stmts: [CodeBlockItemSyntax] = []

    switch member.scope {
    case .shared:
        let ifChain = subContainerSharedAssignmentExpr(
            member: member,
            selectedArguments: selectedArguments
        )
        stmts.append(CodeBlockItemSyntax(item: .stmt(StmtSyntax(ExpressionStmtSyntax(expression: ExprSyntax(ifChain))))))

    case .transient, .none:
        // `.none` should be unreachable — `DIContainerValidator` (M-5)
        // rejects `@SubContainer` without a scope — but we stay silent here
        // rather than force a crash during macro expansion.
        break
    }

    // Both scopes capture the override wedges so the Overrides builder has
    // something to inspect at runtime (used by child accessor / helper).
    stmts.append(
        CodeBlockItemSyntax(item: .expr(assignExpr(
            targetName: "_override_sub_\(member.name)",
            valueName: member.name
        )))
    )
    stmts.append(
        CodeBlockItemSyntax(item: .expr(assignExpr(
            targetName: "_override_sub_apply_\(member.name)",
            valueName: member.overrideClosureName
        )))
    )

    return stmts
}

/// Renders the `if let direct = override { ... } else if let apply = ... { ... } else { ... }`
/// three-branch storage assignment used for `.shared` sub-containers. Built
/// directly as SwiftSyntax so malformed child type spellings cannot crash a
/// string-reparse fallback during macro expansion.
private func subContainerSharedAssignmentExpr(
    member: SubContainerMemberModel,
    selectedArguments: [(childLabel: String, parentName: String)]
) -> IfExprSyntax {
    let storageName = "_storage_sub_\(member.name)"
    let overrideParam = member.name
    let applyParam = member.overrideClosureName
    let directAssignment = assignExprWithValue(
        targetName: storageName,
        value: ExprSyntax(
            DeclReferenceExprSyntax(baseName: .identifier("direct"))
        )
    )
    let applyAssignment = assignExprWithValue(
        targetName: storageName,
        value: subContainerInitializerExpr(
            childType: member.type,
            argumentMappings: selectedArguments,
            trailingOverrideExpression: ExprSyntax(
                DeclReferenceExprSyntax(baseName: .identifier("apply"))
            )
        )
    )
    let defaultAssignment = assignExprWithValue(
        targetName: storageName,
        value: subContainerInitializerExpr(
            childType: member.type,
            argumentMappings: selectedArguments
        )
    )
    let elseIfExpr = makeSubContainerOptionalBindingIfExpr(
        bindingName: "apply",
        sourceName: applyParam,
        assignment: applyAssignment,
        elseBody: .codeBlock(
            CodeBlockSyntax(
                statements: CodeBlockItemListSyntax([
                    CodeBlockItemSyntax(item: .expr(defaultAssignment))
                ])
            )
        )
    )

    return makeSubContainerOptionalBindingIfExpr(
        bindingName: "direct",
        sourceName: overrideParam,
        assignment: directAssignment,
        elseBody: .ifExpr(elseIfExpr)
    )
}

private func subContainerInitializerExpr(
    childType: TypeSyntax,
    argumentMappings: [(childLabel: String, parentName: String)],
    trailingOverrideExpression: ExprSyntax? = nil,
    parentMemberBaseName: String = "self",
    parentMemberPrefix: String = "_storage_"
) -> ExprSyntax {
    let totalArgumentCount = argumentMappings.count + (trailingOverrideExpression == nil ? 0 : 1)
    var arguments: [LabeledExprSyntax] = argumentMappings.enumerated().map { index, mapping in
        let hasTrailingOverride = trailingOverrideExpression != nil
        let isLast = index == argumentMappings.count - 1 && !hasTrailingOverride
        return LabeledExprSyntax(
            label: .identifier(mapping.childLabel),
            colon: .colonToken(),
            expression: makeSelfMemberAccessExpr(
                name: "\(parentMemberPrefix)\(mapping.parentName)",
                baseName: parentMemberBaseName
            ),
            trailingComma: isLast || totalArgumentCount == 0 ? nil : .commaToken()
        )
    }

    if let trailingOverrideExpression {
        arguments.append(
            LabeledExprSyntax(
                label: nil,
                colon: nil,
                expression: trailingOverrideExpression,
                trailingComma: nil
            )
        )
    }

    let call = FunctionCallExprSyntax(
        calledExpression: ExprSyntax("\(childType.trimmed)"),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax(arguments),
        rightParen: .rightParenToken()
    )
    return ExprSyntax(call)
}

private func resolvedSubContainerArguments(
    member: SubContainerMemberModel,
    autoWireParentMemberNames: [String]
) -> [(childLabel: String, parentName: String)] {
    if !member.explicitBindings.isEmpty {
        return member.explicitBindings.map { binding in
            (childLabel: binding.childInputName, parentName: binding.parentMemberName)
        }
    }

    let selectedNames = member.parentDependencies.isEmpty
        ? autoWireParentMemberNames
        : member.parentDependencies
    return selectedNames.map { name in
        (childLabel: name, parentName: name)
    }
}

private func makeSubContainerOptionalBindingIfExpr(
    bindingName: String,
    sourceName: String,
    assignment: ExprSyntax,
    elseBody: IfExprSyntax.ElseBody
) -> IfExprSyntax {
    IfExprSyntax(
        ifKeyword: .keyword(.if, trailingTrivia: .space),
        conditions: ConditionElementListSyntax([
            ConditionElementSyntax(
                condition: .optionalBinding(
                    OptionalBindingConditionSyntax(
                        bindingSpecifier: .keyword(.let, trailingTrivia: .space),
                        pattern: IdentifierPatternSyntax(
                            identifier: .identifier(bindingName, trailingTrivia: .space)
                        ),
                        initializer: InitializerClauseSyntax(
                            equal: .equalToken(trailingTrivia: .space),
                            value: DeclReferenceExprSyntax(
                                baseName: .identifier(sourceName, trailingTrivia: .space)
                            )
                        )
                    )
                )
            )
        ]),
        body: CodeBlockSyntax(
            leftBrace: .leftBraceToken(trailingTrivia: .space),
            statements: CodeBlockItemListSyntax([
                CodeBlockItemSyntax(item: .expr(assignment))
            ]),
            rightBrace: .rightBraceToken(leadingTrivia: .space)
        ),
        elseKeyword: .keyword(.else, leadingTrivia: .space, trailingTrivia: .space),
        elseBody: elseBody
    )
}
