
struct AppContainer {
    var userID: String {
        get {
            return _storage_userID
        }
    }

    private let _storage_userID: String
    var baseURL: String {
        get {
            return _storage_baseURL
        }
    }

    private let _storage_baseURL: String

    init(userID: String, baseURL: String) {
        self._storage_userID = userID
        self._storage_baseURL = baseURL
    }
}