
struct AppContainer {
    struct Overrides {
        var custom: String
    }
    var userID: String {
        get {
            return _storage_userID
        }
    }

    private let _storage_userID: String
    var apiClient: APIClient {
        get {
            return _storage_apiClient
        }
    }

    private let _storage_apiClient: APIClient

    init(userID: String, apiClient: APIClient? = nil) {
        self._storage_userID = userID
        self._storage_apiClient = apiClient ?? APIClient()
    }
}