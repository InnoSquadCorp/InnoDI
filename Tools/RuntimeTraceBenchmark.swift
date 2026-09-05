import Foundation

@inline(never)
private func control(_ providerID: String) -> Int {
    providerID.utf8.count
}

@inline(never)
private func disabledResolution(
    _ context: DITraceContext,
    providerID: String
) -> Int {
    let instanceID = context.start(providerID: providerID)
    context.record(.success, providerID: providerID, instanceID: instanceID)
    return instanceID == nil ? providerID.utf8.count : 0
}

@main
private enum RuntimeTraceBenchmark {
    static func main() throws {
        let arguments = CommandLine.arguments
        let iterations = argument("--iterations", in: arguments).flatMap(Int.init)
            ?? 1_000_000
        let enabledIterations = argument(
            "--enabled-iterations",
            in: arguments
        ).flatMap(Int.init) ?? 20_000
        guard iterations > 0, enabledIterations > 0 else {
            throw BenchmarkError.invalidIterations
        }

        let providerID = "Benchmark.AppContainer.client"
        var checksum = 0
        for _ in 0..<10_000 {
            checksum &+= control(providerID)
            checksum &+= disabledResolution(.disabled, providerID: providerID)
        }

        let controlStart = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations {
            checksum &+= control(providerID)
        }
        let controlElapsed = DispatchTime.now().uptimeNanoseconds - controlStart

        let disabledStart = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations {
            checksum &+= disabledResolution(.disabled, providerID: providerID)
        }
        let disabledElapsed = DispatchTime.now().uptimeNanoseconds - disabledStart

        let buffer = DIBoundedTraceBuffer(capacity: enabledIterations * 2)
        let enabled = DITraceContext(sink: buffer)
        let enabledStart = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<enabledIterations {
            let instanceID = enabled.start(providerID: providerID)
            enabled.record(
                .success,
                providerID: providerID,
                instanceID: instanceID
            )
        }
        let enabledElapsed = DispatchTime.now().uptimeNanoseconds - enabledStart
        let recordedEventCount = buffer.snapshot().events.count
        checksum &+= recordedEventCount

        let disabledNet = disabledElapsed > controlElapsed
            ? disabledElapsed - controlElapsed : 0
        let report: [String: Any] = [
            "schemaVersion": 1,
            "iterations": iterations,
            "enabledIterations": enabledIterations,
            "disabledNetNanosecondsPerResolution":
                Double(disabledNet) / Double(iterations),
            "enabledNanosecondsPerEvent":
                Double(enabledElapsed) / Double(enabledIterations * 2),
            "recordedEventCount": recordedEventCount,
            "checksum": checksum,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: report,
            options: [.prettyPrinted, .sortedKeys]
        )
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func argument(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

private enum BenchmarkError: Error { case invalidIterations }
