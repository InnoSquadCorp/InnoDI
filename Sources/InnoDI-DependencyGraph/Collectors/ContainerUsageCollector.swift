import InnoDICore
import SwiftSyntax

final class ContainerUsageCollector: SyntaxVisitor, DeclarationPathTracking {
    let containerIDsByDisplayName: [String: [String]]
    var edges: [DependencyGraphEdge] = []

    private var currentRelativeFilePath: String = ""
    var declarationPath: [String] = []
    private var activeContainerIDs: [String] = []
    private var activeContainerMarkers: [Bool] = []

    init(containerIDsByDisplayName: [String: [String]], viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        self.containerIDsByDisplayName = containerIDsByDisplayName
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        beginContainerCandidateDeclaration(name: node.name.text, attributes: node.attributes)
    }

    override func visitPost(_ node: StructDeclSyntax) {
        endDeclaration()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        beginContainerCandidateDeclaration(name: node.name.text, attributes: node.attributes)
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        endDeclaration()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        beginContainerCandidateDeclaration(name: node.name.text, attributes: node.attributes)
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        endDeclaration()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        beginDeclaration(name: node.name.text, isContainer: false)
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        endDeclaration()
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let sourceID = activeContainerIDs.last,
              let destinationID = calledContainerID(node.calledExpression) else {
            return .visitChildren
        }

        edges.append(
            DependencyGraphEdge(
                fromID: sourceID,
                toID: destinationID,
                label: edgeLabel(from: node.arguments)
            )
        )

        return .visitChildren
    }

    func walkFile(relativePath: String, tree: SourceFileSyntax) {
        currentRelativeFilePath = relativePath
        declarationPath.removeAll(keepingCapacity: true)
        activeContainerIDs.removeAll(keepingCapacity: true)
        activeContainerMarkers.removeAll(keepingCapacity: true)
        walk(tree)
    }

    private func beginContainerCandidateDeclaration(name: String, attributes: AttributeListSyntax?) -> SyntaxVisitorContinueKind {
        let isContainer = parseDIContainerAttribute(attributes) != nil
        return beginDeclaration(name: name, isContainer: isContainer)
    }

    private func beginDeclaration(name: String, isContainer: Bool) -> SyntaxVisitorContinueKind {
        pushDeclarationContext(named: name)
        activeContainerMarkers.append(isContainer)

        if isContainer {
            let id = makeContainerID(fileRelativePath: currentRelativeFilePath, declarationPath: declarationPath)
            activeContainerIDs.append(id)
        }

        return .visitChildren
    }

    private func endDeclaration() {
        if activeContainerMarkers.popLast() == true {
            _ = activeContainerIDs.popLast()
        }
        _ = popDeclarationContext()
    }

    private func calledContainerID(_ expr: ExprSyntax) -> String? {
        let raw = expr.trimmedDescription
        let lastComponent = raw.split(separator: ".").last ?? ""
        let base = lastComponent.split(separator: "<").first ?? lastComponent
        let displayName = String(base)

        guard let candidateIDs = containerIDsByDisplayName[displayName], candidateIDs.count == 1 else {
            return nil
        }

        return candidateIDs[0]
    }

    private func edgeLabel(from arguments: LabeledExprListSyntax) -> String? {
        guard let first = arguments.first else { return nil }
        return first.label?.text
    }
}
