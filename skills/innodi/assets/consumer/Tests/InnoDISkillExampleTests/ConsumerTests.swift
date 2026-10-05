import InnoDI
import Testing
@testable import InnoDISkillExample

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct ConsumerTests {
    @Test func constructsTypedDependencyAndOverrides() {
        let live = AppServices(baseURL: "live", count: ConstructionCount())
        #expect(live.client.baseURL == "live")
        let fake = AppServices(baseURL: "live", count: ConstructionCount()) {
            $0.client = APIClient(baseURL: "fake")
        }
        #expect(fake.client.baseURL == "fake")
    }

    @Test func prewarmIsSelectiveAndSharesCacheAcrossCopies() {
        let count = ConstructionCount()
        let services = AppServices(baseURL: "live", count: count)
        let copy = services
        #expect(count.value == 0)
        services.prewarm()
        #expect(count.value == 0)
        services.prewarm(.label)
        copy.prewarm(.label)
        #expect(copy.label == "live")
        #expect(count.value == 1)
    }

    @Test func explicitNilSkipsLiveFactoryAndUseDefaultRestoresIt() {
        let count = ConstructionCount()
        let empty = AppServices(baseURL: "live", count: count) {
            $0.set(\.label, to: nil)
        }
        #expect(empty.label == nil)
        #expect(count.value == 0)
        let restored = AppServices(baseURL: "live", count: count) {
            $0.set(\.label, to: nil)
            $0.useDefault(\.label)
        }
        #expect(restored.label == "live")
        #expect(count.value == 1)
    }

    @Test func ownedReadinessAndIdempotentClose() async throws {
        let loader = SessionLoader()
        let owner = try await SessionServices.makeOwned(loader: loader)
        #expect(await loader.attempts == 0)
        try await owner.requireReady(.session)
        #expect(try await owner.container.session == 42)
        await owner.close()
        await owner.close()
        do {
            _ = try await owner.container.session
            Issue.record("A closed owner must reject async reads")
        } catch DIAsyncScopeError.closed { /* expected */ }
    }

    @Test func failedPreparationRequiresExplicitRetry() async throws {
        let loader = SessionLoader(failFirst: true)
        let owner = try await SessionServices.makeOwned(loader: loader)
        let report = try await owner.prepare(.session)
        #expect(!report.isReady)
        #expect(await loader.attempts == 1)
        try await owner.retryAndRequireReady(.session)
        #expect(try await owner.container.session == 42)
        #expect(await loader.attempts == 2)
        await owner.close()
    }

    @Test func cancellingOneReaderDoesNotCancelSharedConstruction() async throws {
        let loader = SessionLoader(gateFirst: true)
        let owner = try await SessionServices.makeOwned(loader: loader)
        let reader = Task { @MainActor in try await owner.container.session }
        await loader.waitUntilStarted()
        reader.cancel()
        do {
            _ = try await reader.value
            Issue.record("The cancelled reader must throw")
        } catch is CancellationError { /* provider remains alive */ }
        await loader.release()
        #expect(try await owner.container.session == 42)
        #expect(await loader.attempts == 1)
        await owner.close()
    }

    @Test func preparedOperationReturnsValueAndClosesEscapedView() async throws {
        let escaped = try await SessionServices.withPrepared(.session, loader: SessionLoader()) {
            services in
            let value = try await services.session
            #expect(value == 42)
            return services
        }
        do {
            _ = try await escaped.session
            Issue.record("withPrepared must close before returning")
        } catch DIAsyncScopeError.closed { /* expected */ }
    }

    @Test func ownedOverrideSkipsFactory() async throws {
        let loader = SessionLoader(failFirst: true)
        let owner = try await SessionServices.makeOwnedWithOverrides(loader: loader) {
            $0.session = 99
        }
        try await owner.requireReady(.session)
        #expect(try await owner.container.session == 99)
        #expect(await loader.attempts == 0)
        await owner.close()
    }

    @Test func preparedPreflightFailureDoesNotStartFactory() async throws {
        let loader = SessionLoader()
        do {
            _ = try await SessionServices.withPrepared(.session, loader: loader, overrides: { _ in
                throw ExampleFailure.operation
            }) { services in try await services.session }
            Issue.record("A throwing preflight must fail")
        } catch ExampleFailure.operation { /* expected */ }
        #expect(await loader.attempts == 0)
    }

    @Test func swiftUIBoundaryCompiles() {
        _ = makePreview()
    }
}
