import Foundation
import Testing

@testable import InnoDI

@Suite("DI runtime tracing")
struct DITracingTests {
    private enum ExpectedFailure: Error { case failed }

    @Test("disabled tracing does not evaluate or allocate events")
    func disabledPathIsLazy() {
        var evaluations = 0
        let context = DITraceContext.disabled
        context.emit({
            evaluations += 1
            return DITraceEvent(
                providerID: "App.secret",
                instanceID: UUID(),
                kind: .start
            )
        }())

        #expect(!context.isEnabled)
        #expect(evaluations == 0)
        #expect(context.start(providerID: "App.secret") == nil)
    }

    @Test("bounded buffers retain newest metadata-only events")
    func boundedBuffer() throws {
        let buffer = DIBoundedTraceBuffer(capacity: 2)
        let context = DITraceContext(sink: buffer)
        let first = try #require(context.start(providerID: "App.first"))
        context.record(.success, providerID: "App.first", instanceID: first)
        _ = try #require(context.start(providerID: "App.second"))

        let snapshot = buffer.snapshot()
        #expect(snapshot.events.map(\.providerID) == ["App.first", "App.second"])
        #expect(snapshot.events.map(\.kind) == [.success, .start])
        #expect(snapshot.droppedEventCount == 1)
    }

    @Test("concurrent writers do not lose events below capacity")
    func concurrentWriters() async {
        let buffer = DIBoundedTraceBuffer(capacity: 200)
        let context = DITraceContext(sink: buffer)

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<100 {
                group.addTask {
                    let providerID = "App.provider\(index)"
                    let instanceID = context.start(providerID: providerID)
                    context.record(.success, providerID: providerID, instanceID: instanceID)
                }
            }
        }

        let snapshot = buffer.snapshot()
        #expect(snapshot.events.count == 200)
        #expect(snapshot.droppedEventCount == 0)
        #expect(Set(snapshot.events.map(\.instanceID)).count == 100)
    }

    @Test("resolution spans report every terminal outcome without payloads")
    func resolutionOutcomesAreMetadataOnly() async throws {
        let secretCanary = "token-super-secret-42"
        let buffer = DIBoundedTraceBuffer(capacity: 16)
        let context = DITraceContext(sink: buffer)

        let value = context.withResolution(providerID: "App.success") { 42 }
        #expect(value == 42)
        #expect(throws: ExpectedFailure.failed) {
            try context.withResolution(providerID: "App.failure") {
                _ = secretCanary
                throw ExpectedFailure.failed
            }
        }
        await #expect(throws: CancellationError.self) {
            try await context.withResolution(providerID: "App.cancel") {
                await Task.yield()
                throw CancellationError()
            }
        }

        let events = buffer.snapshot().events
        #expect(events.map(\.kind) == [
            .start, .success, .start, .failure, .start, .cancel,
        ])
        #expect(Set(events.map(\.instanceID)).count == 3)
        let encoded = try String(
            decoding: JSONEncoder().encode(events),
            as: UTF8.self
        )
        #expect(!encoded.contains(secretCanary))
    }

    @Test("disabled resolution spans execute directly")
    func disabledResolutionExecutesDirectly() async throws {
        let context = DITraceContext.disabled
        var syncCalls = 0
        let syncValue = context.withResolution(providerID: "App.sync") {
            syncCalls += 1
            return 1
        }
        let asyncValue = await context.withResolution(providerID: "App.async") {
            await Task.yield()
            return 2
        }

        #expect(syncValue == 1)
        #expect(asyncValue == 2)
        #expect(syncCalls == 1)
    }
}
