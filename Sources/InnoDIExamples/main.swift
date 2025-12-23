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

    @Provide(.shared, factory: APIClient(baseURL: config.baseURL))
    var apiClient: APIClient

    @Provide(.shared, factory: UserService(client: apiClient))
    var userService: UserService
}

let container = AppContainer(config: Config(baseURL: "https://api.example.com"))
print("Live baseURL:", container.userService.client.baseURL)

var overrides = AppContainer.Overrides()
overrides.apiClient = APIClient(baseURL: "mock://")
let mockContainer = AppContainer(overrides: overrides, config: Config(baseURL: "https://api.example.com"))
print("Mock baseURL:", mockContainer.userService.client.baseURL)
