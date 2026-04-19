
struct AppContainer {
    var apiClient: APIClientProtocol & LoggerProtocol {
        get {
            return _storage_apiClient
        }
    }

    private let _storage_apiClient: APIClientProtocol & LoggerProtocol

    init(apiClient: (APIClientProtocol & LoggerProtocol)? = nil) {
        self._storage_apiClient = apiClient ?? APIClient()
    }
}