import Foundation
import Testing

@Suite("Runtime trace performance script contracts")
struct RuntimeTracePerformanceScriptTests {
    @Test("Budget preserves legacy gates and adds saturation and contention")
    func budgetCoverage() throws {
        let root = packageRootURL()
        let data = try Data(
            contentsOf: root.appendingPathComponent(
                "Tools/runtime-trace-performance-budget.json"
            )
        )
        let budget = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(budget["schemaVersion"] as? Int == 1)
        #expect(budget["disabledNetNanosecondsPerResolution"] as? Double == 210)
        #expect(budget["enabledNanosecondsPerEvent"] as? Double == 600)
        #expect((budget["saturatedNanosecondsPerEvent"] as? Double) != nil)
        #expect((budget["snapshotNanosecondsPerRetainedEvent"] as? Double) != nil)
        #expect((budget["contendedNanosecondsPerEvent"] as? Double) != nil)
    }

    @Test("Gate validates every production capacity and ring accounting")
    func scriptCoverage() throws {
        let script = try String(
            contentsOf: packageRootURL().appendingPathComponent(
                "Tools/measure-runtime-trace-performance.sh"
            ),
            encoding: .utf8
        )

        #expect(script.contains("[64, 4096, 65536]"))
        #expect(script.contains("lost ring-buffer accounting"))
        #expect(script.contains("writer and snapshot contention"))
        #expect(script.contains("snapshot overhead exceeds its budget"))
        #expect(script.contains("contended runtime trace overhead exceeds its budget"))
    }

    @Test("Benchmark uses the generated-provider trace owner path")
    func benchmarkUsesTraceOwner() throws {
        let source = try String(
            contentsOf: packageRootURL().appendingPathComponent(
                "Tools/RuntimeTraceBenchmark.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("_InnoDITraceOwner("))
        #expect(source.contains("owner.start(member:"))
        #expect(source.contains("owner.finish(.success"))
        #expect(source.contains("DispatchQueue.concurrentPerform"))
        #expect(source.contains("saturatedMeasurements"))
    }
}
