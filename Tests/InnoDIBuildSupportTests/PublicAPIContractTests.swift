import Foundation
import Testing

@Suite("Public API baseline contracts")
struct PublicAPIContractTests {
    @Test("Baseline covers source-authored API for both library products")
    func baselineScope() throws {
        let baselineURL = packageRootURL()
            .appendingPathComponent("Tools/public-api-baseline.json")
        let data = try Data(contentsOf: baselineURL)
        let payload = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(payload["schemaVersion"] as? Int == 2)

        let graphs = try #require(payload["graphs"] as? [[String: Any]])
        let graphNames = Set(graphs.compactMap { $0["file"] as? String })
        #expect(
            graphNames == [
                "InnoDI.symbols.json",
                "InnoDISwiftUI.symbols.json",
            ]
        )

        let swiftUIGraph = try #require(
            graphs.first { $0["file"] as? String == "InnoDISwiftUI.symbols.json" }
        )
        let swiftUISymbols = try #require(
            swiftUIGraph["symbols"] as? [[String: Any]]
        )
        #expect(swiftUISymbols.count == 6)
        #expect(swiftUISymbols.allSatisfy { symbol in
            guard let identifier = symbol["identifier"] as? [String: Any],
                  let precise = identifier["precise"] as? String else {
                return false
            }
            return precise.contains("InnoDISwift")
        })
        #expect(swiftUISymbols.allSatisfy { symbol in
            symbol["declaration"] is String
                && symbol["declarationFragments"] == nil
                && symbol["functionSignature"] == nil
        })
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
            macroTests.components(separatedBy: "Tools/check-public-api.py").count - 1 == 3
        )
        #expect(
            release.components(separatedBy: "Tools/check-public-api.py").count - 1 == 1
        )
    }
}
