
struct AppContainer {
    struct Overrides {
        var custom: String
    }
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var userID: String

    // MARK: - Initialization
    init(userID: String) {
        self._storage_userID = userID
    }
}