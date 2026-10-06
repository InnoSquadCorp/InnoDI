import InnoDICore
import SwiftSyntax
import SwiftSyntaxBuilder

private let ownedViewTypeName = "_InnoDIOwnedView"
private let ownedOwnerTypeName = "_InnoDIOwner"
private let ownedProviderTypeName = "_InnoDIOwnedProvider"
private let ownedSelfTypeName = "_InnoDIOwnedSelf"

/// Generate a second, explicit construction path. In particular, never create
/// the legacy container: its eager Task storage would escape this owner.
func makeOwnedContainerDecls(model: DIContainerExpansionModel) throws -> [DeclSyntax] {
    let cells = ownedSendableCellNames(model)
    let factory = try makeOwnedFactory(model, sendableCells: cells)
    var declarations = [
        makeOwnedView(model, sendableCells: cells),
        makeOwnedOwner(model),
        makeOwnedOverridesFactory(model, directFactory: factory),
        factory
    ]
    if !model.asyncSharedMembers.isEmpty {
        declarations.insert(makeWithPreparedFactory(model, directFactory: factory), at: declarations.count - 1)
        declarations.insert(makeOwnedProviderEnum(model), at: 0)
    }
    let declaredTypes = model.members.map(\.type) + model.subContainerMembers.map(\.type)
    if declaredTypes.contains(where: { type in
        type.tokens(viewMode: .sourceAccurate).contains { $0.text == "Self" }
    }) {
        // Let Swift bind Self in the original nominal scope. Spelling that
        // nominal's name here is unsafe when a nested type shadows its name.
        declarations.insert(DeclSyntax(TypeAliasDeclSyntax(
            modifiers: accessModifiers(model.accessLevel),
            name: .identifier(ownedSelfTypeName),
            initializer: TypeInitializerClauseSyntax(value: TypeSyntax("Self"))
        )), at: 0)
    }
    return declarations
}

/// Reuse the existing override builder and delegate to the sole owned wiring
/// implementation. Its separate name preserves existing child-override trailing
/// closures on makeOwned; Swift permits omitting a trailing closure's label.
/// Throwing preflight finishes before any live factory can start.
private func makeOwnedOverridesFactory(
    _ model: DIContainerExpansionModel,
    directFactory: DeclSyntax
) -> DeclSyntax {
    var function = directFactory.cast(FunctionDeclSyntax.self)
    function.name = .identifier("makeOwnedWithOverrides")
    let inputNames = Set(model.inputMembers.map(\.name))
    let directParameters = function.signature.parameterClause.parameters
    var parameters = directParameters.filter {
        inputNames.contains($0.firstName.text) || $0.firstName.text == "_innoDITrace"
    }
    for index in parameters.indices { parameters[index].trailingComma = .commaToken() }
    let actor = model.ownedMainActor ? "@_Concurrency.MainActor " : ""
    parameters.append(FunctionParameterSyntax(
        firstName: .wildcardToken(), secondName: .identifier("_innoDIApplyOverrides"),
        type: TypeSyntax(stringLiteral: "\(actor)(inout Self.Overrides) throws -> Void")
    ))
    function.signature.parameterClause.parameters = parameters

    let arguments = directParameters.map { parameter -> LabeledExprSyntax in
        let name = parameter.firstName.text
        let expression: ExprSyntax = inputNames.contains(name) || name == "_innoDITrace"
            ? ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(name)))
            : ExprSyntax(MemberAccessExprSyntax(
                base: DeclReferenceExprSyntax(baseName: .identifier("_innoDIOverrides")),
                declName: DeclReferenceExprSyntax(baseName: .identifier(name))
            ))
        return LabeledExprSyntax(label: .identifier(name), colon: .colonToken(), expression: expression)
    }
    let call = FunctionCallExprSyntax(
        calledExpression: MemberAccessExprSyntax(
            base: DeclReferenceExprSyntax(baseName: .keyword(.Self)),
            declName: DeclReferenceExprSyntax(baseName: .identifier("makeOwned"))
        ),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax(arguments.enumerated().map { index, argument in
            argument.with(\.trailingComma, index + 1 < arguments.count ? .commaToken() : nil)
        }),
        rightParen: .rightParenToken()
    )
    function.body = CodeBlockSyntax(statements: CodeBlockItemListSyntax([
        "try _Concurrency.Task.checkCancellation()",
        "var _innoDIOverrides = Self.Overrides()",
        "try _innoDIApplyOverrides(&_innoDIOverrides)",
        "return try await \(call)"
    ]))
    return DeclSyntax(function)
}

/// One structured consumer operation, using the same concrete owned factory.
/// Keep cleanup outside the successful do block so post-cleanup cancellation
/// cannot enter the catch path and call close a second time.
private func makeWithPreparedFactory(
    _ model: DIContainerExpansionModel,
    directFactory: DeclSyntax
) -> DeclSyntax {
    let actor = model.ownedMainActor ? "@_Concurrency.MainActor " : ""
    let result = "_InnoDIPreparedResult"
    var function = directFactory.cast(FunctionDeclSyntax.self)
    function.name = .identifier("withPrepared")
    function.genericParameterClause = GenericParameterClauseSyntax(parameters: GenericParameterListSyntax([
        GenericParameterSyntax(name: .identifier(result))
    ]))
    function.signature.returnClause = ReturnClauseSyntax(type: TypeSyntax(stringLiteral: result))
    let inputs = Set(model.inputMembers.map(\.name))
    let forwarded = function.signature.parameterClause.parameters.filter {
        inputs.contains($0.firstName.text) || $0.firstName.text == "_innoDITrace"
    }
    var parameters = FunctionParameterListSyntax([
        FunctionParameterSyntax(firstName: .wildcardToken(), secondName: .identifier("_innoDIProvider"),
                                type: TypeSyntax(stringLiteral: ownedProviderTypeName)),
        FunctionParameterSyntax(firstName: .wildcardToken(), secondName: .identifier("_innoDIAdditional"),
                                type: TypeSyntax(stringLiteral: ownedProviderTypeName), ellipsis: .ellipsisToken())
    ] + Array(forwarded))
    parameters.append(FunctionParameterSyntax(
        firstName: .identifier("overrides"), secondName: .identifier("_innoDIApplyOverrides"),
        type: TypeSyntax(stringLiteral: "\(actor)(inout Self.Overrides) throws -> Void"),
        defaultValue: InitializerClauseSyntax(value: ExprSyntax("{ _ in }"))
    ))
    parameters.append(FunctionParameterSyntax(
        firstName: .identifier("operation"), secondName: .identifier("_innoDIOperation"),
        type: TypeSyntax(stringLiteral: "\(model.ownedMainActor ? actor : "nonisolated(nonsending) ")(\(ownedViewTypeName)) async throws -> \(result)")
    ))
    for index in parameters.indices.dropLast() { parameters[index].trailingComma = .commaToken() }
    function.signature.parameterClause.parameters = parameters
    var arguments = forwarded.map { parameter in
        LabeledExprSyntax(label: .identifier(parameter.firstName.text), colon: .colonToken(),
                          expression: ExprSyntax(DeclReferenceExprSyntax(baseName: parameter.firstName)),
                          trailingComma: .commaToken())
    }
    arguments.append(LabeledExprSyntax(expression: ExprSyntax("_innoDIApplyOverrides")))
    let create = FunctionCallExprSyntax(
        calledExpression: ExprSyntax("Self.makeOwnedWithOverrides"),
        leftParen: .leftParenToken(), arguments: LabeledExprListSyntax(arguments), rightParen: .rightParenToken()
    )
    function.body = CodeBlockSyntax(statements: CodeBlockItemListSyntax([
        "try _Concurrency.Task.checkCancellation()",
        "let _innoDIOwner = try await \(create)",
        "let _innoDIResult: \(raw: result)",
        """
        do {
            let _innoDIReport = try await _innoDIOwner._innoDICoordinator.prepare(
                ([_innoDIProvider] + _innoDIAdditional).map { $0._innoDIProviderID }
            )
            try _Concurrency.Task.checkCancellation()
            try _innoDIReport.requireReady()
            _innoDIResult = try await _innoDIOperation(_innoDIOwner.container)
        } catch {
            await _innoDIOwner.close()
            throw error
        }
        """,
        "await _innoDIOwner.close()",
        "try _Concurrency.Task.checkCancellation()",
        "return _innoDIResult"
    ]))
    return DeclSyntax(function)
}

/// Changing only TypeSyntax preserves original factory bodies, nested helper
/// lookup and lexical Self inside makeOwned. A generated nested view has a
/// different Self and therefore uses a compiler-bound outer witness in its types.
private final class OwnedTypeRewriter: SyntaxRewriter {
    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: IdentifierTypeSyntax) -> TypeSyntax {
        guard node.name.text == "Self" else { return super.visit(node) }
        return TypeSyntax(node.with(\.name, .identifier(ownedSelfTypeName)))
    }
}

private func ownedType(_ type: TypeSyntax) -> TypeSyntax {
    OwnedTypeRewriter().rewrite(type).cast(TypeSyntax.self)
}

private func ownedAccess(_ model: DIContainerExpansionModel) -> String {
    model.accessLevel.map { "\($0) " } ?? ""
}

private func ownedActor(_ model: DIContainerExpansionModel) -> String {
    model.ownedMainActor ? "@_Concurrency.MainActor\n" : ""
}

private func ownedAsyncIsolation(_ model: DIContainerExpansionModel) -> String {
    model.ownedMainActor ? "" : "nonisolated(nonsending) "
}

/// A synchronous lazy cell captured by an async factory must have checked
/// Sendable payloads and captures, including the transitive lazy chain.
private func ownedSendableCellNames(_ model: DIContainerExpansionModel) -> Set<String> {
    guard !model.ownedMainActor else { return [] }
    var names = Set(model.asyncSharedMembers.flatMap(\.explicitDependencies))
    var pending = Array(names)
    let lazy = Dictionary(uniqueKeysWithValues: model.syncSharedMembers
        .filter { $0.initialization == .onDemand }.map { ($0.name, $0) })
    while let name = pending.popLast() {
        guard let member = lazy[name] else { continue }
        for dependency in member.explicitDependencies where names.insert(dependency).inserted {
            pending.append(dependency)
        }
    }
    return names
}

private func ownedCellType(_ member: ProvideMemberModel, sendableCells: Set<String>) -> String {
    sendableCells.contains(member.name) ? "_InnoDISendableSharedCell" : "_InnoDISharedCell"
}

private func makeOwnedProviderEnum(_ model: DIContainerExpansionModel) -> DeclSyntax {
    let cases = model.asyncSharedMembers.map {
        MemberBlockItemSyntax(decl: EnumCaseDeclSyntax(elements: EnumCaseElementListSyntax([
            EnumCaseElementSyntax(name: .identifier($0.name))
        ])))
    }
    let dispatch = model.asyncSharedMembers.map {
        "case .\($0.name): return \"\($0.name)\""
    }.joined(separator: "\n")
    let id: DeclSyntax = """
        fileprivate var _innoDIProviderID: Swift.String {
            switch self { \(raw: dispatch) }
        }
        """
    return DeclSyntax(EnumDeclSyntax(
        modifiers: accessModifiers(model.accessLevel),
        name: .identifier(ownedProviderTypeName),
        inheritanceClause: InheritanceClauseSyntax(inheritedTypes: InheritedTypeListSyntax([
            InheritedTypeSyntax(type: TypeSyntax("Swift.Sendable"))
        ])),
        memberBlock: MemberBlockSyntax(members: MemberBlockItemListSyntax(
            cases + (model.asyncSharedMembers.isEmpty ? [] : [MemberBlockItemSyntax(decl: id)])
        ))
    ))
}

private func makeOwnedView(
    _ model: DIContainerExpansionModel,
    sendableCells: Set<String>
) -> DeclSyntax {
    let access = ownedAccess(model)
    var declarations: [String] = ["fileprivate let _innoDITraceOwner: InnoDI._InnoDITraceOwner"]
    for member in model.members {
        let type = ownedType(member.type).trimmedDescription
        // Mirror the authored member access, rather than granting broader
        // visibility just because the container is public.
        let memberAccess = member.accessLevel.map { "\($0) " } ?? ""
        if member.scope == .transient {
            declarations.append("fileprivate let _innoDIResolver_\(member.name): () -> \(type)")
            declarations.append("\(memberAccess)var \(member.name): \(type) { _innoDIResolver_\(member.name)() }")
        } else if member.isAsyncFactory {
            declarations.append("fileprivate let _innoDIScope_\(member.name): InnoDI.DIAsyncScope<\(type)>")
            declarations.append("""
                \(memberAccess)\(ownedAsyncIsolation(model))var \(member.name): \(type) {
                    get async throws {
                        let value = try await _innoDIScope_\(member.name).value()
                        _innoDITraceOwner.cacheHit(member: "\(member.name)")
                        return value
                    }
                }
                """)
        } else if member.scope == .shared, member.initialization == .onDemand {
            let cell = ownedCellType(member, sendableCells: sendableCells)
            declarations.append("fileprivate let _innoDICell_\(member.name): InnoDI.\(cell)<\(type)>")
            declarations.append("\(memberAccess)var \(member.name): \(type) { _innoDICell_\(member.name).value() }")
        } else {
            declarations.append("fileprivate let _innoDIValue_\(member.name): \(type)")
            let trace = member.scope == .shared
                ? "_innoDITraceOwner.cacheHit(member: \"\(member.name)\")\n" : ""
            declarations.append("\(memberAccess)var \(member.name): \(type) { \(trace)return _innoDIValue_\(member.name) }")
        }
    }
    for child in model.subContainerMembers {
        let type = ownedType(child.type).trimmedDescription
        let childAccess = child.bindingSyntax.parent?.as(PatternBindingListSyntax.self)?.parent?
            .as(VariableDeclSyntax.self).map { declarationAccessLevel(for: $0.modifiers) } ?? nil
        // A private stored child would make the synthesized view initializer
        // private to the nested type, so the outer makeOwned could not call it.
        // Keep construction storage file-local and mirror only the authored
        // read access, just as provider members do above.
        declarations.append("fileprivate let _innoDIChild_\(child.name): \(type)")
        declarations.append("\(childAccess.map { "\($0) " } ?? "")var \(child.name): \(type) { _innoDIChild_\(child.name) }")
    }
    return DeclSyntax(stringLiteral: """
        \(ownedActor(model))\(access)struct \(ownedViewTypeName) {
            \(declarations.joined(separator: "\n"))
        }
        """)
}

private func makeOwnedOwner(_ model: DIContainerExpansionModel) -> DeclSyntax {
    let access = ownedAccess(model)
    let isolation = ownedAsyncIsolation(model)
    // There is no constructible selection for a sync-only graph. Emitting
    // methods with an uninhabited required argument triggers unreachable-code
    // warnings in actual consumer compilation under warnings-as-errors.
    if model.asyncSharedMembers.isEmpty {
        return DeclSyntax(stringLiteral: """
            \(ownedActor(model))\(access)struct \(ownedOwnerTypeName) {
                \(access)let container: \(ownedViewTypeName)
                fileprivate let _innoDICoordinator: InnoDI._InnoDIAsyncOwner
                \(access)\(isolation)func close() async {
                    await _innoDICoordinator.close()
                }
            }
            """)
    }
    let tokens = "_ provider: \(ownedProviderTypeName), _ additional: \(ownedProviderTypeName)..."
    let localScopes = model.asyncSharedMembers.map {
        "let _innoDIScope_\($0.name) = container._innoDIScope_\($0.name)"
    }.joined(separator: "\n")
    let cancels = model.asyncSharedMembers.map {
        "case .\($0.name): await _innoDIScope_\($0.name).cancel()"
    }.joined(separator: "\n")
    let statuses = model.asyncSharedMembers.map {
        "case .\($0.name): return await container._innoDIScope_\($0.name).status()"
    }.joined(separator: "\n")
    return DeclSyntax(stringLiteral: """
        \(ownedActor(model))\(access)struct \(ownedOwnerTypeName) {
            \(access)let container: \(ownedViewTypeName)
            fileprivate let _innoDICoordinator: InnoDI._InnoDIAsyncOwner

            @discardableResult
            \(access)\(isolation)func prepare(\(tokens)) async throws -> InnoDI.DIAsyncPreparationReport {
                try await _innoDICoordinator.prepare(([provider] + additional).map { $0._innoDIProviderID })
            }

            @discardableResult
            \(access)\(isolation)func retry(\(tokens)) async throws -> InnoDI.DIAsyncPreparationReport {
                try await _innoDICoordinator.retry(([provider] + additional).map { $0._innoDIProviderID })
            }

            /// Returns only after selected providers are ready. Caller
            /// cancellation wins over a non-ready preparation report.
            \(access)\(isolation)func requireReady(\(tokens)) async throws {
                try _Concurrency.Task.checkCancellation()
                let report = try await _innoDICoordinator.prepare(([provider] + additional).map { $0._innoDIProviderID })
                try _Concurrency.Task.checkCancellation()
                try report.requireReady()
            }

            /// Retries the existing failed/cancelled subgraph, then requires
            /// readiness. It is not refresh and does not close this owner.
            \(access)\(isolation)func retryAndRequireReady(\(tokens)) async throws {
                try _Concurrency.Task.checkCancellation()
                let report = try await _innoDICoordinator.retry(([provider] + additional).map { $0._innoDIProviderID })
                try _Concurrency.Task.checkCancellation()
                try report.requireReady()
            }

            /// Cancels only selected scopes that are running at each individual
            /// cancellation point. Idle/ready scopes are unchanged. Cancelled
            /// scopes require explicit retry; this operation does not close them.
            \(access)\(isolation)func cancel(\(tokens)) async {
                \(localScopes)
                await _innoDICoordinator.withCancellation {
                    for selected in [provider] + additional {
                        switch selected { \(cancels) }
                    }
                }
            }

            \(access)\(isolation)func status(_ provider: \(ownedProviderTypeName)) async -> InnoDI.DIAsyncProviderStatus {
                switch provider { \(statuses) }
            }

            \(access)\(isolation)func close() async {
                await _innoDICoordinator.close()
            }
        }
        """)
}

private func makeOwnedFactory(
    _ model: DIContainerExpansionModel,
    sendableCells: Set<String>
) throws -> DeclSyntax {
    let plan = try DIContainerInitializationPlan(model: model)
    // This model projection filters all members. Reuse it rather than
    // repeating an O(N) scan for every topologically ordered transient.
    let transientMembers = model.transientMembers
    // Unlike the ordinary initializer, the owned path emits a detached resolver
    // for every transient. Include their deferred edges even if no shared root
    // reaches them, and keep cells in authored order for deterministic output.
    let deferredNames = Set(model.members.flatMap {
        $0.softClosureDependencies + $0.providerClosureDependencies
    })
    let deferredMembers = model.members.filter {
        deferredNames.contains($0.name) && $0.supportsLazySoftTarget
    }
    let deferredTargets = Set(deferredMembers.map(\.name))
    var parameters: [FunctionParameterSyntax] = model.inputMembers.map {
        FunctionParameterSyntax(firstName: .identifier($0.name), type: inputParameterType(for: $0))
    }
    for member in model.sharedMembers + transientMembers {
        parameters.append(FunctionParameterSyntax(
            firstName: .identifier(member.name), type: optionalParameterType(for: member.type),
            defaultValue: InitializerClauseSyntax(value: NilLiteralExprSyntax())
        ))
    }
    for child in model.subContainerMembers {
        parameters.append(FunctionParameterSyntax(
            firstName: .identifier(child.name), type: optionalParameterType(for: child.type),
            defaultValue: InitializerClauseSyntax(value: NilLiteralExprSyntax())
        ))
        parameters.append(FunctionParameterSyntax(
            firstName: .identifier(child.overrideClosureName),
            type: overrideApplyClosureType(
                overridesTypeDescription: "\(child.type.trimmedDescription).\(innoDIMountOverridesTypeName)",
                isMainActor: model.ownedMainActor, isOptional: true
            ),
            defaultValue: InitializerClauseSyntax(value: NilLiteralExprSyntax())
        ))
    }
    parameters.append(FunctionParameterSyntax(
        firstName: .identifier("_innoDITrace"), type: TypeSyntax("InnoDI.DITraceContext"),
        defaultValue: InitializerClauseSyntax(value: ExprSyntax(".disabled"))
    ))
    for index in parameters.indices.dropLast() { parameters[index].trailingComma = .commaToken() }

    var statements: [CodeBlockItemSyntax] = [
        "try _Concurrency.Task.checkCancellation()",
        "let _innoDIAdmission = InnoDI._InnoDIAsyncAdmission()",
        "let _innoDITraceOwner = InnoDI._InnoDITraceOwner(context: _innoDITrace, containerType: Self.self)"
    ]
    if !deferredMembers.isEmpty {
        statements.append(CodeBlockItemSyntax(item: .decl(
            makeDeferredCellSupportDecl()
        )))
        for member in deferredMembers {
            statements.append(CodeBlockItemSyntax(item: .decl(
                makeLazyCellDecl(name: member.name, type: member.type)
            )))
        }
    }
    var expressions: [String: ExprSyntax] = [:]
    for input in model.inputMembers {
        expressions[input.name] = ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(input.name)))
        if deferredTargets.contains(input.name) {
            statements.append("_innoDILazyCell_\(raw: input.name).storeValue(\(raw: input.name))")
        }
    }
    for member in plan.syncShared {
        let factory = try makeFactoryExpr(
            member: member, availableNames: [], availableExpressions: expressions,
            deferredTargetNameSet: deferredTargets, fallbackOverrideNames: [], allowUnresolvedDependencyFallback: false
        )
        if member.initialization == .onDemand {
            let cell = ownedCellType(member, sendableCells: sendableCells)
            statements.append("""
                let _innoDICell_\(raw: member.name): InnoDI.\(raw: cell)<\(member.type)> = if let _innoDIOverride = \(raw: member.name) {
                    InnoDI.\(raw: cell)(traceOwner: _innoDITraceOwner, providerName: "\(raw: member.name)", value: _innoDIOverride)
                } else {
                    InnoDI.\(raw: cell)(traceOwner: _innoDITraceOwner, providerName: "\(raw: member.name)") { \(factory) }
                }
                """)
            expressions[member.name] = "_innoDICell_\(raw: member.name).value()"
        } else {
            statements.append("""
                let _innoDIValue_\(raw: member.name): \(member.type) = if let _innoDIOverride = \(raw: member.name) {
                    _innoDITraceOwner.overridden(member: "\(raw: member.name)", value: _innoDIOverride)
                } else {
                    _innoDITraceOwner.withResolution(member: "\(raw: member.name)") { \(factory) }
                }
                """)
            expressions[member.name] = "_innoDIValue_\(raw: member.name)"
        }
        if deferredTargets.contains(member.name) {
            if member.initialization == .onDemand {
                statements.append("_innoDILazyCell_\(raw: member.name).bindResolver { _innoDICell_\(raw: member.name).value() }")
            } else {
                statements.append("_innoDILazyCell_\(raw: member.name).storeValue(_innoDIValue_\(raw: member.name))")
            }
        }
    }
    // Synchronous transients are ordinary per-read factories, not owned tasks.
    // Concrete resolver captures never refer to the view or lifecycle owner.
    // Reuse the graph and factory builders; emitting once avoids diamond growth.
    let transientOrder = try stableInitializationOrder(transientMembers.map {
        InitializationOrderNode(name: $0.name, hardDependencies: $0.hardClosureDependencies + $0.withDependencies)
    })
    var transientExpressions = expressions
    for member in transientMembers {
        transientExpressions[member.name] = "_innoDIResolver_\(raw: member.name)()"
    }
    for index in transientOrder {
        let member = transientMembers[index]
        let factory = try makeFactoryExpr(
            member: member, availableNames: [], availableExpressions: transientExpressions,
            deferredTargetNameSet: deferredTargets, fallbackOverrideNames: [], allowUnresolvedDependencyFallback: false
        )
        statements.append("""
            let _innoDIResolver_\(raw: member.name): () -> \(member.type) = {
                if let _innoDIOverride = \(raw: member.name) {
                    return _innoDITraceOwner.overridden(member: "\(raw: member.name)", value: _innoDIOverride)
                }
                return _innoDITraceOwner.withResolution(member: "\(raw: member.name)") { \(factory) }
            }
            """)
        if deferredTargets.contains(member.name) {
            statements.append("_innoDILazyCell_\(raw: member.name).bindResolver(_innoDIResolver_\(raw: member.name))")
        }
    }
    expressions = transientExpressions
    let asyncNames = Set(model.asyncSharedMembers.map(\.name))
    for member in plan.asyncShared {
        var arguments = expressions
        var dependencies: [CodeBlockItemSyntax] = []
        // Owned reads can throw even when the authored factory cannot. Resolve
        // arguments before invoking that unchanged closure; do not promote its
        // declared effects or put a throwing expression inside a nonthrowing call.
        for dependency in member.explicitDependencies where asyncNames.contains(dependency) {
            dependencies.append("""
                let _innoDIArgument_\(raw: dependency) = try await _innoDITraceOwner.withWait(member: "\(raw: member.name)", forMember: "\(raw: dependency)") {
                    try await _innoDIScope_\(raw: dependency).value()
                }
                """)
            arguments[dependency] = "_innoDIArgument_\(raw: dependency)"
        }
        let factory = try makeAsyncFactoryExpr(
            member: member, resolvedDependencyExpressions: arguments, taskBindings: [:],
            deferredTargetNameSet: deferredTargets, fallbackOverrideNames: [], allowUnresolvedDependencyFallback: false
        )
        let awaitFactory: ExprSyntax = member.asyncFactoryIsThrowing ? "try await \(factory)" : "await \(factory)"
        let actor = model.ownedMainActor ? "@_Concurrency.MainActor in" : ""
        let dependencyBody = CodeBlockItemListSyntax(dependencies)
        statements.append("""
            let _innoDIScope_\(raw: member.name): InnoDI.DIAsyncScope<\(member.type)> = if let _innoDIOverride = \(raw: member.name) {
                InnoDI.DIAsyncScope(
                    value: _innoDITraceOwner.overridden(member: "\(raw: member.name)", value: _innoDIOverride),
                    providerID: "\(raw: member.name)", admission: _innoDIAdmission
                )
            } else {
                InnoDI.DIAsyncScope(providerID: "\(raw: member.name)", admission: _innoDIAdmission) { \(raw: actor)
                    try await _innoDITraceOwner.withResolution(member: "\(raw: member.name)") {
                        \(dependencyBody)
                        try _Concurrency.Task.checkCancellation()
                        let _innoDIValue = \(awaitFactory)
                        try _Concurrency.Task.checkCancellation()
                        return _innoDIValue
                    }
                }
            }
            """)
    }
    // Children are borrowed legacy values, never lifecycle nodes. Existing
    // child validation already rejects asynchronous parent arguments.
    for child in model.subContainerMembers {
        let mappings = resolvedSubContainerArguments(member: child, autoWireParentMemberNames: model.members.map(\.name))
        let base = subContainerInitializerExpr(childType: child.type, argumentMappings: mappings, parentMemberExpressions: expressions)
        let applied = subContainerInitializerExpr(
            childType: child.type, argumentMappings: mappings, trailingOverrideExpression: "_innoDIApply",
            parentMemberExpressions: expressions
        )
        statements.append("""
            let _innoDIChild_\(raw: child.name): \(child.type) = if let _innoDIDirect = \(raw: child.name) {
                _innoDIDirect
            } else if let _innoDIApply = \(raw: child.overrideClosureName) {
                \(applied)
            } else {
                \(base)
            }
            """)
    }
    let nodes = model.asyncSharedMembers.map { member in
        let dependencies = member.explicitDependencies.filter { asyncNames.contains($0) }
            .map { "\"\($0)\"" }.joined(separator: ", ")
        return "InnoDI.DIAsyncPreparationNode(provider: _innoDIScope_\(member.name), dependencies: \(member.name) == nil ? [\(dependencies)] : [])"
    }.joined(separator: ",\n")
    let closes = model.asyncSharedMembers.reversed().map { "await _innoDIScope_\($0.name).close()" }.joined(separator: "\n")
    statements.append("let _innoDICoordinator: InnoDI._InnoDIAsyncOwner")
    statements.append("""
        do {
            _innoDICoordinator = try InnoDI._InnoDIAsyncOwner(admission: _innoDIAdmission, nodes: [\(raw: nodes)])
        } catch {
            \(raw: closes)
            throw error
        }
        """)
    var viewArguments = ["_innoDITraceOwner: _innoDITraceOwner"]
    for member in model.members {
        if member.scope == .transient {
            viewArguments.append("_innoDIResolver_\(member.name): _innoDIResolver_\(member.name)")
        } else if member.isAsyncFactory {
            viewArguments.append("_innoDIScope_\(member.name): _innoDIScope_\(member.name)")
        } else if member.scope == .shared, member.initialization == .onDemand {
            viewArguments.append("_innoDICell_\(member.name): _innoDICell_\(member.name)")
        } else {
            viewArguments.append("_innoDIValue_\(member.name): \(expressions[member.name]!.trimmedDescription)")
        }
    }
    viewArguments += model.subContainerMembers.map { "_innoDIChild_\($0.name): _innoDIChild_\($0.name)" }
    let starts = plan.asyncShared.filter { $0.initialization == .eager }
        .map { "_ = try await _innoDIScope_\($0.name).start()" }.joined(separator: "\n")
    statements.append("""
        do {
            let _innoDIView = \(raw: ownedViewTypeName)(\(raw: viewArguments.joined(separator: ", ")))
            let _innoDIOwner = \(raw: ownedOwnerTypeName)(container: _innoDIView, _innoDICoordinator: _innoDICoordinator)
            try _Concurrency.Task.checkCancellation()
            \(raw: starts)
            try _Concurrency.Task.checkCancellation()
            return _innoDIOwner
        } catch {
            await _innoDICoordinator.close()
            throw error
        }
        """)
    // Parse the small declaration shell, then insert structured parameter and
    // body nodes. The user factory AST enters only via the existing builders.
    let shell: DeclSyntax = """
        \(raw: ownedActor(model))\(raw: ownedAccess(model))\(raw: ownedAsyncIsolation(model))static func makeOwned() async throws -> \(raw: ownedOwnerTypeName) {}
        """
    var function = shell.cast(FunctionDeclSyntax.self)
    function.signature.parameterClause.parameters = FunctionParameterListSyntax(parameters)
    function.body = CodeBlockSyntax(statements: CodeBlockItemListSyntax(statements))
    return DeclSyntax(function)
}
