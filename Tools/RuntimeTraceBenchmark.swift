import Dispatch
import Foundation

@inline(never)
private func control(_ providerID: String) -> Int {
    providerID.utf8.count
}

@inline(never)
private func disabledResolution(
    _ owner: _InnoDITraceOwner,
    member: String
) -> Int {
    let span = owner.start(member: member)
    owner.finish(.success, span: span)
    return span == nil ? member.utf8.count : 0
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
        let member = "client"
        let disabledOwner = _InnoDITraceOwner(
            context: .disabled,
            containerType: RuntimeTraceBenchmark.self
        )
        var checksum = 0
        for _ in 0..<10_000 {
            checksum &+= control(providerID)
            checksum &+= disabledResolution(disabledOwner, member: member)
        }

        let controlStart = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations {
            checksum &+= control(providerID)
        }
        let controlElapsed = DispatchTime.now().uptimeNanoseconds - controlStart

        let disabledStart = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations {
            checksum &+= disabledResolution(disabledOwner, member: member)
        }
        let disabledElapsed = DispatchTime.now().uptimeNanoseconds - disabledStart

        let buffer = DIBoundedTraceBuffer(capacity: enabledIterations * 2)
        let enabledOwner = _InnoDITraceOwner(
            context: DITraceContext(sink: buffer),
            containerType: RuntimeTraceBenchmark.self
        )
        let enabledStart = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<enabledIterations {
            let span = enabledOwner.start(member: member)
            enabledOwner.finish(.success, span: span)
        }
        let enabledElapsed = DispatchTime.now().uptimeNanoseconds - enabledStart
        let recordedEventCount = buffer.snapshot().events.count
        checksum &+= recordedEventCount

        let capacities = [64, 4_096, 65_536]
        var saturatedMeasurements: [[String: Any]] = []
        for capacity in capacities {
            let resolutionCount = capacity + enabledIterations
            let saturatedBuffer = DIBoundedTraceBuffer(capacity: capacity)
            let owner = _InnoDITraceOwner(
                context: DITraceContext(sink: saturatedBuffer),
                containerType: RuntimeTraceBenchmark.self
            )
            let start = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<resolutionCount {
                let span = owner.start(member: member)
                owner.finish(.success, span: span)
            }
            let elapsed = DispatchTime.now().uptimeNanoseconds - start
            let snapshotStart = DispatchTime.now().uptimeNanoseconds
            let snapshot = saturatedBuffer.snapshot()
            let snapshotElapsed = DispatchTime.now().uptimeNanoseconds - snapshotStart
            let emittedEventCount = resolutionCount * 2
            checksum &+= snapshot.events.count
            checksum &+= snapshot.droppedEventCount
            saturatedMeasurements.append([
                "capacity": capacity,
                "emittedEventCount": emittedEventCount,
                "retainedEventCount": snapshot.events.count,
                "droppedEventCount": snapshot.droppedEventCount,
                "nanosecondsPerEvent": Double(elapsed) / Double(emittedEventCount),
                "snapshotNanosecondsPerRetainedEvent":
                    Double(snapshotElapsed) / Double(snapshot.events.count),
            ])
        }

        let contentionCapacity = 4_096
        let writerCount = 4
        let snapshotCount = 512
        let resolutionsPerWriter = max(1, enabledIterations / writerCount)
        let contendedBuffer = DIBoundedTraceBuffer(capacity: contentionCapacity)
        let contendedOwner = _InnoDITraceOwner(
            context: DITraceContext(sink: contendedBuffer),
            containerType: RuntimeTraceBenchmark.self
        )
        let contentionStart = DispatchTime.now().uptimeNanoseconds
        DispatchQueue.concurrentPerform(iterations: writerCount + 1) { worker in
            if worker == writerCount {
                for _ in 0..<snapshotCount {
                    _ = contendedBuffer.snapshot()
                }
            } else {
                let writerMember = "writer\(worker)"
                for _ in 0..<resolutionsPerWriter {
                    let span = contendedOwner.start(member: writerMember)
                    contendedOwner.finish(.success, span: span)
                }
            }
        }
        let contentionElapsed = DispatchTime.now().uptimeNanoseconds - contentionStart
        let contendedEventCount = writerCount * resolutionsPerWriter * 2
        let contendedSnapshot = contendedBuffer.snapshot()
        checksum &+= contendedSnapshot.events.count
        checksum &+= contendedSnapshot.droppedEventCount

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
            "saturatedMeasurements": saturatedMeasurements,
            "contention": [
                "capacity": contentionCapacity,
                "writerCount": writerCount,
                "snapshotCount": snapshotCount,
                "emittedEventCount": contendedEventCount,
                "retainedEventCount": contendedSnapshot.events.count,
                "droppedEventCount": contendedSnapshot.droppedEventCount,
                "nanosecondsPerEvent":
                    Double(contentionElapsed) / Double(contendedEventCount),
            ],
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
