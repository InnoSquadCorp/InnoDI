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
    /// All valid `@DIContainer` types synthesize the complete overrides
    /// scaffolding. A user-defined nested `Overrides` type is rejected before
    /// this path. Input-only and empty containers receive an empty builder so
    /// parents can always forward `@SubContainer` override closures into child
    /// containers.
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

        // `.transient` sub-containers are backed by a stored builder closure
        // that `_InnoDISubContainerAccessor` emits. The init connects it to a
        // dependency-only resolver context after every peer is initialized;
        // no whole-container snapshot is retained.

        decls.append(
            try generateInit(
                for: model,
                prependingInitializationMARK: prependingInitializationMARK
            )
        )

        if let prewarm = makePrewarmDecl(model: model) {
            decls.append(
                prewarm.prependingMARK("// MARK: - On-Demand Prewarming")
            )
        }

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
        decls.append(makeMountOverridesAliasDecl(model: model))
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

private func makePrewarmDecl(
    model: DIContainerExpansionModel
) -> DeclSyntax? {
    let members = model.syncSharedMembers.filter {
        $0.initialization == .onDemand
    }
    guard !members.isEmpty else { return nil }

    let accessPrefix = model.accessLevel.map { "\($0) " } ?? ""
    let actorPrefix = model.options.mainActor ? "@MainActor\n" : ""
    let matches = members.map { member in
        """
        if provider == \\Self.\(member.name) {
            _ = self.\(member.name)
            matched = true
        }
        """
    }.joined(separator: "\n")

    return DeclSyntax(
        stringLiteral: """
        \(actorPrefix)\(accessPrefix)func prewarm(_ providers: Swift.PartialKeyPath<Self>...) throws {
            for provider in providers {
                var matched = false
                \(matches)
                if !matched {
                    throw InnoDI.DIPrewarmError.unsupportedProvider
                }
            }
        }
        """
    )
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

    // Start with deferred wrappers consumed by shared construction. A
    // transient target's detached resolver may itself contain deferred edges,
    // so walk only the hard-transient portion reachable from those roots and
    // add its Lazy/Provider targets. Unrelated transient accessors keep their
    // allocation-free direct path.
    let transientMembersByNameForDeferredPlanning = Dictionary(
        uniqueKeysWithValues: transientMembers.map { ($0.name, $0) }
    )
    var initTimeDeferredTargetNames = Set(
        sharedMembers.flatMap {
            $0.softClosureDependencies + $0.providerClosureDependencies
        }
    )
    var pendingDetachedSourceNames = Array(initTimeDeferredTargetNames)
    var visitedDetachedSourceNames = Set<String>()
    while let name = pendingDetachedSourceNames.popLast() {
        guard let transient = transientMembersByNameForDeferredPlanning[name],
              !transient.isAsyncFactory,
              visitedDetachedSourceNames.insert(name).inserted else {
            continue
        }
        let nestedDeferredNames = transient.softClosureDependencies
            + transient.providerClosureDependencies
        initTimeDeferredTargetNames.formUnion(nestedDeferredNames)
        pendingDetachedSourceNames.append(contentsOf: nestedDeferredNames)
        pendingDetachedSourceNames.append(contentsOf: transient.hardClosureDependencies)
        pendingDetachedSourceNames.append(contentsOf: transient.withDependencies)
    }
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
            type: inputParameterType(for: member),
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
    // (`<name>Overrides: ((inout Child._InnoDIMountOverrides) -> Void)? = nil`). Both
    // default to `nil` so existing call sites stay unchanged; the Overrides
    // builder threads named values in via the convenience init.
    for (index, member) in subContainerMembers.enumerated() {
        let isLastMember = index == subContainerMembers.count - 1
        let directType = optionalParameterType(for: member.type)
        let childTypeDescription = member.type.trimmedDescription
        let applyTypeSyntax = overrideApplyClosureType(
            overridesTypeDescription: "\(childTypeDescription).\(innoDIMountOverridesTypeName)",
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
    var resolvedDependencyExpressions: [String: ExprSyntax] = [:]
    var taskBindings: [String: AsyncTaskBinding] = [:]
    var availableDependencyExpressions: [String: ExprSyntax] = [:]
    let asyncResolvedTargetNames = Set(
        asyncSharedMembers.flatMap { member in
            member.closureParameterReferences
                .filter { $0.kind == .hard }
                .map(\.name)
        }
    )
    let onDemandHardDependencyNames = Set(
        syncSharedMembers
            .filter { $0.initialization == .onDemand }
            .flatMap(\.explicitDependencies)
    )

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
        if onDemandHardDependencyNames.contains(member.name) {
            availableDependencyExpressions[member.name] = ExprSyntax(
                DeclReferenceExprSyntax(baseName: .identifier(member.name))
            )
        }

        if asyncResolvedTargetNames.contains(member.name) {
            resolvedDependencyExpressions[member.name] = ExprSyntax(
                DeclReferenceExprSyntax(baseName: .identifier(member.name))
            )
        }

        if deferredTargetNameSet.contains(member.name) {
            // _innoDILazyCell_<name>.store(self._storage_<name>)
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
            availableExpressions: availableDependencyExpressions,
            deferredTargetNameSet: deferredTargetNameSet,
            fallbackOverrideNames: fallbackOverrideNames,
            allowUnresolvedDependencyFallback: allowUnresolvedDependencyFallback
        )

        let storageName = "_storage_\(member.name)"
        if member.initialization == .onDemand {
            let cellName = "_innoDIOnDemand_\(member.name)"
            let typeDescription = member.type.trimmedDescription
            let declaration: CodeBlockItemSyntax = """
                let \(raw: cellName): InnoDI._InnoDISharedCell<\(raw: typeDescription)> = if let _innoDIOverride = \(raw: member.name) {
                    InnoDI._InnoDISharedCell(value: _innoDIOverride)
                } else {
                    InnoDI._InnoDISharedCell { \(factoryExpr) }
                }
                """
            statements.append(declaration)
            statements.append(
                CodeBlockItemSyntax(
                    item: .expr(
                        assignExpr(
                            targetName: storageName,
                            valueName: cellName
                        )
                    )
                )
            )
            let valueExpression: ExprSyntax = "\(raw: cellName).value()"
            availableDependencyExpressions[member.name] = valueExpression
        } else {
            let initializerExpr = ExprSyntax(
                InfixOperatorExprSyntax(
                    leftOperand: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(member.name))),
                    operator: BinaryOperatorExprSyntax(operator: .binaryOperator("??")),
                    rightOperand: factoryExpr
                )
            )
            statements.append(CodeBlockItemSyntax(item: .expr(assignExprWithValue(targetName: storageName, value: initializerExpr))))
            if onDemandHardDependencyNames.contains(member.name) {
                let localName = "_innoDIOnDemandDependency_\(member.name)"
                statements.append(
                    CodeBlockItemSyntax(
                        item: .decl(
                            letBinding(
                                name: localName,
                                value: makeProviderStorageReadExpr(
                                    name: storageName
                                )
                            )
                        )
                    )
                )
                availableDependencyExpressions[member.name] = ExprSyntax(
                    DeclReferenceExprSyntax(baseName: .identifier(localName))
                )
            }
        }

        if asyncResolvedTargetNames.contains(member.name) {
            if member.initialization == .onDemand,
               let expression = availableDependencyExpressions[member.name] {
                // Keep the shared-cell read inside the async task's live
                // factory branch so a direct async override does not trigger
                // an otherwise unused on-demand dependency.
                resolvedDependencyExpressions[member.name] = expression
            } else {
                let resolvedName = "_innoDIResolved_\(member.name)"
                let resolvedDecl = letBinding(
                    name: resolvedName,
                    value: makeProviderStorageReadExpr(name: storageName)
                )
                statements.append(CodeBlockItemSyntax(item: .decl(resolvedDecl)))
                resolvedDependencyExpressions[member.name] = ExprSyntax(
                    DeclReferenceExprSyntax(baseName: .identifier(resolvedName))
                )
            }
        }

        if deferredTargetNameSet.contains(member.name) {
            if member.initialization == .onDemand {
                let cellName = "_innoDIOnDemand_\(member.name)"
                let bind: CodeBlockItemSyntax = """
                    _innoDILazyCell_\(raw: member.name).bindResolver {
                        \(raw: cellName).value()
                    }
                    """
                statements.append(bind)
            } else {
                statements.append(
                    CodeBlockItemSyntax(item: .expr(makeLazyCellStoreExpr(name: member.name, storageName: storageName)))
                )
            }
        }
    }

    for member in asyncSharedMembers {
        let taskName = "_innoDITask_\(member.name)"
        let successType = taskSuccessTypeDescription(for: member.type)
        let failureType = member.asyncFactoryIsThrowing ? "Error" : "Never"
        let createExpr = try makeAsyncFactoryExpr(
            member: member,
            resolvedDependencyExpressions: resolvedDependencyExpressions,
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

    // Sub-container storage.
    //
    // `.shared` children are built (or replaced by an override) exactly
    // once here and assigned to `_storage_sub_<name>`.
    //
    // `.transient` children capture a closure in `_innoDISubBuild_<name>`
    // (a `private let` peer emitted by `_InnoDISubContainerAccessor`). The
    // closure initially resolves through an init-local cell. Once every peer
    // is initialized, that cell is bound to a dependency-only context below.
    let autoWireParentMemberNames = (inputMembers + sharedMembers + transientMembers).map(\.name)
    let onDemandParentMemberNames = Set(
        syncSharedMembers
            .filter { $0.initialization == .onDemand }
            .map(\.name)
    )
    for member in subContainerMembers {
        statements.append(contentsOf: makeSubContainerInitStatements(
            member: member,
            autoWireParentMemberNames: autoWireParentMemberNames,
            onDemandParentMemberNames: onDemandParentMemberNames
        ))
    }
    if hasTransientSubContainer {
        for member in subContainerMembers where member.scope == .transient {
            statements.append(
                CodeBlockItemSyntax(
                    item: .decl(
                        makeDeferredCellDecl(
                            cellName: "_innoDISubBuildCell_\(member.name)",
                            type: member.type
                        )
                    )
                )
            )
            let assignBuildClosure: CodeBlockItemSyntax = """
                self._innoDISubBuild_\(raw: member.name) = {
                    _innoDISubBuildCell_\(raw: member.name).resolve()
                }
                """
            statements.append(assignBuildClosure)
        }

    }

    // Build dependency-only contexts after every stored peer is initialized.
    // Inputs are captured from their init parameters. Eager shared values are
    // copied into locals; on-demand shared dependencies retain their cell and
    // remain unevaluated until a transient resolver actually asks for them.
    let transientDeferredTargetMembers = transientMembers.filter { deferredTargetNameSet.contains($0.name) }
    if !transientDeferredTargetMembers.isEmpty || hasTransientSubContainer {
        let transientMembersByName = Dictionary(
            uniqueKeysWithValues: transientMembers.map { ($0.name, $0) }
        )
        var detachedRequiredStableNames = Set<String>()
        var pendingDetachedNames = transientDeferredTargetMembers.map(\.name)
        for member in subContainerMembers where member.scope == .transient {
            pendingDetachedNames.append(contentsOf: resolvedSubContainerArguments(
                member: member,
                autoWireParentMemberNames: autoWireParentMemberNames
            ).map(\.parentName))
        }
        var visitedDetachedTransientNames = Set<String>()
        while let name = pendingDetachedNames.popLast() {
            guard let transient = transientMembersByName[name],
                  !transient.isAsyncFactory else {
                detachedRequiredStableNames.insert(name)
                continue
            }
            guard visitedDetachedTransientNames.insert(name).inserted else {
                continue
            }
            let hardNames = transient.hardClosureDependencies
                + transient.withDependencies
            pendingDetachedNames.append(contentsOf: hardNames)
        }

        var detachedStableExpressions: [String: ExprSyntax] = [:]
        for member in inputMembers {
            detachedStableExpressions[member.name] = ExprSyntax(
                DeclReferenceExprSyntax(baseName: .identifier(member.name))
            )
        }
        for member in syncSharedMembers
            where detachedRequiredStableNames.contains(member.name) {
            if member.initialization == .onDemand {
                detachedStableExpressions[member.name] = "_innoDIOnDemand_\(raw: member.name).value()"
            } else {
                let localName = "_innoDIResolverValue_\(member.name)"
                statements.append(
                    CodeBlockItemSyntax(
                        item: .decl(
                            letBinding(
                                name: localName,
                                value: makeProviderStorageReadExpr(
                                    name: "_storage_\(member.name)"
                                )
                            )
                        )
                    )
                )
                detachedStableExpressions[member.name] = ExprSyntax(
                    DeclReferenceExprSyntax(baseName: .identifier(localName))
                )
            }
        }

        for member in transientDeferredTargetMembers {
            let resolver = try makeDetachedTransientFactoryExpr(
                member: member,
                transientMembersByName: transientMembersByName,
                stableExpressions: detachedStableExpressions,
                deferredTargetNameSet: deferredTargetNameSet,
                fallbackOverrideNames: fallbackOverrideNames,
                allowUnresolvedDependencyFallback: allowUnresolvedDependencyFallback
            )
            statements.append(
                """
                _innoDILazyCell_\(raw: member.name).bindResolver {
                    \(resolver)
                }
                """
            )
        }

        for member in subContainerMembers where member.scope == .transient {
            let childTypeDesc = member.type.trimmedDescription
            let selectedArguments = resolvedSubContainerArguments(
                member: member,
                autoWireParentMemberNames: autoWireParentMemberNames
            )
            var parentExpressions = detachedStableExpressions
            for parentName in selectedArguments.map(\.parentName)
                where parentExpressions[parentName] == nil {
                guard let transient = transientMembersByName[parentName],
                      !transient.isAsyncFactory else {
                    continue
                }
                parentExpressions[parentName] = try makeDetachedTransientFactoryExpr(
                    member: transient,
                    transientMembersByName: transientMembersByName,
                    stableExpressions: detachedStableExpressions,
                    deferredTargetNameSet: deferredTargetNameSet,
                    fallbackOverrideNames: fallbackOverrideNames,
                    allowUnresolvedDependencyFallback: allowUnresolvedDependencyFallback
                )
            }
            let baseInitializer = subContainerInitializerExpr(
                childType: member.type,
                argumentMappings: selectedArguments,
                parentMemberExpressions: parentExpressions
            )
            let overrideInitializer = subContainerInitializerExpr(
                childType: member.type,
                argumentMappings: selectedArguments,
                trailingOverrideExpression: ExprSyntax(
                    DeclReferenceExprSyntax(baseName: .identifier("apply"))
                ),
                parentMemberExpressions: parentExpressions
            )
            let assignStmt: CodeBlockItemSyntax = """
                _innoDISubBuildCell_\(raw: member.name).bindResolver { () -> \(raw: childTypeDesc) in
                    if let direct = \(raw: member.name) {
                        return direct
                    }
                    if let apply = \(raw: member.overrideClosureName) {
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
