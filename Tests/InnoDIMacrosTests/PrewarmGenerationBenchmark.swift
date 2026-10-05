import Foundation
import InnoDITestSupport
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

/// Separate from composite-v2: explicitly exercises the generated on-demand
/// API and records syntax growth as well as expansion latency. Never compare
/// these samples to the composite release baseline or relax that baseline.
@Suite("Prewarm generation benchmark", .serialized)
struct PrewarmGenerationBenchmark {
    private enum InvalidWorkload: Error { case expansion }

    @Test(.disabled(if: ProcessInfo.processInfo.environment["INNODI_PREWARM_BENCH_OUTPUT"] == nil))
    func measureGeneration() throws {
        let environment = ProcessInfo.processInfo.environment
        let count = max(1, Int(environment["INNODI_PREWARM_BENCH_PROVIDERS"] ?? "10") ?? 10)
        let samples = max(1, Int(environment["INNODI_PREWARM_BENCH_SAMPLES"] ?? "30") ?? 30)
        let warmups = max(1, Int(environment["INNODI_PREWARM_BENCH_WARMUPS"] ?? "30") ?? 30)
        let members = (0..<count).map { index in
            "@Provide(.shared, initialization: .onDemand, factory: \(index)) var provider\(index): Int"
        }.joined(separator: "\n")
        let source = "@DIContainer struct Container {\n\(members)\n}"
        func run() throws -> Int {
            let result = expandMacroSource(source, macros: DIContainerMacroTests.macros)
            guard result.diagnostics.isEmpty,
                  result.expansion.contains("func prewarm(_ providers:"),
                  result.expansion.contains("_storage_provider\(count - 1)"),
                  result.expansion.contains("_InnoDISharedCell<Int>") else {
                throw InvalidWorkload.expansion
            }
            return result.expansion.utf8.count
        }
        let generatedBytes = try run()
        for _ in 0..<warmups { _ = try run() }
        var durations: [Double] = []
        let clock = ContinuousClock()
        var checksum = 0
        for _ in 0..<samples {
            let duration = try clock.measure { checksum += try run() }
            durations.append(Double(duration.components.seconds) * 1_000
                + Double(duration.components.attoseconds) / 1e15)
        }
        let report: [String: Any] = [
            "schema_version": 1, "workload": "sync-on-demand-prewarm-generation-v1",
            "providers": count, "samples": samples, "warmups": warmups,
            "samples_ms": durations, "generated_utf8_bytes": generatedBytes,
            "checksum": checksum, "compiler": environment["SWIFT_VERSION"] ?? "record separately",
        ]
        let output = try #require(environment["INNODI_PREWARM_BENCH_OUTPUT"])
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: output))
    }
}
