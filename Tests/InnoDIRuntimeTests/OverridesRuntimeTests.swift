import Testing

import InnoDI

// MARK: - Fixtures

protocol APIClientProtocol: Sendable {
    func tag() -> String
}

struct LiveAPIClient: APIClientProtocol {
    func tag() -> String { "live" }
}

struct MockAPIClient: APIClientProtocol {
    let value: String
    func tag() -> String { value }
}

struct ViewModel: Sendable {
    let id: String
    let apiTag: String
}

@DIContainer
struct RuntimeContainer {
    @Provide(.input)
    var userID: String

    @Provide(.shared, factory: { LiveAPIClient() })
    var apiClient: any APIClientProtocol

    @Provide(.transient, factory: { (apiClient: any APIClientProtocol) in
        ViewModel(id: "vm", apiTag: apiClient.tag())
    }, concrete: true)
    var viewModel: ViewModel
}

// MARK: - Runtime exercise

/// End-to-end runtime tests for the `@DIContainer` Overrides builder: the
/// convenience trailing-closure init and the four `withOverrides` effect
/// overloads must funnel user overrides into the primary init correctly.
///
/// Compile-time correctness is covered by `OverridesBuilderTests` (snapshot
/// matrix). These tests assert the *runtime* semantics: overrides actually
/// land, defaults are honored when omitted, and every effect overload
/// dispatches.
@Suite("@DIContainer Overrides runtime")
struct OverridesRuntimeTests {
    @Test("Convenience init defaults to the live factory when no override is applied")
    func defaultsWithoutOverride() {
        let container = RuntimeContainer(userID: "u1") { _ in }
        #expect(container.userID == "u1")
        #expect(container.apiClient.tag() == "live")
        #expect(container.viewModel.apiTag == "live")
    }

    @Test("Convenience init applies the shared override into the resolved accessor")
    func sharedOverrideWins() {
        let container = RuntimeContainer(userID: "u1") { overrides in
            overrides.apiClient = MockAPIClient(value: "mock-shared")
        }
        #expect(container.apiClient.tag() == "mock-shared")
        // The transient factory pulls the shared apiClient from the container,
        // so the override propagates through to downstream dependencies.
        #expect(container.viewModel.apiTag == "mock-shared")
    }

    @Test("Convenience init applies the transient override (stored value is returned each access)")
    func transientOverrideIsStored() {
        let fixed = ViewModel(id: "override", apiTag: "override-tag")
        let container = RuntimeContainer(userID: "u1") { overrides in
            overrides.viewModel = fixed
        }
        // `.transient` override is returned verbatim on every access.
        #expect(container.viewModel.id == "override")
        #expect(container.viewModel.id == "override")
    }

    @Test("withOverrides sync, non-throwing dispatches the operation closure")
    func withOverridesSyncNonThrowing() {
        let tag = RuntimeContainer.withOverrides(userID: "u1") { overrides in
            overrides.apiClient = MockAPIClient(value: "sync")
        } operation: { container in
            container.apiClient.tag()
        }
        #expect(tag == "sync")
    }

    @Test("withOverrides sync, throwing rethrows from the operation closure")
    func withOverridesSyncThrowing() throws {
        struct E: Error {}

        let tag = RuntimeContainer.withOverrides(userID: "u1") { overrides in
            overrides.apiClient = MockAPIClient(value: "sync-throws")
        } operation: { container -> String in
            container.apiClient.tag()
        }
        #expect(tag == "sync-throws")

        #expect(throws: E.self) {
            try RuntimeContainer.withOverrides(userID: "u1") { _ in
            } operation: { _ -> String in
                throw E()
            }
        }
    }

    @Test("withOverrides async, non-throwing awaits the operation closure")
    func withOverridesAsyncNonThrowing() async {
        let tag = await RuntimeContainer.withOverrides(userID: "u1") { overrides in
            overrides.apiClient = MockAPIClient(value: "async")
        } operation: { container in
            await Task { container.apiClient.tag() }.value
        }
        #expect(tag == "async")
    }

    @Test("withOverrides async, throwing awaits + rethrows from the operation closure")
    func withOverridesAsyncThrowing() async throws {
        struct E: Error {}

        let tag = try await RuntimeContainer.withOverrides(userID: "u1") { overrides in
            overrides.apiClient = MockAPIClient(value: "async-throws")
        } operation: { container async throws -> String in
            await Task.yield()
            return container.apiClient.tag()
        }
        #expect(tag == "async-throws")

        do {
            _ = try await RuntimeContainer.withOverrides(userID: "u1") { _ in
            } operation: { _ async throws -> String in
                await Task.yield()
                throw E()
            }
            Issue.record("Expected async throwing withOverrides overload to rethrow the operation error.")
        } catch is E {
        }
    }
}
