import Foundation
import InnoDICore
import InnoDIDependencyGraphCore
import InnoDIWorkspaceAnalysis
import SwiftParser
import Testing
@testable import InnoDIDependencyGraphCLI

@Suite("Graph binding integrity")
struct GraphBindingIntegrityTests {
    private func graph() -> DependencyGraphAnalysis {
        let source = Parser.parse(source: """
        import InnoDI
        @DIContainerRole(role: ContainerRole.component) struct Child {
            @Input var dependency: Int
        }
        @DIContainerRole(role: ContainerRole.component) struct AssistedChild {
            @Input var config: Int
            @Input(.assisted) var request: Int
        }
        @DIContainerRole(role: ContainerRole.root) struct Root {
            @Input var client: Int
            @Input var other: Int
            @Provide(.transient, factory: { (client: Int) in client }) var derived: Int
            @SubContainer(scope: .shared, bindings: [(child: \\Child.dependency, parent: \\Root.client)])
            var first: Child
            @SubContainer(scope: .transient, bindings: [(child: \\Child.dependency, parent: \\Root.other)])
            var second: Child
            @SubContainerFactory(AssistedChild.self, bindings: [(child: \\AssistedChild.config, parent: \\Root.client)])
            var factory: AssistedChild.AssistedFactory
        }
        """)
        let root = URL(fileURLWithPath: "/workspace")
        let snapshot = WorkspaceSourceSnapshot(
            rootPath: root.path, rootURL: root,
            files: [.init(relativePath: "Sources/Graph.swift", fileURL: root.appendingPathComponent("Sources/Graph.swift"), syntax: source)]
        )
        return collectDependencyGraph(snapshot: snapshot, validateDAG: false)
    }

    private func payload() throws -> [String: Any] {
        let graph = graph()
        let rendered = try renderJSON(
            scope: .init(primaryTargetID: "App", rootPruning: .all),
            nodes: graph.nodes, edges: graph.edges, providers: graph.providers
        )
        return try #require(JSONSerialization.jsonObject(with: Data(rendered.utf8)) as? [String: Any])
    }

    private func load(_ payload: [String: Any]) throws -> GraphJSON.Document {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("InnoDI-GraphBindings-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try JSONSerialization.data(withJSONObject: payload).write(to: file)
        return try loadGraphJSONDocument(at: file.path)
    }

    @Test("Child mounts and assisted factories depend on their own canonical parent bindings")
    func mountQueriesRemainInstanceSpecific() throws {
        let graph = graph()
        let client = try #require(graph.providers.first { $0.name == "client" })
        let first = try #require(graph.providers.first { $0.name == "first" })
        let second = try #require(graph.providers.first { $0.name == "second" })
        let factory = try #require(graph.providers.first { $0.name == "factory" })
        #expect(first.canonicalDependencyIDs == [client.id])
        #expect(factory.canonicalDependencyIDs == [client.id])
        #expect(!second.canonicalDependencyIDs.contains(client.id))
        let why = try renderGraphQuery(.why(first.id), nodes: graph.nodes, edges: graph.edges, providers: graph.providers)
        #expect(why.contains("Dependencies: \(client.id)"))
        let dependents = try renderGraphQuery(.dependents(client.id), nodes: graph.nodes, edges: graph.edges, providers: graph.providers)
        #expect(dependents.contains(first.id))
        #expect(dependents.contains(factory.id))
        #expect(!dependents.contains(second.id))
        _ = try load(payload())
    }

    @Test("Renamed and repeated external parameter labels remain valid")
    func canonicalIDsAreIndependentOfLabels() throws {
        var document = try payload()
        var providers = try #require(document["providers"] as? [[String: Any]])
        let derived = try #require(providers.firstIndex { $0["name"] as? String == "derived" })
        var bindings = try #require(providers[derived]["dependencyBindings"] as? [[String: Any]])
        bindings[0]["parameter"] = "renamedClient"
        bindings.append(bindings[0])
        providers[derived]["dependencyBindings"] = bindings
        document["providers"] = providers
        _ = try load(document)
    }

    @Test("Invalid references cannot pass a self-diff contract gate", arguments: [
        "missing-factory", "foreign-factory", "provider-nontransient", "lazy-async",
        "missing-child", "missing-parent", "foreign-parent", "wrong-child-role",
        "assisted-child-input", "wrong-mount", "wrong-ownership", "duplicate-child",
        "missing-child-binding", "missing-ownership-edge", "wrong-owner-role"
    ])
    func rejectsInvalidBindings(_ variant: String) throws {
        var document = try payload()
        var providers = try #require(document["providers"] as? [[String: Any]])
        let derived = try #require(providers.firstIndex { $0["name"] as? String == "derived" })
        let first = try #require(providers.firstIndex { $0["name"] as? String == "first" })
        let input = try #require(providers.firstIndex { $0["name"] as? String == "dependency" })
        let client = try #require(providers.firstIndex { $0["name"] as? String == "client" })
        var factoryBindings = try #require(providers[derived]["dependencyBindings"] as? [[String: Any]])
        var childBindings = try #require(providers[first]["containerBindings"] as? [[String: Any]])
        switch variant {
        case "missing-factory": factoryBindings[0]["providerID"] = "missing"
        case "foreign-factory": factoryBindings[0]["providerID"] = providers[input]["id"]
        case "provider-nontransient": factoryBindings[0]["kind"] = "provider"
        case "lazy-async":
            factoryBindings[0]["kind"] = "lazy"
            providers[client]["effect"] = "async"
        case "missing-child": childBindings[0]["childInputID"] = "missing"
        case "missing-parent": childBindings[0]["parentProviderID"] = "missing"
        case "foreign-parent": childBindings[0]["parentProviderID"] = providers[input]["id"]
        case "wrong-child-role": providers[input]["role"] = "provider"
        case "assisted-child-input": providers[input]["inputKind"] = "assisted"
        case "wrong-mount": childBindings[0]["childInputID"] = providers[client]["id"]
        case "wrong-ownership": childBindings[0]["ownership"] = "assisted"
        case "duplicate-child": childBindings.append(childBindings[0])
        case "missing-child-binding": childBindings = []
        case "missing-ownership-edge":
            let edges = try #require(document["edges"] as? [[String: Any]])
            document["edges"] = edges.filter { $0["label"] as? String != "first" }
        case "wrong-owner-role": providers[first]["role"] = "provider"
        default: Issue.record("Unknown mutation \(variant)")
        }
        providers[derived]["dependencyBindings"] = factoryBindings
        providers[first]["containerBindings"] = childBindings
        document["providers"] = providers
        #expect(throws: GraphInspectionError.self) { _ = try load(document) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("InnoDI-InvalidGraph-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try JSONSerialization.data(withJSONObject: document).write(to: file)
        let result = try runCLI(["--diff", file.path, file.path, "--check-contract"])
        #expect(result.exitCode == ExitCode.failure)
        #expect(!result.stderr.isEmpty)
    }
}
