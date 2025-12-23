import InnoDI

struct App {
    func run() {
        let config = AppConfig(baseURL: "https://api.example.com", environment: "prod")
        let container = AppContainer(config: config)
        _ = container.apiClient
        _ = container.analytics
        _ = container.featureFlags
        _ = container.featureContainer.userRepository
    }
}

App().run()
