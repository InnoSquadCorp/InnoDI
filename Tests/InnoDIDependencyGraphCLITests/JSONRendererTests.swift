import Foundation
import InnoDICore
import Testing

@testable import InnoDI_DependencyGraph

@Suite("JSON renderer")
struct JSONRendererTests {
    private func makeGraph() -> ([DependencyGraphNode], [DependencyGraphEdge]) {
        let nodes = [
            DependencyGraphNode(
                id: "AppContainer",
                displayName: "AppContainer",
                semanticPath: "App.AppContainer",
                isRoot: true,
                requiredInputs: ["config"]
            ),
            DependencyGraphNode(
                id: "FeatureContainer",
                displayName: "FeatureContainer",
                semanticPath: "App.FeatureContainer",
                isRoot: false,
                requiredInputs: []
            )
        ]
        let edges = [
            DependencyGraphEdge(fromID: "AppContainer", toID: "FeatureContainer", label: nil, isOwnership: true),
            DependencyGraphEdge(fromID: "FeatureContainer", toID: "AppContainer", label: "config", isSoft: true)
        ]
        return (nodes, edges)
    }

    @Test("Output parses as valid JSON with expected schema")
    func renderedOutputIsValidJSON() throws {
        let (nodes, edges) = makeGraph()
        let rendered = renderJSON(nodes: nodes, edges: edges)

        let data = Data(rendered.utf8)
        let decoded = try JSONDecoder().decode(GraphJSON.Document.self, from: data)

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.nodes.count == 2)
        #expect(decoded.edges.count == 2)

        let appNode = try #require(decoded.nodes.first { $0.id == "AppContainer" })
        #expect(appNode.isRoot)
        #expect(appNode.requiredInputs == ["config"])

        let ownershipEdge = try #require(decoded.edges.first { $0.kind == .ownership })
        #expect(ownershipEdge.from == "AppContainer")
        #expect(ownershipEdge.to == "FeatureContainer")

        let softEdge = try #require(decoded.edges.first { $0.kind == .soft })
        #expect(softEdge.label == "config")
    }

    @Test("Empty graph produces empty node/edge lists")
    func emptyGraph() throws {
        let rendered = renderJSON(nodes: [], edges: [])
        let decoded = try JSONDecoder().decode(GraphJSON.Document.self, from: Data(rendered.utf8))
        #expect(decoded.schemaVersion == 1)
        #expect(decoded.nodes.isEmpty)
        #expect(decoded.edges.isEmpty)
    }
}
