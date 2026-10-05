import Foundation
@testable import InnoDI
import Testing

private actor OwnerTestSignal {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        opened = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private actor OwnerTestLog {
    private var values: [String] = []
    func append(_ value: String) { values.append(value) }
    func entries() -> [String] { values }
}

private actor OwnerCloseProbe: DIAsyncPreparing {
    nonisolated let providerID: String
    let entered = OwnerTestSignal()
    let release = OwnerTestSignal()
    private let log: OwnerTestLog
    private var phase: DIAsyncProviderStatus.State = .idle
    private var closes = 0

    init(_ providerID: String, log: OwnerTestLog = OwnerTestLog()) {
        self.providerID = providerID
        self.log = log
    }

    func status() -> DIAsyncProviderStatus {
        .init(providerID: providerID, generation: 0, state: phase)
    }

    func prepare() -> DIAsyncProviderStatus { status() }
    func retry() throws {
        throw DIAsyncScopeError.retryRequiresFailure(providerID: providerID)
    }

    func close() async {
        closes += 1
        await entered.open()
        await release.wait()
        phase = .closed
        await log.append(providerID)
    }

    func closeCount() -> Int { closes }
}

private enum OwnerTestFailure: Error { case expected }

private actor OwnerRetryOperation {
    private var calls = 0
    func run() throws -> Int {
        calls += 1
        if calls == 1 { throw OwnerTestFailure.expected }
        return calls
    }
}

private actor OwnerCancellableOperation {
    let started = OwnerTestSignal()
    let release = OwnerTestSignal()
    private var calls = 0

    func run() async -> Int {
        calls += 1
        if calls == 1 {
            await started.open()
            await release.wait()
        }
        return 8
    }
}

@Suite("Owned async admission boundary", .timeLimit(.minutes(1)))
struct DIAsyncAdmissionTests {
    @Test("Terminal close permanently rejects all provider IDs")
    func terminalClose() async throws {
        let admission = _InnoDIAsyncAdmission()
        try await admission.admit(providerID: "selected")
        try await admission.admit(providerID: "unrelated")
        await admission.closeAdmission()
        await admission.closeAdmission()
        #expect(await admission.isClosed())
        for providerID in ["selected", "unrelated"] {
            await #expect(throws: DIAsyncScopeError.closed(providerID: providerID)) {
                try await admission.admit(providerID: providerID)
            }
        }
    }

}

@Suite("Owned async lifecycle coordination", .timeLimit(.minutes(1)))
struct DIAsyncOwnerTests {
    @Test("Owner reuses validated graph preparation and transactional retry")
    func preparationAndRetry() async throws {
        let admission = _InnoDIAsyncAdmission()
        let operation = OwnerRetryOperation()
        let parent = DIAsyncScope(providerID: "parent", admission: admission) {
            try await operation.run()
        }
        let child = DIAsyncScope<Int>(providerID: "child", admission: admission) { 9 }
        let unused = DIAsyncScope<Int>(providerID: "unused", admission: admission) { 10 }
        let owner = try _InnoDIAsyncOwner(admission: admission, nodes: [
            .init(provider: parent),
            .init(provider: child, dependencies: ["parent"]),
            .init(provider: unused),
        ])
        let failed = try await owner.prepare(["child"])
        #expect(failed.entries.map(\.disposition) == [.failed, .blocked])
        #expect(await unused.status().state == .idle)
        let retried = try await owner.retry(["child"])
        #expect(retried.isReady)
        #expect(retried.entries.map(\.providerID) == ["parent", "child"])
        #expect(await parent.status().generation == 1)
        #expect(await child.status().generation == 1)
        #expect(await unused.status().state == .idle)
        await owner.close()
        #expect(await unused.status().state == .closed)
    }

    @Test("Owner initialization preserves plan validation")
    func validatesNodes() throws {
        let admission = _InnoDIAsyncAdmission()
        let scope = DIAsyncScope<Int>(providerID: "value", admission: admission) { 1 }
        #expect(throws: DIAsyncPreparationPlanError.duplicateProvider("value")) {
            try _InnoDIAsyncOwner(admission: admission, nodes: [
                .init(provider: scope), .init(provider: scope),
            ])
        }
        #expect(throws: DIAsyncPreparationPlanError.unknownDependency(
            providerID: "value", dependencyID: "missing"
        )) {
            try _InnoDIAsyncOwner(admission: admission, nodes: [
                .init(provider: scope, dependencies: ["missing"]),
            ])
        }
    }

    @Test("The close barrier rejects cached reads before later scopes are closed")
    func closeBarrierPrecedesScopeTraversal() async throws {
        let admission = _InnoDIAsyncAdmission()
        let scope = DIAsyncScope(value: 7, providerID: "later", admission: admission)
        let blocker = OwnerCloseProbe("first-close")
        let owner = try _InnoDIAsyncOwner(admission: admission, nodes: [
            .init(provider: scope), .init(provider: blocker, dependencies: ["later"]),
        ])
        let closing = Task { await owner.close() }
        await blocker.entered.wait()
        #expect(await admission.isClosed())
        #expect(await scope.status().state == .ready)
        #expect(await scope.prepare().state == .closed)
        // Reporting denied admission does not overwrite the cached phase.
        #expect(await scope.status().state == .ready)
        await #expect(throws: DIAsyncScopeError.closed(providerID: "later")) {
            try await scope.value()
        }
        await #expect(throws: DIAsyncScopeError.closed(providerID: "later")) {
            try await scope.start()
        }
        await #expect(throws: DIAsyncScopeError.closed(providerID: "later")) {
            try await scope.retry()
        }
        await #expect(throws: DIAsyncScopeError.closed(providerID: "later")) {
            try await scope.resetForSubgraphRetry()
        }
        await #expect(throws: DIAsyncScopeError.closed(providerID: "later")) {
            try await owner.prepare(["later", "first-close"])
        }
        await #expect(throws: DIAsyncScopeError.closed(providerID: "_InnoDIAsyncOwner")) {
            try await owner.retry([])
        }
        await blocker.release.open()
        await closing.value
        #expect(await scope.status().state == .closed)
    }

    @Test("A read admitted before close can finish while later scope teardown waits")
    func earlierAdmissionMayWin() async throws {
        let admission = _InnoDIAsyncAdmission()
        let started = OwnerTestSignal()
        let release = OwnerTestSignal()
        let scope = DIAsyncScope<Int>(providerID: "value", admission: admission) {
            await started.open()
            await release.wait()
            return 42
        }
        let blocker = OwnerCloseProbe("blocker")
        let owner = try _InnoDIAsyncOwner(admission: admission, nodes: [
            .init(provider: scope), .init(provider: blocker, dependencies: ["value"]),
        ])
        let admittedRead = Task { try await scope.value() }
        await started.wait()
        let closing = Task { await owner.close() }
        await blocker.entered.wait()
        await release.open()
        #expect(try await admittedRead.value == 42)
        await #expect(throws: DIAsyncScopeError.closed(providerID: "value")) {
            try await scope.value()
        }
        await blocker.release.open()
        await closing.value
        #expect(await scope.status().state == .closed)
    }

    @Test("Concurrent and cancelled close callers all await one complete teardown")
    func closeCallersJoinCompletion() async throws {
        let admission = _InnoDIAsyncAdmission()
        let log = OwnerTestLog()
        let parent = OwnerCloseProbe("parent", log: log)
        let child = OwnerCloseProbe("child", log: log)
        let owner = try _InnoDIAsyncOwner(admission: admission, nodes: [
            .init(provider: parent), .init(provider: child, dependencies: ["parent"]),
        ])
        let first = Task {
            await owner.close()
            #expect(await parent.status().state == .closed)
            #expect(await child.status().state == .closed)
        }
        await child.entered.wait()
        let callers = (0..<20).map { _ in
            Task {
                await owner.close()
                #expect(await parent.status().state == .closed)
                #expect(await child.status().state == .closed)
            }
        }
        first.cancel()
        for caller in callers { caller.cancel() }
        await child.release.open()
        await parent.entered.wait()
        #expect(await child.status().state == .closed)
        #expect(await parent.status().state == .idle)
        await parent.release.open()
        await first.value
        for caller in callers { await caller.value }
        await owner.close()
        #expect(await log.entries() == ["child", "parent"])
        #expect(await parent.closeCount() == 1)
        #expect(await child.closeCount() == 1)
    }

    @Test("Cancellation leaves selected ready and unrelated work available")
    func cancellationDoesNotPauseAdmission() async throws {
        let admission = _InnoDIAsyncAdmission()
        let operation = OwnerCancellableOperation()
        let scope = DIAsyncScope<Int>(providerID: "selected", admission: admission) {
            await operation.run()
        }
        let cached = DIAsyncScope(value: 9, providerID: "cached", admission: admission)
        let idle = DIAsyncScope<Int>(providerID: "idle", admission: admission) { 10 }
        let runningOperation = OwnerCancellableOperation()
        let running = DIAsyncScope<Int>(providerID: "running", admission: admission) {
            await runningOperation.run()
        }
        let retryOperation = OwnerRetryOperation()
        let failed = DIAsyncScope<Int>(providerID: "failed", admission: admission) {
            try await retryOperation.run()
        }
        let owner = try _InnoDIAsyncOwner(admission: admission, nodes: [
            .init(provider: scope), .init(provider: cached), .init(provider: idle),
            .init(provider: running), .init(provider: failed),
        ])
        _ = try await scope.start()
        _ = try await running.start()
        await operation.started.wait()
        await runningOperation.started.wait()
        #expect(await failed.prepare().state == .failed)
        let entered = OwnerTestSignal()
        let release = OwnerTestSignal()
        let cancellation = Task {
            await owner.withCancellation {
                await entered.open()
                await release.wait()
                await scope.cancel()
                await cached.cancel()
            }
        }
        await entered.wait()
        // The selected ready value and all unrelated states stay accessible
        // while the selected running scope has not reached its cancel turn.
        #expect(try await cached.value() == 9)
        #expect(try await cached.start().state == .ready)
        #expect(await cached.prepare().state == .ready)
        #expect(try await owner.prepare(["cached"]).isReady)
        #expect(try await scope.start().state == .running)
        _ = try await idle.start()
        #expect(try await idle.value() == 10)
        #expect(try await owner.prepare(["idle"]).isReady)
        #expect(try await running.start().state == .running)
        await runningOperation.release.open()
        #expect(try await running.value() == 8)
        #expect(try await owner.retry(["failed"]).isReady)
        #expect(try await failed.value() == 2)
        await release.open()
        await cancellation.value
        #expect(await scope.status().state == .cancelled)
        #expect(await cached.status().state == .ready)
        #expect(try await cached.value() == 9)
        await #expect(throws: CancellationError.self) { try await scope.value() }
        #expect(try await owner.retry(["selected"]).isReady)
        #expect(try await scope.value() == 8)
        #expect(await scope.status().generation == 1)
        await operation.release.open()
        await owner.close()
    }

    @Test("A factory throwing the public closed error remains a provider failure", arguments: [false, true])
    func factoryClosedErrorIsNotAdmissionDenial(bound: Bool) async throws {
        let admission = _InnoDIAsyncAdmission()
        let operation: DIAsyncScope<Int>.Operation = {
            throw DIAsyncScopeError.closed(providerID: "value")
        }
        let scope: DIAsyncScope<Int>
        if bound {
            scope = DIAsyncScope(providerID: "value", admission: admission, operation: operation)
        } else {
            scope = DIAsyncScope(providerID: "value", operation: operation)
        }
        #expect(await scope.prepare().state == .failed)
        #expect(await scope.status().state == .failed)
        #expect(await admission.isClosed() == false)
        await scope.close()
    }

    @Test("Concrete cancellation affects selected running work without propagating to dependencies")
    func cancellationDoesNotPropagate() async throws {
        let admission = _InnoDIAsyncAdmission()
        let parentOperation = OwnerCancellableOperation()
        let childOperation = OwnerCancellableOperation()
        let parent = DIAsyncScope<Int>(providerID: "parent", admission: admission) {
            await parentOperation.run()
        }
        let child = DIAsyncScope<Int>(providerID: "child", admission: admission) {
            await childOperation.run()
        }
        let idle = DIAsyncScope<Int>(providerID: "idle", admission: admission) { 1 }
        let owner = try _InnoDIAsyncOwner(admission: admission, nodes: [
            .init(provider: parent),
            .init(provider: child, dependencies: ["parent"]),
            .init(provider: idle),
        ])
        _ = try await parent.start()
        _ = try await child.start()
        await parentOperation.started.wait()
        await childOperation.started.wait()
        await owner.withCancellation {
            await child.cancel()
            await idle.cancel()
        }
        #expect(await parent.status().state == .running)
        #expect(await child.status().state == .cancelled)
        #expect(await idle.status().state == .idle)
        await parentOperation.release.open()
        await childOperation.release.open()
        #expect(try await parent.value() == 8)
        await owner.close()
    }

    @Test("Different cancellation selections serialize without coalescing or caller cancellation")
    func cancellationBodiesSerialize() async throws {
        let admission = _InnoDIAsyncAdmission()
        let owner = try _InnoDIAsyncOwner(admission: admission, nodes: [])
        let log = OwnerTestLog()
        let firstEntered = OwnerTestSignal()
        let firstRelease = OwnerTestSignal()
        let secondEntered = OwnerTestSignal()
        let secondRelease = OwnerTestSignal()
        let first = Task {
            await owner.withCancellation {
                await log.append("first-enter")
                await firstEntered.open()
                await firstRelease.wait()
                #expect(!Task.isCancelled)
                await log.append("first-exit")
            }
        }
        await firstEntered.wait()
        let second = Task {
            await owner.withCancellation {
                #expect(!Task.isCancelled)
                await log.append("second-enter")
                await secondEntered.open()
                await secondRelease.wait()
                await log.append("second-exit")
            }
        }
        first.cancel()
        second.cancel()
        await firstRelease.open()
        await secondEntered.wait()
        #expect(await log.entries() == ["first-enter", "first-exit", "second-enter"])
        try await admission.admit(providerID: "value")
        await secondRelease.open()
        await first.value
        await second.value
        #expect(await log.entries() == ["first-enter", "first-exit", "second-enter", "second-exit"])
        try await admission.admit(providerID: "value")
        await owner.close()
    }

    @Test("Close during cancellation closes admission and skips queued bodies")
    func closeDuringCancellation() async throws {
        let admission = _InnoDIAsyncAdmission()
        let scope = DIAsyncScope(value: 1, providerID: "value", admission: admission)
        let owner = try _InnoDIAsyncOwner(admission: admission, nodes: [.init(provider: scope)])
        let entered = OwnerTestSignal()
        let release = OwnerTestSignal()
        let log = OwnerTestLog()
        let active = Task {
            await owner.withCancellation {
                await entered.open()
                await release.wait()
                await log.append("active-complete")
            }
            #expect(await scope.status().state == .closed)
        }
        await entered.wait()
        let queued = Task {
            await owner.withCancellation { await log.append("queued-ran") }
            #expect(await scope.status().state == .closed)
        }
        let closing = Task { await owner.close() }
        // This observes a state transition, not elapsed time or a yield count.
        while !(await admission.isClosed()) { await Task.yield() }
        #expect(await scope.status().state == .ready)
        let afterClose = Task {
            await owner.withCancellation { await log.append("after-close-ran") }
            #expect(await scope.status().state == .closed)
        }
        await release.open()
        await active.value
        await queued.value
        await afterClose.value
        await closing.value
        #expect(await log.entries() == ["active-complete"])
        await #expect(throws: DIAsyncScopeError.closed(providerID: "value")) {
            try await admission.admit(providerID: "value")
        }
    }

    @Test("Overlapping coordinators never pause admission during cancellation")
    func overlappingCoordinatorsDoNotPauseAdmission() async throws {
        let admission = _InnoDIAsyncAdmission()
        let firstOwner = try _InnoDIAsyncOwner(admission: admission, nodes: [])
        let secondOwner = try _InnoDIAsyncOwner(admission: admission, nodes: [])
        let firstEntered = OwnerTestSignal()
        let firstRelease = OwnerTestSignal()
        let secondEntered = OwnerTestSignal()
        let secondRelease = OwnerTestSignal()
        let first = Task {
            await firstOwner.withCancellation {
                await firstEntered.open()
                await firstRelease.wait()
            }
        }
        let second = Task {
            await secondOwner.withCancellation {
                await secondEntered.open()
                await secondRelease.wait()
            }
        }
        await firstEntered.wait()
        await secondEntered.wait()
        await firstRelease.open()
        await first.value
        try await admission.admit(providerID: "value")
        await secondRelease.open()
        await second.value
        try await admission.admit(providerID: "value")
        await firstOwner.close()
        await secondOwner.close()
    }

    @Test("Closing a reserved retry permits cleanup while rejecting post-barrier reads",
          arguments: [false, true])
    func closeDuringReservedRetry(cancelRetry: Bool) async throws {
        let admission = _InnoDIAsyncAdmission()
        let scope = DIAsyncScope<Int>(providerID: "value", admission: admission) {
            throw OwnerTestFailure.expected
        }
        _ = await scope.prepare()
        let nodes = [DIAsyncPreparationNode(provider: scope)]
        let plan = try DIAsyncPreparationPlan(nodes: nodes)
        let owner = try _InnoDIAsyncOwner(admission: admission, nodes: nodes)
        let reserved = OwnerTestSignal()
        let release = OwnerTestSignal()
        let retry = Task {
            try await plan.retry(["value"], beforeCommit: {
                await reserved.open()
                await release.wait()
            })
        }
        await reserved.wait()
        let closing = Task { await owner.close() }
        while !(await admission.isClosed()) { await Task.yield() }
        // These must reject before waiting on the still-held reservation.
        await #expect(throws: DIAsyncScopeError.closed(providerID: "value")) {
            try await scope.value()
        }
        await #expect(throws: DIAsyncScopeError.closed(providerID: "value")) {
            try await scope.start()
        }
        await #expect(throws: DIAsyncScopeError.closed(providerID: "value")) {
            try await plan.retry(["value"])
        }
        if cancelRetry { retry.cancel() }
        await release.open()
        if cancelRetry {
            await #expect(throws: CancellationError.self) { try await retry.value }
        } else {
            _ = try await retry.value
        }
        await closing.value
        #expect(await scope.status().state == .closed)
        #expect(await scope.status().generation == (cancelRetry ? 0 : 1))
    }

    @Test("Close does not drain a factory that ignores cancellation and rejects its late value")
    func cancellationIgnoringFactoryDoesNotBlockClose() async throws {
        let admission = _InnoDIAsyncAdmission()
        let started = OwnerTestSignal()
        let release = OwnerTestSignal()
        let returned = AsyncStream<Bool>.makeStream()
        let scope = DIAsyncScope<Int>(providerID: "value", admission: admission) {
            await started.open()
            await release.wait()
            returned.continuation.yield(Task.isCancelled)
            returned.continuation.finish()
            return 17
        }
        let owner = try _InnoDIAsyncOwner(admission: admission, nodes: [.init(provider: scope)])
        let read = Task { try await scope.value() }
        await started.wait()
        await owner.close()
        #expect(await scope.status().state == .closed)
        await #expect(throws: DIAsyncScopeError.closed(providerID: "value")) { try await read.value }
        await release.open()
        var returnedIterator = returned.stream.makeAsyncIterator()
        #expect(await returnedIterator.next() == true)
        await #expect(throws: DIAsyncScopeError.closed(providerID: "value")) { try await scope.value() }
        #expect(await scope.status().state == .closed)
    }

    @Test("Scopes retain admission without retaining the lifecycle owner", arguments: [false, true])
    func ownerAndScopeHaveNoCaptureCycle(closeFirst: Bool) async throws {
        var admission: _InnoDIAsyncAdmission? = _InnoDIAsyncAdmission()
        weak var weakAdmission = admission
        defer { weakAdmission = nil }
        var scope: DIAsyncScope<Int>? = DIAsyncScope(
            value: 1, providerID: "value", admission: admission!
        )
        weak var weakScope = scope
        defer { weakScope = nil }
        var owner: _InnoDIAsyncOwner? = try _InnoDIAsyncOwner(
            admission: admission!, nodes: [.init(provider: scope!)]
        )
        weak var weakOwner = owner
        defer { weakOwner = nil }
        if closeFirst {
            await owner?.withCancellation { }
            await owner?.close()
        }
        admission = nil
        owner = nil
        #expect(weakOwner == nil)
        #expect(weakAdmission != nil)
        #expect(weakScope != nil)
        scope = nil
        #expect(weakScope == nil)
        #expect(weakAdmission == nil)
    }
}
