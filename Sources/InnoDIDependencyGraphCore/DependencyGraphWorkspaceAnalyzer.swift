import Foundation
import InnoDICore
import InnoDIWorkspaceAnalysis

package struct DependencyGraphAnalysis {
    package let nodes: [DependencyGraphNode]
    package let edges: [DependencyGraphEdge]

    package init(nodes: [DependencyGraphNode], edges: [DependencyGraphEdge]) {
        self.nodes = nodes
        self.edges = edges
    }
}

package struct DependencyGraphCommandResult: Equatable, Sendable {
    package let exitCode: Int32
    package let stdout: String
    package let stderr: String

    package init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

package enum DependencyGraphCoreExitCode {
    package static let success: Int32 = 0
    package static let dagValidationFailure: Int32 = 3
}

package func collectDependencyGraph(
    snapshot: WorkspaceSourceSnapshot,
    validateDAG: Bool
) -> DependencyGraphAnalysis {
    let collection = collectDependencyGraphWithDiagnostics(
        snapshot: snapshot,
        validateDAG: validateDAG
    )
    return DependencyGraphAnalysis(nodes: collection.nodes, edges: collection.edges)
}

package func collectRenderableDependencyGraph(
    snapshot: WorkspaceSourceSnapshot,
    validateDAG: Bool
) -> DependencyGraphAnalysis {
    let analysis = collectDependencyGraph(snapshot: snapshot, validateDAG: validateDAG)
    let rendered = rootPrunedRenderGraph(nodes: analysis.nodes, edges: analysis.edges)
    return DependencyGraphAnalysis(nodes: rendered.nodes, edges: rendered.edges)
}

package func validateDependencyGraph(snapshot: WorkspaceSourceSnapshot) -> DependencyGraphCommandResult {
    let collection = collectDependencyGraphWithDiagnostics(snapshot: snapshot, validateDAG: true)
    guard !collection.nodes.isEmpty else {
        return DependencyGraphCommandResult(
            exitCode: DependencyGraphCoreExitCode.success,
            stdout: "DAG validation passed (no @DIContainer declarations found).\n",
            stderr: ""
        )
    }

    return validateDependencyGraph(
        nodes: collection.nodes,
        edges: collection.edges,
        semanticIssues: collection.semanticIssues
    )
}

private struct DependencyGraphDiagnosticCollection {
    let nodes: [DependencyGraphNode]
    let edges: [DependencyGraphEdge]
    let semanticIssues: [SemanticContainerReferenceIssue]
}

private func collectDependencyGraphWithDiagnostics(
    snapshot: WorkspaceSourceSnapshot,
    validateDAG: Bool
) -> DependencyGraphDiagnosticCollection {
    if let manifest = snapshot.analysisManifest {
        return collectTargetScopedDependencyGraphWithDiagnostics(
            snapshot: snapshot,
            manifest: manifest,
            validateDAG: validateDAG
        )
    }

    let collector = ContainerCollector()
    for sourceFile in snapshot.files {
        collector.walkFile(relativePath: sourceFile.relativePath, tree: sourceFile.syntax)
    }

    let nodes = normalizeNodes(collector.nodes)
    guard !nodes.isEmpty else {
        return DependencyGraphDiagnosticCollection(nodes: [], edges: [], semanticIssues: [])
    }

    let semanticResolver = SemanticResolverIndex(
        nominalTypes: nodes.map {
            SemanticNominalTypeRecord(
                path: $0.semanticPath,
                components: $0.semanticPath.split(separator: ".").map(String.init)
            )
        },
        topLevelTypeAliases: collector.typeAliases
    )
    let containerIDsBySemanticPathAll = Dictionary(grouping: nodes, by: { $0.semanticPath })
        .mapValues { group in group.map(\.id).sorted() }
    let eligibleNodes = nodes.filter(\.validateDAG)
    let containerIDsBySemanticPathEligible = Dictionary(grouping: eligibleNodes, by: { $0.semanticPath })
        .mapValues { group in group.map(\.id).sorted() }

    let usageCollector = ContainerUsageCollector(
        allContainerIDsBySemanticPath: containerIDsBySemanticPathAll,
        eligibleContainerIDsBySemanticPath: validateDAG ? containerIDsBySemanticPathEligible : containerIDsBySemanticPathAll,
        semanticResolver: semanticResolver
    )
    for sourceFile in snapshot.files {
        usageCollector.walkFile(relativePath: sourceFile.relativePath, tree: sourceFile.syntax)
    }

    var ownershipEdges: [DependencyGraphEdge] = []
    var ownershipSemanticIssues: [SemanticContainerReferenceIssue] = []
    var ownershipFallbackMatchedReferences: [String] = []
    let ownershipEligibleContainerIDsBySemanticPath = validateDAG
        ? containerIDsBySemanticPathEligible
        : containerIDsBySemanticPathAll
    let ownershipResolver = GraphContainerResolver.legacy(
        allContainerIDsBySemanticPath: containerIDsBySemanticPathAll,
        eligibleContainerIDsBySemanticPath:
            ownershipEligibleContainerIDsBySemanticPath,
        semanticResolver: semanticResolver
    )
    for reference in collector.subContainerReferences {
        guard let childReference = reference.childReference else {
            ownershipSemanticIssues.append(
                SemanticContainerReferenceIssue(
                    sourceID: reference.parentID,
                    destinationDisplayName: reference.childDisplayName,
                    state: .excluded,
                    destinationCandidates: [],
                    excludedReason: nil,
                    aliasExpansionTrace: [],
                    usedSuffixFallback: false
                )
            )
            continue
        }
        guard let resolvedID = resolveContainerReferenceID(
            reference: childReference,
            sourceID: reference.parentID,
            resolver: ownershipResolver,
            semanticIssues: &ownershipSemanticIssues,
            fallbackMatchedReferences: &ownershipFallbackMatchedReferences
        ) else {
            continue
        }
        ownershipEdges.append(
            DependencyGraphEdge(
                fromID: reference.parentID,
                toID: resolvedID,
                label: reference.memberName,
                isOwnership: true
            )
        )
    }

    return DependencyGraphDiagnosticCollection(
        nodes: nodes,
        edges: deduplicateEdges(usageCollector.edges + ownershipEdges),
        semanticIssues: usageCollector.semanticIssues + ownershipSemanticIssues
    )
}

private struct TargetScopedCollectedSource {
    let sourceFile: WorkspaceSourceFile
    let targetID: WorkspaceTargetID
    let sourceImports: TargetAwareSourceImports
    let subContainerReferences: [PendingSubContainerReference]
}

private func collectTargetScopedDependencyGraphWithDiagnostics(
    snapshot: WorkspaceSourceSnapshot,
    manifest: WorkspaceAnalysisManifest,
    validateDAG: Bool
) -> DependencyGraphDiagnosticCollection {
    var collectedSources: [TargetScopedCollectedSource] = []
    var rawNodesByTargetID: [
        WorkspaceTargetID: [DependencyGraphNode]
    ] = [:]
    var aliasesByTargetID: [
        WorkspaceTargetID: [TargetAwareContainerAlias]
    ] = [:]
    var exportedImportsByTargetID: [
        WorkspaceTargetID: TargetAwareSourceImports
    ] = [:]

    for sourceFile in snapshot.files.sorted(by: {
        $0.sourceIdentity < $1.sourceIdentity
    }) {
        guard let targetID = sourceFile.targetID else {
            continue
        }
        let sourceImports = targetAwareSourceImports(in: sourceFile.syntax)
        let collector = ContainerCollector()
        collector.walkFile(
            relativePath: sourceFile.sourceIdentity,
            tree: sourceFile.syntax
        )
        let aliases = collector.typeAliases.map {
            TargetAwareContainerAlias(
                record: $0,
                sourceIdentity: sourceFile.sourceIdentity,
                sourceImports: sourceImports
            )
        }
        rawNodesByTargetID[targetID, default: []].append(
            contentsOf: collector.nodes
        )
        aliasesByTargetID[targetID, default: []].append(
            contentsOf: aliases
        )
        exportedImportsByTargetID[targetID] =
            (exportedImportsByTargetID[targetID] ?? .empty).merging(
                sourceImports.exportedOnly
            )
        collectedSources.append(
            TargetScopedCollectedSource(
                sourceFile: sourceFile,
                targetID: targetID,
                sourceImports: sourceImports,
                subContainerReferences: collector.subContainerReferences
            )
        )
    }

    let nodesByTargetID = rawNodesByTargetID.mapValues(normalizeNodes)
    let nodes = normalizeNodes(nodesByTargetID.values.flatMap { $0 })
    guard !nodes.isEmpty else {
        return DependencyGraphDiagnosticCollection(
            nodes: [],
            edges: [],
            semanticIssues: []
        )
    }

    let resolutionIndex = TargetAwareContainerResolutionIndex(
        manifest: manifest,
        nodesByTargetID: nodesByTargetID,
        aliasesByTargetID: aliasesByTargetID,
        exportedImportsByTargetID: exportedImportsByTargetID,
        validateDAG: validateDAG
    )
    var edges: [DependencyGraphEdge] = []
    var semanticIssues: [SemanticContainerReferenceIssue] = []

    for collectedSource in collectedSources {
        let resolver = resolutionIndex.resolver(
            from: collectedSource.targetID,
            sourceImports: collectedSource.sourceImports
        )
        let usageCollector = ContainerUsageCollector(
            referenceResolver: resolver
        )
        usageCollector.walkFile(
            relativePath: collectedSource.sourceFile.sourceIdentity,
            tree: collectedSource.sourceFile.syntax
        )
        edges.append(contentsOf: usageCollector.edges)
        semanticIssues.append(contentsOf: usageCollector.semanticIssues)

        var ownershipFallbackMatchedReferences: [String] = []
        for reference in collectedSource.subContainerReferences {
            guard let childReference = reference.childReference else {
                semanticIssues.append(
                    SemanticContainerReferenceIssue(
                        sourceID: reference.parentID,
                        destinationDisplayName: reference.childDisplayName,
                        state: .excluded,
                        destinationCandidates: [],
                        excludedReason: nil,
                        aliasExpansionTrace: [],
                        usedSuffixFallback: false
                    )
                )
                continue
            }
            guard let resolvedID = resolveContainerReferenceID(
                reference: childReference,
                sourceID: reference.parentID,
                resolver: resolver,
                semanticIssues: &semanticIssues,
                fallbackMatchedReferences:
                    &ownershipFallbackMatchedReferences
            ) else {
                continue
            }
            edges.append(
                DependencyGraphEdge(
                    fromID: reference.parentID,
                    toID: resolvedID,
                    label: reference.memberName,
                    isOwnership: true
                )
            )
        }
    }

    return DependencyGraphDiagnosticCollection(
        nodes: nodes,
        edges: deduplicateEdges(edges),
        semanticIssues: semanticIssues
    )
}

private func rootPrunedRenderGraph(
    nodes: [DependencyGraphNode],
    edges: [DependencyGraphEdge]
) -> (nodes: [DependencyGraphNode], edges: [DependencyGraphEdge]) {
    let rootIDs = nodes.filter(\.isRoot).map(\.id)
    guard !rootIDs.isEmpty else {
        return (nodes, edges)
    }

    var adjacency: [String: [String]] = [:]
    for edge in edges {
        adjacency[edge.fromID, default: []].append(edge.toID)
    }

    var reachableIDs = Set(rootIDs)
    var queue = rootIDs
    var index = 0
    while index < queue.count {
        let currentID = queue[index]
        index += 1
        for nextID in adjacency[currentID, default: []] where reachableIDs.insert(nextID).inserted {
            queue.append(nextID)
        }
    }

    return (
        nodes.filter { reachableIDs.contains($0.id) },
        edges.filter { reachableIDs.contains($0.fromID) && reachableIDs.contains($0.toID) }
    )
}

private func validateDependencyGraph(
    nodes: [DependencyGraphNode],
    edges: [DependencyGraphEdge],
    semanticIssues: [SemanticContainerReferenceIssue]
) -> DependencyGraphCommandResult {
    let eligibleNodes = nodes.filter(\.validateDAG)
    guard !eligibleNodes.isEmpty else {
        return DependencyGraphCommandResult(
            exitCode: DependencyGraphCoreExitCode.success,
            stdout: "DAG validation passed (all containers opted out via validateDAG: false).\n",
            stderr: ""
        )
    }

    let nodeIDs = Set(eligibleNodes.map(\.id))
    let eligibleEdges = edges.filter { nodeIDs.contains($0.fromID) && nodeIDs.contains($0.toID) }
    let eligibleSemanticIssues = semanticIssues.filter { nodeIDs.contains($0.sourceID) }

    let adjacency = buildCycleDetectionAdjacency(nodes: eligibleNodes, edges: eligibleEdges)
    let cycleResult = analyzeDependencyCycles(adjacency: adjacency)
    let cycles = cycleResult.cycles
    if cycles.isEmpty && eligibleSemanticIssues.isEmpty && !cycleResult.truncatedByDepthLimit {
        return DependencyGraphCommandResult(
            exitCode: DependencyGraphCoreExitCode.success,
            stdout: "DAG validation passed.\n",
            stderr: ""
        )
    }

    let labelsByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.displayName) })
    var lines: [String] = ["DAG validation failed."]

    let ambiguousIssues = eligibleSemanticIssues.filter { $0.state == .ambiguous }
    let unresolvedIssues = eligibleSemanticIssues.filter { $0.state == .unresolved }
    let excludedIssues = eligibleSemanticIssues.filter { $0.state == .excluded }

    if !ambiguousIssues.isEmpty {
        lines.append("Ambiguous container references:")
        let unique = Set(ambiguousIssues).sorted { lhs, rhs in
            if lhs.sourceID == rhs.sourceID {
                return lhs.destinationDisplayName < rhs.destinationDisplayName
            }
            return lhs.sourceID < rhs.sourceID
        }
        for item in unique {
            let source = labelsByID[item.sourceID] ?? item.sourceID
            if item.destinationCandidates.isEmpty {
                lines.append("- [graph.ambiguous-container-reference] \(source) -> \(item.destinationDisplayName)")
            } else {
                let candidateSummary = item.destinationCandidates.joined(separator: ", ")
                lines.append(
                    "- [graph.ambiguous-container-reference] \(source) -> \(item.destinationDisplayName) candidates: \(candidateSummary)"
                )
            }
        }
    }

    if !unresolvedIssues.isEmpty {
        lines.append("Unresolved container references:")
        let unique = Set(unresolvedIssues).sorted { lhs, rhs in
            if lhs.sourceID == rhs.sourceID {
                return lhs.destinationDisplayName < rhs.destinationDisplayName
            }
            return lhs.sourceID < rhs.sourceID
        }
        for item in unique {
            let source = labelsByID[item.sourceID] ?? item.sourceID
            lines.append("- [graph.unresolved-container-reference] \(source) -> \(item.destinationDisplayName)")
        }
    }

    if !excludedIssues.isEmpty {
        lines.append("Excluded container references:")
        let unique = Set(excludedIssues).sorted { lhs, rhs in
            if lhs.sourceID == rhs.sourceID {
                return lhs.destinationDisplayName < rhs.destinationDisplayName
            }
            return lhs.sourceID < rhs.sourceID
        }
        for item in unique {
            let source = labelsByID[item.sourceID] ?? item.sourceID
            let detail = item.excludedReason ?? "unsupported semantic reference shape"
            lines.append("- [graph.excluded-container-reference] \(source) -> \(item.destinationDisplayName) reason: \(detail)")
        }
    }

    if !cycles.isEmpty {
        lines.append("Detected dependency cycles:")
        for cycle in cycles {
            let labels = cycle.map { labelsByID[$0] ?? $0 }
            lines.append("- [graph.dependency-cycle] \(labels.joined(separator: " -> "))")
        }
    }

    if cycleResult.truncatedByDepthLimit {
        if cycles.isEmpty {
            lines.append("Detected dependency cycles:")
        }
        lines.append("- [graph.dependency-cycle] cycle detection truncated at depth limit before validation completed")
    }

    return DependencyGraphCommandResult(
        exitCode: DependencyGraphCoreExitCode.dagValidationFailure,
        stdout: "",
        stderr: lines.joined(separator: "\n") + "\n"
    )
}
