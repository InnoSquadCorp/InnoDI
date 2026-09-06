import InnoDICore
import SwiftSyntax

/// A pending ownership reference discovered inside a `@DIContainer` body:
/// "this parent owns a child container of this written type". The type
/// description is whatever the author wrote at the `@SubContainer` property
/// site — `FeatureContainer`, `Feature.Container`, `NestedModule.Scope`,
/// etc. The CLI resolves these into concrete parent→child container IDs
/// after every container has been catalogued.
struct PendingSubContainerReference {
    enum OwnershipKind: Equatable {
        case subContainer
        case assistedFactory
    }
    /// Stable ID of the parent container node.
    let parentID: String
    /// Dotted semantic path of the parent container (used for diagnostics
    /// and disambiguation when the same type name appears under multiple
    /// namespaces).
    let parentSemanticPath: String
    /// Parent member name (e.g. `feature`) — threaded into the edge label
    /// so "owns" edges are readable in the graph.
    let memberName: String
    /// Type text as written at the `@SubContainer` declaration
    /// (`"FeatureContainer"`, `"ChildAlias"`, `"FeatureContainer<T>"`, …).
    /// Used for diagnostics when the type cannot be normalized into a
    /// semantic reference.
    let childDisplayName: String
    /// Normalized semantic reference for the child when the written type
    /// shape is supported by the shared resolver. `nil` for excluded forms
    /// such as generic specializations.
    let childReference: SemanticTypeReference?
    let ownershipKind: OwnershipKind
    let bindingPairs: [SubContainerBindingArgument]
    let usesImplicitSameNameWiring: Bool
}

struct PendingMultibindingContribution {
    let containerID: String
    let collectionName: String
    let contributorName: String
    let order: Int
}

final class ContainerCollector: SyntaxVisitor, DeclarationPathTracking {
    var nodes: [DependencyGraphNode] = []
    var typeAliases: [SemanticTypeAliasRecord] = []
    /// `@SubContainer` references collected while walking each container
    /// body. Resolved into graph edges by `resolveSubContainerReferences`
    /// once every container has been visited.
    var subContainerReferences: [PendingSubContainerReference] = []
    var multibindingContributions: [PendingMultibindingContribution] = []
    var providers: [DependencyGraphProvider] = []

    private let moduleIdentity: String?
    private var currentRelativeFilePath: String = ""
    private var sourceLocationConverter: SourceLocationConverter?
    var declarationPath: [String] = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        moduleIdentity = nil
        super.init(viewMode: viewMode)
    }

    init(
        moduleIdentity: String,
        viewMode: SyntaxTreeViewMode = .sourceAccurate
    ) {
        self.moduleIdentity = moduleIdentity
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        visitContainerDeclaration(node, name: node.name.text)
    }

    override func visitPost(_ node: StructDeclSyntax) {
        _ = endDeclarationContext()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        visitContainerDeclaration(node, name: node.name.text)
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        _ = endDeclarationContext()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        visitContainerDeclaration(node, name: node.name.text)
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        _ = endDeclarationContext()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        visitContainerDeclaration(node, name: node.name.text)
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        _ = endDeclarationContext()
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let target = normalizedSemanticTypeReference(node.initializer.value) else {
            return .skipChildren
        }

        let components = declarationPath + [node.name.text]
        let path = components.joined(separator: ".")

        typeAliases.append(
            SemanticTypeAliasRecord(
                path: path,
                components: components,
                target: target
            )
        )
        return .skipChildren
    }

    func walkFile(relativePath: String, tree: SourceFileSyntax) {
        currentRelativeFilePath = relativePath
        sourceLocationConverter = SourceLocationConverter(
            fileName: relativePath,
            tree: tree
        )
        declarationPath.removeAll(keepingCapacity: true)
        walk(tree)
    }

    private func visitContainerDeclaration(_ node: some DeclGroupSyntax, name: String) -> SyntaxVisitorContinueKind {
        beginDeclarationContext(named: name)
        collectIfContainer(node, displayName: name)
        return .visitChildren
    }

    private func collectIfContainer(_ node: some DeclGroupSyntax, displayName: String) {
        guard let containerAttr = parseDIContainerAttribute(node.attributes) else { return }
        guard classifyDIContainerDeclaration(node).isSupported else { return }
        let semanticPath = declarationPath.joined(separator: ".")
        let parentID = GraphIdentity.makeContainerID(
            fileRelativePath: currentRelativeFilePath,
            declarationPath: declarationPath,
            moduleIdentity: moduleIdentity
        )

        var requiredInputs: [String] = []
        var assistedInputs: [String] = []
        for member in node.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            guard let binding = varDecl.bindings.first,
                  let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  let typeAnnotation = binding.typeAnnotation else {
                continue
            }
            let memberName = pattern.identifier.text
            let memberType = typeAnnotation.type.trimmedDescription
            let source = providerSourceLocation(for: varDecl)

            // `@SubContainer` ownership edge collection. Parent/child IDs
            // stay unresolved at this stage — the AppMain pass feeds the
            // child's semantic reference through the shared resolver after
            // the full file set has been walked so ownership edges follow
            // the same alias/suffix/ambiguity policy as regular container
            // references.
            if let subcontainer = parseSubContainerAttribute(varDecl.attributes) {
                let childType = typeAnnotation.type.trimmedDescription
                let bindingPairs: [SubContainerBindingArgument]
                let usesImplicitSameNameWiring: Bool
                if subcontainer.bindingsParseState.hasArgument {
                    bindingPairs = subcontainer.bindings
                    usesImplicitSameNameWiring = false
                } else {
                    switch subcontainer.sameNameWiring {
                    case let .parsed(_, dependencies):
                        bindingPairs = dependencies.map {
                            SubContainerBindingArgument(
                                childName: $0,
                                parentName: $0
                            )
                        }
                        usesImplicitSameNameWiring = false
                    case .omitted:
                        bindingPairs = []
                        usesImplicitSameNameWiring = true
                    case .invalid:
                        bindingPairs = []
                        usesImplicitSameNameWiring = false
                    }
                }
                providers.append(
                    DependencyGraphProvider(
                        id: providerID(containerID: parentID, memberName: memberName),
                        containerID: parentID,
                        name: memberName,
                        type: memberType,
                        role: .subcontainer,
                        lifetime: subcontainer.scope == .transient ? .transient : .shared,
                        initialization: subcontainer.scope == .transient ? .onAccess : .eager,
                        isolation: containerAttr.mainActor ? .mainActor : .nonisolated,
                        effect: .sync,
                        dependencies: subcontainer.dependencies + subcontainer.bindings.map(\.parentName),
                        source: source
                    )
                )
                subContainerReferences.append(
                    PendingSubContainerReference(
                        parentID: parentID,
                        parentSemanticPath: semanticPath,
                        memberName: pattern.identifier.text,
                        childDisplayName: childType,
                        childReference: normalizedSemanticTypeReference(typeAnnotation.type),
                        ownershipKind: .subContainer,
                        bindingPairs: bindingPairs,
                        usesImplicitSameNameWiring: usesImplicitSameNameWiring
                    )
                )
                continue
            }

            guard let provide = parseProvideAttribute(varDecl.attributes)
            else { continue }
            let factoryWiring = providerFactoryWiring(
                provide: provide,
                containerID: parentID
            )
            if let childType = provide.assistedFactoryChildType {
                providers.append(
                    DependencyGraphProvider(
                        id: providerID(containerID: parentID, memberName: memberName),
                        containerID: parentID,
                        name: memberName,
                        type: memberType,
                        role: .assistedFactory,
                        lifetime: .transient,
                        initialization: .assisted,
                        isolation: containerAttr.mainActor ? .mainActor : .nonisolated,
                        effect: .sync,
                        dependencies: factoryWiring.dependencies,
                        dependencyBindings: factoryWiring.bindings,
                        source: source
                    )
                )
                subContainerReferences.append(
                    PendingSubContainerReference(
                        parentID: parentID,
                        parentSemanticPath: semanticPath,
                        memberName: pattern.identifier.text,
                        childDisplayName: childType.trimmedDescription,
                        childReference: normalizedSemanticTypeReference(
                            childType
                        ),
                        ownershipKind: .assistedFactory,
                        bindingPairs: zip(
                            provide.dependencyLabels,
                            provide.dependencies
                        ).map {
                            SubContainerBindingArgument(
                                childName: $0.0,
                                parentName: $0.1
                            )
                        },
                        usesImplicitSameNameWiring: false
                    )
                )
                continue
            }

            if provide.isMultibinding {
                providers.append(
                    DependencyGraphProvider(
                        id: providerID(containerID: parentID, memberName: memberName),
                        containerID: parentID,
                        name: memberName,
                        type: memberType,
                        role: .multibinding,
                        lifetime: .transient,
                        initialization: .onAccess,
                        isolation: containerAttr.mainActor ? .mainActor : .nonisolated,
                        effect: .sync,
                        dependencies: factoryWiring.dependencies,
                        dependencyBindings: factoryWiring.bindings,
                        source: source
                    )
                )
                for (order, contributor) in provide.dependencies.enumerated() {
                    multibindingContributions.append(
                        PendingMultibindingContribution(
                            containerID: parentID,
                            collectionName: pattern.identifier.text,
                            contributorName: contributor,
                            order: order
                        )
                    )
                }
                continue
            }

            let role: DependencyGraphProvider.Role = provide.scope == .input
                ? .input : .provider
            let lifetime: DependencyGraphProvider.Lifetime
            let initialization: DependencyGraphProvider.Initialization
            switch provide.scope {
            case .input:
                lifetime = .external
                initialization = provide.inputKind == .assisted ? .assisted : .external
            case .transient:
                lifetime = .transient
                initialization = .onAccess
            case .shared, .none:
                lifetime = .shared
                initialization = provide.initialization == .onDemand
                    ? .onDemand : .eager
            }
            let effect: DependencyGraphProvider.Effect
            if provide.asyncFactoryExpr == nil {
                effect = .sync
            } else if provide.asyncFactoryIsThrowing {
                effect = .asyncThrows
            } else {
                effect = .async
            }
            providers.append(
                DependencyGraphProvider(
                    id: providerID(containerID: parentID, memberName: memberName),
                    containerID: parentID,
                    name: memberName,
                    type: memberType,
                    role: role,
                    lifetime: lifetime,
                    initialization: initialization,
                    isolation: containerAttr.mainActor ? .mainActor : .nonisolated,
                    effect: effect,
                    inputKind: provide.scope == .input
                        ? (provide.inputKind == .assisted ? .assisted : .container)
                        : nil,
                    dependencies: factoryWiring.dependencies,
                    dependencyBindings: factoryWiring.bindings,
                    source: source
                )
            )

            guard provide.scope == .input else { continue }
            if provide.inputKind == .assisted {
                assistedInputs.append(pattern.identifier.text)
            } else {
                requiredInputs.append(pattern.identifier.text)
            }
        }

        nodes.append(
            DependencyGraphNode(
                id: parentID,
                displayName: displayName,
                semanticPath: semanticPath,
                isRoot: containerAttr.root,
                validateDAG: containerAttr.validateDAG,
                requiredInputs: requiredInputs,
                assistedInputs: assistedInputs
            )
        )
    }

    private func providerID(containerID: String, memberName: String) -> String {
        "\(containerID).\(memberName)"
    }

    private func providerFactoryWiring(
        provide: ProvideArguments,
        containerID: String
    ) -> (
        dependencies: [String],
        bindings: [DependencyGraphProvider.DependencyBinding]
    ) {
        if let expression = provide.asyncFactoryExpr ?? provide.factoryExpr,
           let references = managedFactoryDependencyReferences(in: expression) {
            return (
                references.map(\.name),
                references.map { reference in
                    DependencyGraphProvider.DependencyBinding(
                        parameter: reference.name,
                        providerID: providerID(
                            containerID: containerID,
                            memberName: reference.name
                        ),
                        kind: reference.kind
                    )
                }
            )
        }

        let labels = provide.dependencyLabels.count == provide.dependencies.count
            ? provide.dependencyLabels
            : provide.dependencies
        return (
            provide.dependencies,
            zip(labels, provide.dependencies).map { label, dependency in
                DependencyGraphProvider.DependencyBinding(
                    parameter: label,
                    providerID: providerID(
                        containerID: containerID,
                        memberName: dependency
                    ),
                    kind: .hard
                )
            }
        )
    }

    private func providerSourceLocation(
        for declaration: VariableDeclSyntax
    ) -> DependencyGraphProvider.SourceLocation {
        let location = sourceLocationConverter?.location(
            for: declaration.positionAfterSkippingLeadingTrivia
        )
        return DependencyGraphProvider.SourceLocation(
            path: currentRelativeFilePath,
            line: location?.line ?? 1,
            column: location?.column ?? 1
        )
    }
}
