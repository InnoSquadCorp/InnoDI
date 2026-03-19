import InnoDICore
import SwiftSyntax

final class ContainerCollector: SyntaxVisitor, DeclarationPathTracking {
    var nodes: [DependencyGraphNode] = []
    var typeAliases: [SemanticTypeAliasRecord] = []

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

        var requiredInputs: [String] = []
        for member in node.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            guard let provide = parseProvideAttribute(varDecl.attributes), provide.scope == .input else { continue }
            guard let binding = varDecl.bindings.first,
                  let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                continue
            }
            requiredInputs.append(pattern.identifier.text)
        }

        let id = GraphIdentity.makeContainerID(fileRelativePath: currentRelativeFilePath, declarationPath: declarationPath)
        nodes.append(
            DependencyGraphNode(
                id: id,
                displayName: displayName,
                semanticPath: semanticPath,
                isRoot: containerAttr.root,
                validateDAG: containerAttr.validateDAG,
                requiredInputs: requiredInputs
            )
        )
    }
}
