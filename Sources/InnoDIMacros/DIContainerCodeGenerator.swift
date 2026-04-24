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
            mainActorEnabled: model.options.mainActor,
            validateDAGEnabled: model.options.validateDAG
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

        // `.transient` sub-containers are backed by a stored
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

private let unresolvedDependencyHelperName = "_innoDIUnresolvedDependency"

internal func accessModifiers(_ accessLevel: String?) -> DeclModifierListSyntax {
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
    mainActorEnabled: Bool,
    validateDAGEnabled: Bool
) -> DeclSyntax {
    let modifiers = accessModifiers(accessLevel)
    var params: [FunctionParameterSyntax] = []
    let allowUnresolvedDependencyFallback = !validateDAGEnabled
    let fallbackOverrideNames = Set(sharedMembers.map(\.name) + transientMembers.map(\.name))

    // Only deferred wrappers (`Lazy<T>` / `Provider<T>`) that are consumed
    // from the synthesized init (`.shared` / `asyncFactory`) need
    // `_LazyCell` storage.
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

    // Two parameters per `@SubContainer` member — a direct
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

    if allowUnresolvedDependencyFallback {
        statements.append(
            CodeBlockItemSyntax(item: .decl(unresolvedDependencyHelperDecl()))
        )
    }

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
            deferredTargetNameSet: deferredTargetNameSet,
            fallbackOverrideNames: fallbackOverrideNames,
            allowUnresolvedDependencyFallback: allowUnresolvedDependencyFallback
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
            deferredTargetNameSet: deferredTargetNameSet,
            fallbackOverrideNames: fallbackOverrideNames,
            allowUnresolvedDependencyFallback: allowUnresolvedDependencyFallback
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

    // Sub-container storage.
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

internal func optionalParameterType(for type: TypeSyntax) -> TypeSyntax {
    let trimmed = type.trimmedDescription

    if trimmed.hasPrefix("any ") || trimmed.hasPrefix("some ") || trimmed.contains("&") {
        return TypeSyntax(stringLiteral: "(\(trimmed))?")
    }

    return TypeSyntax(stringLiteral: "\(trimmed)?")
}

private func makeFactoryExpr(
    member: ProvideMemberModel,
    availableNames: [String],
    deferredTargetNameSet: Set<String>,
    fallbackOverrideNames: Set<String>,
    allowUnresolvedDependencyFallback: Bool
) -> ExprSyntax {
    if let factory = member.factory {
        if let closure = factory.as(ClosureExprSyntax.self) {
            let argumentExpressions = closureArgumentExpressions(
                member: member,
                closure: closure,
                availableNames: availableNames,
                deferredTargetNameSet: deferredTargetNameSet,
                fallbackOverrideNames: fallbackOverrideNames,
                allowUnresolvedDependencyFallback: allowUnresolvedDependencyFallback
            )
            return makeClosureCallExpr(closure: closure, argumentExpressions: argumentExpressions)
        }
        return factory
    }

    if let initializer = member.initializer {
        return initializer
    }

    if let typeExpr = member.typeExpr {
        let args = labeledDependencyArguments(
            dependencies: member.withDependencies,
            availableNames: availableNames,
            fallbackOverrideNames: fallbackOverrideNames,
            allowUnresolvedDependencyFallback: allowUnresolvedDependencyFallback
        )

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

private func labeledDependencyArguments(
    dependencies: [String],
    availableNames: [String],
    fallbackOverrideNames: Set<String>,
    allowUnresolvedDependencyFallback: Bool
) -> [LabeledExprSyntax] {
    dependencies.enumerated().map { index, dependency in
        LabeledExprSyntax(
            label: .identifier(dependency),
            colon: .colonToken(),
            expression: resolvedInitDependencyExpression(
                name: dependency,
                availableNames: availableNames,
                fallbackOverrideNames: fallbackOverrideNames,
                allowUnresolvedDependencyFallback: allowUnresolvedDependencyFallback
            ),
            trailingComma: index == dependencies.count - 1 ? nil : .commaToken()
        )
    }
}

private func makeAsyncFactoryExpr(
    member: ProvideMemberModel,
    resolvedValueBindings: [String: String],
    taskBindings: [String: AsyncTaskBinding],
    deferredTargetNameSet: Set<String>,
    fallbackOverrideNames: Set<String>,
    allowUnresolvedDependencyFallback: Bool
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
                taskBindings: taskBindings,
                fallbackOverrideNames: fallbackOverrideNames,
                allowUnresolvedDependencyFallback: allowUnresolvedDependencyFallback
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
    deferredTargetNameSet: Set<String>,
    fallbackOverrideNames: Set<String>,
    allowUnresolvedDependencyFallback: Bool
) -> [ExprSyntax] {
    let references = member.closureParameterReferences
    // Shorthand closures or attribute-level mismatches may cause the
    // reference list to be out-of-sync with the AST; fall back to a
    // name-only parse in that case.
    if references.isEmpty {
        let parsed = parseClosureParameterNames(closure)
        return parsed.names.map { name in
            resolvedInitDependencyExpression(
                name: name,
                availableNames: availableNames,
                fallbackOverrideNames: fallbackOverrideNames,
                allowUnresolvedDependencyFallback: allowUnresolvedDependencyFallback
            )
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
        expressions.append(
            resolvedInitDependencyExpression(
                name: ref.name,
                availableNames: availableNames,
                fallbackOverrideNames: fallbackOverrideNames,
                allowUnresolvedDependencyFallback: allowUnresolvedDependencyFallback
            )
        )
    }
    return expressions
}

private func dependencyExpression(
    for dependencyName: String,
    resolvedValueBindings: [String: String],
    taskBindings: [String: AsyncTaskBinding],
    fallbackOverrideNames: Set<String>,
    allowUnresolvedDependencyFallback: Bool
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

    return unresolvedInitDependencyFallbackExpression(
        name: dependencyName,
        fallbackOverrideNames: fallbackOverrideNames,
        allowUnresolvedDependencyFallback: allowUnresolvedDependencyFallback
    )
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

private func resolvedInitDependencyExpression(
    name: String,
    availableNames: [String],
    fallbackOverrideNames: Set<String>,
    allowUnresolvedDependencyFallback: Bool
) -> ExprSyntax {
    if let resolvedName = resolveClosureParameter(name: name, availableNames: availableNames) {
        return makeSelfMemberAccessExpr(name: resolvedName)
    }

    return unresolvedInitDependencyFallbackExpression(
        name: name,
        fallbackOverrideNames: fallbackOverrideNames,
        allowUnresolvedDependencyFallback: allowUnresolvedDependencyFallback
    )
}

private func unresolvedInitDependencyFallbackExpression(
    name: String,
    fallbackOverrideNames: Set<String>,
    allowUnresolvedDependencyFallback: Bool
) -> ExprSyntax {
    guard allowUnresolvedDependencyFallback else {
        fatalError("Unresolved dependency '\(name)' reached code generation.")
    }

    let unresolved = unresolvedDependencyHelperExpr(name: name)
    if fallbackOverrideNames.contains(name) {
        return nilCoalescingExpr(optionalName: name, fallback: unresolved)
    }
    return unresolved
}

private func unresolvedDependencyHelperDecl() -> DeclSyntax {
    DeclSyntax(
        """
        func \(raw: unresolvedDependencyHelperName)<T>(_ name: String) -> T {
            fatalError("InnoDI could not resolve dependency '\\(name)' while expanding a container with validateDAG: false. Supply an explicit override or complete the container wiring.")
        }
        """
    )
}

private func unresolvedDependencyHelperExpr(name: String) -> ExprSyntax {
    let call = FunctionCallExprSyntax(
        calledExpression: DeclReferenceExprSyntax(baseName: .identifier(unresolvedDependencyHelperName)),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax([
            LabeledExprSyntax(expression: ExprSyntax(StringLiteralExprSyntax(content: name)))
        ]),
        rightParen: .rightParenToken()
    )
    return ExprSyntax(call)
}

private func nilCoalescingExpr(optionalName: String, fallback: ExprSyntax) -> ExprSyntax {
    ExprSyntax(
        InfixOperatorExprSyntax(
            leftOperand: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(optionalName))),
            operator: BinaryOperatorExprSyntax(operator: .binaryOperator("??")),
            rightOperand: fallback
        )
    )
}

internal func assignExpr(targetName: String, valueName: String) -> ExprSyntax {
    let valueExpr = ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(valueName)))
    let assignment = InfixOperatorExprSyntax(
        leftOperand: makeSelfMemberAccessExpr(name: targetName),
        operator: AssignmentExprSyntax(),
        rightOperand: valueExpr
    )
    return ExprSyntax(assignment)
}

internal func assignExprWithValue(targetName: String, value: ExprSyntax) -> ExprSyntax {
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

internal func mainActorAttributeList() -> AttributeListSyntax {
    AttributeListSyntax([
        AttributeListSyntax.Element(
            AttributeSyntax(
                attributeName: IdentifierTypeSyntax(name: .identifier("MainActor"))
            )
        )
    ])
}
