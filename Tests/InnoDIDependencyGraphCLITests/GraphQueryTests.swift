import Foundation
import InnoDICore
import InnoDIDependencyGraphCore
import Testing

@testable import InnoDIDependencyGraphCLI

@Suite("Dependency graph queries")
struct GraphQueryTests {
    private let nodes = [
        DependencyGraphNode(
            id: "App::AppContainer",
            displayName: "AppContainer",
            semanticPath: "App.AppContainer",
            isRoot: true,
            requiredInputs: []
        ),
        DependencyGraphNode(
            id: "Feature::FeatureContainer",
            displayName: "FeatureContainer",
            semanticPath: "Feature.FeatureContainer",
            isRoot: false,
            requiredInputs: ["client"]
        ),
        DependencyGraphNode(
            id: "Data::DataContainer",
            displayName: "DataContainer",
            semanticPath: "Data.DataContainer",
            isRoot: false,
            requiredInputs: []
        ),
        DependencyGraphNode(
            id: "Preview::PreviewContainer",
            displayName: "PreviewContainer",
            semanticPath: "Preview.PreviewContainer",
            isRoot: false,
            requiredInputs: []
        ),
    ]

    private let edges = [
        DependencyGraphEdge(
            fromID: "App::AppContainer",
            toID: "Feature::FeatureContainer",
            label: "feature",
            isOwnership: true
        ),
        DependencyGraphEdge(
            fromID: "Feature::FeatureContainer",
            toID: "Data::DataContainer",
            label: "data"
        ),
    ]

    @Test("Why reports a deterministic shortest root path")
    func whyQuery() throws {
        let output = try renderGraphQuery(
            .why("DataContainer"),
            nodes: nodes,
            edges: edges
        )

        #expect(
            output == """
            Why DataContainer
            - AppContainer --[owns: feature]--> FeatureContainer
            - FeatureContainer --[depends: data]--> DataContainer

            """
        )
    }

    @Test("Dependents include direct and transitive consumers")
    func dependentsQuery() throws {
        let output = try renderGraphQuery(
            .dependents("Data.DataContainer"),
            nodes: nodes,
            edges: edges
        )

        #expect(
            output == """
            Dependents of DataContainer (2)
            - FeatureContainer (distance 1)
            - AppContainer (distance 2)

            """
        )
    }

    @Test("Unused reports nodes outside every root-reachable graph")
    func unusedQuery() throws {
        let output = try renderGraphQuery(
            .unused,
            nodes: nodes,
            edges: edges
        )

        #expect(
            output == """
            Unused containers (1)
            - PreviewContainer

            """
        )
    }

    @Test("Queries reject missing, ambiguous, rootless, and unreachable selections")
    func queryFailures() {
        #expect(throws: GraphInspectionError.nodeNotFound(selector: "Missing")) {
            try renderGraphQuery(.why("Missing"), nodes: nodes, edges: edges)
        }

        let duplicate = DependencyGraphNode(
            id: "Other::DataContainer",
            displayName: "DataContainer",
            semanticPath: "Other.DataContainer",
            isRoot: false,
            requiredInputs: []
        )
        #expect(
            throws: GraphInspectionError.ambiguousNode(
                selector: "DataContainer",
                candidates: ["Data::DataContainer", "Other::DataContainer"]
            )
        ) {
            try renderGraphQuery(
                .dependents("DataContainer"),
                nodes: nodes + [duplicate],
                edges: edges
            )
        }

        #expect(throws: GraphInspectionError.noRoots) {
            try renderGraphQuery(
                .unused,
                nodes: Array(nodes.dropFirst()),
                edges: edges
            )
        }

        #expect(
            throws: GraphInspectionError.unreachableFromRoots(
                selector: "PreviewContainer"
            )
        ) {
            try renderGraphQuery(
                .why("PreviewContainer"),
                nodes: nodes,
                edges: edges
            )
        }
    }

    @Test("Query failures provide actionable CLI descriptions")
    func queryFailureDescriptions() {
        #expect(
            GraphInspectionError.nodeNotFound(selector: "Missing").errorDescription
                == "No container matches 'Missing'. Use an exact graph ID, semantic path, or display name."
        )
        #expect(
            GraphInspectionError.ambiguousNode(
                selector: "ServiceContainer",
                candidates: ["FeatureA::ServiceContainer", "FeatureB::ServiceContainer"]
            ).errorDescription
                == "Container selector 'ServiceContainer' is ambiguous. Candidates: FeatureA::ServiceContainer, FeatureB::ServiceContainer"
        )
        #expect(
            GraphInspectionError.noRoots.errorDescription
                == "This query requires at least one explicit graph root."
        )
        #expect(
            GraphInspectionError.unreachableFromRoots(selector: "PreviewContainer")
                .errorDescription
                == "Container 'PreviewContainer' is not reachable from any explicit graph root."
        )
        #expect(
            GraphInspectionError.unsupportedSchema(
                path: "graph-v2.json",
                found: 2,
                expected: 3
            ).errorDescription
                == "Graph document 'graph-v2.json' uses schema v2; --diff currently requires schema v3."
        )
    }

    @Test("Graph diff reports scope, node, and edge changes")
    func graphDiff() throws {
        let before = try graphDocument(
            nodes: Array(nodes.prefix(2)),
            edges: Array(edges.prefix(1)),
            pruning: .roots
        )
        let changedFeature = DependencyGraphNode(
            id: "Feature::FeatureContainer",
            displayName: "FeatureContainer",
            semanticPath: "Feature.FeatureContainer",
            isRoot: false,
            requiredInputs: ["client", "session"]
        )
        let after = try graphDocument(
            nodes: [nodes[0], changedFeature, nodes[2]],
            edges: edges,
            pruning: .all
        )

        let output = renderGraphDiff(before: before, after: after)
        let report = compareGraphDocuments(before: before, after: after)

        #expect(report.hasChanges)
        #expect(output.contains("Scope: App, pruning=roots -> App, pruning=all"))
        #expect(output.contains("Nodes added (1)\n+ Data::DataContainer"))
        #expect(output.contains("Nodes changed (1)"))
        #expect(output.contains("inputs [client] -> [client, session]"))
        #expect(output.contains("Edges added (1)"))
        #expect(
            output.contains(
                "+ Feature::FeatureContainer --[hard: data]--> Data::DataContainer"
            )
        )
    }

    @Test("Graph diff report treats identical documents as unchanged")
    func unchangedGraphDiff() throws {
        let document = try graphDocument(
            nodes: Array(nodes.prefix(2)),
            edges: Array(edges.prefix(1)),
            pruning: .roots
        )

        let report = compareGraphDocuments(before: document, after: document)

        #expect(!report.hasChanges)
        #expect(renderGraphDiff(report).contains("Scope: unchanged"))
    }

    private func graphDocument(
        nodes: [DependencyGraphNode],
        edges: [DependencyGraphEdge],
        pruning: DependencyGraphRootPruning
    ) throws -> GraphJSON.Document {
        let rendered = try renderJSON(
            scope: GraphJSON.Scope(
                primaryTargetID: "App",
                rootPruning: pruning
            ),
            nodes: nodes,
            edges: edges
        )
        return try JSONDecoder().decode(
            GraphJSON.Document.self,
            from: Data(rendered.utf8)
        )
    }
}
