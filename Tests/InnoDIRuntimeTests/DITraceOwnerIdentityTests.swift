import Foundation
import InnoDI
import Synchronization
import Testing

@available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
private final class OwnerRecordingSink: DITraceSink {
    private let events = Mutex<[DITraceEvent]>([])
    private let callback = Mutex<(@Sendable () -> Void)?>(nil)

    func install(_ body: @escaping @Sendable () -> Void) {
        callback.withLock { $0 = body }
    }

    func record(_ event: DITraceEvent) {
        events.withLock { $0.append(event) }
        let body = callback.withLock { callback in
            let body = callback
            callback = nil
            return body
        }
        body?()
    }

    var snapshot: [DITraceEvent] { events.withLock { $0 } }
}

// Checked-Sendable Mutex coverage requires newer Apple OS versions.
// The runtime deployment floor is unchanged.
@Suite("Trace owner identity and lifetime")
struct DITraceOwnerIdentityTests {
    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    @Test("Copies share correlation while explicit old spans remain usable")
    func copiesShareCorrelation() {
        let sink = OwnerRecordingSink()
        let owner = _InnoDITraceOwner(context: .init(sink: sink, generation: 42), containerType: Self.self)
        let copy = owner
        let first = owner.start(member: "service")
        copy.finish(.success, span: first)
        copy.cacheHit(member: "service")
        let second = copy.start(member: "service")
        owner.finish(.success, span: second)
        owner.cacheHit(member: "service")
        copy.cacheHit(member: "service", span: first)
        let events = sink.snapshot
        #expect(events.count == 7)
        #expect(Set(events.map(\.ownerID)).count == 1)
        #expect(Set(events.map(\.generation)) == [42])
        #expect(events[0].instanceID == events[1].instanceID)
        #expect(events[0].instanceID == events[2].instanceID)
        #expect(events[0].instanceID != events[3].instanceID)
        #expect(events[3].instanceID == events[5].instanceID)
        #expect(events[0].instanceID == events[6].instanceID)
    }

    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    @Test("Identical contexts create independent owner identities")
    func independentInitializations() {
        let sink = OwnerRecordingSink()
        let context = DITraceContext(sink: sink, generation: 3)
        let first = _InnoDITraceOwner(context: context, containerType: Self.self)
        let second = _InnoDITraceOwner(context: context, containerType: Self.self)
        _ = first.start(member: "value")
        _ = second.start(member: "value")
        let events = sink.snapshot
        #expect(events.count == 2)
        #expect(events[0].ownerID != events[1].ownerID)
        #expect(events[0].providerID == events[1].providerID)
        #expect(events[0].generation == events[1].generation)
    }

    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    @Test("Enabled sink callbacks can enter the same owner's other cell")
    func sameOwnerReentry() {
        let sink = OwnerRecordingSink()
        let owner = _InnoDITraceOwner(context: .init(sink: sink), containerType: Self.self)
        let other = _InnoDISendableSharedCell(traceOwner: owner, providerName: "other", factory: { 9 })
        sink.install {
            #expect(other.value() == 9)
            let nested = owner.start(member: "nested")
            owner.finish(.success, span: nested)
        }
        let primary = _InnoDISendableSharedCell(traceOwner: owner, providerName: "primary", factory: { 7 })
        #expect(primary.value() == 7)
        #expect(other.value() == 9)
        let events = sink.snapshot
        #expect(Set(events.map(\.ownerID)).count == 1)
        #expect(events.filter { $0.kind == .start }.count == 3)
    }

    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    @Test("Span does not keep a sink alive after the final owner copy")
    func sinkLifetime() {
        weak var observed: OwnerRecordingSink?
        var copies: [_InnoDITraceOwner] = []
        var span: _InnoDITraceOwner.Span?
        do {
            let sink = OwnerRecordingSink()
            observed = sink
            let owner = _InnoDITraceOwner(context: .init(sink: sink), containerType: Self.self)
            copies = [owner, owner]
            span = owner.start(member: "service")
        }
        #expect(observed != nil)
        copies.removeLast()
        #expect(observed != nil)
        copies.removeAll()
        #expect(observed == nil)
        withExtendedLifetime(span) {}
    }

    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    @Test("Disabled bookkeeping preserves operation and error behavior")
    func disabledEntryPoints() async {
        enum Failure: Error { case expected }
        for owner in [_InnoDITraceOwner.disabled, .init(context: .disabled, containerType: Self.self)] {
            #expect(!owner.isEnabled)
            #expect(owner.providerID(member: "value") == nil)
            #expect(owner.start(member: "value") == nil)
            owner.finish(.success, span: nil)
            owner.cacheHit(member: "value")
            owner.wait(.waitStart, member: "value", for: nil)
            #expect(owner.overridden(member: "value", value: 9) == 9)
            var calls = 0
            let result: Int = owner.withResolution(member: "value") { calls += 1; return 7 }
            #expect(result == 7 && calls == 1)
            #expect(throws: Failure.self) {
                try owner.withResolution(member: "value") { throw Failure.expected }
            }
            let asyncResult = await owner.withResolution(member: "value") { () async -> Int in 11 }
            #expect(asyncResult == 11)
        }
    }

    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    @Test("Mapped provider IDs and generation survive metadata sharing")
    func mappedProviderIdentity() {
        let sink = OwnerRecordingSink()
        let module = String(reflecting: Self.self).split(separator: ".").first.map(String.init)!
        let owner = _InnoDITraceOwner(
            context: .init(sink: sink, targetIDsByModule: [module: "TestTarget"], generation: 17),
            containerType: Self.self
        )
        #expect(owner.providerID(member: "service") == "TestTarget::DITraceOwnerIdentityTests.service")
        _ = owner.start(member: "service")
        #expect(sink.snapshot.first?.generation == 17)
        #expect(sink.snapshot.first?.providerID == owner.providerID(member: "service"))
    }

    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    @Test("Enabled failure cancellation and override events preserve order")
    func terminalEventOrder() {
        enum Failure: Error { case expected }
        let sink = OwnerRecordingSink()
        let owner = _InnoDITraceOwner(context: .init(sink: sink), containerType: Self.self)
        #expect(throws: Failure.self) {
            try owner.withResolution(member: "failure") { throw Failure.expected }
        }
        #expect(throws: CancellationError.self) {
            try owner.withResolution(member: "cancel") { throw CancellationError() }
        }
        #expect(owner.overridden(member: "override", value: 7) == 7)
        let events = sink.snapshot
        #expect(events.map(\.kind) == [.start, .failure, .start, .cancel, .start, .override])
        for i in stride(from: 0, to: 6, by: 2) {
            #expect(events[i].instanceID == events[i + 1].instanceID)
        }
    }

    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    @Test("Wait end retains the original span pair across suspension")
    func waitSpanCorrelation() async {
        let sink = OwnerRecordingSink()
        let owner = _InnoDITraceOwner(context: .init(sink: sink), containerType: Self.self)
        _ = owner.start(member: "outer")
        _ = owner.start(member: "inner")
        let value = await owner.withWait(member: "outer", forMember: "inner") {
            await Task.yield()
            _ = owner.start(member: "outer")
            _ = owner.start(member: "inner")
            return 9
        }
        #expect(value == 9)
        let waits = sink.snapshot.filter { $0.kind == .waitStart || $0.kind == .waitEnd }
        #expect(waits.map(\.kind) == [.waitStart, .waitEnd])
        #expect(waits[0].instanceID == waits[1].instanceID)
        #expect(waits[0].relatedInstanceID == waits[1].relatedInstanceID)
    }

    @available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)
    @Test("Concurrent copies keep distinct spans under one owner identity")
    func concurrentCopies() async {
        let sink = OwnerRecordingSink()
        let owner = _InnoDITraceOwner(context: .init(sink: sink), containerType: Self.self)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    let copy = owner
                    let span = copy.start(member: "value")
                    copy.finish(.success, span: span)
                }
            }
        }
        let events = sink.snapshot
        #expect(events.count == 200)
        #expect(Set(events.map(\.ownerID)).count == 1)
        let started = events.filter { $0.kind == .start }.map(\.instanceID)
        let finished = events.filter { $0.kind == .success }.map(\.instanceID)
        #expect(Set(started).count == 100)
        #expect(Set(started) == Set(finished))
    }

}
