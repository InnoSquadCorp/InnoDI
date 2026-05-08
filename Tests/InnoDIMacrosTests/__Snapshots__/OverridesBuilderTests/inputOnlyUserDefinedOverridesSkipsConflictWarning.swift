
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

    // MARK: - Initialization
    init(userID: String) {
        self._storage_userID = userID
    }
}