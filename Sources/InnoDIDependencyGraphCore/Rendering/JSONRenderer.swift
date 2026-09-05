import Foundation
import InnoDICore

/// Renders the dependency graph as a machine-readable JSON document.
///
/// The schema is deliberately small and versioned so CI pipelines, IDE
/// plugins, or web viewers can consume it without re-parsing Mermaid/DOT.
///
/// Schema v4 adds canonical provider semantics and diagnostic-only source
/// locations. Target-qualified identity and explicit analysis scope remain
/// required from schema v2.
package func renderJSON(
    scope: GraphJSON.Scope,
    nodes: [DependencyGraphNode],
    edges: [DependencyGraphEdge],
    providers: [DependencyGraphProvider] = []
) throws -> String {
    let nodePayloads: [GraphJSON.Node] = nodes.map { node in
        GraphJSON.Node(
            id: node.id,
            displayName: node.displayName,
            semanticPath: node.semanticPath,
            isRoot: node.isRoot,
            requiredInputs: node.requiredInputs.sorted(),
            assistedInputs: node.assistedInputs.sorted()
        )
    }
    .sorted { $0.id < $1.id }

    let edgePayloads: [GraphJSON.Edge] = edges.map { edge in
        GraphJSON.Edge(
            from: edge.fromID,
            to: edge.toID,
            label: edge.label,
            kind: edgeKind(for: edge),
            contributor: edge.contributor,
            order: edge.order
        )
    }
    .sorted(by: GraphJSON.Edge.canonicalOrder)

    let providerPayloads = providers.map(GraphJSON.Provider.init)
        .sorted { $0.id < $1.id }

    let document = GraphJSON.Document(
        schemaVersion: GraphJSON.currentSchemaVersion,
        scope: scope,
        nodes: nodePayloads,
        edges: edgePayloads,
        providers: providerPayloads
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
    if edge.isContribution { return .contribution }
    if edge.isAssistedFactoryOwnership { return .assistedFactoryOwnership }
    if edge.isOwnership { return .ownership }
    if edge.isProvider { return .provider }
    if edge.isSoft { return .soft }
    return .hard
}

/// Namespaces the JSON schema types so they stay close to the renderer
/// and aren't accidentally reused for an unrelated payload.
package enum GraphJSON {
    package static let currentSchemaVersion = 4

    package struct Document: Codable, Equatable {
        package let schemaVersion: Int
        package let scope: Scope
        package let nodes: [Node]
        package let edges: [Edge]
        package let providers: [Provider]

        package init(
            schemaVersion: Int,
            scope: Scope,
            nodes: [Node],
            edges: [Edge],
            providers: [Provider] = []
        ) {
            self.schemaVersion = schemaVersion
            self.scope = scope
            self.nodes = nodes
            self.edges = edges
            self.providers = providers
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case scope
            case nodes
            case edges
            case providers
        }

        package init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            scope = try container.decode(Scope.self, forKey: .scope)
            nodes = try container.decode([Node].self, forKey: .nodes)
            edges = try container.decode([Edge].self, forKey: .edges)
            providers = try container.decodeIfPresent(
                [Provider].self,
                forKey: .providers
            ) ?? []
        }
    }

    package struct Provider: Codable, Equatable {
        package let id: String
        package let containerID: String
        package let name: String
        package let type: String
        package let role: DependencyGraphProvider.Role
        package let lifetime: DependencyGraphProvider.Lifetime
        package let initialization: DependencyGraphProvider.Initialization
        package let isolation: DependencyGraphProvider.Isolation
        package let effect: DependencyGraphProvider.Effect
        package let inputKind: DependencyGraphProvider.InputKind?
        package let dependencies: [String]
        package let source: Source

        package init(_ provider: DependencyGraphProvider) {
            id = provider.id
            containerID = provider.containerID
            name = provider.name
            type = provider.type
            role = provider.role
            lifetime = provider.lifetime
            initialization = provider.initialization
            isolation = provider.isolation
            effect = provider.effect
            inputKind = provider.inputKind
            dependencies = provider.dependencies
            source = Source(provider.source)
        }

        package struct Source: Codable, Equatable {
            package let path: String
            package let line: Int
            package let column: Int

            package init(_ source: DependencyGraphProvider.SourceLocation) {
                path = source.path
                line = source.line
                column = source.column
            }
        }

        package var semanticIdentity: SemanticIdentity {
            SemanticIdentity(
                containerID: containerID,
                name: name,
                type: type,
                role: role,
                lifetime: lifetime,
                initialization: initialization,
                isolation: isolation,
                effect: effect,
                inputKind: inputKind,
                dependencies: dependencies
            )
        }

        package struct SemanticIdentity: Equatable {
            let containerID: String
            let name: String
            let type: String
            let role: DependencyGraphProvider.Role
            let lifetime: DependencyGraphProvider.Lifetime
            let initialization: DependencyGraphProvider.Initialization
            let isolation: DependencyGraphProvider.Isolation
            let effect: DependencyGraphProvider.Effect
            let inputKind: DependencyGraphProvider.InputKind?
            let dependencies: [String]
        }
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
        package let assistedInputs: [String]

        package init(
            id: String,
            displayName: String,
            semanticPath: String,
            isRoot: Bool,
            requiredInputs: [String],
            assistedInputs: [String]
        ) {
            self.id = id
            self.displayName = displayName
            self.semanticPath = semanticPath
            self.isRoot = isRoot
            self.requiredInputs = requiredInputs
            self.assistedInputs = assistedInputs
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case displayName
            case semanticPath
            case isRoot
            case requiredInputs
            case assistedInputs
        }

        package init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            displayName = try container.decode(String.self, forKey: .displayName)
            semanticPath = try container.decode(String.self, forKey: .semanticPath)
            isRoot = try container.decode(Bool.self, forKey: .isRoot)
            requiredInputs = try container.decode([String].self, forKey: .requiredInputs)
            assistedInputs = try container.decodeIfPresent(
                [String].self,
                forKey: .assistedInputs
            ) ?? []
        }
    }

    package struct Edge: Codable, Equatable {
        package let from: String
        package let to: String
        package let label: String?
        package let kind: EdgeKind
        package let contributor: String?
        package let order: Int?

        package init(
            from: String,
            to: String,
            label: String?,
            kind: EdgeKind,
            contributor: String? = nil,
            order: Int? = nil
        ) {
            self.from = from
            self.to = to
            self.label = label
            self.kind = kind
            self.contributor = contributor
            self.order = order
        }

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
            if lhs.order != rhs.order {
                return (lhs.order ?? .min) < (rhs.order ?? .min)
            }
            if lhs.contributor != rhs.contributor {
                return (lhs.contributor ?? "") < (rhs.contributor ?? "")
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
        case assistedFactoryOwnership
        case contribution
    }

    package enum EncodingError: Error, Equatable {
        case invalidUTF8
    }
}
