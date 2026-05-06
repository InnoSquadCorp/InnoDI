import InnoDI

struct APIClient {
    let baseURL: String
}

@DIContainer
struct AppContainer {
    @Provide(.input)
    var baseURL: String

    @Provide(.shared, APIClient.self, with: [\AppContainer.baseURL], concrete: true)
    var apiClient: APIClient
}

let container = AppContainer(baseURL: "https://api.example.com")
_ = container.apiClient
