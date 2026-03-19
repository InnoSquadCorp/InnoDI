import InnoDICore
import SwiftSyntax

struct SemanticContainerReferenceIssue: Hashable {
    let sourceID: String
    let destinationDisplayName: String
    let state: SemanticResolutionState
    let destinationCandidates: [String]
    let excludedReason: String?
    let aliasExpansionTrace: [String]
    let usedSuffixFallback: Bool
}

final class ContainerUsageCollector: SyntaxVisitor, DeclarationPathTracking {
    private struct DeclarationEntry {
        let isContainer: Bool
        let containerID: String?
    }

    let allContainerIDsBySemanticPath: [String: [String]]
    let eligibleContainerIDsBySemanticPath: [String: [String]]
    let semanticResolver: SemanticResolverIndex
    var edges: [DependencyGraphEdge] = []
    var semanticIssues: [SemanticContainerReferenceIssue] = []
    var fallbackMatchedReferences: [String] = []

    private var currentRelativeFilePath: String = ""
    var declarationPath: [String] = []
    private var activeDeclarations: [DeclarationEntry] = []

    init(
        allContainerIDsBySemanticPath: [String: [String]],
        eligibleContainerIDsBySemanticPath: [String: [String]],
        semanticResolver: SemanticResolverIndex,
        viewMode: SyntaxTreeViewMode = .sourceAccurate
    ) {
        self.allContainerIDsBySemanticPath = allContainerIDsBySemanticPath
        self.eligibleContainerIDsBySemanticPath = eligibleContainerIDsBySemanticPath
        self.semanticResolver = semanticResolver
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
        guard let sourceID = activeContainerID else {
            return .visitChildren
        }

        guard let destinationID = calledContainerID(node.calledExpression, sourceID: sourceID) else {
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
        activeDeclarations.removeAll(keepingCapacity: true)
        walk(tree)
    }

    private func beginContainerCandidateDeclaration(name: String, attributes: AttributeListSyntax?) -> SyntaxVisitorContinueKind {
        let isContainer = parseDIContainerAttribute(attributes) != nil
        return beginDeclaration(name: name, isContainer: isContainer)
    }

    private func beginDeclaration(name: String, isContainer: Bool) -> SyntaxVisitorContinueKind {
        beginDeclarationContext(named: name)
        let containerID = isContainer
            ? GraphIdentity.makeContainerID(fileRelativePath: currentRelativeFilePath, declarationPath: declarationPath)
            : nil
        activeDeclarations.append(DeclarationEntry(isContainer: isContainer, containerID: containerID))

        return .visitChildren
    }

    private func endDeclaration() {
        _ = activeDeclarations.popLast()
        _ = endDeclarationContext()
    }

    private var activeContainerID: String? {
        for entry in activeDeclarations.reversed() where entry.isContainer {
            if let containerID = entry.containerID {
                return containerID
            }
        }
        return nil
    }

    private func calledContainerID(_ expr: ExprSyntax, sourceID: String) -> String? {
        guard let reference = normalizedSemanticExpressionReference(expr) else {
            return nil
        }

        let resolution = semanticResolver.resolvePath(
            for: reference,
            candidatePaths: Set(allContainerIDsBySemanticPath.keys)
        )

        switch resolution.state {
        case .resolved:
            guard let resolvedPath = resolution.resolvedPath,
                  let allCandidateIDs = allContainerIDsBySemanticPath[resolvedPath] else {
                return nil
            }
            let candidateIDs = eligibleContainerIDsBySemanticPath[resolvedPath] ?? []
            if candidateIDs.isEmpty && !allCandidateIDs.isEmpty {
                return nil
            }

            if candidateIDs.count > 1 {
                semanticIssues.append(
                    SemanticContainerReferenceIssue(
                        sourceID: sourceID,
                        destinationDisplayName: reference.displayPath,
                        state: .ambiguous,
                        destinationCandidates: candidateIDs,
                        excludedReason: nil,
                        aliasExpansionTrace: resolution.aliasExpansionTrace,
                        usedSuffixFallback: resolution.usedSuffixFallback
                    )
                )
                return nil
            }

            if resolution.usedSuffixFallback {
                fallbackMatchedReferences.append("\(sourceID) -> \(reference.displayPath)")
            }
            return candidateIDs[0]
        case .ambiguous:
            let eligibleCandidates = resolution.candidates.flatMap { eligibleContainerIDsBySemanticPath[$0] ?? [] }.sorted()
            if eligibleCandidates.isEmpty {
                return nil
            }
            if eligibleCandidates.count == 1 {
                return eligibleCandidates[0]
            }
            semanticIssues.append(
                SemanticContainerReferenceIssue(
                    sourceID: sourceID,
                    destinationDisplayName: reference.displayPath,
                    state: .ambiguous,
                    destinationCandidates: eligibleCandidates,
                    excludedReason: nil,
                    aliasExpansionTrace: resolution.aliasExpansionTrace,
                    usedSuffixFallback: resolution.usedSuffixFallback
                )
            )
            return nil
        case .excluded, .unresolved:
            semanticIssues.append(
                SemanticContainerReferenceIssue(
                    sourceID: sourceID,
                    destinationDisplayName: reference.displayPath,
                    state: resolution.state,
                    destinationCandidates: resolution.candidates,
                    excludedReason: resolution.excludedReason,
                    aliasExpansionTrace: resolution.aliasExpansionTrace,
                    usedSuffixFallback: resolution.usedSuffixFallback
                )
            )
            return nil
        }
    }

    private func edgeLabel(from arguments: LabeledExprListSyntax) -> String? {
        guard let first = arguments.first else { return nil }
        return first.label?.text
    }
}
