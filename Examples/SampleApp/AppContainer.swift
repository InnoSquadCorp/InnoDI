import InnoDI

struct AppConfig {
    let baseURL: String
    let environment: String
}

struct Logger {
    let subsystem: String
}

struct Database {
    let path: String
}

struct Cache {
    let maxEntries: Int
}

struct APIClient {
    let config: AppConfig
    let logger: Logger
}

struct Analytics {
    let apiClient: APIClient
    let logger: Logger
}

struct FeatureFlags {
    let environment: String
}

struct AuthService {
    let apiClient: APIClient
    let cache: Cache
}

struct UserRepository {
    let database: Database
    let authService: AuthService
}

@DIContainer
struct FeatureContainer {
    @Input
    var apiClient: APIClient

    @Input
    var cache: Cache

    @Input
    var database: Database

    @Input
    var analytics: Analytics

    @Provide(.shared, factory: { (apiClient: APIClient, cache: Cache) in
        AuthService(apiClient: apiClient, cache: cache)
    })
    var authService: AuthService

    @Provide(.shared, factory: { (database: Database, authService: AuthService) in
        UserRepository(database: database, authService: authService)
    })
    var userRepository: UserRepository
}

@DIContainerRole(role: ContainerRole.root)
struct AppContainer {
    @Input
    var config: AppConfig

    @Provide(.shared, factory: Logger(subsystem: "InnoDI.SampleApp"))
    var logger: Logger

    @Provide(.shared, factory: Database(path: "app.db"))
    var database: Database

    @Provide(.shared, factory: Cache(maxEntries: 500))
    var cache: Cache

    @Provide(.shared, APIClient.self, with: [\Self.config, \Self.logger])
    var apiClient: APIClient

    @Provide(.shared, Analytics.self, with: [\Self.apiClient, \Self.logger])
    var analytics: Analytics

    @Provide(.shared, factory: { (config: AppConfig) in
        FeatureFlags(environment: config.environment)
    })
    var featureFlags: FeatureFlags

    @SubContainer(
        scope: .shared,
        with: [
            \AppContainer.apiClient,
            \AppContainer.cache,
            \AppContainer.database,
            \AppContainer.analytics
        ]
    )
    var featureContainer: FeatureContainer
}
