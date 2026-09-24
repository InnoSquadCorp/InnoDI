import InnoDI
import Testing

private final class FactoryToken: Sendable {
    let value = 42
    let onDeinit: @Sendable () -> Void
    init(onDeinit: @escaping @Sendable () -> Void = {}) { self.onDeinit = onDeinit }
    deinit { onDeinit() }
}
private enum CaptureFailure: Error { case expected }
private actor CaptureBarrier {
    private var started = false
    private var starts: [CheckedContinuation<Void, Never>] = []
    private var finish: CheckedContinuation<Void, Never>?
    func run() async {
        started = true
        for waiter in starts { waiter.resume() }
        starts.removeAll()
        await withCheckedContinuation { finish = $0 }
    }
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { starts.append($0) }
    }
    func release() { finish?.resume(); finish = nil }
}

@Suite("Async scope factory capture lifetime")
struct DIAsyncScopeCaptureTests {
    @Test("Permanent close releases factory-only captures while scope remains alive", arguments: ["idle", "ready", "failed"])
    func terminalFactoryRelease(state: String) async throws {
        var token: FactoryToken? = FactoryToken()
        weak var weakToken = token
        defer { weakToken = nil }
        let scope = DIAsyncScope<Int>(providerID: "capture") { [token = token!] in
            if state == "failed" { throw CaptureFailure.expected }
            return token.value
        }
        token = nil
        if state != "idle" {
            do { _ = try await scope.value() } catch { #expect(state == "failed") }
        }
        #expect(weakToken != nil)
        await scope.close()
        #expect(weakToken == nil)
        #expect(await scope.status().state == .closed)
        await scope.close()
        await #expect(throws: DIAsyncScopeError.retryRequiresFailure(providerID: "capture")) { try await scope.retry() }
        await #expect(throws: DIAsyncScopeError.closed(providerID: "capture")) { try await scope.value() }
    }

    @Test("Closing running work does not invalidate its own captures", .timeLimit(.minutes(1)))
    func runningOperationRetainsCaptureUntilReturn() async throws {
        let barrier = CaptureBarrier()
        let released = AsyncStream<Void>.makeStream()
        var token: FactoryToken? = FactoryToken { released.continuation.finish() }
        weak var weakToken = token
        defer { weakToken = nil }
        let scope = DIAsyncScope<Int>(providerID: "running") { [token = token!] in
            await barrier.run()
            return token.value
        }
        token = nil
        let waiter = Task { try await scope.value() }
        await barrier.waitUntilStarted()
        await scope.close()
        #expect(weakToken != nil)
        await #expect(throws: DIAsyncScopeError.closed(providerID: "running")) { try await waiter.value }
        await barrier.release()
        // A deinit signal, not a sleep/yield count, proves the operation's own
        // captures have been released after its independently scheduled return.
        var iterator = released.stream.makeAsyncIterator()
        _ = await iterator.next()
        #expect(weakToken == nil)
        #expect(await scope.status().state == .closed)
    }
}
