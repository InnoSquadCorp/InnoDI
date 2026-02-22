import Foundation
import InnoDICore

func runDependencyGraphCLI() -> Int32 {
    let (rootPath, format, outputPath) = parseArguments()
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
        return writeNoContainersMessage(outputPath: outputPath)
    }

    let containerIDsByDisplayName = Dictionary(grouping: nodes, by: { $0.displayName })
        .mapValues { group in group.map(\.id).sorted() }

    let usageCollector = ContainerUsageCollector(containerIDsByDisplayName: containerIDsByDisplayName)
    for parsed in parsedFiles {
        usageCollector.walkFile(relativePath: parsed.relativePath, tree: parsed.tree)
    }

    let edges = deduplicateEdges(usageCollector.edges)

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

private func writeNoContainersMessage(outputPath: String?) -> Int32 {
    let errorMessage = "No @DIContainer found in project.\n"

    if let outputPath {
        do {
            try errorMessage.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
        } catch {
            fputs("Error writing to file: \(error)\n", stderr)
            return 2
        }
    } else {
        fputs(errorMessage, stderr)
    }

    return 1
}
