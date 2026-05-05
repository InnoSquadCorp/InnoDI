import Foundation
import InnoDICore

/// Renders the dependency graph as a machine-readable JSON document.
///
/// The schema is deliberately flat and stable across releases so CI
/// pipelines, IDE plugins, or web viewers can consume the output without
/// re-parsing the Mermaid/DOT text formats.
///
/// Schema version is embedded as `"schemaVersion": 1`; any breaking change
/// must bump that number and extend the consumer contract in a RELEASING
/// note.
package func renderJSON(nodes: [DependencyGraphNode], edges: [DependencyGraphEdge]) -> String {
    let nodePayloads: [GraphJSON.Node] = nodes.map { node in
        GraphJSON.Node(
            id: node.id,
            displayName: node.displayName,
            semanticPath: node.semanticPath,
            isRoot: node.isRoot,
            requiredInputs: node.requiredInputs
        )
    }

    let edgePayloads: [GraphJSON.Edge] = edges.map { edge in
        GraphJSON.Edge(
            from: edge.fromID,
            to: edge.toID,
            label: edge.label,
            kind: edgeKind(for: edge)
        )
    }

    let document = GraphJSON.Document(
        schemaVersion: 1,
        nodes: nodePayloads,
        edges: edgePayloads
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    do {
        let data = try encoder.encode(document)
        return (String(data: data, encoding: .utf8) ?? "{}") + "\n"
    } catch {
        return "{}\n"
    }
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
    package struct Document: Codable, Equatable {
        package let schemaVersion: Int
        package let nodes: [Node]
        package let edges: [Edge]
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
    }

    package enum EdgeKind: String, Codable, Equatable {
        case hard
        case soft
        case provider
        case ownership
    }
}
