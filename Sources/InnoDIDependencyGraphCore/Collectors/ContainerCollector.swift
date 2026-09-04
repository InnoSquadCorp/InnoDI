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

    private let moduleIdentity: String?
    private var currentRelativeFilePath: String = ""
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

            // `@SubContainer` ownership edge collection. Parent/child IDs
            // stay unresolved at this stage — the AppMain pass feeds the
            // child's semantic reference through the shared resolver after
            // the full file set has been walked so ownership edges follow
            // the same alias/suffix/ambiguity policy as regular container
            // references.
            if parseSubContainerAttribute(varDecl.attributes) != nil {
                guard let binding = varDecl.bindings.first,
                      let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                      let typeAnnotation = binding.typeAnnotation else {
                    continue
                }
                let childType = typeAnnotation.type.trimmedDescription
                subContainerReferences.append(
                    PendingSubContainerReference(
                        parentID: parentID,
                        parentSemanticPath: semanticPath,
                        memberName: pattern.identifier.text,
                        childDisplayName: childType,
                        childReference: normalizedSemanticTypeReference(typeAnnotation.type),
                        ownershipKind: .subContainer
                    )
                )
                continue
            }

            guard let provide = parseProvideAttribute(varDecl.attributes)
            else { continue }
            guard let binding = varDecl.bindings.first,
                  let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                continue
            }

            if let childType = provide.assistedFactoryChildType {
                subContainerReferences.append(
                    PendingSubContainerReference(
                        parentID: parentID,
                        parentSemanticPath: semanticPath,
                        memberName: pattern.identifier.text,
                        childDisplayName: childType.trimmedDescription,
                        childReference: normalizedSemanticTypeReference(
                            childType
                        ),
                        ownershipKind: .assistedFactory
                    )
                )
                continue
            }

            if provide.isMultibinding {
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
}
