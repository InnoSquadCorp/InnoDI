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
struct ContainerNode {
    let name: String
    let isRoot: Bool
    let requiredInputs: [String]
}

struct DependencyEdge {
    let from: String
    let to: String
    let label: String?
}

final class ContainerCollector: SyntaxVisitor {
    var nodes: [ContainerNode] = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        collect(from: node)
        return .skipChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        collect(from: node)
        return .skipChildren
    }

    private func collect(from node: some DeclGroupSyntax) {
        guard let containerAttr = parseDIContainerAttribute(node.attributes) else { return }

        let name: String
        if let structNode = node.as(StructDeclSyntax.self) {
            name = structNode.name.text
        } else if let classNode = node.as(ClassDeclSyntax.self) {
            name = classNode.name.text
        } else {
            return
        }

        var requiredInputs: [String] = []

        for member in node.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            let provide = parseProvideAttribute(varDecl.attributes)
            if !provide.hasProvide { continue }
            if provide.scope != .input { continue }

            guard let binding = varDecl.bindings.first,
                  let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                continue
            }

            requiredInputs.append(pattern.identifier.text)
        }

        nodes.append(ContainerNode(
            name: name,
            isRoot: containerAttr.root,
            requiredInputs: requiredInputs
        ))
    }
}

final class ContainerUsageCollector: SyntaxVisitor {
    let containerNames: Set<String>
    var currentContainer: String?
    var edges: [DependencyEdge] = []

    init(containerNames: Set<String>, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        self.containerNames = containerNames
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let previous = currentContainer
        if parseDIContainerAttribute(node.attributes) != nil {
            currentContainer = node.name.text
            defer { currentContainer = previous }
            for member in node.memberBlock.members {
                walk(member)
            }
            return .skipChildren
        }
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let previous = currentContainer
        if parseDIContainerAttribute(node.attributes) != nil {
            currentContainer = node.name.text
            defer { currentContainer = previous }
            for member in node.memberBlock.members {
                walk(member)
            }
            return .skipChildren
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let sourceContainer = currentContainer,
              let calleeName = calledContainerName(node.calledExpression) else {
            return .visitChildren
        }

        edges.append(DependencyEdge(
            from: sourceContainer,
            to: calleeName,
            label: edgeLabel(from: node.arguments)
        ))

        return .visitChildren
    }

    private func calledContainerName(_ expr: ExprSyntax) -> String? {
        let raw = expr.trimmedDescription
        let lastComponent = raw.split(separator: ".").last ?? ""
        let base = lastComponent.split(separator: "<").first ?? lastComponent
        let name = String(base)
        return containerNames.contains(name) ? name : nil
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

func renderMermaid(nodes: [ContainerNode], edges: [DependencyEdge]) -> String {
    var result = "graph TD\n"
    for node in nodes where node.isRoot {
        result += "    \(node.name)[root]\n"
    }
    for node in nodes where !node.isRoot {
        result += "    \(node.name)\n"
    }
    for edge in edges {
        let label = edge.label.map { "|\($0)|" } ?? ""
        result += "    \(edge.from) -->\(label) \(edge.to)\n"
    }
    result += "\n"
    return result
}

func renderDOT(nodes: [ContainerNode], edges: [DependencyEdge]) -> String {
    var result = "digraph InnoDI {\n"
    result += "  rankdir=TB;\n"
    result += "\n"
    result += "  // Nodes\n"
    for node in nodes {
        let fill = node.isRoot ? "#e1f5fe" : "#e5e7eb"
        result += "  \"\(node.name)\" [shape=box, style=rounded,filled, fillcolor=\(fill)];\n"
    }
    result += "\n"
    result += "  // Edges\n"
    for edge in edges {
        if let label = edge.label {
            result += "  \"\(edge.from)\" -> \"\(edge.to)\" [label=\"\(label)\"];\n"
        } else {
            result += "  \"\(edge.from)\" -> \"\(edge.to)\";\n"
        }
    }
    result += "}\n"
    return result
}

func renderASCII(nodes: [ContainerNode], edges: [DependencyEdge]) -> String {
    let maxNameLen = nodes.map { $0.name.count }.max() ?? 10

    var result = "InnoDI Dependency Graph\n"
    result += String(repeating: "=", count: maxNameLen + 15) + "\n"
    result += "Nodes:\n"
    for node in nodes {
        let padding = String(repeating: " ", count: maxNameLen - node.name.count)
        let root = node.isRoot ? " [ROOT]" : ""
        let inputs = node.requiredInputs.isEmpty ? "" : " (inputs: \(node.requiredInputs.joined(separator: ", ")))"
        result += "  \(padding)\(node.name)\(root)\(inputs)\n"
    }
    result += "\n"
    result += "Edges:\n"
    for edge in edges {
        let labelPart = edge.label.map { ":\($0)" } ?? ""
        let padding = String(repeating: " ", count: maxNameLen - edge.from.count)
        result += "  \(padding)\(edge.from) -->\(edge.to)\(labelPart)\n"
    }
    return result
}

func normalizedNodes(_ nodes: [ContainerNode]) -> [ContainerNode] {
    var map: [String: (isRoot: Bool, inputs: Set<String>)] = [:]
    for node in nodes {
        var entry = map[node.name] ?? (isRoot: false, inputs: [])
        entry.isRoot = entry.isRoot || node.isRoot
        entry.inputs.formUnion(node.requiredInputs)
        map[node.name] = entry
    }

    return map.keys.sorted().map { name in
        let entry = map[name]!
        return ContainerNode(name: name, isRoot: entry.isRoot, requiredInputs: entry.inputs.sorted())
    }
}

func deduplicatedEdges(_ edges: [DependencyEdge]) -> [DependencyEdge] {
    var seen: Set<String> = []
    var result: [DependencyEdge] = []

    for edge in edges {
        let key = "\(edge.from)->\(edge.to)|\(edge.label ?? "")"
        if seen.insert(key).inserted {
            result.append(edge)
        }
    }

    return result
}

func main() -> Int32 {
    let (rootPath, format, output) = parseArguments()
    let outputFormat = format ?? .mermaid

    let files = loadSwiftFiles(rootPath: rootPath)

    let collector = ContainerCollector()
    for file in files {
        guard let tree = try? parseSourceFile(at: file) else { continue }
        collector.walk(tree)
    }

    let nodes = normalizedNodes(collector.nodes)
    let containerNames: Set<String> = Set(nodes.map { $0.name })

    let usageCollector = ContainerUsageCollector(containerNames: containerNames)
    for file in files {
        guard let tree = try? parseSourceFile(at: file) else { continue }
        usageCollector.walk(tree)
    }

    guard !nodes.isEmpty else {
        let errorMsg = "No @DIContainer found in project.\n"
        if let output = output {
            do {
                try errorMsg.write(to: URL(fileURLWithPath: output), atomically: true, encoding: .utf8)
            } catch {
                fputs("Error writing to file: \(error)\n", stderr)
            }
        } else {
            fputs(errorMsg, stderr)
        }
        return 1
    }

    let edges = deduplicatedEdges(usageCollector.edges)

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
            // Generate PNG using dot
            do {
                let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("innodi_temp.dot")
                try result.write(to: tempURL, atomically: true, encoding: .utf8)
                
                // Find dot path
                let whichProcess = Process()
                whichProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
                whichProcess.arguments = ["-c", "which dot"]
                let pipe = Pipe()
                whichProcess.standardOutput = pipe
                try whichProcess.run()
                whichProcess.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let dotPath = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if let dotPath = dotPath, !dotPath.isEmpty {
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
                
                // Clean up temp file
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

exit(main())
