import Dispatch
import Foundation
import InnoDI
import Testing

private actor OwnedProbe {
    private var calls = 0
    private var started: [CheckedContinuation<Void, Never>] = []
    private var release: CheckedContinuation<Void, Never>?
    private var released = false

    func begin() async -> Int {
        calls += 1
        let pending = started
        started.removeAll()
        for waiter in pending { waiter.resume() }
        if !released { await withCheckedContinuation { release = $0 } }
        return calls
    }

    func waitForStart() async {
        if calls > 0 { return }
        await withCheckedContinuation { started.append($0) }
    }

    func finish() {
        released = true
        release?.resume()
        release = nil
    }

    func count() -> Int { calls }
}

private actor OwnedAttempts {
    enum Failure: Error { case firstAttempt }
    var calls = 0
    func value() throws -> Int {
        calls += 1
        if calls == 1 { throw Failure.firstAttempt }
        return calls
    }
}

/// Test-only scheduling barrier. Production trace sinks must not block; here
/// it lets close finish after construction tracing starts but before the user
/// factory is invoked. Every wait is bounded so a regression cannot hang CI.
private final class OwnedFactoryEntryGate: DITraceSink, Sendable {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let finished = DispatchSemaphore(value: 0)

    func record(_ event: DITraceEvent) {
        switch event.kind {
        case .start:
            entered.signal()
            #expect(release.wait(timeout: .now() + 10) == .success)
        case .success, .failure, .cancel:
            finished.signal()
        default:
            break
        }
    }

    func wait(_ semaphore: DispatchSemaphore) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: semaphore.wait(timeout: .now() + 10) == .success)
            }
        }
    }
}

@DIContainer(generateOwned: true)
fileprivate struct OwnedEagerContainer {
    @Input var probe: OwnedProbe
    @Provide(.shared, asyncFactory: { (probe: OwnedProbe) async in await probe.begin() })
    var service: Int
}

@DIContainer(generateOwned: true)
fileprivate struct OwnedDeferredContainer {
    @Input var probe: OwnedProbe
    @Provide(.shared, initialization: .onDemand, asyncFactory: { (probe: OwnedProbe) async in await probe.begin() })
    var service: Int
}

@DIContainer(generateOwned: true)
fileprivate struct OwnedRetryContainer {
    @Input var attempts: OwnedAttempts
    @Provide(.shared, initialization: .onDemand, asyncFactory: { (attempts: OwnedAttempts) async throws in try await attempts.value() })
    var service: Int
}

@DIContainer(generateOwned: true)
fileprivate struct OwnedChainContainer {
    @Input var probe: OwnedProbe
    @Provide(.shared, initialization: .onDemand, asyncFactory: { (probe: OwnedProbe) async in await probe.begin() })
    var dependency: Int
    @Provide(.shared, initialization: .onDemand, asyncFactory: { (dependency: Int) async throws in dependency + 1 })
    var service: Int
}

private final class OwnedLocalValue {}

@DIContainer(generateOwned: true)
fileprivate struct OwnedCallerContainer {
    @Input var input: OwnedLocalValue
    @Provide(.shared, initialization: .onDemand, factory: { (input: OwnedLocalValue) in input })
    var shared: OwnedLocalValue
}

@DIContainer
fileprivate struct OwnedBorrowedChild {
    @Input var input: OwnedLocalValue
}

@DIContainerRole(role: ContainerRole.local, mainActor: true, generateOwned: true)
fileprivate struct OwnedBorrowingParent {
    @Input var input: OwnedLocalValue
    @SubContainer(scope: .shared, with: [\Self.input]) var child: OwnedBorrowedChild
    @Provide(.shared, asyncFactory: { () async in 7 }) var service: Int
}

@Suite("Macro-generated explicit owned lifetimes")
struct OwnedContainerRuntimeTests {
    @Test("Close observed before user-factory entry rejects already-cancelled work")
    func closeBeforeFactoryEntry() async throws {
        let probe = OwnedProbe()
        // If the regression invokes the factory, it returns without hanging;
        // its call count then proves that the entry guard was missing.
        await probe.finish()
        let gate = OwnedFactoryEntryGate()
        let owner = try await OwnedEagerContainer.makeOwned(
            probe: probe, _innoDITrace: DITraceContext(sink: gate)
        )
        defer { gate.release.signal() }
        #expect(await gate.wait(gate.entered))
        await owner.close()
        #expect(await owner.status(.service).state == .closed)
        gate.release.signal()
        #expect(await gate.wait(gate.finished))
        #expect(await probe.count() == 0)
        await #expect(throws: DIAsyncScopeError.closed(providerID: "service")) {
            _ = try await owner.container.service
        }
    }

    @Test("Closing an idle on-demand owner never admits its factory")
    func closeBeforeOnDemandAdmission() async throws {
        let probe = OwnedProbe()
        await probe.finish()
        let owner = try await OwnedDeferredContainer.makeOwned(probe: probe)
        await owner.close()
        await owner.close()
        await #expect(throws: DIAsyncScopeError.closed(providerID: "service")) {
            _ = try await owner.container.service
        }
        #expect(await probe.count() == 0)
    }

    @Test("Close does not drain a factory already admitted and running")
    func closeKeepsNonDrainingContract() async throws {
        let probe = OwnedProbe()
        let trace = OwnedFactoryEntryGate()
        trace.release.signal()
        let owner = try await OwnedEagerContainer.makeOwned(
            probe: probe, _innoDITrace: DITraceContext(sink: trace)
        )
        await probe.waitForStart()
        let timeout = Task {
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            Issue.record("close waited for a cancellation-ignoring factory")
            await probe.finish()
        }
        defer { timeout.cancel() }
        await owner.close()
        timeout.cancel()
        await timeout.value
        #expect(await probe.count() == 1)
        #expect(await owner.status(.service).state == .closed)
        // The factory is still suspended until explicitly released. Its late
        // result cannot reopen the owner or be returned by a subsequent read.
        await probe.finish()
        #expect(await trace.wait(trace.finished))
        #expect(await owner.status(.service).state == .closed)
        await #expect(throws: DIAsyncScopeError.closed(providerID: "service")) {
            _ = try await owner.container.service
        }
    }

    @Test("Eager construction returns after admission without waiting for readiness")
    func eagerAdmission() async throws {
        let probe = OwnedProbe()
        let owner = try await OwnedEagerContainer.makeOwned(probe: probe)
        await probe.waitForStart()
        #expect(await owner.status(.service).state == .running)
        await probe.finish()
        #expect(try await owner.container.service == 1)
        await owner.close()
    }

    @Test("Copied owners and escaped views share terminal close, independent owners do not")
    func sharedLifetime() async throws {
        let probe = OwnedProbe()
        await probe.finish()
        let owner = try await OwnedDeferredContainer.makeOwned(probe: probe)
        let other = try await OwnedDeferredContainer.makeOwned(probe: probe)
        let copied = owner
        let view = owner.container
        #expect(await probe.count() == 0)
        #expect(try await view.service == 1)
        await copied.close()
        await owner.close()
        await #expect(throws: DIAsyncScopeError.closed(providerID: "service")) {
            _ = try await view.service
        }
        #expect(try await other.container.service == 2)
        await other.close()
    }

    @Test("Direct override prunes runtime factory edges and never reads unused dependencies")
    func overridePruning() async throws {
        let probe = OwnedProbe()
        let owner = try await OwnedChainContainer.makeOwned(probe: probe, service: 42)
        let report = try await owner.prepare(.service)
        #expect(report.isReady)
        #expect(report.entries.map(\.providerID) == ["service"])
        #expect(await probe.count() == 0)
        #expect(try await owner.container.service == 42)
        #expect(await owner.status(.dependency).state == .idle)
        await owner.close()
        await #expect(throws: DIAsyncScopeError.closed(providerID: "service")) {
            _ = try await owner.container.service
        }
    }

    @Test("Failed selection retries and advances its generation")
    func retry() async throws {
        let owner = try await OwnedRetryContainer.makeOwned(attempts: OwnedAttempts())
        let failure = try await owner.prepare(.service)
        #expect(!failure.isReady)
        #expect(await owner.status(.service).state == .failed)
        let retried = try await owner.retry(.service)
        #expect(retried.isReady)
        #expect(try await owner.container.service == 2)
        #expect(await owner.status(.service).generation == 1)
        await owner.close()
    }

    @Test("Cancel selects exact running scopes, does not close, and preserves retry")
    func cancel() async throws {
        let probe = OwnedProbe()
        let owner = try await OwnedEagerContainer.makeOwned(probe: probe)
        await probe.waitForStart()
        await owner.cancel(.service)
        #expect(await owner.status(.service).state == .cancelled)
        await probe.finish()
        let report = try await owner.retry(.service)
        #expect(report.isReady)
        #expect(try await owner.container.service == 2)
        await owner.close()
    }

    @Test("Cancelling idle and ready selections keeps their values available")
    func cancelDoesNotAffectIdleOrReady() async throws {
        let probe = OwnedProbe()
        await probe.finish()
        let owner = try await OwnedDeferredContainer.makeOwned(probe: probe)
        await owner.cancel(.service)
        #expect(await owner.status(.service).state == .idle)
        #expect(try await owner.container.service == 1)
        await owner.cancel(.service)
        #expect(await owner.status(.service).state == .ready)
        #expect(try await owner.container.service == 1)
        await owner.close()
    }

    @MainActor
    @Test("Non-Sendable synchronous values stay on the caller and remain readable after close")
    func synchronousBorrowing() async throws {
        let input = OwnedLocalValue()
        let owner = try await OwnedCallerContainer.makeOwned(input: input)
        let view = owner.container
        #expect(view.shared === input)
        await owner.close()
        #expect(view.input === input)
        #expect(view.shared === input)
    }

    @MainActor
    @Test("Shared child containers borrow inputs and are not adopted by the parent owner")
    func borrowedChild() async throws {
        let input = OwnedLocalValue()
        let owner = try await OwnedBorrowingParent.makeOwned(input: input)
        let child = owner.container.child
        #expect(child.input === input)
        await owner.close()
        #expect(child.input === input)
    }
}
