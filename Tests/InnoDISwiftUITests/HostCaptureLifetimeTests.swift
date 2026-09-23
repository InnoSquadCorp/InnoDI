import Combine
import InnoDISwiftUI
import Testing

private actor HostCaptureSignal {
    private var signalled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if signalled { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func signal() {
        signalled = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

@MainActor
private final class HostCapturedValue {
    let value: Int
    init(_ value: Int) { self.value = value }
}

@Suite("Host capture lifetime")
@MainActor
struct HostCaptureLifetimeTests {
    @Test("Close releases factory and close captures while the owner stays alive")
    func closeReleasesCaptures() async {
        let owner = DIContainerHostOwner<Int, Int>()
        weak var weakFactory: HostCapturedValue?
        weak var weakClose: HostCapturedValue?
        do {
            let factoryValue = HostCapturedValue(7)
            let closeValue = HostCapturedValue(11)
            weakFactory = factoryValue
            weakClose = closeValue
            owner.start(
                identity: 1,
                factory: { _ in factoryValue.value },
                close: { _ in #expect(closeValue.value == 11) }
            )
        }
        for await phase in owner.$phase.values {
            if case .ready = phase { break }
        }
        #expect(weakFactory != nil)
        #expect(weakClose != nil)
        await owner.close()
        #expect(weakFactory == nil)
        #expect(weakClose == nil)
        owner.retry()
        if case .idle = owner.phase {} else { Issue.record("Closed owner must stay idle") }
    }

    @Test("A new generation started during close keeps its retry and close callbacks")
    func startDuringCloseKeepsNewCallbacks() async {
        enum Failure: Error { case expected }
        let owner = DIContainerHostOwner<Int, Int>()
        let closeStarted = HostCaptureSignal()
        let closeRelease = HostCaptureSignal()
        owner.start(identity: 1, factory: { $0 }, close: { _ in
            await closeStarted.signal()
            await closeRelease.wait()
        })
        for await phase in owner.$phase.values {
            if case .ready = phase { break }
        }
        let closing = Task { await owner.close() }
        await closeStarted.wait()
        var attempts = 0
        var closed: [Int] = []
        owner.start(identity: 2, factory: { identity in
            attempts += 1
            if attempts == 1 { throw Failure.expected }
            return identity
        }, close: { closed.append($0) })
        await closeRelease.signal()
        await closing.value
        for await phase in owner.$phase.values {
            if case .failed = phase { break }
        }
        owner.retry()
        for await phase in owner.$phase.values {
            if case .ready = phase { break }
        }
        #expect(attempts == 2)
        await owner.close()
        #expect(closed == [2])
    }
}
