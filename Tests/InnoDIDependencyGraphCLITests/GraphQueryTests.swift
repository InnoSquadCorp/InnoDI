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

    private let providers = [
        DependencyGraphProvider(
            id: "Data::DataContainer.client",
            containerID: "Data::DataContainer",
            name: "client",
            type: "Client",
            role: .provider,
            lifetime: .shared,
            initialization: .onDemand,
            isolation: .nonisolated,
            effect: .asyncThrows,
            source: .init(path: "Sources/Data.swift", line: 12, column: 5)
        ),
        DependencyGraphProvider(
            id: "Data::DataContainer.repository",
            containerID: "Data::DataContainer",
            name: "repository",
            type: "Repository",
            role: .provider,
            lifetime: .transient,
            initialization: .onAccess,
            isolation: .nonisolated,
            effect: .sync,
            dependencies: ["renamedClient"],
            dependencyBindings: [
                .init(
                    parameter: "renamedClient",
                    providerID: "Data::DataContainer.client",
                    kind: .hard
                ),
            ],
            source: .init(path: "Sources/Data.swift", line: 18, column: 5)
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

    @Test("provider queries include contract, source, and transitive dependents")
    func providerQueries() throws {
        let why = try renderGraphQuery(
            .why("DataContainer.client"),
            nodes: nodes,
            edges: edges,
            providers: providers
        )
        let dependents = try renderGraphQuery(
            .dependents("Data::DataContainer.client"),
            nodes: nodes,
            edges: edges,
            providers: providers
        )

        #expect(why.contains("Why provider Data::DataContainer.client"))
        #expect(why.contains("Source: Sources/Data.swift:12:5"))
        #expect(why.contains("initialization=onDemand"))
        #expect(why.contains("Runtime provenance: attach a DITraceContext"))
        #expect(dependents.contains("Data::DataContainer.repository (distance 1"))
    }

    @Test("container and provider namespace collisions require an explicit qualifier")
    func namespaceCollision() throws {
        let collidingContainer = DependencyGraphNode(
            id: "Services::client",
            displayName: "client",
            semanticPath: "Services.client",
            isRoot: false,
            requiredInputs: []
        )
        let collidingNodes = nodes + [collidingContainer]

        #expect(
            throws: GraphInspectionError.ambiguousTarget(
                selector: "client",
                containerCandidates: ["Services::client"],
                providerCandidates: ["Data::DataContainer.client"]
            )
        ) {
            try renderGraphQuery(
                .why("client"),
                nodes: collidingNodes,
                edges: edges,
                providers: providers
            )
        }

        let container = try renderGraphQuery(
            .dependents("container:client"),
            nodes: collidingNodes,
            edges: edges,
            providers: providers
        )
        let provider = try renderGraphQuery(
            .why("provider:client"),
            nodes: collidingNodes,
            edges: edges,
            providers: providers
        )
        let exactProvider = try renderGraphQuery(
            .why("Data::DataContainer.client"),
            nodes: collidingNodes,
            edges: edges,
            providers: providers
        )
        let exactContainer = try renderGraphQuery(
            .dependents("Services::client"),
            nodes: collidingNodes,
            edges: edges,
            providers: providers
        )

        #expect(container == "Dependents of client (0)\n")
        #expect(exactContainer == container)
        #expect(provider.contains("Why provider Data::DataContainer.client"))
        #expect(provider.contains("Source: Sources/Data.swift:12:5"))
        #expect(exactProvider == provider)
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
        #expect(throws: GraphInspectionError.targetNotFound(selector: "Missing")) {
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
            GraphInspectionError.targetNotFound(selector: "Missing").errorDescription
                == "No container or provider matches 'Missing'. Use an exact graph ID or qualify the selector with container: or provider:."
        )
        #expect(
            GraphInspectionError.ambiguousNode(
                selector: "ServiceContainer",
                candidates: ["FeatureA::ServiceContainer", "FeatureB::ServiceContainer"]
            ).errorDescription
                == "Container selector 'ServiceContainer' is ambiguous. Candidates: FeatureA::ServiceContainer, FeatureB::ServiceContainer"
        )
        #expect(
            GraphInspectionError.ambiguousTarget(
                selector: "client",
                containerCandidates: ["Feature::client"],
                providerCandidates: ["Data::DataContainer.client"]
            ).errorDescription
                == "Graph selector 'client' matches both namespaces. Containers: Feature::client; providers: Data::DataContainer.client. Qualify it with container: or provider:."
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
                expected: 6
            ).errorDescription
                == "Graph document 'graph-v2.json' uses schema v2; --diff currently requires schema v6."
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

    @Test("Graph diff rejects a decodable schema-v2 document with a stable error")
    func rejectsSchemaV2Document() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("innodi-graph-v2-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let payload = """
        {
          "schemaVersion": 2,
          "scope": { "primaryTargetID": "App", "rootPruning": "roots" },
          "nodes": [{
            "id": "App::AppContainer",
            "displayName": "AppContainer",
            "semanticPath": "App.AppContainer",
            "isRoot": true,
            "requiredInputs": []
          }],
          "edges": []
        }
        """
        try Data(payload.utf8).write(to: fileURL, options: .atomic)

        #expect(throws: GraphInspectionError.unsupportedSchema(
            path: fileURL.path,
            found: 2,
            expected: 6
        )) {
            _ = try loadGraphJSONDocument(at: fileURL.path)
        }
    }

    @Test("Graph diff rejects duplicate identities and dangling references")
    func rejectsMalformedCurrentDocuments() throws {
        let payloads: [(String, String)] = [
            ("duplicate-node", """
            {
              "schemaVersion": 6,
              "scope": { "primaryTargetID": "App", "rootPruning": "all" },
              "nodes": [
                { "id": "App", "displayName": "App", "semanticPath": "App", "isRoot": true, "requiredInputs": [] },
                { "id": "App", "displayName": "Again", "semanticPath": "Again", "isRoot": false, "requiredInputs": [] }
              ],
              "edges": [],
              "providers": []
            }
            """),
            ("dangling-edge", """
            {
              "schemaVersion": 6,
              "scope": { "primaryTargetID": "App", "rootPruning": "all" },
              "nodes": [{ "id": "App", "displayName": "App", "semanticPath": "App", "isRoot": true, "requiredInputs": [] }],
              "edges": [{ "from": "App", "to": "Missing", "kind": "hard" }],
              "providers": []
            }
            """),
            ("dangling-provider", """
            {
              "schemaVersion": 6,
              "scope": { "primaryTargetID": "App", "rootPruning": "all" },
              "nodes": [{ "id": "App", "displayName": "App", "semanticPath": "App", "isRoot": true, "requiredInputs": [] }],
              "edges": [],
              "providers": [{
                "id": "Missing.value", "containerID": "Missing", "name": "value", "type": "Int",
                "role": "input", "lifetime": "external", "initialization": "external",
                "isolation": "nonisolated", "effect": "sync", "inputKind": "container",
                "dependencies": [], "dependencyBindings": [], "containerBindings": [],
                "source": { "path": "App.swift", "line": 1, "column": 1 }
              }]
            }
            """),
            ("duplicate-collection-key", """
            {
              "schemaVersion": 6,
              "scope": { "primaryTargetID": "App", "rootPruning": "all" },
              "nodes": [{ "id": "App", "displayName": "App", "semanticPath": "App", "isRoot": true, "requiredInputs": [] }],
              "edges": [],
              "providers": [
                {
                  "id": "App.auth", "containerID": "App", "name": "auth", "type": "Service",
                  "role": "provider", "lifetime": "shared", "initialization": "eager",
                  "isolation": "nonisolated", "effect": "sync", "dependencies": [],
                  "dependencyBindings": [], "containerBindings": [],
                  "source": { "path": "App.swift", "line": 1, "column": 1 }
                },
                {
                  "id": "App.providers", "containerID": "App", "name": "providers", "type": "Providers",
                  "role": "provider", "lifetime": "transient", "initialization": "onAccess",
                  "isolation": "nonisolated", "effect": "sync", "dependencies": [],
                  "dependencyBindings": [], "containerBindings": [],
                  "collection": {
                    "kind": "keyedProviders",
                    "entries": [
                      { "key": "same", "order": 0, "providerID": "App.auth", "providerLifetime": "shared" },
                      { "key": "same", "order": 1, "providerID": "App.auth", "providerLifetime": "shared" }
                    ]
                  },
                  "source": { "path": "App.swift", "line": 2, "column": 1 }
                }
              ]
            }
            """),
        ]

        for (name, payload) in payloads {
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("innodi-graph-\(name)-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: fileURL) }
            try Data(payload.utf8).write(to: fileURL, options: .atomic)
            #expect(throws: GraphInspectionError.self) {
                _ = try loadGraphJSONDocument(at: fileURL.path)
            }
        }
    }

    @Test("Schema v6 rejects missing provider binding metadata")
    func rejectsMissingVersionSixBindingMetadata() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("innodi-graph-missing-bindings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let payload = """
        {
          "schemaVersion": 6,
          "scope": { "primaryTargetID": "App", "rootPruning": "all" },
          "nodes": [{
            "id": "App", "displayName": "App", "semanticPath": "App",
            "isRoot": true, "requiredInputs": [], "assistedInputs": []
          }],
          "edges": [],
          "providers": [{
            "id": "App.value", "containerID": "App", "name": "value", "type": "Int",
            "role": "input", "lifetime": "external", "initialization": "external",
            "isolation": "nonisolated", "effect": "sync", "inputKind": "container",
            "dependencies": [], "source": { "path": "App.swift", "line": 1, "column": 1 }
          }]
        }
        """
        try Data(payload.utf8).write(to: fileURL, options: .atomic)

        #expect(throws: DecodingError.self) {
            _ = try loadGraphJSONDocument(at: fileURL.path)
        }
    }

    @Test("Schema v6 rejects every malformed collection contract dimension")
    func rejectsMalformedCollectionContracts() throws {
        let containerID = "App"
        let contributorID = "App.auth"
        let contributor = DependencyGraphProvider(
            id: contributorID,
            containerID: containerID,
            name: "auth",
            type: "Service",
            role: .provider,
            lifetime: .shared,
            initialization: .eager,
            isolation: .nonisolated,
            effect: .sync,
            source: .init(path: "App.swift", line: 1, column: 1)
        )
        let variants: [(
            name: String,
            contract: DependencyGraphProvider.CollectionContract,
            expected: String
        )] = [
            (
                "missing-key",
                .init(
                    kind: .keyed,
                    entries: [
                        .init(
                            key: nil,
                            order: 0,
                            providerID: contributorID,
                            providerLifetime: .shared
                        ),
                    ]
                ),
                "entry without a key"
            ),
            (
                "unexpected-key",
                .init(
                    kind: .ordered,
                    entries: [
                        .init(
                            key: "auth",
                            order: 0,
                            providerID: contributorID,
                            providerLifetime: .shared
                        ),
                    ]
                ),
                "unexpected key"
            ),
            (
                "order-gap",
                .init(
                    kind: .providers,
                    entries: [
                        .init(
                            key: nil,
                            order: 1,
                            providerID: contributorID,
                            providerLifetime: .shared
                        ),
                    ]
                ),
                "contiguous from zero"
            ),
            (
                "missing-contributor",
                .init(
                    kind: .keyedProviders,
                    entries: [
                        .init(
                            key: "missing",
                            order: 0,
                            providerID: "App.missing",
                            providerLifetime: .transient
                        ),
                    ]
                ),
                "is missing or belongs to another container"
            ),
            (
                "stale-lifetime",
                .init(
                    kind: .keyedProviders,
                    entries: [
                        .init(
                            key: "auth",
                            order: 0,
                            providerID: contributorID,
                            providerLifetime: .transient
                        ),
                    ]
                ),
                "stale lifetime metadata"
            ),
        ]

        for variant in variants {
            let collectionProvider = DependencyGraphProvider(
                id: "App.collection",
                containerID: containerID,
                name: "collection",
                type: "Collection",
                role: .provider,
                lifetime: .transient,
                initialization: .onAccess,
                isolation: .nonisolated,
                effect: .sync,
                collection: variant.contract,
                source: .init(path: "App.swift", line: 2, column: 1)
            )
            let rendered = try renderJSON(
                scope: .init(
                    primaryTargetID: "App",
                    rootPruning: .all
                ),
                nodes: [
                    .init(
                        id: containerID,
                        displayName: "App",
                        semanticPath: "App",
                        isRoot: true,
                        requiredInputs: []
                    ),
                ],
                edges: [],
                providers: [contributor, collectionProvider]
            )
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "innodi-graph-collection-\(variant.name)-\(UUID().uuidString).json"
                )
            defer { try? FileManager.default.removeItem(at: fileURL) }
            try Data(rendered.utf8).write(to: fileURL, options: .atomic)

            do {
                _ = try loadGraphJSONDocument(at: fileURL.path)
                Issue.record("Expected malformed collection \(variant.name) to fail")
            } catch {
                #expect(error.localizedDescription.contains(variant.expected))
            }
        }
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
