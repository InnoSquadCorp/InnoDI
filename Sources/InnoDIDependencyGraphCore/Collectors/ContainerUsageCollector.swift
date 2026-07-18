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

struct GraphContainerResolution {
    let state: SemanticResolutionState
    let allCandidateIDs: [String]
    let eligibleCandidateIDs: [String]
    let excludedReason: String?
    let aliasExpansionTrace: [String]
    let usedSuffixFallback: Bool
    let requiresDiagnostic: Bool

    init(
        state: SemanticResolutionState,
        allCandidateIDs: [String],
        eligibleCandidateIDs: [String],
        excludedReason: String?,
        aliasExpansionTrace: [String],
        usedSuffixFallback: Bool,
        requiresDiagnostic: Bool = false
    ) {
        self.state = state
        self.allCandidateIDs = allCandidateIDs
        self.eligibleCandidateIDs = eligibleCandidateIDs
        self.excludedReason = excludedReason
        self.aliasExpansionTrace = aliasExpansionTrace
        self.usedSuffixFallback = usedSuffixFallback
        self.requiresDiagnostic = requiresDiagnostic
    }

    static func unresolved(
        aliasExpansionTrace: [String] = []
    ) -> Self {
        Self(
            state: .unresolved,
            allCandidateIDs: [],
            eligibleCandidateIDs: [],
            excludedReason: nil,
            aliasExpansionTrace: aliasExpansionTrace,
            usedSuffixFallback: false
        )
    }

    static func excluded(
        reason: String,
        aliasExpansionTrace: [String]
    ) -> Self {
        Self(
            state: .excluded,
            allCandidateIDs: [],
            eligibleCandidateIDs: [],
            excludedReason: reason,
            aliasExpansionTrace: aliasExpansionTrace,
            usedSuffixFallback: false,
            requiresDiagnostic: true
        )
    }
}

struct GraphContainerResolver {
    private let resolution: (SemanticTypeReference) -> GraphContainerResolution

    init(
        resolution: @escaping (SemanticTypeReference) -> GraphContainerResolution
    ) {
        self.resolution = resolution
    }

    func resolve(
        _ reference: SemanticTypeReference
    ) -> GraphContainerResolution {
        resolution(reference)
    }

    static func legacy(
        allContainerIDsBySemanticPath: [String: [String]],
        eligibleContainerIDsBySemanticPath: [String: [String]],
        semanticResolver: SemanticResolverIndex
    ) -> Self {
        let candidatePaths = Set(allContainerIDsBySemanticPath.keys)
        return Self { reference in
            let semanticResolution = semanticResolver.resolvePath(
                for: reference,
                candidatePaths: candidatePaths
            )
            let matchingPaths: [String]
            switch semanticResolution.state {
            case .resolved:
                matchingPaths = semanticResolution.resolvedPath.map { [$0] }
                    ?? []
            case .ambiguous:
                matchingPaths = semanticResolution.candidates
            case .excluded, .unresolved:
                matchingPaths = []
            }

            return GraphContainerResolution(
                state: semanticResolution.state,
                allCandidateIDs: uniqueSortedIDs(
                    matchingPaths.flatMap {
                        allContainerIDsBySemanticPath[$0] ?? []
                    }
                ),
                eligibleCandidateIDs: uniqueSortedIDs(
                    matchingPaths.flatMap {
                        eligibleContainerIDsBySemanticPath[$0] ?? []
                    }
                ),
                excludedReason: semanticResolution.excludedReason,
                aliasExpansionTrace: semanticResolution.aliasExpansionTrace,
                usedSuffixFallback: semanticResolution.usedSuffixFallback
            )
        }
    }
}

private func uniqueSortedIDs(_ values: [String]) -> [String] {
    Array(Set(values)).sorted()
}

func resolveContainerReferenceID(
    reference: SemanticTypeReference,
    sourceID: String,
    resolver: GraphContainerResolver,
    semanticIssues: inout [SemanticContainerReferenceIssue],
    fallbackMatchedReferences: inout [String]
) -> String? {
    let resolution = resolver.resolve(reference)

    switch resolution.state {
    case .resolved:
        let allCandidateIDs = resolution.allCandidateIDs
        guard !allCandidateIDs.isEmpty else {
            return nil
        }
        let candidateIDs = resolution.eligibleCandidateIDs
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
        let eligibleCandidates = resolution.eligibleCandidateIDs
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
                destinationCandidates: resolution.allCandidateIDs,
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
        let isContainerBoundary: Bool
        let containerID: String?
    }

    let referenceResolver: GraphContainerResolver
    var edges: [DependencyGraphEdge] = []
    var semanticIssues: [SemanticContainerReferenceIssue] = []
    var fallbackMatchedReferences: [String] = []

    private let moduleIdentity: String?
    private var currentRelativeFilePath: String = ""
    var declarationPath: [String] = []
    private var activeDeclarations: [DeclarationEntry] = []

    init(
        allContainerIDsBySemanticPath: [String: [String]],
        eligibleContainerIDsBySemanticPath: [String: [String]],
        semanticResolver: SemanticResolverIndex,
        viewMode: SyntaxTreeViewMode = .sourceAccurate
    ) {
        moduleIdentity = nil
        self.referenceResolver = .legacy(
            allContainerIDsBySemanticPath: allContainerIDsBySemanticPath,
            eligibleContainerIDsBySemanticPath: eligibleContainerIDsBySemanticPath,
            semanticResolver: semanticResolver
        )
        super.init(viewMode: viewMode)
    }

    init(
        referenceResolver: GraphContainerResolver,
        moduleIdentity: String? = nil,
        viewMode: SyntaxTreeViewMode = .sourceAccurate
    ) {
        self.moduleIdentity = moduleIdentity
        self.referenceResolver = referenceResolver
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
        beginContainerCandidateDeclaration(node, name: node.name.text)
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        endDeclaration()
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        beginContainerCandidateDeclaration(node, name: node.name.text)
    }

    override func visitPost(_ node: ProtocolDeclSyntax) {
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
        let isContainerBoundary = parseDIContainerAttribute(node.attributes) != nil
        let isContainer = isContainerBoundary
            && classifyDIContainerDeclaration(node).isSupported
        let continueKind = beginDeclaration(
            name: name,
            isContainerBoundary: isContainerBoundary,
            isContainer: isContainer
        )

        if isContainer, let sourceID = activeContainerID {
            collectDeferredEdges(in: node, sourceID: sourceID)
        }

        return continueKind
    }

    private func beginDeclaration(
        name: String,
        isContainerBoundary: Bool,
        isContainer: Bool
    ) -> SyntaxVisitorContinueKind {
        beginDeclarationContext(named: name)
        let containerID = isContainer
            ? GraphIdentity.makeContainerID(
                fileRelativePath: currentRelativeFilePath,
                declarationPath: declarationPath,
                moduleIdentity: moduleIdentity
            )
            : nil
        activeDeclarations.append(
            DeclarationEntry(
                isContainerBoundary: isContainerBoundary,
                containerID: containerID
            )
        )

        return .visitChildren
    }

    private func endDeclaration() {
        _ = activeDeclarations.popLast()
        _ = endDeclarationContext()
    }

    private var activeContainerID: String? {
        for entry in activeDeclarations.reversed() {
            if entry.isContainerBoundary {
                return entry.containerID
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
            resolver: referenceResolver,
            semanticIssues: &semanticIssues,
            fallbackMatchedReferences: &fallbackMatchedReferences
        )
    }

    private func collectDeferredEdges(in node: some DeclGroupSyntax, sourceID: String) {
        for reference in deferredEdgeReferences(in: node) {
            guard let targetReference = reference.targetReference else {
                continue
            }
            guard let destinationID = collectableDeferredContainerID(
                targetReference,
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

    private func collectableDeferredContainerID(_ reference: SemanticTypeReference, sourceID: String) -> String? {
        let resolution = referenceResolver.resolve(reference)

        switch resolution.state {
        case .resolved:
            let allCandidateIDs = resolution.allCandidateIDs
            let eligibleIDs = resolution.eligibleCandidateIDs
            guard allCandidateIDs.isEmpty == false,
                  eligibleIDs.count == 1 else {
                return nil
            }

            if resolution.usedSuffixFallback {
                fallbackMatchedReferences.append("\(sourceID) -> \(reference.displayPath)")
            }
            return eligibleIDs[0]
        case .ambiguous:
            return nil
        case .excluded:
            if resolution.requiresDiagnostic {
                semanticIssues.append(
                    SemanticContainerReferenceIssue(
                        sourceID: sourceID,
                        destinationDisplayName: reference.displayPath,
                        state: .excluded,
                        destinationCandidates: resolution.allCandidateIDs,
                        excludedReason: resolution.excludedReason,
                        aliasExpansionTrace: resolution.aliasExpansionTrace,
                        usedSuffixFallback: resolution.usedSuffixFallback
                    )
                )
            }
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
                    destinationCandidates: resolution.allCandidateIDs,
                    excludedReason: resolution.excludedReason,
                    aliasExpansionTrace: resolution.aliasExpansionTrace,
                    usedSuffixFallback: resolution.usedSuffixFallback
                )
            )
            return nil
        }
    }

    private func deferredEdgeReferences(
        in node: some DeclGroupSyntax
    ) -> [FactoryDependencyReference] {
        let references = node.memberBlock.members.flatMap { member in
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  !variable.modifiers.contains(where: { $0.name.text == "static" }),
                  let attribute = findInnoDIAttribute(named: "Provide", in: variable.attributes),
                  let binding = variable.bindings.first,
                  binding.pattern.is(IdentifierPatternSyntax.self),
                  binding.typeAnnotation != nil else {
                return [FactoryDependencyReference]()
            }

            let provideArguments = parseProvideArguments(attribute)
            return [
                provideArguments.factoryExpr,
                provideArguments.asyncFactoryExpr,
            ]
            .compactMap { $0 }
            .flatMap { managedFactoryDependencyReferences(in: $0) ?? [] }
            .filter { $0.kind != .hard && $0.targetReference != nil }
        }

        var seen: Set<String> = []
        return references.filter { reference in
            guard let targetReference = reference.targetReference else {
                return false
            }
            let key = "\(reference.kind.rawValue):\(targetReference.displayPath)"
            return seen.insert(key).inserted
        }
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

        let resolution = referenceResolver.resolve(calledReference)
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
