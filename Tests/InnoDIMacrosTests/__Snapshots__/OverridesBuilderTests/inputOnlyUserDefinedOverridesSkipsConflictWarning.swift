
struct AppContainer {
    struct Overrides {
        var custom: String
    }
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var userID: String

    private var _storage_userID: String? = nil

    // MARK: - Initialization
    init(userID: String) {
        self._storage_userID = userID
    }
}