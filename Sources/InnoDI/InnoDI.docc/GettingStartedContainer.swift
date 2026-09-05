import InnoDI

struct APIClient {
    let baseURL: String
}

@DIContainer
struct AppContainer {
    @Input
    var baseURL: String

    @Provide(.shared, APIClient.self, with: [\Self.baseURL])
    var apiClient: APIClient
}

let container = AppContainer(baseURL: "https://api.example.com")
_ = container.apiClient
