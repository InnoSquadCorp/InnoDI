import InnoDICore
import SwiftSyntax

struct AmbiguousContainerReference: Hashable {
    let sourceID: String
    let destinationDisplayName: String
}

final class ContainerUsageCollector: SyntaxVisitor, DeclarationPathTracking {
    private struct DeclarationEntry {
        let isContainer: Bool
        let containerID: String?
    }

    let containerIDsByDisplayName: [String: [String]]
    var edges: [DependencyGraphEdge] = []
    var ambiguousReferences: [AmbiguousContainerReference] = []

    private var currentRelativeFilePath: String = ""
    var declarationPath: [String] = []
    private var activeDeclarations: [DeclarationEntry] = []

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
        guard let displayName = calledContainerDisplayName(from: expr) else {
            return nil
        }

        guard let candidateIDs = containerIDsByDisplayName[displayName] else {
            return nil
        }

        if candidateIDs.count > 1 {
            ambiguousReferences.append(
                AmbiguousContainerReference(
                    sourceID: sourceID,
                    destinationDisplayName: displayName
                )
            )
            return nil
        }

        return candidateIDs[0]
    }

    private func calledContainerDisplayName(from expr: ExprSyntax) -> String? {
        if let declReference = expr.as(DeclReferenceExprSyntax.self) {
            return declReference.baseName.text
        }

        if let memberAccess = expr.as(MemberAccessExprSyntax.self) {
            let memberName = memberAccess.declName.baseName.text
            if memberName == "init", let base = memberAccess.base {
                return calledContainerDisplayName(from: base)
            }
            if memberName == "self", let base = memberAccess.base {
                return calledContainerDisplayName(from: base)
            }
            return memberName
        }

        if let genericSpecialization = expr.as(GenericSpecializationExprSyntax.self) {
            return calledContainerDisplayName(from: genericSpecialization.expression)
        }

        if let functionCall = expr.as(FunctionCallExprSyntax.self) {
            return calledContainerDisplayName(from: functionCall.calledExpression)
        }

        if let forceUnwrap = expr.as(ForceUnwrapExprSyntax.self) {
            return calledContainerDisplayName(from: forceUnwrap.expression)
        }

        if let optionalChaining = expr.as(OptionalChainingExprSyntax.self) {
            return calledContainerDisplayName(from: optionalChaining.expression)
        }

        if let tryExpr = expr.as(TryExprSyntax.self) {
            return calledContainerDisplayName(from: tryExpr.expression)
        }

        if let awaitExpr = expr.as(AwaitExprSyntax.self) {
            return calledContainerDisplayName(from: awaitExpr.expression)
        }

        return nil
    }

    private func edgeLabel(from arguments: LabeledExprListSyntax) -> String? {
        guard let first = arguments.first else { return nil }
        return first.label?.text
    }
}
