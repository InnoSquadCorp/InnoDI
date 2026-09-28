import Foundation
import InnoDITestSupport
import SwiftParser
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

/// Independent, versioned diagnostic workloads. These samples must never be
/// combined with the established composite-v2 release baseline or its history.
@Suite("Feature macro performance workloads", .serialized)
struct MacroFeaturePerformanceBenchmark {
    private struct Workload {
        let id: String
        let version: Int
        let dimensions: [String: Int]
        let source: String
        let requiredOutput: [String]
    }

    private static let macros = DIContainerMacroTests.macros.merging([
        "AssistedFactory": AssistedFactoryMacro.self,
        "Multibinding": ProvideMacro.self,
        "GenerateMock": GenerateMockMacro.self,
    ] as [String: any Macro.Type]) { _, new in new }

    private static let workloads: [Workload] = {
        let staticNames = (0..<8).map { "config\($0)" }
        let assistedNames = (0..<8).map { "id\($0)" }
        let inputs = staticNames.map { "@Input var \($0): Int" }
            + assistedNames.map { "@Input(.assisted) var \($0): Int" }
        let order = (staticNames + assistedNames).map { "\"\($0)\"" }.joined(separator: ", ")
        let staticPaths = staticNames.map { "\\Child.\($0)" }.joined(separator: ", ")
        let assistedPaths = assistedNames.map { "\\Child.\($0)" }.joined(separator: ", ")
        let members = (0..<64).map { "item\($0)" }
        let providers = members.map { "@Provide(.shared, factory: 1) var \($0): Int" }.joined(separator: "\n")
        let paths = members.map { "\\Self.\($0)" }.joined(separator: ", ")
        let methods = (0..<32).map { index in
            let effects = index % 2 == 0 ? "" : "async throws(Failure)"
            return "func load\(index)(id: Int) \(effects) -> String"
        }.joined(separator: "\n")
        return [
            Workload(id: "assisted-factory", version: 1,
                dimensions: ["static_inputs": 8, "assisted_inputs": 8], source: """
                @DIContainer
                struct Child {
                    \(inputs.joined(separator: "\n"))
                    @_InnoDIAssistedFactoryMetadata(order: [\(order)], escaping: [], mainActor: false)
                    @AssistedFactory(Child.self, static: [\(staticPaths)], assisted: [\(assistedPaths)])
                    struct AssistedFactory {}
                }
                """, requiredOutput: ["func callAsFunction(", "config7: self.config7", "id7: id7", "struct Overrides"]),
            Workload(id: "large-multibinding", version: 1,
                dimensions: ["contributors": 64, "collections": 1], source: """
                @DIContainer
                struct CollectionContainer {
                    \(providers)
                    @Multibinding([\(paths)]) var values: [Int]
                }
                """, requiredOutput: members.map { "_storage_\($0)" } + ["_override_values", "var values: [Int]"]),
            Workload(id: "mock-generation", version: 1,
                dimensions: ["methods": 32, "typed_async_throwing_methods": 16], source: """
                enum Failure: Error { case expected }
                @GenerateMock protocol Service {
                    \(methods)
                }
                """, requiredOutput: (0..<32).map { "load\($0)Calls" }
                    + ["final class ServiceMock", "missingStubSelectors", "Result<String, Failure>"]),
        ]
    }()

    @Test("Every versioned workload expands successfully and missing generation is rejected")
    func workloadContracts() throws {
        for workload in Self.workloads {
            try Self.expand(workload)
            #expect(throws: WorkloadError.self) { try Self.expand(workload, source: "") }
            #expect(throws: WorkloadError.self) {
                try Self.expand(workload, source: workload.source + "\n@DIContainer struct Invalid { var unmanaged: Int }")
            }
        }
    }

    @Test(.disabled(if: ProcessInfo.processInfo.environment["INNODI_FEATURE_BENCH_OUTPUT"] == nil))
    func measureFeatures() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let output = environment["INNODI_FEATURE_BENCH_OUTPUT"],
              let candidate = environment["INNODI_FEATURE_BENCH_SHA"],
              let compiler = environment["SWIFT_VERSION"],
              let iterations = Int(environment["INNODI_FEATURE_BENCH_ITERATIONS"] ?? "10"),
              (1...100).contains(iterations) else { throw WorkloadError.invalidConfiguration }
        let warmups = max(10, iterations)
        var measurements: [[String: Any]] = []
        for workload in Self.workloads {
            for _ in 0..<warmups { try Self.expand(workload) }
            var samples: [Double] = []
            for _ in 0..<iterations {
                let duration = try ContinuousClock().measure { try Self.expand(workload) }
                samples.append(Double(duration.components.seconds) * 1_000
                    + Double(duration.components.attoseconds) / 1e15)
            }
            measurements.append([
                "id": workload.id, "workload_version": workload.version,
                "dimensions": workload.dimensions, "workload_verified": true,
                "iterations": iterations, "warmup_iterations": warmups,
                "samples_ms": samples, "min_ms": samples.min()!,
                "mean_ms": samples.reduce(0, +) / Double(samples.count),
            ])
        }
        let report: [String: Any] = [
            "schema_version": 1, "candidate_sha": candidate,
            "source_tree_clean": environment["INNODI_FEATURE_BENCH_CLEAN"] == "true",
            "swift_version": compiler, "configuration": "debug-in-process",
            "enforcement": "report-only-unbaselined", "workloads": measurements,
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: output), options: .atomic)
    }

    private static func expand(_ workload: Workload, source: String? = nil) throws {
        let result = expandMacroSource(source ?? workload.source, macros: macros,
                                      testModuleName: "FeatureBench", testFileName: "bench.swift")
        guard result.diagnostics.isEmpty, !Parser.parse(source: result.expansion).hasError,
              workload.requiredOutput.allSatisfy({ result.expansion.contains($0) }) else {
            throw WorkloadError.invalidExpansion(workload.id, result.diagnostics.map(\.message))
        }
    }

    private enum WorkloadError: Error {
        case invalidConfiguration
        case invalidExpansion(String, [String])
    }
}
