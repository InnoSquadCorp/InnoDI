import SwiftSyntax

/// The namespace a generated module qualifier must resolve in.
///
/// Most generated qualifiers appear in type positions. Runtime support such
/// as `InnoDI._innoDITrap`, however, is an expression lookup and can be
/// shadowed by either a type or a value declaration.
package enum GeneratedQualifierNamespaceRequirement: Hashable {
    case typeOnly
    case typeOrValue
}

/// A module qualifier emitted by one generated-code lookup context.
package struct GeneratedQualifierRequirement: Hashable {
    package let name: String
    package let namespace: GeneratedQualifierNamespaceRequirement

    package init(
        _ name: String,
        namespace: GeneratedQualifierNamespaceRequirement = .typeOnly
    ) {
        self.name = name
        self.namespace = namespace
    }
}

/// Qualifiers emitted for one attached macro target, grouped by the lexical
/// lookup context in which the compiler will resolve them.
///
/// Keeping these contexts separate is important. A generated member body can
/// see enclosing and inherited members, while a generated file-scope
/// extension cannot. Attached accessor attributes have their own lookup rules
/// and are retained here so macro and build validation can evolve from the
/// same source-of-truth model.
package struct GeneratedQualifierUsage {
    package let attachedAttributes: Set<GeneratedQualifierRequirement>
    package let memberBodies: Set<GeneratedQualifierRequirement>
    package let fileScopeExtensions: Set<GeneratedQualifierRequirement>

    package init(
        attachedAttributes: Set<GeneratedQualifierRequirement> = [],
        memberBodies: Set<GeneratedQualifierRequirement> = [],
        fileScopeExtensions: Set<GeneratedQualifierRequirement> = []
    ) {
        self.attachedAttributes = attachedAttributes
        self.memberBodies = memberBodies
        self.fileScopeExtensions = fileScopeExtensions
    }

    package static func container(
        declaration: some DeclGroupSyntax
    ) -> GeneratedQualifierUsage {
        let attributes = declaration.attributes
        let options = parseDIContainerAttribute(attributes)
        let members = DirectManagedMemberCollector.collect(from: declaration)

        var attachedAttributes: Set<GeneratedQualifierRequirement> = []
        if members.contains(where: \.isManaged) {
            attachedAttributes.insert(.init("InnoDI"))
        }

        var memberBodies: Set<GeneratedQualifierRequirement> = []
        if options?.mainActor == true {
            memberBodies.insert(.init("Swift"))
        }

        let provides = members.compactMap(\.provide)
        let validProvides = provides.filter(\.hasLocallyValidConstruction)
        let inputNames = Set(
            validProvides.filter { $0.scope == .input }.map(\.name)
        )
        let syncShared = validProvides.filter {
            $0.scope == .shared && !$0.isAsync
        }
        let asyncShared = validProvides.filter {
            $0.scope == .shared && $0.isAsync
        }

        if !asyncShared.isEmpty {
            memberBodies.formUnion([
                .init("Swift"),
                .init("_Concurrency"),
            ])
        }

        let validTargetsByName = Dictionary(
            validProvides.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var deferredTargetNames: Set<String> = []
        for source in validProvides where source.scope == .shared {
            for reference in source.references {
                guard reference.kind != .hard,
                      let target = validTargetsByName[reference.name],
                      target.supports(reference.kind) else {
                    continue
                }
                deferredTargetNames.insert(reference.name)
            }
        }

        let hasTransientSubContainer = members.contains { member in
            member.subContainer?.scope == .transient
        }
        if !deferredTargetNames.isEmpty || hasTransientSubContainer {
            memberBodies.formUnion([
                .init("Swift"),
                .init("InnoDI", namespace: .typeOrValue),
            ])
        }

        if options?.validateDAG == false,
           emitsUnresolvedFallback(
            inputNames: inputNames,
            syncShared: syncShared,
            asyncShared: asyncShared,
            deferredTargetNames: deferredTargetNames,
            validTargetsByName: validTargetsByName
           ) {
            memberBodies.insert(
                .init("InnoDI", namespace: .typeOrValue)
            )
        }

        // A stacked bridge always emits Swift-qualified member support. The
        // bridge site deliberately leaves that qualifier container-owned so a
        // single source declaration produces one diagnostic path.
        if findAttribute(
            named: "DIEnvironmentBridge",
            allowingQualifiedModules: ["InnoDISwiftUI"],
            in: attributes
        ) != nil {
            memberBodies.insert(.init("Swift"))
        }

        var fileScopeExtensions: Set<GeneratedQualifierRequirement> = []
        if findInnoDIAttribute(named: "DIComponent", in: attributes) != nil
            || findInnoDIAttribute(
                named: "DIHierarchyRoot",
                in: attributes
            ) != nil {
            fileScopeExtensions.insert(.init("InnoDI"))
        }

        return GeneratedQualifierUsage(
            attachedAttributes: attachedAttributes,
            memberBodies: memberBodies,
            fileScopeExtensions: fileScopeExtensions
        )
    }

    package static func environmentBridge(
        isContainer: Bool
    ) -> GeneratedQualifierUsage {
        var memberBodies: Set<GeneratedQualifierRequirement> = [
            .init("SwiftUI"),
        ]
        if !isContainer {
            memberBodies.insert(.init("Swift"))
        }
        return GeneratedQualifierUsage(
            memberBodies: memberBodies,
            fileScopeExtensions: [.init("InnoDISwiftUI")]
        )
    }
}

private enum ManagedDependencyKind: Equatable {
    case hard
    case lazy
    case provider
}

private struct ManagedDependencyReference {
    let name: String
    let kind: ManagedDependencyKind
}

private struct ManagedProvideMember {
    let sourceOrder: Int
    let name: String
    let scope: ProvideScope?
    let factory: ExprSyntax?
    let asyncFactory: ExprSyntax?
    let typeExpression: ExprSyntax?
    let initializer: ExprSyntax?
    let withDependencies: [String]
    let withDependenciesAreValid: Bool
    let references: [ManagedDependencyReference]

    var isAsync: Bool {
        asyncFactory != nil
    }

    var hasLocallyValidConstruction: Bool {
        guard let scope, withDependenciesAreValid else { return false }
        let constructionSourceCount = [
            factory != nil,
            asyncFactory != nil,
            typeExpression != nil,
            initializer != nil,
        ].filter { $0 }.count
        switch scope {
        case .input:
            return constructionSourceCount == 0 && withDependencies.isEmpty
        case .shared, .transient:
            guard constructionSourceCount == 1 else { return false }
            if !withDependencies.isEmpty && typeExpression == nil {
                return false
            }
            if let asyncFactory {
                return isAsyncClosure(asyncFactory)
            }
            return true
        }
    }

    func supports(_ dependencyKind: ManagedDependencyKind) -> Bool {
        guard let scope else { return false }
        switch dependencyKind {
        case .hard:
            return true
        case .lazy:
            switch scope {
            case .input:
                return true
            case .shared, .transient:
                return !isAsync
            }
        case .provider:
            return scope == .transient && !isAsync
        }
    }
}

private struct ManagedSubContainerMember {
    let scope: SubContainerScopeValue?
}

private struct DirectManagedMember {
    let provide: ManagedProvideMember?
    let subContainer: ManagedSubContainerMember?

    var isManaged: Bool {
        provide != nil || subContainer != nil
    }
}

private final class DirectManagedMemberCollector: SyntaxVisitor {
    private var sourceOrder = 0
    private(set) var members: [DirectManagedMember] = []

    static func collect(
        from declaration: some DeclGroupSyntax
    ) -> [DirectManagedMember] {
        let collector = DirectManagedMemberCollector(viewMode: .sourceAccurate)
        for member in declaration.memberBlock.members {
            collector.walk(member.decl)
        }
        return collector.members
    }

    override func visit(
        _ node: VariableDeclSyntax
    ) -> SyntaxVisitorContinueKind {
        defer { sourceOrder += 1 }

        if let attribute = findInnoDIAttribute(
            named: "Provide",
            in: node.attributes
        ) {
            let arguments = parseProvideArguments(attribute)
            for binding in node.bindings {
                guard let identifier = binding.pattern.as(
                    IdentifierPatternSyntax.self
                ) else {
                    continue
                }
                let factory = arguments.factoryExpr
                    ?? arguments.asyncFactoryExpr
                let references = factory
                    .flatMap { dependencyReferences(in: $0) }
                    ?? []
                members.append(
                    DirectManagedMember(
                        provide: ManagedProvideMember(
                            sourceOrder: sourceOrder,
                            name: identifier.identifier.text,
                            scope: arguments.scope,
                            factory: arguments.factoryExpr,
                            asyncFactory: arguments.asyncFactoryExpr,
                            typeExpression: arguments.typeExpr,
                            initializer: binding.initializer?.value,
                            withDependencies: arguments.dependencies,
                            withDependenciesAreValid:
                                !arguments.dependenciesParseState.isInvalid,
                            references: references
                        ),
                        subContainer: nil
                    )
                )
            }
            return .skipChildren
        }

        if let attribute = findInnoDIAttribute(
            named: "SubContainer",
            in: node.attributes
        ) {
            let arguments = parseSubContainerArguments(attribute)
            members.append(
                DirectManagedMember(
                    provide: nil,
                    subContainer: ManagedSubContainerMember(
                        scope: arguments.scope
                    )
                )
            )
        }
        return .skipChildren
    }

    override func visit(
        _ node: IfConfigDeclSyntax
    ) -> SyntaxVisitorContinueKind { .skipChildren }

    override func visit(
        _ node: StructDeclSyntax
    ) -> SyntaxVisitorContinueKind { .skipChildren }

    override func visit(
        _ node: ClassDeclSyntax
    ) -> SyntaxVisitorContinueKind { .skipChildren }

    override func visit(
        _ node: EnumDeclSyntax
    ) -> SyntaxVisitorContinueKind { .skipChildren }

    override func visit(
        _ node: ActorDeclSyntax
    ) -> SyntaxVisitorContinueKind { .skipChildren }

    override func visit(
        _ node: ProtocolDeclSyntax
    ) -> SyntaxVisitorContinueKind { .skipChildren }

    override func visit(
        _ node: ExtensionDeclSyntax
    ) -> SyntaxVisitorContinueKind { .skipChildren }

    override func visit(
        _ node: FunctionDeclSyntax
    ) -> SyntaxVisitorContinueKind { .skipChildren }
}

private func dependencyReferences(
    in expression: ExprSyntax
) -> [ManagedDependencyReference]? {
    guard let closure = expression.as(ClosureExprSyntax.self),
          let parameterClause = closure.signature?.parameterClause else {
        return expression.is(ClosureExprSyntax.self) ? [] : nil
    }

    switch parameterClause {
    case .simpleInput(let parameters):
        return parameters.compactMap { parameter in
            let name = parameter.name.text
            guard name != "_" else { return nil }
            return ManagedDependencyReference(name: name, kind: .hard)
        }
    case .parameterClause(let clause):
        return clause.parameters.compactMap { parameter in
            let token = parameter.secondName ?? parameter.firstName
            let name = token.text
            guard name != "_" else { return nil }
            let kind: ManagedDependencyKind
            switch deferredDependencyWrapperKind(for: parameter.type) {
            case .lazy:
                kind = .lazy
            case .provider:
                kind = .provider
            case .none:
                kind = .hard
            }
            return ManagedDependencyReference(name: name, kind: kind)
        }
    }
}

private func isAsyncClosure(_ expression: ExprSyntax) -> Bool {
    expression.as(ClosureExprSyntax.self)?
        .signature?
        .effectSpecifiers?
        .asyncSpecifier != nil
}

private func emitsUnresolvedFallback(
    inputNames: Set<String>,
    syncShared: [ManagedProvideMember],
    asyncShared: [ManagedProvideMember],
    deferredTargetNames: Set<String>,
    validTargetsByName: [String: ManagedProvideMember]
) -> Bool {
    var availableSyncNames = inputNames
    for member in syncShared.sorted(by: sourceOrder) {
        if member.references.contains(where: { reference in
            dependencyRequiresFallback(
                reference,
                availableNames: availableSyncNames,
                deferredTargetNames: deferredTargetNames,
                validTargetsByName: validTargetsByName,
                normalizingStoragePrefix: true
            )
        }) || member.withDependencies.contains(where: {
            !dependencyIsAvailable(
                $0,
                in: availableSyncNames,
                normalizingStoragePrefix: true
            )
        }) {
            return true
        }
        availableSyncNames.insert(member.name)
    }

    var availableAsyncNames = availableSyncNames
    for member in asyncShared.sorted(by: sourceOrder) {
        if member.references.contains(where: { reference in
            dependencyRequiresFallback(
                reference,
                availableNames: availableAsyncNames,
                deferredTargetNames: deferredTargetNames,
                validTargetsByName: validTargetsByName,
                normalizingStoragePrefix: false
            )
        }) {
            return true
        }
        availableAsyncNames.insert(member.name)
    }
    return false
}

private func dependencyRequiresFallback(
    _ reference: ManagedDependencyReference,
    availableNames: Set<String>,
    deferredTargetNames: Set<String>,
    validTargetsByName: [String: ManagedProvideMember],
    normalizingStoragePrefix: Bool
) -> Bool {
    switch reference.kind {
    case .hard:
        return !dependencyIsAvailable(
            reference.name,
            in: availableNames,
            normalizingStoragePrefix: normalizingStoragePrefix
        )
    case .lazy, .provider:
        if deferredTargetNames.contains(reference.name) {
            return false
        }
        guard validTargetsByName[reference.name] != nil else {
            return true
        }
        // A known but unsupported target is rejected before code generation,
        // so it does not produce the validateDAG opt-out fallback.
        return false
    }
}

private let providerStoragePrefix = "_storage_"

private func dependencyIsAvailable(
    _ name: String,
    in availableNames: Set<String>,
    normalizingStoragePrefix: Bool
) -> Bool {
    if availableNames.contains(name) {
        return true
    }
    guard normalizingStoragePrefix else {
        return false
    }

    let normalizedName = name.removingProviderStoragePrefix
    return availableNames.contains {
        $0.removingProviderStoragePrefix == normalizedName
    }
}

private extension String {
    var removingProviderStoragePrefix: String {
        guard hasPrefix(providerStoragePrefix) else { return self }
        return String(dropFirst(providerStoragePrefix.count))
    }
}

private func sourceOrder(
    _ lhs: ManagedProvideMember,
    _ rhs: ManagedProvideMember
) -> Bool {
    lhs.sourceOrder < rhs.sourceOrder
}
