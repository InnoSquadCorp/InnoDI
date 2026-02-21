import InnoDI

struct Config {
    let baseURL: String
}

struct APIClient {
    let baseURL: String
}

struct UserService {
    let client: APIClient
}

@DIContainer(root: true)
struct AppContainer {
    @Provide(.input)
    var config: Config

    @Provide(.shared, factory: { (config: Config) in APIClient(baseURL: config.baseURL) }, concrete: true)
    var apiClient: APIClient

    @Provide(.shared, factory: { (apiClient: APIClient) in UserService(client: apiClient) }, concrete: true)
    var userService: UserService
}

let container = AppContainer(config: Config(baseURL: "https://api.example.com"))
print("Live baseURL:", container.userService.client.baseURL)

let mockContainer = AppContainer(
    config: Config(baseURL: "https://api.example.com"),
    apiClient: APIClient(baseURL: "mock://")
)
print("Mock baseURL:", mockContainer.userService.client.baseURL)
