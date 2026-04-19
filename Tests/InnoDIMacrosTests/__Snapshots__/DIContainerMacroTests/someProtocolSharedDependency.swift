
struct AppContainer {
    var apiClient: some APIClientProtocol {
        get {
            return _storage_apiClient
        }
    }

    private let _storage_apiClient: some APIClientProtocol

    init(apiClient: (some APIClientProtocol)? = nil) {
        self._storage_apiClient = apiClient ?? APIClient()
    }
}