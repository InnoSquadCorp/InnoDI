import Foundation
@testable import InnoDI
import Testing

private final class ScopeOverrideToken: Sendable {
    let identity = UUID()
}

private enum ValueTestFailure: Error { case expected }

private actor ValueTestRetryOperation {
    private var count = 0
    func run() throws -> Int {
        count += 1
        if count == 1 { throw ValueTestFailure.expected }
        return count
    }
}

private func resetSeededScope<P: DIAsyncPreparing>(_ provider: P) async throws {
    try await provider.resetForSubgraphRetry()
}

private extension DIAsyncScope {
    func valueTestHasOwnedTask() -> Bool {
        let storage = Mirror(reflecting: self).children.first { $0.label == "ownedTask" }?.value
        return (storage as? Task<Value, any Error>) != nil
    }
}

@Suite("Async scope ready overrides", .timeLimit(.minutes(1)))
struct DIAsyncScopeValueTests {
    @Test("Legacy factory inference and initializer references keep their exact signatures")
    func legacyFactoryOverloadsRemainCompatible() async throws {
        let make = DIAsyncScope<Int>.init(providerID:operation:)
        let referenced = make("reference", { 42 })
        let inferred = DIAsyncScope(providerID: "inferred") { 9 }
        #expect(await referenced.status().state == .idle)
        #expect(await inferred.status().state == .idle)
        #expect(try await referenced.value() == 42)
        #expect(try await inferred.value() == 9)
        await referenced.close()
        await inferred.close()
    }

    @Test("A closure can be a typed ready value without becoming a factory")
    func closureValuedOverride() async throws {
        let value: @Sendable () -> Int = { 11 }
        let scope = DIAsyncScope(value: value, providerID: "closure-value")
        #expect(await scope.status().state == .ready)
        let resolved = try await scope.value()
        #expect(resolved() == 11)
        #expect(!(await scope.valueTestHasOwnedTask()))
        await scope.close()
    }

    @Test("Concrete overrides begin ready and preserve identity without a task")
    func initiallyReady() async throws {
        let token = ScopeOverrideToken()
        let scope = DIAsyncScope(value: token, providerID: "override")
        let ready = DIAsyncProviderStatus(providerID: "override", generation: 0, state: .ready)
        #expect(await scope.status() == ready)
        #expect(try await scope.start() == ready)
        #expect(await scope.prepare() == ready)
        #expect(try await scope.value() === token)
        #expect(!(await scope.valueTestHasOwnedTask()))
        await #expect(throws: DIAsyncScopeError.retryRequiresFailure(providerID: "override")) {
            try await scope.retry()
        }
        await scope.close()
    }

    @Test("Optional nil remains a concrete ready override")
    func optionalNilOverride() async throws {
        let scope = DIAsyncScope<Int?>(value: nil, providerID: "optional")
        #expect(await scope.status().state == .ready)
        #expect(try await scope.value() == nil)
        try await scope.resetForSubgraphRetry()
        #expect(await scope.status().state == .idle)
        #expect(try await scope.start().state == .ready)
        #expect(try await scope.value() == nil)
        #expect(await scope.status().generation == 1)
        #expect(!(await scope.valueTestHasOwnedTask()))
        await scope.close()
    }

    @Test("Reset advances the generation and restores the typed seed directly",
          arguments: ["concrete", "existential", "generic"], ["start", "value"])
    func resetPreservesSeed(dispatch: String, admission: String) async throws {
        let token = ScopeOverrideToken()
        let scope = DIAsyncScope(value: token, providerID: "override")
        switch dispatch {
        case "concrete": try await scope.resetForSubgraphRetry()
        case "existential": try await (scope as any DIAsyncPreparing).resetForSubgraphRetry()
        default: try await resetSeededScope(scope)
        }
        #expect(await scope.status() == DIAsyncProviderStatus(providerID: "override", generation: 1, state: .idle))
        if admission == "start" { #expect(try await scope.start().state == .ready) }
        #expect(try await scope.value() === token)
        #expect(await scope.status() == DIAsyncProviderStatus(providerID: "override", generation: 1, state: .ready))
        #expect(!(await scope.valueTestHasOwnedTask()))
        await scope.close()
    }

    @Test("Subgraph retry preserves override identity in the new generation")
    func transactionalRetryPreservesSeed() async throws {
        let operation = ValueTestRetryOperation()
        let failed = DIAsyncScope(providerID: "failed") { try await operation.run() }
        let token = ScopeOverrideToken()
        let seeded = DIAsyncScope(value: token, providerID: "override")
        _ = await failed.prepare()
        let plan = try DIAsyncPreparationPlan(nodes: [
            .init(provider: failed), .init(provider: seeded, dependencies: ["failed"])
        ])
        #expect(try await plan.retry(["override"]).isReady)
        #expect(await failed.status().generation == 1)
        #expect(await seeded.status().generation == 1)
        #expect(try await seeded.value() === token)
        #expect(!(await seeded.valueTestHasOwnedTask()))
        try await plan.close(["override"])
    }

    @Test("Close releases cached and reusable values while the scope stays alive", arguments: [false, true])
    func closeReleasesSeed(resetFirst: Bool) async throws {
        var token: ScopeOverrideToken? = ScopeOverrideToken()
        weak var weakToken = token
        defer { weakToken = nil }
        let scope = DIAsyncScope(value: token!, providerID: "release")
        token = nil
        if resetFirst { try await scope.resetForSubgraphRetry() }
        #expect(weakToken != nil)
        await scope.close()
        #expect(weakToken == nil)
        #expect(await scope.status().state == .closed)
        await scope.close()
        await #expect(throws: DIAsyncScopeError.closed(providerID: "release")) { try await scope.start() }
        await #expect(throws: DIAsyncScopeError.closed(providerID: "release")) { try await scope.value() }
        await #expect(throws: DIAsyncScopeError.closed(providerID: "release")) { try await scope.resetForSubgraphRetry() }
        #expect(await scope.status().generation == (resetFirst ? 1 : 0))
    }
}
