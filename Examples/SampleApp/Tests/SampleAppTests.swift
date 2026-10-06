import Testing
@testable import SampleApp

@Suite("SampleApp container")
struct SampleAppTests {
    @Test("Owned startup retries a failed preparation and closes after success")
    func ownedStartupLifecycle() async throws {
        let outcome = try await runOwnedLifecycleExample()
        #expect(outcome == StartupOutcome(session: "ready", attempts: 2, closed: true))
    }

    @Test("Root and feature dependencies resolve")
    func rootAndFeatureDependenciesResolve() {
        let config = AppConfig(baseURL: "https://api.example.com", environment: "prod")
        let container = AppContainer(config: config)

        #expect(container.apiClient.config.baseURL == "https://api.example.com")
        #expect(container.analytics.logger.subsystem == "InnoDI.SampleApp")
        #expect(container.featureFlags.environment == "prod")
        #expect(container.featureContainer.userRepository.database.path == "app.db")
        #expect(container.featureContainer.userRepository.authService.cache.maxEntries == 500)
    }
}
