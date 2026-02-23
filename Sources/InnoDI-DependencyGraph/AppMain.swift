import Foundation
import InnoDICore

func runDependencyGraphCLI() -> Int32 {
    let (rootPath, format, outputPath, validateDAG) = parseArguments()
    let outputFormat = format ?? .mermaid

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

    let containerIDsByDisplayName = Dictionary(grouping: nodes, by: { $0.displayName })
        .mapValues { group in group.map(\.id).sorted() }

    let usageCollector = ContainerUsageCollector(containerIDsByDisplayName: containerIDsByDisplayName)
    for parsed in parsedFiles {
        usageCollector.walkFile(relativePath: parsed.relativePath, tree: parsed.tree)
    }

    let edges = deduplicateEdges(usageCollector.edges)
    if validateDAG {
        return runDAGValidation(
            nodes: nodes,
            edges: edges,
            ambiguousReferences: usageCollector.ambiguousReferences,
            outputPath: outputPath
        )
    }

    let rendered: String
    switch outputFormat {
    case .mermaid:
        rendered = renderMermaid(nodes: nodes, edges: edges)
    case .dot:
        rendered = renderDOT(nodes: nodes, edges: edges)
    case .ascii:
        rendered = renderASCII(nodes: nodes, edges: edges)
    }

    return writeGraphOutput(rendered, format: outputFormat, outputPath: outputPath)
}

private func runDAGValidation(
    nodes: [DependencyGraphNode],
    edges: [DependencyGraphEdge],
    ambiguousReferences: [AmbiguousContainerReference],
    outputPath: String?
) -> Int32 {
    let eligibleNodes = nodes.filter(\.validateDAG)
    guard !eligibleNodes.isEmpty else {
        return writeValidationMessage("DAG validation passed (all containers opted out via validateDAG: false).\n", outputPath: outputPath)
    }

    let nodeIDs = Set(eligibleNodes.map(\.id))
    let eligibleEdges = edges.filter { nodeIDs.contains($0.fromID) && nodeIDs.contains($0.toID) }
    let eligibleAmbiguous = ambiguousReferences.filter { nodeIDs.contains($0.sourceID) }

    var adjacency: [String: [String]] = [:]
    for node in eligibleNodes {
        adjacency[node.id] = []
    }
    for edge in eligibleEdges {
        adjacency[edge.fromID, default: []].append(edge.toID)
    }

    let cycles = detectDependencyCycles(adjacency: adjacency)
    if cycles.isEmpty && eligibleAmbiguous.isEmpty {
        return writeValidationMessage("DAG validation passed.\n", outputPath: outputPath)
    }

    let labelsByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.displayName) })
    var lines: [String] = ["DAG validation failed."]

    if !eligibleAmbiguous.isEmpty {
        lines.append("Ambiguous container references:")
        let unique = Set(eligibleAmbiguous).sorted { lhs, rhs in
            if lhs.sourceID == rhs.sourceID {
                return lhs.destinationDisplayName < rhs.destinationDisplayName
            }
            return lhs.sourceID < rhs.sourceID
        }
        for item in unique {
            let source = labelsByID[item.sourceID] ?? item.sourceID
            lines.append("- [graph.ambiguous-container-reference] \(source) -> \(item.destinationDisplayName)")
        }
    }

    if !cycles.isEmpty {
        lines.append("Detected dependency cycles:")
        for cycle in cycles {
            let labels = cycle.map { labelsByID[$0] ?? $0 }
            lines.append("- [graph.dependency-cycle] \(labels.joined(separator: " -> "))")
        }
    }

    let report = lines.joined(separator: "\n") + "\n"
    if let outputPath {
        do {
            try report.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
        } catch {
            fputs("Error writing to file: \(error)\n", stderr)
            return ExitCode.ioError
        }
    } else {
        fputs(report, stderr)
    }
    return ExitCode.dagValidationFailure
}

private func writeNoContainersMessage(outputPath: String?) -> Int32 {
    let errorMessage = "No @DIContainer found in project.\n"

    if let outputPath {
        do {
            try errorMessage.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
        } catch {
            fputs("Error writing to file: \(error)\n", stderr)
            return ExitCode.ioError
        }
    } else {
        fputs(errorMessage, stderr)
    }

    return ExitCode.noContainers
}

private func writeValidationMessage(_ message: String, outputPath: String?) -> Int32 {
    if let outputPath {
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
