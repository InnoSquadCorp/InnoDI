import Foundation
import InnoDI
import Testing

private final class ReadyPathToken: Sendable {
    let identity = UUID()
}

@Suite("On-demand ready fast path", .timeLimit(.minutes(1)))
struct OnDemandReadyPathTests {
    @Test("Ready reads preserve identity, factory count, and tracing", arguments: [false, true])
    func identityAndTracing(traced: Bool) {
        let buffer = DIBoundedTraceBuffer(capacity: 2_000)
        let owner: _InnoDITraceOwner = traced
            ? .init(context: .init(sink: buffer), containerType: Self.self) : .disabled
        var calls = 0
        let token = ReadyPathToken()
        let cell = _InnoDISharedCell<ReadyPathToken>(traceOwner: owner, providerName: "value") {
            calls += 1
            return token
        }
        #expect(cell.value() === token)
        for _ in 0..<1_000 { #expect(cell.value() === token) }
        #expect(calls == 1)
        let events = buffer.snapshot().events
        #expect(events.filter { $0.kind == .start }.count == (traced ? 1 : 0))
        #expect(events.filter { $0.kind == .success }.count == (traced ? 1 : 0))
        #expect(events.filter { $0.kind == .cacheHit }.count == (traced ? 1_000 : 0))
    }

    @Test("A ready nil and a closure payload are real cached values")
    func readyPayloads() {
        let optional = _InnoDISharedCell<Int?>(value: nil)
        let closure = _InnoDISharedCell<() -> Int>(value: { 42 })
        for _ in 0..<1_000 {
            #expect(optional.value() == nil)
            #expect(closure.value()() == 42)
        }
    }

    @Test("Pending and ready cells release captures and cached values", arguments: [false, true])
    func resourceRelease(resolve: Bool) {
        var token: ReadyPathToken? = ReadyPathToken()
        weak var weakToken = token
        defer { weakToken = nil }
        var cell: _InnoDISharedCell<ReadyPathToken>? = _InnoDISharedCell { [value = token!] in value }
        token = nil
        #expect(weakToken != nil)
        if resolve { _ = cell?.value() }
        cell = nil
        #expect(weakToken == nil)
    }

    @Test("Checked Sendable cells coalesce cold readers and preserve concurrent ready identity")
    func concurrentReaders() async {
        let buffer = DIBoundedTraceBuffer(capacity: 256)
        let proof = _InnoDITraceOwner(context: .init(sink: buffer), containerType: Self.self)
        let token = ReadyPathToken()
        let cell = _InnoDISendableSharedCell<ReadyPathToken>(traceOwner: .disabled, providerName: "value") {
            let span = proof.start(member: "factory")
            proof.finish(.success, span: span)
            return token
        }
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    for _ in 0..<100 { #expect(cell.value() === token) }
                }
            }
        }
        #expect(buffer.snapshot().events.filter { $0.kind == .start }.count == 1)
        #expect(buffer.snapshot().events.filter { $0.kind == .success }.count == 1)
    }
}
