import Foundation
import InnoDICore

func runDependencyGraphCLI() -> Int32 {
    let parsed: ParsedArguments
    switch parseArguments() {
    case .parsed(let args, let warnings):
        parsed = args
        for warning in warnings {
            fputs("\(warning)\n", stderr)
        }
    case .helpRequested:
        printUsage()
        return 0
    case .failed(let error):
        fputs("\(error.message)\n", stderr)
        printUsage()
        return 1
    }

    let rootPath = parsed.root
    let outputPath = parsed.output
    let validateDAG = parsed.validateDAG
    let outputFormat = parsed.format ?? .mermaid

    let files = loadSwiftFiles(rootPath: rootPath)
    let parsedFiles = files.compactMap { file in
        let relative = relativePath(of: file, fromRoot: rootPath)
        do {
            let tree = try parseSourceFile(at: file)
            return (relativePath: relative, tree: tree)
        } catch {
            fputs("Warning: failed to parse '\(relative)' (\(file)): \(error)\n", stderr)
            return nil
        }
    }

    let collector = ContainerCollector()
    for parsed in parsedFiles {
        collector.walkFile(relativePath: parsed.relativePath, tree: parsed.tree)
    }

    let nodes = normalizeNodes(collector.nodes)
    guard !nodes.isEmpty else {
        if validateDAG {
            return writeValidationMessage("DAG validation passed (no @DIContainer declarations found).\n", outputPath: outputPath)
        }
        return writeNoContainersMessage(outputPath: outputPath)
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
    for parsed in parsedFiles {
        usageCollector.walkFile(relativePath: parsed.relativePath, tree: parsed.tree)
    }

    // Ownership edges come from `@SubContainer` members on `@DIContainer`
    // types. Resolve them through the shared semantic resolver so aliases,
    // suffix fallback, opted-out duplicates, and ambiguity all behave the
    // same way as regular container references gathered from call sites.
    var ownershipEdges: [DependencyGraphEdge] = []
    var ownershipSemanticIssues: [SemanticContainerReferenceIssue] = []
    var ownershipFallbackMatchedReferences: [String] = []
    let ownershipEligibleContainerIDsBySemanticPath = validateDAG
        ? containerIDsBySemanticPathEligible
        : containerIDsBySemanticPathAll
    let candidatePaths = Set(containerIDsBySemanticPathAll.keys)
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
            candidatePaths: candidatePaths,
            allContainerIDsBySemanticPath: containerIDsBySemanticPathAll,
            eligibleContainerIDsBySemanticPath: ownershipEligibleContainerIDsBySemanticPath,
            semanticResolver: semanticResolver,
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

    let edges = deduplicateEdges(usageCollector.edges + ownershipEdges)
    if validateDAG {
        return runDAGValidation(
            nodes: nodes,
            edges: edges,
            semanticIssues: usageCollector.semanticIssues + ownershipSemanticIssues,
            outputPath: outputPath
        )
    }

    let renderedGraph = rootPrunedRenderGraph(nodes: nodes, edges: edges)

    let rendered: String
    switch outputFormat {
    case .mermaid:
        rendered = renderMermaid(nodes: renderedGraph.nodes, edges: renderedGraph.edges)
    case .dot:
        rendered = renderDOT(nodes: renderedGraph.nodes, edges: renderedGraph.edges)
    case .ascii:
        rendered = renderASCII(nodes: renderedGraph.nodes, edges: renderedGraph.edges)
    case .json:
        rendered = renderJSON(nodes: renderedGraph.nodes, edges: renderedGraph.edges)
    }

    return writeGraphOutput(rendered, format: outputFormat, outputPath: outputPath)
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

private func runDAGValidation(
    nodes: [DependencyGraphNode],
    edges: [DependencyGraphEdge],
    semanticIssues: [SemanticContainerReferenceIssue],
    outputPath: String?
) -> Int32 {
    let eligibleNodes = nodes.filter(\.validateDAG)
    guard !eligibleNodes.isEmpty else {
        return writeValidationMessage("DAG validation passed (all containers opted out via validateDAG: false).\n", outputPath: outputPath)
    }

    let nodeIDs = Set(eligibleNodes.map(\.id))
    let eligibleEdges = edges.filter { nodeIDs.contains($0.fromID) && nodeIDs.contains($0.toID) }
    let eligibleSemanticIssues = semanticIssues.filter { nodeIDs.contains($0.sourceID) }

    // Deferred edges are intentionally excluded from cycle detection:
    // `Lazy<T>` defers resolution until after construction, and `Provider<T>`
    // re-enters a transient accessor on demand. Both still render in the
    // graph, but neither should participate in init-time cycle validation.
    let adjacency = buildCycleDetectionAdjacency(nodes: eligibleNodes, edges: eligibleEdges)
    let cycleResult = analyzeDependencyCycles(adjacency: adjacency)
    let cycles = cycleResult.cycles
    if cycles.isEmpty && eligibleSemanticIssues.isEmpty && !cycleResult.truncatedByDepthLimit {
        return writeValidationMessage("DAG validation passed.\n", outputPath: outputPath)
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

    let report = lines.joined(separator: "\n") + "\n"
    if let outputPath, outputPath != "-" {
        do {
            try report.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
        } catch {
            fputs("Error writing to file: \(error)\n", stderr)
            return ExitCode.ioError
        }
    } else if outputPath == "-" {
        fputs(report, stdout)
    } else {
        fputs(report, stderr)
    }
    return ExitCode.dagValidationFailure
}

private func writeNoContainersMessage(outputPath: String?) -> Int32 {
    let errorMessage = "No @DIContainer found in project.\n"

    if let outputPath, outputPath != "-" {
        do {
            try errorMessage.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
        } catch {
            fputs("Error writing to file: \(error)\n", stderr)
            return ExitCode.ioError
        }
    } else if outputPath == "-" {
        fputs(errorMessage, stdout)
    } else {
        fputs(errorMessage, stderr)
    }

    return ExitCode.noContainers
}

private func writeValidationMessage(_ message: String, outputPath: String?) -> Int32 {
    if let outputPath, outputPath != "-" {
        do {
            try message.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
        } catch {
            fputs("Error writing to file: \(error)\n", stderr)
            return ExitCode.ioError
        }
    } else {
        fputs(message, stdout)
    }
    return ExitCode.success
}
