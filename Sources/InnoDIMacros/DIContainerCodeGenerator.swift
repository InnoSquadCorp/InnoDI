import SwiftSyntax
import SwiftSyntaxBuilder

/// Raised by codegen helpers when they encounter an invariant that the
/// validator was supposed to reject earlier. Callers at the macro
/// expansion boundary convert this into an `internalCodegenInvariant`
/// diagnostic so the user sees a clear "please file a bug" message
/// instead of an anonymous macro plugin crash.
struct CodegenInvariantError: Error {
    let description: String
}

struct DIContainerCodeGenerator {
    static func generateInit(
        for model: DIContainerExpansionModel,
        prependingInitializationMARK: Bool = true
    ) throws -> DeclSyntax {
        let initDecl = try makeInitDecl(
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
        if prependingInitializationMARK {
            return initDecl.prependingMARK("// MARK: - Initialization")
        }
        return initDecl
    }

    /// Generates the full member set: primary init + (if applicable) `Overrides`
    /// struct + convenience init + 4 `withOverrides` effect overloads.
    ///
    /// All `@DIContainer` types synthesize the overrides scaffolding unless a
    /// user-defined nested `Overrides` type suppresses generation. Input-only
    /// containers now receive an empty builder so parents can always forward
    /// `@SubContainer` override closures into child containers.
    ///
    /// Each generated declaration is prefixed with a `// MARK:` comment so
    /// that consumers expanding the macro in Xcode (or reading recorded
    /// snapshots in code review) can scan the four logical sections —
    /// initialization, overrides builder, convenience init, withOverrides
    /// effect overloads — without parsing the whole expansion.
    static func generateAll(
        for model: DIContainerExpansionModel,
        prependingInitializationMARK: Bool = true
    ) throws -> [DeclSyntax] {
        var decls: [DeclSyntax] = []

        // `.transient` sub-containers are backed by a stored
        // builder closure that `@SubContainer.PeerMacro` emits; the init
        // assigns that closure using a `_lazySelf` snapshot so it can
        // reach parent members on every invocation. The closure logic is
        // generated inline by `makeSubContainerInitStatements` — no extra
        // member-level decls are needed here.

        decls.append(
            try generateInit(
                for: model,
                prependingInitializationMARK: prependingInitializationMARK
            )
        )

        let featureRootHelpers = makeFeatureRootHelperDecls(
            subContainerMembers: model.subContainerMembers,
            accessLevel: model.accessLevel,
            isMainActor: model.options.mainActor
        )
        for (index, helper) in featureRootHelpers.enumerated() {
            if index == 0 {
                decls.append(helper.prependingMARK("// MARK: - SwiftUI Feature Roots"))
            } else {
                decls.append(helper)
            }
        }

        decls.append(
            makeOverridesStructDecl(model: model)
                .prependingMARK("// MARK: - Overrides Builder")
        )
        decls.append(
            makeConvenienceInitDecl(model: model)
                .prependingMARK("// MARK: - Convenience Init with Overrides")
        )

        // The four withOverrides effect overloads form one logical group.
        // The first overload carries the group's `// MARK: -` header; each
        // subsequent overload carries a sub-MARK that names its effect
        // shape so reviewers can see which variant they are looking at.
        let withOverridesMethods = makeWithOverridesMethods(model: model)
        let withOverridesLabels = [
            "// MARK: - withOverrides",
            "// MARK: - withOverrides (throws)",
            "// MARK: - withOverrides (async)",
            "// MARK: - withOverrides (async throws)",
        ]
        guard withOverridesMethods.count == withOverridesLabels.count else {
            throw CodegenInvariantError(
                description: "makeWithOverridesMethods produced \(withOverridesMethods.count) overload(s), but DIContainerCodeGenerator has \(withOverridesLabels.count) withOverrides MARK label(s). Keep makeWithOverridesMethods, withOverridesLabels, and decl insertion in sync."
            )
        }
        for (index, method) in withOverridesMethods.enumerated() {
            decls.append(method.prependingMARK(withOverridesLabels[index]))
        }

        return decls
    }
}

/// Tracks an async `Task`-based binding introduced by `makeInitDecl` so that
/// downstream factory/dependency expression builders can emit
/// `await <task>.value` (or `try await`) references in the correct order.
internal struct AsyncTaskBinding {
    let name: String
    let isThrowing: Bool
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
) throws -> DeclSyntax {
    let modifiers = accessModifiers(accessLevel)
    var params: [FunctionParameterSyntax] = []
    let allowUnresolvedDependencyFallback = !validateDAGEnabled
    let fallbackOverrideNames = Set(sharedMembers.map(\.name) + transientMembers.map(\.name))

    // Only deferred wrappers (`Lazy<T>` / `Provider<T>`) that are consumed
    // from the synthesized init (`.shared` / `asyncFactory`) need local
    // deferred-cell storage. Transient accessors emit `Lazy({ self.<name> })`
    // / `Provider({ self.<name> })` directly and therefore do not need
    // init-time boxes or late resolver bindings.
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
    let hasTransientSubContainer = subContainerMembers.contains(where: { $0.scope == .transient })

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
        let applyTypeSyntax = overrideApplyClosureType(
            overridesTypeDescription: "\(childTypeDescription).Overrides",
            isMainActor: mainActorEnabled,
            isOptional: true
        )

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

    if !deferredTargetMembers.isEmpty || hasTransientSubContainer {
        statements.append(
            CodeBlockItemSyntax(item: .decl(makeDeferredCellSupportDecl()))
        )
    }

    // Declare one local reference box per soft-target member. These boxes are
    // `let` bindings wrapping a class instance, so the Lazy wrappers we emit
    // below can resolve after init completes, even though factories that
    // capture the box run before the target storage is assigned. For struct
    // containers, this avoids the "cannot capture self in init" problem
    // entirely because the box is a local `let`, not a reference to `self`.
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
        let factoryExpr = try makeFactoryExpr(
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
        let createExpr = try makeAsyncFactoryExpr(
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
