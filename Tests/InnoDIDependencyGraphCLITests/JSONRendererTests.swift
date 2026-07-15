import Foundation
import InnoDICore
import InnoDIDependencyGraphCore
import Testing

@Suite("JSON renderer")
struct JSONRendererTests {
    private let scope = GraphJSON.Scope(
        primaryTargetID: "swiftpm:root-package:App",
        rootPruning: .all
    )

    private func makeGraph() -> ([DependencyGraphNode], [DependencyGraphEdge]) {
        let nodes = [
            DependencyGraphNode(
                id: "swiftpm:root-package:App::AppContainer",
                displayName: "AppContainer",
                semanticPath: "App.AppContainer",
                isRoot: true,
                requiredInputs: ["config"]
            ),
            DependencyGraphNode(
                id: "swiftpm:root-package:App::FeatureContainer",
                displayName: "FeatureContainer",
                semanticPath: "App.FeatureContainer",
                isRoot: false,
                requiredInputs: []
            ),
            DependencyGraphNode(
                id: "swiftpm:root-package:App::LoggingContainer",
                displayName: "LoggingContainer",
                semanticPath: "App.LoggingContainer",
                isRoot: false,
                requiredInputs: []
            )
        ]
        let edges = [
            DependencyGraphEdge(
                fromID: "swiftpm:root-package:App::AppContainer",
                toID: "swiftpm:root-package:App::FeatureContainer",
                label: nil,
                isOwnership: true
            ),
            DependencyGraphEdge(
                fromID: "swiftpm:root-package:App::FeatureContainer",
                toID: "swiftpm:root-package:App::AppContainer",
                label: "config",
                isSoft: true
            ),
            DependencyGraphEdge(
                fromID: "swiftpm:root-package:App::AppContainer",
                toID: "swiftpm:root-package:App::LoggingContainer",
                label: "logger"
            ),
            DependencyGraphEdge(
                fromID: "swiftpm:root-package:App::FeatureContainer",
                toID: "swiftpm:root-package:App::LoggingContainer",
                label: "makeLogger",
                isProvider: true
            )
        ]
        return (nodes, edges)
    }

    @Test("Output parses as valid JSON with expected schema")
    func renderedOutputIsValidJSON() throws {
        let (nodes, edges) = makeGraph()
        let rendered = try renderJSON(
            scope: scope,
            nodes: nodes,
            edges: edges
        )

        let data = Data(rendered.utf8)
        let decoded = try JSONDecoder().decode(GraphJSON.Document.self, from: data)
        let rawDocument = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(decoded.schemaVersion == GraphJSON.currentSchemaVersion)
        #expect(decoded.scope == scope)
        #expect(Set(rawDocument.keys) == [
            "edges",
            "nodes",
            "schemaVersion",
            "scope",
        ])
        let rawScope = try #require(
            rawDocument["scope"] as? [String: Any]
        )
        #expect(Set(rawScope.keys) == ["primaryTargetID", "rootPruning"])
        let rawNodes = try #require(
            rawDocument["nodes"] as? [[String: Any]]
        )
        #expect(Set(try #require(rawNodes.first).keys) == [
            "displayName",
            "id",
            "isRoot",
            "requiredInputs",
            "semanticPath",
        ])
        let rawEdges = try #require(
            rawDocument["edges"] as? [[String: Any]]
        )
        let labeledEdge = try #require(
            rawEdges.first { $0["label"] != nil }
        )
        #expect(Set(labeledEdge.keys) == ["from", "kind", "label", "to"])
        #expect(decoded.nodes.count == 3)
        #expect(decoded.edges.count == 4)

        let appNode = try #require(
            decoded.nodes.first {
                $0.id == "swiftpm:root-package:App::AppContainer"
            }
        )
        #expect(appNode.isRoot)
        #expect(appNode.requiredInputs == ["config"])

        let ownershipEdge = try #require(decoded.edges.first { $0.kind == .ownership })
        #expect(
            ownershipEdge.from
                == "swiftpm:root-package:App::AppContainer"
        )
        #expect(
            ownershipEdge.to
                == "swiftpm:root-package:App::FeatureContainer"
        )

        let softEdge = try #require(decoded.edges.first { $0.kind == .soft })
        #expect(softEdge.label == "config")

        let hardEdge = try #require(decoded.edges.first { $0.kind == .hard })
        #expect(hardEdge.label == "logger")

        let providerEdge = try #require(decoded.edges.first { $0.kind == .provider })
        #expect(providerEdge.label == "makeLogger")
    }

    @Test("Empty graph produces empty node/edge lists")
    func emptyGraph() throws {
        let rendered = try renderJSON(
            scope: scope,
            nodes: [],
            edges: []
        )
        let decoded = try JSONDecoder().decode(GraphJSON.Document.self, from: Data(rendered.utf8))
        #expect(decoded.schemaVersion == GraphJSON.currentSchemaVersion)
        #expect(decoded.scope == scope)
        #expect(decoded.nodes.isEmpty)
        #expect(decoded.edges.isEmpty)
    }

    @Test("Canonical JSON is independent of collector order")
    func canonicalOrdering() throws {
        let (nodes, edges) = makeGraph()

        let forward = try renderJSON(
            scope: scope,
            nodes: nodes,
            edges: edges
        )
        let reversed = try renderJSON(
            scope: scope,
            nodes: Array(nodes.reversed()),
            edges: Array(edges.reversed())
        )

        #expect(forward == reversed)
        let decoded = try JSONDecoder().decode(
            GraphJSON.Document.self,
            from: Data(forward.utf8)
        )
        #expect(decoded.nodes.map(\.id) == decoded.nodes.map(\.id).sorted())
        #expect(decoded.edges.first?.kind == .ownership)
    }
}
