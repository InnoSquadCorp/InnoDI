import Foundation
import InnoDICore

/// Renders the dependency graph as a machine-readable JSON document.
///
/// The schema is deliberately small and versioned so CI pipelines, IDE
/// plugins, or web viewers can consume it without re-parsing Mermaid/DOT.
///
/// Schema v2 makes analysis scope explicit and requires target-qualified node
/// identities. Callers therefore expose JSON only for manifest-backed graphs.
package func renderJSON(
    scope: GraphJSON.Scope,
    nodes: [DependencyGraphNode],
    edges: [DependencyGraphEdge]
) throws -> String {
    let nodePayloads: [GraphJSON.Node] = nodes.map { node in
        GraphJSON.Node(
            id: node.id,
            displayName: node.displayName,
            semanticPath: node.semanticPath,
            isRoot: node.isRoot,
            requiredInputs: node.requiredInputs.sorted()
        )
    }
    .sorted { $0.id < $1.id }

    let edgePayloads: [GraphJSON.Edge] = edges.map { edge in
        GraphJSON.Edge(
            from: edge.fromID,
            to: edge.toID,
            label: edge.label,
            kind: edgeKind(for: edge)
        )
    }
    .sorted(by: GraphJSON.Edge.canonicalOrder)

    let document = GraphJSON.Document(
        schemaVersion: GraphJSON.currentSchemaVersion,
        scope: scope,
        nodes: nodePayloads,
        edges: edgePayloads
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    let data = try encoder.encode(document)
    guard let rendered = String(data: data, encoding: .utf8) else {
        throw GraphJSON.EncodingError.invalidUTF8
    }
    return rendered + "\n"
}

private func edgeKind(for edge: DependencyGraphEdge) -> GraphJSON.EdgeKind {
    if edge.isOwnership { return .ownership }
    if edge.isProvider { return .provider }
    if edge.isSoft { return .soft }
    return .hard
}

/// Namespaces the JSON schema types so they stay close to the renderer
/// and aren't accidentally reused for an unrelated payload.
package enum GraphJSON {
    package static let currentSchemaVersion = 2

    package struct Document: Codable, Equatable {
        package let schemaVersion: Int
        package let scope: Scope
        package let nodes: [Node]
        package let edges: [Edge]
    }

    package struct Scope: Codable, Equatable {
        package let primaryTargetID: String
        package let rootPruning: DependencyGraphRootPruning

        package init(
            primaryTargetID: String,
            rootPruning: DependencyGraphRootPruning
        ) {
            self.primaryTargetID = primaryTargetID
            self.rootPruning = rootPruning
        }
    }

    package struct Node: Codable, Equatable {
        package let id: String
        package let displayName: String
        package let semanticPath: String
        package let isRoot: Bool
        package let requiredInputs: [String]
    }

    package struct Edge: Codable, Equatable {
        package let from: String
        package let to: String
        package let label: String?
        package let kind: EdgeKind

        fileprivate static func canonicalOrder(
            _ lhs: Self,
            _ rhs: Self
        ) -> Bool {
            if lhs.from != rhs.from {
                return lhs.from < rhs.from
            }
            if lhs.to != rhs.to {
                return lhs.to < rhs.to
            }
            if lhs.kind != rhs.kind {
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
            switch (lhs.label, rhs.label) {
            case (nil, .some):
                return true
            case (.some, nil):
                return false
            case (.some(let lhsLabel), .some(let rhsLabel)):
                return lhsLabel < rhsLabel
            case (nil, nil):
                return false
            }
        }
    }

    package enum EdgeKind: String, Codable, Equatable {
        case hard
        case soft
        case provider
        case ownership
    }

    package enum EncodingError: Error, Equatable {
        case invalidUTF8
    }
}
