import Foundation
import InnoDICore
import SwiftParser
import SwiftSyntax

enum OutputFormat {
    case mermaid, dot, ascii

    init?(string: String) {
        switch string.lowercased() {
        case "mermaid": self = .mermaid
        case "dot": self = .dot
        case "ascii": self = .ascii
        default: return nil
        }
    }
}

final class ContainerCollector: SyntaxVisitor {
    var nodes: [DependencyGraphNode] = []

    private var currentRelativeFilePath: String = ""
    private var declarationPath: [String] = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        declarationPath.append(node.name.text)
        collectIfContainer(node)
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        _ = declarationPath.popLast()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        declarationPath.append(node.name.text)
        collectIfContainer(node)
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        _ = declarationPath.popLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        declarationPath.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        _ = declarationPath.popLast()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        declarationPath.append(node.name.text)
        collectIfContainer(node)
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        _ = declarationPath.popLast()
    }

    func walkFile(relativePath: String, tree: SourceFileSyntax) {
        currentRelativeFilePath = relativePath
        declarationPath.removeAll(keepingCapacity: true)
        walk(tree)
    }

    private func collectIfContainer(_ node: some DeclGroupSyntax) {
        guard let containerAttr = parseDIContainerAttribute(node.attributes) else { return }

        let displayName: String
        if let structNode = node.as(StructDeclSyntax.self) {
            displayName = structNode.name.text
        } else if let classNode = node.as(ClassDeclSyntax.self) {
            displayName = classNode.name.text
        } else if let actorNode = node.as(ActorDeclSyntax.self) {
            displayName = actorNode.name.text
        } else {
            return
        }

        var requiredInputs: [String] = []

        for member in node.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            let provide = parseProvideAttribute(varDecl.attributes)
            if !provide.hasProvide || provide.scope != .input { continue }

            guard let binding = varDecl.bindings.first,
                  let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                continue
            }

            requiredInputs.append(pattern.identifier.text)
        }

        let id = makeContainerID(fileRelativePath: currentRelativeFilePath, declarationPath: declarationPath)

        nodes.append(
            DependencyGraphNode(
                id: id,
                displayName: displayName,
                isRoot: containerAttr.root,
                requiredInputs: requiredInputs
            )
        )
    }
}

final class ContainerUsageCollector: SyntaxVisitor {
    let containerIDsByDisplayName: [String: [String]]
    var edges: [DependencyGraphEdge] = []

    private var currentRelativeFilePath: String = ""
    private var declarationPath: [String] = []
    private var activeContainerIDs: [String] = []
    private var activeContainerMarkers: [Bool] = []

    init(containerIDsByDisplayName: [String: [String]], viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        self.containerIDsByDisplayName = containerIDsByDisplayName
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        declarationPath.append(node.name.text)

        let isContainer = parseDIContainerAttribute(node.attributes) != nil
        activeContainerMarkers.append(isContainer)
        if isContainer {
            let id = makeContainerID(fileRelativePath: currentRelativeFilePath, declarationPath: declarationPath)
            activeContainerIDs.append(id)
        }

        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        if activeContainerMarkers.popLast() == true {
            _ = activeContainerIDs.popLast()
        }
        _ = declarationPath.popLast()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        declarationPath.append(node.name.text)

        let isContainer = parseDIContainerAttribute(node.attributes) != nil
        activeContainerMarkers.append(isContainer)
        if isContainer {
            let id = makeContainerID(fileRelativePath: currentRelativeFilePath, declarationPath: declarationPath)
            activeContainerIDs.append(id)
        }

        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        if activeContainerMarkers.popLast() == true {
            _ = activeContainerIDs.popLast()
        }
        _ = declarationPath.popLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        declarationPath.append(node.name.text)
        activeContainerMarkers.append(false)
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        _ = activeContainerMarkers.popLast()
        _ = declarationPath.popLast()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        declarationPath.append(node.name.text)

        let isContainer = parseDIContainerAttribute(node.attributes) != nil
        activeContainerMarkers.append(isContainer)
        if isContainer {
            let id = makeContainerID(fileRelativePath: currentRelativeFilePath, declarationPath: declarationPath)
            activeContainerIDs.append(id)
        }

        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        if activeContainerMarkers.popLast() == true {
            _ = activeContainerIDs.popLast()
        }
        _ = declarationPath.popLast()
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

func loadSwiftFiles(rootPath: String) -> [String] {
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(atPath: rootPath) else { return [] }
    var results: [String] = []

    while let item = enumerator.nextObject() as? String {
        if item.hasPrefix(".") { continue }
        if shouldSkip(path: item) { continue }
        if item.hasSuffix(".swift") {
            results.append((rootPath as NSString).appendingPathComponent(item))
        }
    }

    return results.sorted()
}

func shouldSkip(path: String) -> Bool {
    let skipTokens = [
        "/.build/",
        "/Derived/",
        "/Tuist/Dependencies/",
        "/.tuist/",
        "/.git/",
        "/Pods/",
        "/Carthage/",
        "/.swiftpm/",
        "/.xcodeproj/",
        "/xcworkspace/"
    ]
    for token in skipTokens where path.contains(token) {
        return true
    }
    return false
}

func parseSourceFile(at path: String) throws -> SourceFileSyntax {
    let source = try String(contentsOfFile: path, encoding: .utf8)
    return Parser.parse(source: source)
}

func parseArguments() -> (root: String, format: OutputFormat?, output: String?) {
    var root = FileManager.default.currentDirectoryPath
    var format: OutputFormat? = nil
    var output: String? = nil

    var iterator = CommandLine.arguments.makeIterator()
    _ = iterator.next()

    while let arg = iterator.next() {
        if arg == "--root", let value = iterator.next() {
            root = value
        } else if arg == "--format", let value = iterator.next() {
            format = OutputFormat(string: value.lowercased())
        } else if arg == "--output", let value = iterator.next() {
            output = value
        } else if arg == "--help" || arg == "-h" {
            printUsage()
            exit(0)
        }
    }

    return (root, format, output)
}

func printUsage() {
    print("Usage: InnoDI-DependencyGraph --root <path> [--format <mermaid|dot|ascii>] [--output <file>]")
    print("")
    print("Options:")
    print("  --root <path>   Root directory of the project (default: current directory)")
    print("  --format <format> Output format: mermaid (default), dot, or ascii")
    print("  --output <file>  Output file path (default: stdout)")
    print("  --help, -h       Show this help message")
}

func renderMermaid(nodes: [DependencyGraphNode], edges: [DependencyGraphEdge]) -> String {
    let aliases = nodeAliases(nodes: nodes)
    let duplicateDisplayNames = duplicateDisplayNameSet(nodes: nodes)

    var result = "graph TD\n"
    for node in nodes {
        guard let alias = aliases[node.id] else { continue }
        var label = displayLabel(for: node, duplicateDisplayNames: duplicateDisplayNames)
        if node.isRoot {
            label += " [root]"
        }
        result += "    \(alias)[\"\(escapeMermaidLabel(label))\"]\n"
    }

    for edge in edges {
        guard let fromAlias = aliases[edge.fromID],
              let toAlias = aliases[edge.toID] else {
            continue
        }
        let label = edge.label.map { "|\(escapeMermaidLabel($0))|" } ?? ""
        result += "    \(fromAlias) -->\(label) \(toAlias)\n"
    }

    result += "\n"
    return result
}

func renderDOT(nodes: [DependencyGraphNode], edges: [DependencyGraphEdge]) -> String {
    let aliases = nodeAliases(nodes: nodes)
    let duplicateDisplayNames = duplicateDisplayNameSet(nodes: nodes)

    var result = "digraph InnoDI {\n"
    result += "  rankdir=TB;\n"
    result += "\n"
    result += "  // Nodes\n"

    for node in nodes {
        guard let alias = aliases[node.id] else { continue }
        let fill = node.isRoot ? "#e1f5fe" : "#e5e7eb"
        let label = escapeDOTLabel(displayLabel(for: node, duplicateDisplayNames: duplicateDisplayNames))
        result += "  \"\(alias)\" [label=\"\(label)\", shape=box, style=rounded,filled, fillcolor=\(fill)];\n"
    }

    result += "\n"
    result += "  // Edges\n"

    for edge in edges {
        guard let fromAlias = aliases[edge.fromID],
              let toAlias = aliases[edge.toID] else {
            continue
        }
        if let label = edge.label {
            result += "  \"\(fromAlias)\" -> \"\(toAlias)\" [label=\"\(escapeDOTLabel(label))\"];\n"
        } else {
            result += "  \"\(fromAlias)\" -> \"\(toAlias)\";\n"
        }
    }

    result += "}\n"
    return result
}

func renderASCII(nodes: [DependencyGraphNode], edges: [DependencyGraphEdge]) -> String {
    let duplicateDisplayNames = duplicateDisplayNameSet(nodes: nodes)
    let labelsByID = Dictionary(uniqueKeysWithValues: nodes.map {
        ($0.id, displayLabel(for: $0, duplicateDisplayNames: duplicateDisplayNames))
    })

    let maxNameLen = labelsByID.values.map { $0.count }.max() ?? 10

    var result = "InnoDI Dependency Graph\n"
    result += String(repeating: "=", count: maxNameLen + 15) + "\n"
    result += "Nodes:\n"

    for node in nodes {
        let label = labelsByID[node.id] ?? node.id
        let padding = String(repeating: " ", count: max(0, maxNameLen - label.count))
        let root = node.isRoot ? " [ROOT]" : ""
        let inputs = node.requiredInputs.isEmpty ? "" : " (inputs: \(node.requiredInputs.joined(separator: ", ")))"
        result += "  \(padding)\(label)\(root)\(inputs)\n"
    }

    result += "\n"
    result += "Edges:\n"

    for edge in edges {
        let fromLabel = labelsByID[edge.fromID] ?? edge.fromID
        let toLabel = labelsByID[edge.toID] ?? edge.toID
        let labelPart = edge.label.map { ":\($0)" } ?? ""
        let padding = String(repeating: " ", count: max(0, maxNameLen - fromLabel.count))
        result += "  \(padding)\(fromLabel) -->\(toLabel)\(labelPart)\n"
    }

    return result
}

func main() -> Int32 {
    let (rootPath, format, output) = parseArguments()
    let outputFormat = format ?? .mermaid

    let files = loadSwiftFiles(rootPath: rootPath)
    let parsedFiles = files.compactMap { file -> (relativePath: String, tree: SourceFileSyntax)? in
        guard let tree = try? parseSourceFile(at: file) else { return nil }
        return (relativePath: relativePath(of: file, fromRoot: rootPath), tree: tree)
    }

    let collector = ContainerCollector()
    for parsed in parsedFiles {
        collector.walkFile(relativePath: parsed.relativePath, tree: parsed.tree)
    }

    let nodes = normalizeNodes(collector.nodes)

    guard !nodes.isEmpty else {
        let errorMsg = "No @DIContainer found in project.\n"
        if let outputPath = output {
            do {
                try errorMsg.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
            } catch {
                fputs("Error writing to file: \(error)\n", stderr)
            }
        } else {
            fputs(errorMsg, stderr)
        }
        return 1
    }

    let containerIDsByDisplayName = Dictionary(grouping: nodes, by: { $0.displayName })
        .mapValues { group in group.map(\.id).sorted() }

    let usageCollector = ContainerUsageCollector(containerIDsByDisplayName: containerIDsByDisplayName)
    for parsed in parsedFiles {
        usageCollector.walkFile(relativePath: parsed.relativePath, tree: parsed.tree)
    }

    let edges = deduplicateEdges(usageCollector.edges)

    let result: String
    switch outputFormat {
    case .mermaid:
        result = renderMermaid(nodes: nodes, edges: edges)
    case .dot:
        result = renderDOT(nodes: nodes, edges: edges)
    case .ascii:
        result = renderASCII(nodes: nodes, edges: edges)
    }

    if let outputPath = output {
        if outputPath.hasSuffix(".png") && outputFormat == .dot {
            do {
                let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("innodi_temp.dot")
                try result.write(to: tempURL, atomically: true, encoding: .utf8)

                let whichProcess = Process()
                whichProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
                whichProcess.arguments = ["-c", "which dot"]
                let pipe = Pipe()
                whichProcess.standardOutput = pipe
                try whichProcess.run()
                whichProcess.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let dotPath = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

                if let dotPath, !dotPath.isEmpty {
                    let dotProcess = Process()
                    dotProcess.executableURL = URL(fileURLWithPath: dotPath)
                    dotProcess.arguments = ["-Tpng", tempURL.path, "-o", outputPath]
                    try dotProcess.run()
                    dotProcess.waitUntilExit()
                    if dotProcess.terminationStatus == 0 {
                        print("PNG generated at \(outputPath)")
                    } else {
                        fputs("Failed to generate PNG\n", stderr)
                        return 1
                    }
                } else {
                    fputs("dot command not found. Please install Graphviz.\n", stderr)
                    return 1
                }

                try? FileManager.default.removeItem(at: tempURL)
            } catch {
                fputs("Error generating PNG: \(error)\n", stderr)
                return 1
            }
        } else {
            do {
                try result.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
            } catch {
                fputs("Error writing to file: \(error)\n", stderr)
                return 1
            }
        }
    } else {
        print(result)
    }

    return 0
}

private func makeContainerID(fileRelativePath: String, declarationPath: [String]) -> String {
    let path = declarationPath.joined(separator: ".")
    return "\(fileRelativePath)#\(path)"
}

private func relativePath(of path: String, fromRoot rootPath: String) -> String {
    let rootURL = URL(fileURLWithPath: rootPath).standardizedFileURL
    let pathURL = URL(fileURLWithPath: path).standardizedFileURL

    let root = rootURL.path
    let fullPath = pathURL.path

    if fullPath == root {
        return pathURL.lastPathComponent
    }

    let rootPrefix = root.hasSuffix("/") ? root : root + "/"
    if fullPath.hasPrefix(rootPrefix) {
        return String(fullPath.dropFirst(rootPrefix.count))
    }

    return fullPath
}

private func nodeAliases(nodes: [DependencyGraphNode]) -> [String: String] {
    var aliases: [String: String] = [:]
    for (index, node) in nodes.enumerated() {
        aliases[node.id] = "N\(index)"
    }
    return aliases
}

private func duplicateDisplayNameSet(nodes: [DependencyGraphNode]) -> Set<String> {
    var counts: [String: Int] = [:]
    for node in nodes {
        counts[node.displayName, default: 0] += 1
    }
    return Set(counts.compactMap { name, count in count > 1 ? name : nil })
}

private func displayLabel(for node: DependencyGraphNode, duplicateDisplayNames: Set<String>) -> String {
    if duplicateDisplayNames.contains(node.displayName) {
        return "\(node.displayName) (\(node.id))"
    }
    return node.displayName
}

private func escapeMermaidLabel(_ label: String) -> String {
    label.replacingOccurrences(of: "\"", with: "\\\"")
}

private func escapeDOTLabel(_ label: String) -> String {
    label
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

exit(main())
