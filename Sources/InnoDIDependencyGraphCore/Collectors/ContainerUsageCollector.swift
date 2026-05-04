import InnoDICore
import SwiftSyntax

struct SemanticContainerReferenceIssue: Hashable, Sendable {
    let sourceID: String
    let destinationDisplayName: String
    let state: SemanticResolutionState
    let destinationCandidates: [String]
    let excludedReason: String?
    let aliasExpansionTrace: [String]
    let usedSuffixFallback: Bool
}

func resolveContainerReferenceID(
    reference: SemanticTypeReference,
    sourceID: String,
    candidatePaths: Set<String>,
    allContainerIDsBySemanticPath: [String: [String]],
    eligibleContainerIDsBySemanticPath: [String: [String]],
    semanticResolver: SemanticResolverIndex,
    semanticIssues: inout [SemanticContainerReferenceIssue],
    fallbackMatchedReferences: inout [String]
) -> String? {
    let resolution = semanticResolver.resolvePath(
        for: reference,
        candidatePaths: candidatePaths
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

final class ContainerUsageCollector: SyntaxVisitor, DeclarationPathTracking {
    private struct DeclarationEntry {
        let isContainer: Bool
        let containerID: String?
    }

    private struct ProvideMemberRecord {
        let name: String
        let factoryClosure: ClosureExprSyntax?
        let asyncFactoryClosure: ClosureExprSyntax?
    }

    private struct DeferredEdgeReference {
        let targetReference: SemanticTypeReference
        let kind: DeferredDependencyWrapperKind
    }

    let allContainerIDsBySemanticPath: [String: [String]]
    let eligibleContainerIDsBySemanticPath: [String: [String]]
    let semanticResolver: SemanticResolverIndex
    private let candidatePaths: Set<String>
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
        self.candidatePaths = Set(allContainerIDsBySemanticPath.keys)
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        beginContainerCandidateDeclaration(node, name: node.name.text)
    }

    override func visitPost(_ node: StructDeclSyntax) {
        endDeclaration()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        beginContainerCandidateDeclaration(node, name: node.name.text)
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        endDeclaration()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        beginContainerCandidateDeclaration(node, name: node.name.text)
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

        guard shouldCollectContainerReference(for: node) else {
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

    private func beginContainerCandidateDeclaration(_ node: some DeclGroupSyntax, name: String) -> SyntaxVisitorContinueKind {
        let isContainer = parseDIContainerAttribute(node.attributes) != nil
        let continueKind = beginDeclaration(name: name, isContainer: isContainer)

        if isContainer, let sourceID = activeContainerID {
            collectDeferredEdges(in: node, sourceID: sourceID)
        }

        return continueKind
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

        return resolvedContainerID(reference, sourceID: sourceID)
    }

    private func resolvedContainerID(_ reference: SemanticTypeReference, sourceID: String) -> String? {
        resolveContainerReferenceID(
            reference: reference,
            sourceID: sourceID,
            candidatePaths: candidatePaths,
            allContainerIDsBySemanticPath: allContainerIDsBySemanticPath,
            eligibleContainerIDsBySemanticPath: eligibleContainerIDsBySemanticPath,
            semanticResolver: semanticResolver,
            semanticIssues: &semanticIssues,
            fallbackMatchedReferences: &fallbackMatchedReferences
        )
    }

    private func collectDeferredEdges(in node: some DeclGroupSyntax, sourceID: String) {
        let provideMembers = provideMemberRecords(in: node)

        for member in provideMembers {
            let deferredReferences = deferredEdgeReferences(for: member)
            for reference in deferredReferences {
                guard let destinationID = collectableDeferredContainerID(
                    reference.targetReference,
                    sourceID: sourceID
                ),
                      destinationID != sourceID else {
                    continue
                }

                edges.append(
                    DependencyGraphEdge(
                        fromID: sourceID,
                        toID: destinationID,
                        label: nil,
                        isSoft: reference.kind == .lazy,
                        isProvider: reference.kind == .provider
                    )
                )
            }
        }
    }

    private func collectableDeferredContainerID(_ reference: SemanticTypeReference, sourceID: String) -> String? {
        let resolution = semanticResolver.resolvePath(for: reference, candidatePaths: candidatePaths)

        switch resolution.state {
        case .resolved:
            guard let resolvedPath = resolution.resolvedPath,
                  let allCandidateIDs = allContainerIDsBySemanticPath[resolvedPath] else {
                return nil
            }

            let eligibleIDs = eligibleContainerIDsBySemanticPath[resolvedPath] ?? []
            guard allCandidateIDs.isEmpty == false,
                  eligibleIDs.count == 1 else {
                return nil
            }

            if resolution.usedSuffixFallback {
                fallbackMatchedReferences.append("\(sourceID) -> \(reference.displayPath)")
            }
            return eligibleIDs[0]
        case .ambiguous, .excluded:
            return nil
        case .unresolved:
            guard reference.components.last?.hasSuffix("Container") == true else {
                return nil
            }

            semanticIssues.append(
                SemanticContainerReferenceIssue(
                    sourceID: sourceID,
                    destinationDisplayName: reference.displayPath,
                    state: .unresolved,
                    destinationCandidates: resolution.candidates,
                    excludedReason: resolution.excludedReason,
                    aliasExpansionTrace: resolution.aliasExpansionTrace,
                    usedSuffixFallback: resolution.usedSuffixFallback
                )
            )
            return nil
        }
    }

    private func provideMemberRecords(in node: some DeclGroupSyntax) -> [ProvideMemberRecord] {
        node.memberBlock.members.compactMap { member in
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  !variable.modifiers.contains(where: { $0.name.text == "static" }),
                  let attribute = findInnoDIAttribute(named: "Provide", in: variable.attributes),
                  let binding = variable.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                  binding.typeAnnotation != nil else {
                return nil
            }

            let provideArguments = parseProvideArguments(attribute)
            return ProvideMemberRecord(
                name: identifier.identifier.text,
                factoryClosure: provideArguments.factoryExpr?.as(ClosureExprSyntax.self),
                asyncFactoryClosure: provideArguments.asyncFactoryExpr?.as(ClosureExprSyntax.self)
            )
        }
    }

    private func deferredEdgeReferences(for member: ProvideMemberRecord) -> [DeferredEdgeReference] {
        let closures = [member.factoryClosure, member.asyncFactoryClosure].compactMap { $0 }
        return deduplicateDeferredEdgeReferences(
            closures.flatMap(deferredEdgeReferences(in:))
        )
    }

    private func deferredEdgeReferences(in closure: ClosureExprSyntax) -> [DeferredEdgeReference] {
        guard let signature = closure.signature,
              let parameterClause = signature.parameterClause else {
            return []
        }

        switch parameterClause {
        case .simpleInput:
            return []
        case .parameterClause(let parameters):
            return parameters.parameters.compactMap { parameter in
                let token = parameter.secondName ?? parameter.firstName
                guard token.text != "_",
                      let kind = deferredDependencyWrapperKind(for: parameter.type),
                      let targetReference = deferredDependencyWrappedTypeReference(parameter.type) else {
                    return nil
                }
                return DeferredEdgeReference(targetReference: targetReference, kind: kind)
            }
        }
    }

    private func deduplicateDeferredEdgeReferences(_ references: [DeferredEdgeReference]) -> [DeferredEdgeReference] {
        var seen: Set<String> = []
        var result: [DeferredEdgeReference] = []

        for reference in references {
            let key = "\(reference.kind.rawValue):\(reference.targetReference.displayPath)"
            if seen.insert(key).inserted {
                result.append(reference)
            }
        }

        return result
    }

    private func edgeLabel(from arguments: LabeledExprListSyntax) -> String? {
        guard let first = arguments.first else { return nil }
        return first.label?.text
    }

    private func shouldCollectContainerReference(for node: FunctionCallExprSyntax) -> Bool {
        guard isInsideProvideAttribute(Syntax(node)),
              let calledReference = normalizedSemanticExpressionReference(node.calledExpression) else {
            return false
        }

        let resolution = semanticResolver.resolvePath(for: calledReference, candidatePaths: candidatePaths)
        switch resolution.state {
        case .resolved, .ambiguous:
            return true
        case .excluded:
            return true
        case .unresolved:
            break
        }

        guard let propertyTypeReference = enclosingProvideBindingTypeReference(from: Syntax(node)),
              propertyTypeReference.displayPath == calledReference.displayPath,
              calledReference.components.last?.hasSuffix("Container") == true else {
            return false
        }

        return true
    }

    private func isInsideProvideAttribute(_ syntax: Syntax) -> Bool {
        var current = syntax.parent
        while let node = current {
            if let attribute = node.as(AttributeSyntax.self),
               matchesInnoDIAttribute(named: "Provide", attributeName: attribute.attributeName) {
                return true
            }
            current = node.parent
        }
        return false
    }

    private func enclosingProvideBindingTypeReference(from syntax: Syntax) -> SemanticTypeReference? {
        var current = syntax.parent
        while let node = current {
            if let variable = node.as(VariableDeclSyntax.self),
               parseProvideAttribute(variable.attributes) != nil,
               let binding = variable.bindings.first,
               let typeAnnotation = binding.typeAnnotation {
                return normalizedSemanticTypeReference(typeAnnotation.type)
            }
            current = node.parent
        }
        return nil
    }
}
