//
//  main.swift
//  InnoDICLI
//

import Foundation
import InnoDICore
import SwiftParser
import SwiftSyntax

struct ContainerInfo {
    let name: String
    let validate: Bool
    let root: Bool
    let requiredInputs: [String]
}

struct ContainerCall {
    let callee: String
    let labels: Set<String>
    let file: String
    let line: Int
}

struct ContainerEdge {
    let from: String
    let to: String
}

struct DiagnosticItem {
    let message: String
    let file: String
    let line: Int
}

final class ContainerCollector: SyntaxVisitor {
    var containers: [String: ContainerInfo] = [:]

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

        containers[name] = ContainerInfo(
            name: name,
            validate: containerAttr.validate,
            root: containerAttr.root,
            requiredInputs: requiredInputs
        )
    }
}

final class ContainerUsageCollector: SyntaxVisitor {
    let containerNames: Set<String>
    var currentContainer: String?
    var calls: [ContainerCall] = []
    var edges: [ContainerEdge] = []

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

        let location = sourceLocation(of: Syntax(node))
        calls.append(ContainerCall(
            callee: calleeName,
            labels: labels,
            file: location.file,
            line: location.line
        ))

        if let currentContainer {
            edges.append(ContainerEdge(from: currentContainer, to: calleeName))
        }

        return .visitChildren
    }

    private func calledContainerName(_ expr: ExprSyntax) -> String? {
        let raw = expr.trimmedDescription
        let lastComponent = raw.split(separator: ".").last ?? ""
        let base = lastComponent.split(separator: "<").first ?? lastComponent
        let name = String(base)
        return containerNames.contains(name) ? name : nil
    }

    private func sourceLocation(of syntax: Syntax) -> (file: String, line: Int) {
        let converter = SourceLocationConverter(fileName: currentFile, tree: currentTree)
        let location = converter.location(for: syntax.positionAfterSkippingLeadingTrivia)
        return (file: location.file, line: location.line)
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

func parseArguments() -> String {
    var root = FileManager.default.currentDirectoryPath
    var iterator = CommandLine.arguments.makeIterator()
    _ = iterator.next()
    while let arg = iterator.next() {
        if arg == "--root", let value = iterator.next() {
            root = value
        }
    }
    return root
}

func main() -> Int32 {
    let rootPath = (parseArguments() as NSString).standardizingPath
    let files = loadSwiftFiles(rootPath: rootPath)

    let collector = ContainerCollector()
    for file in files {
        guard let tree = try? parseSourceFile(at: file) else { continue }
        collector.walk(tree)
    }

    let containers = collector.containers
    if containers.isEmpty {
        return 0
    }

    let usageCollector = ContainerUsageCollector(containerNames: Set(containers.keys))
    for file in files {
        guard let tree = try? parseSourceFile(at: file) else { continue }
        usageCollector.walkFile(path: file, tree: tree)
    }

    var diagnostics: [DiagnosticItem] = []

    for call in usageCollector.calls {
        guard let info = containers[call.callee], info.validate else { continue }
        for required in info.requiredInputs {
            if !call.labels.contains(required) {
                diagnostics.append(
                    DiagnosticItem(
                        message: "InnoDI: \(call.callee) is missing required input '\(required)'.",
                        file: call.file,
                        line: call.line
                    )
                )
            }
        }
    }

    let edges = usageCollector.edges
    var inbound: [String: Int] = [:]
    for name in containers.keys {
        inbound[name] = 0
    }
    for edge in edges {
        inbound[edge.to, default: 0] += 1
    }

    let explicitRoots = containers.values.filter { $0.root && $0.validate }.map { $0.name }
    let rootCandidates = explicitRoots.isEmpty
        ? inbound.filter { $0.value == 0 }.map { $0.key }
        : explicitRoots

    var reachable: Set<String> = []
    var stack = rootCandidates
    while let current = stack.popLast() {
        if reachable.contains(current) { continue }
        reachable.insert(current)
        let next = edges.filter { $0.from == current }.map { $0.to }
        stack.append(contentsOf: next)
    }

    for info in containers.values where info.validate {
        if !reachable.contains(info.name) {
            diagnostics.append(
                DiagnosticItem(
                    message: "InnoDI: \(info.name) is not reachable from any root container.",
                    file: "",
                    line: 1
                )
            )
        }
    }

    if !diagnostics.isEmpty {
        for item in diagnostics {
            if item.file.isEmpty {
                fputs("\(item.message)\n", stderr)
            } else {
                fputs("\(item.file):\(item.line): \(item.message)\n", stderr)
            }
        }
        return 1
    }

    return 0
}

exit(main())
