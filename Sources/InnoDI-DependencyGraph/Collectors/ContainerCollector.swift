import InnoDICore
import SwiftSyntax

/// A pending ownership reference discovered inside a `@DIContainer` body:
/// "this parent owns a child container of this written type". The type
/// description is whatever the author wrote at the `@SubContainer` property
/// site — `FeatureContainer`, `Feature.Container`, `NestedModule.Scope`,
/// etc. The CLI resolves these into concrete parent→child container IDs
/// after every container has been catalogued.
struct PendingSubContainerReference {
    /// Stable ID of the parent container node.
    let parentID: String
    /// Dotted semantic path of the parent container (used for diagnostics
    /// and disambiguation when the same type name appears under multiple
    /// namespaces).
    let parentSemanticPath: String
    /// Parent member name (e.g. `feature`) — threaded into the edge label
    /// so "owns" edges are readable in the graph.
    let memberName: String
    /// Type text as written at the `@SubContainer` declaration, before
    /// type resolution (`"FeatureContainer"`, `"Foo.Bar"`, …).
    let childTypeText: String
}

final class ContainerCollector: SyntaxVisitor, DeclarationPathTracking {
    var nodes: [DependencyGraphNode] = []
    var typeAliases: [SemanticTypeAliasRecord] = []
    /// `@SubContainer` references collected while walking each container
    /// body. Resolved into graph edges by `resolveSubContainerReferences`
    /// once every container has been visited.
    var subContainerReferences: [PendingSubContainerReference] = []

    private var currentRelativeFilePath: String = ""
    var declarationPath: [String] = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
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
        beginDeclarationContext(named: node.name.text)
        return .visitChildren
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
        let semanticPath = declarationPath.joined(separator: ".")
        let parentID = GraphIdentity.makeContainerID(
            fileRelativePath: currentRelativeFilePath,
            declarationPath: declarationPath
        )

        var requiredInputs: [String] = []
        for member in node.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }

            // `@SubContainer` ownership edge collection. Parent/child IDs
            // stay unresolved at this stage — the AppMain pass matches the
            // child's written type description against every known container
            // node's semantic path after the full file set has been walked.
            if parseSubContainerAttribute(varDecl.attributes) != nil {
                guard let binding = varDecl.bindings.first,
                      let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                      let typeAnnotation = binding.typeAnnotation else {
                    continue
                }
                subContainerReferences.append(
                    PendingSubContainerReference(
                        parentID: parentID,
                        parentSemanticPath: semanticPath,
                        memberName: pattern.identifier.text,
                        childTypeText: typeAnnotation.type.trimmedDescription
                    )
                )
                continue
            }

            guard let provide = parseProvideAttribute(varDecl.attributes), provide.scope == .input else { continue }
            guard let binding = varDecl.bindings.first,
                  let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                continue
            }
            requiredInputs.append(pattern.identifier.text)
        }

        nodes.append(
            DependencyGraphNode(
                id: parentID,
                displayName: displayName,
                semanticPath: semanticPath,
                isRoot: containerAttr.root,
                validateDAG: containerAttr.validateDAG,
                requiredInputs: requiredInputs
            )
        )
    }
}
