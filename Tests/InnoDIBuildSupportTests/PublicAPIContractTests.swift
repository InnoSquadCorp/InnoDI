import Foundation
import Testing

@Suite("Public API baseline contracts")
struct PublicAPIContractTests {
    @Test("Baseline covers both library products and SwiftUI extensions")
    func baselineScope() throws {
        let baselineURL = packageRootURL()
            .appendingPathComponent("Tools/public-api-baseline.json")
        let data = try Data(contentsOf: baselineURL)
        let payload = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(payload["schemaVersion"] as? Int == 1)

        let graphs = try #require(payload["graphs"] as? [[String: Any]])
        let graphNames = Set(graphs.compactMap { $0["file"] as? String })
        #expect(graphNames.contains("InnoDI.symbols.json"))
        #expect(graphNames.contains("InnoDISwiftUI.symbols.json"))
        #expect(graphNames.contains { $0.hasPrefix("InnoDISwiftUI@") })

        let symbolCount = graphs.reduce(into: 0) { count, graph in
            count += (graph["symbols"] as? [[String: Any]])?.count ?? 0
        }
        #expect(symbolCount > 0)
    }

    @Test("PR, main, and release workflows enforce the same baseline")
    func workflowParity() throws {
        let root = packageRootURL()
        let macroTests = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/macro-tests.yml"),
            encoding: .utf8
        )
        let release = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/release.yml"),
            encoding: .utf8
        )

        #expect(
            macroTests.components(separatedBy: "Tools/check-public-api.py").count - 1 == 2
        )
        #expect(
            release.components(separatedBy: "Tools/check-public-api.py").count - 1 == 1
        )
    }
}
