
struct AppContainer {
    var apiClient: (any APIClientProtocol)? {
        get {
            return _storage_apiClient
        }
    }

    private let _storage_apiClient: (any APIClientProtocol)?

    init(apiClient: (any APIClientProtocol)?? = nil) {
        self._storage_apiClient = apiClient ?? APIClient()
    }
}