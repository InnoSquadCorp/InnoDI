
struct AppContainer {
    var apiClient: APIClient {
        get {
            return _storage_apiClient
        }
    }

    private let _storage_apiClient: APIClient
}