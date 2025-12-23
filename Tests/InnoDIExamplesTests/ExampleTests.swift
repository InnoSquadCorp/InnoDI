import InnoDI
import Testing

struct ExampleTests {
    @Test
    func containerResolvesSharedDependencies() {
        struct Config {
            let baseURL: String
        }

        struct APIClient {
            let baseURL: String
        }

        struct UserService {
            let client: APIClient
        }

        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var config: Config

            @Provide(.shared, factory: { (config: Config) in APIClient(baseURL: config.baseURL) })
            var apiClient: APIClient

            @Provide(.shared, factory: { (apiClient: APIClient) in UserService(client: apiClient) })
            var userService: UserService
        }

        let container = AppContainer(config: Config(baseURL: "https://test.local"))
        #expect(container.userService.client.baseURL == "https://test.local")
    }
}
