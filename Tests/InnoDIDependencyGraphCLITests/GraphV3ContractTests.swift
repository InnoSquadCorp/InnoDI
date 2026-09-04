import Foundation
import InnoDICore
import InnoDIWorkspaceAnalysis
import SwiftParser
import Testing

@testable import InnoDIDependencyGraphCore
@testable import InnoDIDependencyGraphCLI

@Suite("Graph JSON v3 contract")
struct GraphV3ContractTests {
    @Test("assisted inputs, factory ownership, and contributions are explicit")
    func collectsVersionThreeSemantics() throws {
        let source = Parser.parse(source: """
        @DIContainer
        struct ChildContainer {
            @Input var repository: Repository
            @Input(.assisted) var sessionID: Int
        }

        @DIContainer(root: true)
        struct AppContainer {
            @Provide(.shared, factory: Repository())
            var repository: Repository

            @Provide(.shared, factory: Auth())
            var auth: any Interceptor

            @Provide(.transient, factory: Logging())
            var logging: any Interceptor

            @Multibinding([\\Self.auth, \\Self.logging])
            var interceptors: [any Interceptor]

            @SubContainerFactory(
                ChildContainer.self,
                bindings: [
                    (child: \\ChildContainer.repository, parent: \\AppContainer.repository),
                ]
            )
            var child: ChildContainer.AssistedFactory
        }
        """)
        let root = URL(fileURLWithPath: "/workspace")
        let snapshot = WorkspaceSourceSnapshot(
            rootPath: root.path,
            rootURL: root,
            files: [
                WorkspaceSourceFile(
                    relativePath: "Sources/App/Containers.swift",
                    fileURL: root.appendingPathComponent(
                        "Sources/App/Containers.swift"
                    ),
                    syntax: source
                )
            ]
        )

        let graph = collectDependencyGraph(
            snapshot: snapshot,
            validateDAG: true
        )
        let child = try #require(
            graph.nodes.first { $0.displayName == "ChildContainer" }
        )
        let app = try #require(
            graph.nodes.first { $0.displayName == "AppContainer" }
        )
        #expect(child.requiredInputs == ["repository"])
        #expect(child.assistedInputs == ["sessionID"])

        let factoryEdge = try #require(graph.edges.first {
            $0.isAssistedFactoryOwnership
        })
        #expect(factoryEdge.fromID == app.id)
        #expect(factoryEdge.toID == child.id)
        #expect(factoryEdge.label == "child")

        let contributions = graph.edges.filter(\.isContribution)
            .sorted { ($0.order ?? -1) < ($1.order ?? -1) }
        #expect(contributions.map(\.contributor) == ["auth", "logging"])
        #expect(contributions.map(\.order) == [0, 1])
        #expect(contributions.allSatisfy {
            $0.fromID == app.id && $0.toID == app.id
        })

        let adjacency = buildCycleDetectionAdjacency(
            nodes: graph.nodes,
            edges: graph.edges
        )
        #expect(adjacency[app.id]?.contains(app.id) == false)

        let rendered = try renderJSON(
            scope: GraphJSON.Scope(
                primaryTargetID: "App",
                rootPruning: .all
            ),
            nodes: graph.nodes,
            edges: graph.edges
        )
        let document = try JSONDecoder().decode(
            GraphJSON.Document.self,
            from: Data(rendered.utf8)
        )
        #expect(document.schemaVersion == 3)
        #expect(
            document.edges.contains {
                $0.kind == .assistedFactoryOwnership
            }
        )
        #expect(document.edges.filter { $0.kind == .contribution }.count == 2)
    }

    @Test("human renderers expose every v3 semantic")
    func rendersVersionThreeSemantics() {
        let nodes = [
            DependencyGraphNode(
                id: "App",
                displayName: "AppContainer",
                semanticPath: "AppContainer",
                isRoot: true,
                requiredInputs: [],
                assistedInputs: ["sessionID"]
            ),
            DependencyGraphNode(
                id: "Child",
                displayName: "ChildContainer",
                semanticPath: "ChildContainer",
                isRoot: false,
                requiredInputs: []
            ),
        ]
        let edges = [
            DependencyGraphEdge(
                fromID: "App",
                toID: "Child",
                label: "child",
                isAssistedFactoryOwnership: true
            ),
            DependencyGraphEdge(
                fromID: "App",
                toID: "App",
                label: "interceptors",
                isContribution: true,
                contributor: "auth",
                order: 0
            ),
        ]

        let mermaid = renderMermaid(nodes: nodes, edges: edges)
        let dot = renderDOT(nodes: nodes, edges: edges)
        let ascii = renderASCII(nodes: nodes, edges: edges)

        #expect(mermaid.contains("assisted: sessionID"))
        #expect(mermaid.contains("factory owns: child"))
        #expect(mermaid.contains("contributes[0]: auth → interceptors"))
        #expect(dot.contains("factory owns: child"))
        #expect(dot.contains("contributes[0]: auth -> interceptors"))
        #expect(ascii.contains("(assisted: sessionID)"))
        #expect(ascii.contains("@=> ChildContainer:factory-owns,child"))
        #expect(ascii.contains("+=> AppContainer:contributes[0],auth->interceptors"))
    }

    @Test("contribution order changes trip the graph contract diff")
    func contributionOrderIsContractual() throws {
        let node = DependencyGraphNode(
            id: "App",
            displayName: "AppContainer",
            semanticPath: "AppContainer",
            isRoot: true,
            requiredInputs: []
        )
        func document(order: Int) throws -> GraphJSON.Document {
            let rendered = try renderJSON(
                scope: GraphJSON.Scope(
                    primaryTargetID: "App",
                    rootPruning: .all
                ),
                nodes: [node],
                edges: [
                    DependencyGraphEdge(
                        fromID: "App",
                        toID: "App",
                        label: "interceptors",
                        isContribution: true,
                        contributor: "auth",
                        order: order
                    )
                ]
            )
            return try JSONDecoder().decode(
                GraphJSON.Document.self,
                from: Data(rendered.utf8)
            )
        }

        let report = compareGraphDocuments(
            before: try document(order: 0),
            after: try document(order: 1)
        )
        #expect(report.hasChanges)
        #expect(report.removedEdgeIDs.first?.contains("order=0") == true)
        #expect(report.addedEdgeIDs.first?.contains("order=1") == true)
    }
}
