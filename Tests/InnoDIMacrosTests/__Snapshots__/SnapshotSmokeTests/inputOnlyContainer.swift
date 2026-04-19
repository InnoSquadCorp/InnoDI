
struct AppContainer {
    var baseURL: String {
        get {
            return _storage_baseURL
        }
    }

    private let _storage_baseURL: String

    init(baseURL: String) {
        self._storage_baseURL = baseURL
    }
}