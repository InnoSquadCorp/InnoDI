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
                requiredInputs: ["config"],
                assistedInputs: ["sessionID"]
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
                fromID: "swiftpm:root-package:App::AppContainer",
                toID: "swiftpm:root-package:App::FeatureContainer",
                label: "featureFactory",
                isAssistedFactoryOwnership: true
            ),
            DependencyGraphEdge(
                fromID: "swiftpm:root-package:App::AppContainer",
                toID: "swiftpm:root-package:App::AppContainer",
                label: "interceptors",
                isContribution: true,
                contributor: "auth",
                order: 0
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
            "providers",
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
            "assistedInputs",
            "requiredInputs",
            "semanticPath",
        ])
        let rawEdges = try #require(
            rawDocument["edges"] as? [[String: Any]]
        )
        let labeledEdge = try #require(
            rawEdges.first { $0["kind"] as? String == "hard" }
        )
        #expect(Set(labeledEdge.keys) == ["from", "kind", "label", "to"])
        #expect(decoded.nodes.count == 3)
        #expect(decoded.edges.count == 6)
        #expect(decoded.providers.isEmpty)

        let appNode = try #require(
            decoded.nodes.first {
                $0.id == "swiftpm:root-package:App::AppContainer"
            }
        )
        #expect(appNode.isRoot)
        #expect(appNode.requiredInputs == ["config"])
        #expect(appNode.assistedInputs == ["sessionID"])

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

        let factoryEdge = try #require(
            decoded.edges.first { $0.kind == .assistedFactoryOwnership }
        )
        #expect(factoryEdge.label == "featureFactory")

        let contributionEdge = try #require(
            decoded.edges.first { $0.kind == .contribution }
        )
        #expect(contributionEdge.contributor == "auth")
        #expect(contributionEdge.order == 0)
        let rawContribution = try #require(
            rawEdges.first { $0["kind"] as? String == "contribution" }
        )
        #expect(Set(rawContribution.keys) == [
            "contributor", "from", "kind", "label", "order", "to",
        ])
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

    @Test("collection contracts serialize key order contributor and lifetime")
    func collectionContract() throws {
        let containerID = "swiftpm:root-package:App::AppContainer"
        let contributorID = "\(containerID).auth"
        let providers = [
            DependencyGraphProvider(
                id: contributorID,
                containerID: containerID,
                name: "auth",
                type: "Service",
                role: .provider,
                lifetime: .shared,
                initialization: .eager,
                isolation: .nonisolated,
                effect: .sync,
                source: .init(path: "Sources/App.swift", line: 2, column: 5)
            ),
            DependencyGraphProvider(
                id: "\(containerID).providers",
                containerID: containerID,
                name: "providers",
                type: "DIKeyedProviderCollection<String, Service>",
                role: .provider,
                lifetime: .transient,
                initialization: .onAccess,
                isolation: .nonisolated,
                effect: .sync,
                collection: .init(
                    kind: .keyedProviders,
                    entries: [
                        .init(
                            key: "auth",
                            order: 0,
                            providerID: contributorID,
                            providerLifetime: .shared
                        ),
                    ]
                ),
                source: .init(path: "Sources/App.swift", line: 3, column: 5)
            ),
        ]
        let rendered = try renderJSON(
            scope: scope,
            nodes: [],
            edges: [],
            providers: providers
        )
        let data = Data(rendered.utf8)
        let decoded = try JSONDecoder().decode(GraphJSON.Document.self, from: data)
        let contract = try #require(
            decoded.providers.first { $0.name == "providers" }?.collection
        )

        #expect(contract.kind == .keyedProviders)
        #expect(contract.entries.map(\.key) == ["auth"])
        #expect(contract.entries.map(\.order) == [0])
        #expect(contract.entries.map(\.providerID) == [contributorID])
        #expect(contract.entries.map(\.providerLifetime) == [.shared])

        let rawDocument = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let rawProviders = try #require(
            rawDocument["providers"] as? [[String: Any]]
        )
        let rawProvider = try #require(
            rawProviders.first { $0["name"] as? String == "providers" }
        )
        let rawCollection = try #require(
            rawProvider["collection"] as? [String: Any]
        )
        #expect(Set(rawCollection.keys) == ["entries", "kind"])
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
        #expect(decoded.edges.first?.kind == .contribution)
    }
}
