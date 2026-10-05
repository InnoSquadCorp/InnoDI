import Foundation
@testable import InnoDI
import Testing

private actor PriorityGate {
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if open { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        open = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private extension DIAsyncScope {
    func priorityTestWaiterCount() -> Int {
        let storage = Mirror(reflecting: self).children.first { $0.label == "waiters" }?.value
        return (storage as? [UUID: CheckedContinuation<Value, any Error>])?.count ?? -1
    }
}

private var supportsExplicitPriorityEscalation: Bool {
    if #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) { return true }
    return false
}

@Suite("Owned task reader priority", .timeLimit(.minutes(1)))
struct DIAsyncScopePriorityTests {
    @Test("A higher-priority reader raises existing construction without starting another task",
          .enabled(if: supportsExplicitPriorityEscalation))
    func higherPriorityReaderEscalatesConstruction() async throws {
        let entered = PriorityGate()
        let release = PriorityGate()
        let scope = DIAsyncScope(providerID: "priority") {
            let initial = Task.currentPriority.rawValue
            await entered.release()
            await release.wait()
            return (initial, Task.currentPriority.rawValue)
        }
        let starter = Task.detached(priority: .background) { try await scope.start() }
        await entered.wait()
        let reader = Task.detached(priority: .userInitiated) { try await scope.value() }
        while await scope.priorityTestWaiterCount() != 1 { await Task.yield() }
        await release.release()
        let (initial, final) = try await reader.value
        _ = try await starter.value
        #expect(initial == TaskPriority.background.rawValue)
        #expect(final >= TaskPriority.userInitiated.rawValue)
        #expect(await scope.status().generation == 0)
        await scope.close()
    }

    @Test("A lower-priority reader never lowers already running construction",
          .enabled(if: supportsExplicitPriorityEscalation))
    func lowerPriorityReaderDoesNotDemoteConstruction() async throws {
        let entered = PriorityGate()
        let release = PriorityGate()
        let scope = DIAsyncScope(providerID: "priority") {
            let initial = Task.currentPriority.rawValue
            await entered.release()
            await release.wait()
            return (initial, Task.currentPriority.rawValue)
        }
        let starter = Task.detached(priority: .userInitiated) { try await scope.start() }
        await entered.wait()
        let reader = Task.detached(priority: .background) { try await scope.value() }
        while await scope.priorityTestWaiterCount() != 1 { await Task.yield() }
        await release.release()
        let (initial, final) = try await reader.value
        _ = try await starter.value
        #expect(initial >= TaskPriority.userInitiated.rawValue)
        #expect(final >= initial)
        await scope.close()
    }
}
