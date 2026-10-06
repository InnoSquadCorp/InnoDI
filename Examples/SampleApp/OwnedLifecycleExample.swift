import InnoDI

private enum StartupFailure: Error { case firstAttempt }

actor StartupAttempts {
    private var count = 0

    func connect() throws -> String {
        count += 1
        if count == 1 { throw StartupFailure.firstAttempt }
        return "ready"
    }

    func total() -> Int { count }
}

struct StartupMetrics: Sendable { let label = "startup" }

@DIContainer(generateOwned: true)
struct StartupServices {
    @Input var attempts: StartupAttempts

    @Provide(.shared, initialization: .onDemand, factory: StartupMetrics())
    var metrics: StartupMetrics

    @Provide(.shared, initialization: .onDemand,
             asyncFactory: { (attempts: StartupAttempts) async throws in try await attempts.connect() })
    var session: String
}

struct StartupOutcome: Equatable, Sendable {
    let session: String
    let attempts: Int
    let closed: Bool
}

/// This example deliberately fails its first asynchronous preparation. A retry
/// is explicit, readiness is checked, and both success and error paths close.
nonisolated(nonsending) func runOwnedLifecycleExample() async throws -> StartupOutcome {
    let attempts = StartupAttempts()
    let legacy = StartupServices(attempts: attempts)
    legacy.prewarm(.metrics)
    precondition(legacy.metrics.label == "startup")

    let owner = try await StartupServices.makeOwned(attempts: attempts)
    do {
        let first = try await owner.prepare(.session)
        precondition(!first.isReady)
        try await owner.retryAndRequireReady(.session)
        let session = try await owner.container.session
        await owner.close()
        let status = await owner.status(.session)
        return StartupOutcome(session: session, attempts: await attempts.total(), closed: status.state == .closed)
    } catch {
        await owner.close()
        throw error
    }
}
