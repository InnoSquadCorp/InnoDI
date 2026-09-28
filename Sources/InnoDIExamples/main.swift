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

@DIContainerRole(role: ContainerRole.root)
struct AppContainer {
    @Input
    var config: Config

    @Provide(.shared, factory: { (config: Config) in APIClient(baseURL: config.baseURL) })
    var apiClient: APIClient

    @Provide(.shared, factory: { (apiClient: APIClient) in UserService(client: apiClient) })
    var userService: UserService
}

let container = AppContainer(config: Config(baseURL: "https://api.example.com"))
print("Live baseURL:", container.userService.client.baseURL)

let mockContainer = AppContainer(
    config: Config(baseURL: "https://api.example.com"),
    apiClient: APIClient(baseURL: "mock://")
)
print("Mock baseURL:", mockContainer.userService.client.baseURL)
