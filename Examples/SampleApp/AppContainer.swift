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
    let baseURL: String
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
    @Provide(.input)
    var apiClient: APIClient

    @Provide(.input)
    var cache: Cache

    @Provide(.input)
    var analytics: Analytics

    @Provide(.shared, factory: AuthService(apiClient: apiClient, cache: cache))
    var authService: AuthService

    @Provide(.shared, factory: UserRepository(database: Database(path: "app.db"), authService: authService))
    var userRepository: UserRepository
}

@DIContainer(root: true)
struct AppContainer {
    @Provide(.input)
    var config: AppConfig

    @Provide(.shared, factory: Logger(subsystem: "InnoDI.SampleApp"))
    var logger: Logger

    @Provide(.shared, factory: Database(path: "app.db"))
    var database: Database

    @Provide(.shared, factory: Cache(maxEntries: 500))
    var cache: Cache

    @Provide(.shared, factory: APIClient(baseURL: config.baseURL, logger: logger))
    var apiClient: APIClient

    @Provide(.shared, factory: Analytics(apiClient: apiClient, logger: logger))
    var analytics: Analytics

    @Provide(.shared, factory: FeatureFlags(environment: config.environment))
    var featureFlags: FeatureFlags

    @Provide(.shared, factory: FeatureContainer(apiClient: apiClient, cache: cache, analytics: analytics))
    var featureContainer: FeatureContainer
}
