import InnoDI

struct App {
    func run() {
        let config = AppConfig(baseURL: "https://api.example.com", environment: "prod")
        let container = AppContainer(config: config)
        _ = container.apiClient.config.baseURL
        _ = container.analytics
        _ = container.featureFlags
        _ = container.featureContainer.userRepository
        print("Resolved SampleApp container for \(config.baseURL)")
    }
}

@main
struct SampleAppMain {
    static func main() async throws {
        App().run()
        let outcome = try await runOwnedLifecycleExample()
        precondition(outcome == StartupOutcome(session: "ready", attempts: 2, closed: true))
        print("Prepared, retried, and closed the owned startup services")
    }
}
