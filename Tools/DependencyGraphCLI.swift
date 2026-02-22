import Foundation
import InnoDICore
import SwiftParser
import SwiftSyntax

enum OutputFormat {
    case mermaid
    case dot
    case ascii
}

struct GraphConfig {
    let format: OutputFormat
    let rootPath: String
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
            guard let provide = parseProvideAttribute(varDecl.attributes),
                  provide.scope == .input else { continue }

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
        guard let calleeName = calledContainerName(node.calledExpression) else {
            return .visitChildren
        }

        var labels: Set<String> = []
        for argument in node.arguments {
            if let label = argument.label?.text {
                labels.insert(label)
            } else {
                labels.insert("_")
            }
        }

        edges.append(DependencyEdge(
            from: currentContainer ?? "",
            to: calleeName,
            label: labels.contains("_") ? nil : labels.first
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

    private var currentFile: String = ""
    private var currentTree: SourceFileSyntax = Parser.parse(source: "")

    func walkFile(path: String, tree: SourceFileSyntax) {
        currentFile = path
        currentTree = tree
        walk(tree)
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

    return results
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
        "/.xcworkspace/"
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

func parseArguments() -> (root: String, format: OutputFormat?) {
    var root = FileManager.default.currentDirectoryPath
    var format: OutputFormat? = nil

    var iterator = CommandLine.arguments.makeIterator()
    _ = iterator.next()

    while let arg = iterator.next() {
        if arg == "--root", let value = iterator.next() {
            root = value
        } else if arg == "--format", let value = iterator.next() {
            format = OutputFormat(rawValue: value.lowercased())
        } else if arg == "--help" || arg == "-h" {
            printUsage()
            exit(0)
        }
    }

    return (root, format)
}

func printUsage() {
    print("Usage: InnoDI-DependencyGraph --root <path> [--format <mermaid|dot|ascii>]")
    print("")
    print("Options:")
    print("  --root <path>   Root directory of the project (default: current directory)")
    print("  --format <format> Output format: mermaid (default), dot, or ascii")
    print("  --help, -h       Show this help message")
}

func renderMermaid(nodes: [ContainerNode], edges: [DependencyEdge]) {
    print("graph TD")
    for node in nodes where node.isRoot {
        print("    \\(node.name)[root]")
    }
    for node in nodes where !node.isRoot {
        print("    \\(node.name)")
    }
    for edge in edges {
        let label = edge.label.map { "|\\(self)|" } ?? ""
        print("    \\(edge.from) -->\\(label) \\(edge.to)")
    }
    print()
}

func renderDOT(nodes: [ContainerNode], edges: [DependencyEdge]) {
    print("digraph InnoDI {")
    print("  rankdir=TB;")
    print()
    print("  // Nodes")
    for node in nodes {
        let fill = node.isRoot ? "#e1f5fe" : "#e5e7eb"
        print("  \"\\(node.name)\" [shape=box, style=rounded,filled, fillcolor=\\(fill)];")
    }
    print()
    print("  // Edges")
    for edge in edges {
        if let label = edge.label {
            print("  \"\\(edge.from)\" -> \"\\(edge.to)\" [label=\"\\(label)\"];")
        } else {
            print("  \"\\(edge.from)\" -> \"\\(edge.to)\";")
        }
    }
    print("}")
}

func renderASCII(nodes: [ContainerNode], edges: [DependencyEdge]) {
    let maxNameLen = nodes.map(\\.name.count).max() ?? 10

    print("InnoDI Dependency Graph")
    print(String(repeating: "=", count: maxNameLen + 15))
    print("Nodes:")
    for node in nodes {
        let padding = String(repeating: " ", count: maxNameLen - node.name.count)
        let root = node.isRoot ? " [ROOT]" : ""
        let inputs = node.requiredInputs.isEmpty ? "" : " (inputs: \\(node.requiredInputs.joined(separator: ", ")))"
        print("  \\(padding)\\(node.name)\\(root)\\(inputs)")
    }
    print()
    print("Edges:")
    for edge in edges {
        let labelPart = edge.label.map { ":\\(self)" } ?? ""
        let padding = String(repeating: " ", count: maxNameLen - edge.from.count)
        print("  \\(padding)\\(edge.from) -->\\(edge.to)\\(labelPart)")
    }
}

func main() -> Int32 {
    let (rootPath, format) = parseArguments()
    let outputFormat = format ?? .mermaid

    let files = loadSwiftFiles(rootPath: rootPath)

    let collector = ContainerCollector()
    for file in files {
        guard let tree = try? parseSourceFile(at: file) else { continue }
        collector.walk(tree)
    }

    let containerNames = Array(collector.nodes).map(\\.name)

    let usageCollector = ContainerUsageCollector(containerNames: Set<String>(containerNames))
    for file in files {
        guard let tree = try? parseSourceFile(at: file) else { continue }
        usageCollector.walkFile(path: file, tree: tree)
    }

    guard !collector.nodes.isEmpty else {
        fputs("No @DIContainer found in project.\\n", stderr)
        return 1
    }

    switch outputFormat {
    case .mermaid:
        renderMermaid(nodes: collector.nodes, edges: usageCollector.edges)
    case .dot:
        renderDOT(nodes: collector.nodes, edges: usageCollector.edges)
    case .ascii:
        renderASCII(nodes: collector.nodes, edges: usageCollector.edges)
    }

    return 0
}

exit(main())
