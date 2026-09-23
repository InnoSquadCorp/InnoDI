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

private final class WriterTimingBox: @unchecked Sendable {
    private let lock = NSLock()
    private var intervals: [Int: [Int: (UInt64, UInt64)]] = [:]
    private var snapshots: [Int: (UInt64, UInt64, Int)] = [:]

    func record(writer: Int, round: Int, start: UInt64, end: UInt64) {
        lock.lock()
        intervals[writer, default: [:]][round] = (start, end)
        lock.unlock()
    }

    func recordSnapshot(round: Int, start: UInt64, end: UInt64, retained: Int) {
        lock.lock()
        snapshots[round] = (start, end, retained)
        lock.unlock()
    }

    var maximumElapsedNanoseconds: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return intervals.values.map { rounds in
            rounds.values.reduce(UInt64(0)) { $0 + $1.1 - $1.0 }
        }.max() ?? 0
    }

    var observations: [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return snapshots.keys.sorted().map { round in
            let snapshot = snapshots[round]!
            let writers = intervals.keys.sorted().compactMap { writer -> [String: Any]? in
                guard let interval = intervals[writer]?[round] else { return nil }
                return ["writer": writer, "start": interval.0, "end": interval.1]
            }
            return ["round": round, "start": snapshot.0, "end": snapshot.1,
                    "retainedEventCount": snapshot.2, "writers": writers]
        }
    }
}

/// Dedicated benchmark threads rendezvous outside measured writer intervals.
/// Each round observes a full ring during a distinct 1/64 slice of the writes.
private final class RoundBarrier: @unchecked Sendable {
    private let condition = NSCondition()
    private let participants: Int
    private var arrivals = 0
    private var generation = 0

    init(participants: Int) { self.participants = participants }

    func wait() {
        condition.lock()
        let previous = generation
        arrivals += 1
        if arrivals == participants {
            arrivals = 0
            generation += 1
            condition.broadcast()
        } else {
            while generation == previous { condition.wait() }
        }
        condition.unlock()
    }
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
        // Prefill is separate from measurement. Per-round timestamps prove
        // actual overlap; barrier membership alone is not overlap evidence.
        let snapshotCount = 64
        let contentionSampleCount = 5
        let resolutionsPerWriter = max(snapshotCount, enabledIterations / writerCount)
        let contendedEventCount = writerCount * resolutionsPerWriter * 2
        let eventsPerWriter = resolutionsPerWriter * 2
        var contentionMeasurements: [[String: Any]] = []
        for _ in 0..<contentionSampleCount {
            let contendedBuffer = DIBoundedTraceBuffer(capacity: contentionCapacity)
            let contendedOwner = _InnoDITraceOwner(
                context: DITraceContext(sink: contendedBuffer),
                containerType: RuntimeTraceBenchmark.self
            )
            for _ in 0..<(contentionCapacity / 2) {
                let span = contendedOwner.start(member: member)
                contendedOwner.finish(.success, span: span)
            }
            let writerTimings = WriterTimingBox()
            let barrier = RoundBarrier(participants: writerCount + 1)
            let completion = DispatchGroup()
            let contentionStart = DispatchTime.now().uptimeNanoseconds
            for worker in 0...writerCount {
                completion.enter()
                Thread.detachNewThread {
                    defer { completion.leave() }
                    for round in 0..<snapshotCount {
                        barrier.wait()
                        if worker == writerCount {
                            let start = DispatchTime.now().uptimeNanoseconds
                            let snapshot = contendedBuffer.snapshot()
                            let end = DispatchTime.now().uptimeNanoseconds
                            writerTimings.recordSnapshot(
                                round: round, start: start, end: end,
                                retained: snapshot.events.count
                            )
                        } else {
                            let writerMember = "writer\(worker)"
                            let lower = resolutionsPerWriter * round / snapshotCount
                            let upper = resolutionsPerWriter * (round + 1) / snapshotCount
                            let start = DispatchTime.now().uptimeNanoseconds
                            for _ in lower..<upper {
                                let span = contendedOwner.start(member: writerMember)
                                contendedOwner.finish(.success, span: span)
                            }
                            let end = DispatchTime.now().uptimeNanoseconds
                            writerTimings.record(writer: worker, round: round, start: start, end: end)
                        }
                        barrier.wait()
                    }
                }
            }
            completion.wait()
            let contentionElapsed = DispatchTime.now().uptimeNanoseconds - contentionStart
            let contendedSnapshot = contendedBuffer.snapshot()
            checksum &+= contendedSnapshot.events.count
            checksum &+= contendedSnapshot.droppedEventCount
            contentionMeasurements.append([
                "capacity": contentionCapacity,
                "writerCount": writerCount,
                "snapshotCount": snapshotCount,
                "prefillEventCount": contentionCapacity,
                "observations": writerTimings.observations,
                "emittedEventCount": contendedEventCount,
                "eventsPerWriter": eventsPerWriter,
                "retainedEventCount": contendedSnapshot.events.count,
                "droppedEventCount": contendedSnapshot.droppedEventCount,
                "nanosecondsPerEvent":
                    Double(writerTimings.maximumElapsedNanoseconds) / Double(eventsPerWriter),
                "wallNanosecondsPerEvent":
                    Double(contentionElapsed) / Double(contendedEventCount),
            ])
        }

        let disabledNet = disabledElapsed > controlElapsed
            ? disabledElapsed - controlElapsed : 0
        let report: [String: Any] = [
            "schemaVersion": 2,
            "iterations": iterations,
            "enabledIterations": enabledIterations,
            "disabledNetNanosecondsPerResolution":
                Double(disabledNet) / Double(iterations),
            "enabledNanosecondsPerEvent":
                Double(enabledElapsed) / Double(enabledIterations * 2),
            "recordedEventCount": recordedEventCount,
            "saturatedMeasurements": saturatedMeasurements,
            "contentionMeasurements": contentionMeasurements,
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
