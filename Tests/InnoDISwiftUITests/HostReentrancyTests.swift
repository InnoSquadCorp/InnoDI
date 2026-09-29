import Observation
import SwiftUI
import Testing

@testable import InnoDISwiftUI

@MainActor
private func eventually(_ predicate: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !predicate(), ContinuousClock.now < deadline { await Task.yield() }
    return predicate()
}

/// Observes `owner.phase` through Observation, the way SwiftUI and
/// `withObservationTracking` clients do. Observation calls `onChange` before
/// the new value is stored, so the handler receives the owner's committed
/// transition, which is the phase being published. The observer re-registers
/// inside each callback, as a long-lived client would.
@MainActor
private final class PhaseObserver<Identity: Hashable & Sendable, Container> {
    private let owner: DIContainerHostOwner<Identity, Container>
    private let handler: (DIContainerHostPhase<Identity, Container>) -> Void
    private var isActive = true

    init(
        _ owner: DIContainerHostOwner<Identity, Container>,
        handler: @escaping (DIContainerHostPhase<Identity, Container>) -> Void
    ) {
        self.owner = owner
        self.handler = handler
        register()
    }

    func cancel() { isActive = false }

    private func register() {
        withObservationTracking {
            _ = owner.phase
        } onChange: { [self] in
            MainActor.assumeIsolated {
                guard isActive else { return }
                handler(owner.transitionPhase)
                register()
            }
        }
    }
}

@MainActor
private final class InvalidationCounter {
    var count = 0
}

@Suite("Host synchronous observer reentry", .serialized)
@MainActor
struct HostReentrancyTests {
    @Test("Replacement keeps its phase and cancellable operation", arguments: [false, true])
    func replacementFromObserver(readsUpcomingPhase: Bool) async {
        let owner = DIContainerHostOwner<Int, Int>()
        var replaced = false
        var started = false
        var cancelled = false
        let replace = {
            guard !replaced else { return }
            replaced = true
            owner.start(identity: 2, factory: { _ in
                started = true
                do { try await Task.sleep(for: .seconds(5)) }
                catch { cancelled = true; throw error }
                return 2
            })
        }
        let observer = PhaseObserver(owner) { phase in
            if !readsUpcomingPhase {
                replace()
            } else if case .loading(identity: 1) = phase {
                replace()
            }
        }
        defer { observer.cancel() }
        owner.start(identity: 1, factory: { $0 })
        if case .loading(identity: 2) = owner.phase {} else {
            Issue.record("Replacement phase was overwritten by the old publication")
        }
        #expect(await eventually { started })
        await owner.close()
        #expect(await eventually { cancelled })
    }

    @Test("A same-identity redraw from loading cannot replace callbacks")
    func duplicateStartFromObserver() async {
        let owner = DIContainerHostOwner<Int, Int>()
        var calls: [Int] = []
        var repeated = false
        let observer = PhaseObserver(owner) { phase in
            guard case .loading = phase, !repeated else { return }
            repeated = true
            owner.start(identity: 1, factory: { _ in calls.append(2); return 2 })
        }
        defer { observer.cancel() }
        owner.start(identity: 1, factory: { _ in calls.append(1); return 1 })
        #expect(await eventually { if case .ready = owner.phase { return true }; return false })
        #expect(calls == [1])
        await owner.close()
    }

    @Test("A failure observer can synchronously retry")
    func retryFromObserver() async {
        enum Failure: Error { case expected }
        let owner = DIContainerHostOwner<Int, Int>()
        var attempts = 0
        let observer = PhaseObserver(owner) { phase in
            if case .failed = phase { owner.retry() }
        }
        defer { observer.cancel() }
        owner.start(identity: 1, factory: { identity in
            attempts += 1
            if attempts == 1 { throw Failure.expected }
            return identity
        })
        #expect(await eventually { if case .ready = owner.phase { return true }; return false })
        #expect(attempts == 2)
        await owner.close()
    }

    @Test("Replacement waits for cleanup installed before publication", arguments: [false, true])
    func cleanupBeforePublication(replaceOnIdle: Bool) async {
        let owner = DIContainerHostOwner<Int, Int>()
        var allowClose = false
        var closeStarted = false
        var closeFinished = false
        var replacementStarted = false
        var replaced = false
        let observer = PhaseObserver(owner) { phase in
            let shouldReplace: Bool
            switch phase {
            case .idle: shouldReplace = replaceOnIdle && closeStarted == false
            case .ready(identity: 1, _): shouldReplace = !replaceOnIdle
            default: shouldReplace = false
            }
            guard shouldReplace, !replaced else { return }
            replaced = true
            owner.start(identity: 2, factory: { _ in
                replacementStarted = true
                #expect(closeFinished)
                return 2
            })
        }
        defer { observer.cancel() }
        owner.start(identity: 1, factory: { $0 }, close: { _ in
            closeStarted = true
            #expect(await eventually { allowClose })
            closeFinished = true
        })
        if replaceOnIdle {
            #expect(await eventually { if case .ready = owner.phase { return true }; return false })
        }
        let closing = replaceOnIdle ? Task { await owner.close() } : nil
        #expect(await eventually { closeStarted })
        #expect(!replacementStarted)
        allowClose = true
        await closing?.value
        #expect(await eventually { replacementStarted })
        #expect(await eventually { if case .ready(identity: 2, _) = owner.phase { return true }; return false })
        await owner.close()
    }

    @Test("Creating the lifecycle handle does not invalidate observers")
    func handleCreationDoesNotInvalidate() async {
        let owner = DIContainerHostOwner<Int, Int>()
        let invalidations = InvalidationCounter()
        withObservationTracking {
            _ = owner.phase
            _ = owner.handle
        } onChange: {
            MainActor.assumeIsolated { invalidations.count += 1 }
        }
        _ = owner.handle
        #expect(owner.handle == owner.handle)
        #expect(invalidations.count == 0)

        owner.start(identity: 1, factory: { $0 })
        #expect(invalidations.count == 1)
        await owner.close()
    }
}
