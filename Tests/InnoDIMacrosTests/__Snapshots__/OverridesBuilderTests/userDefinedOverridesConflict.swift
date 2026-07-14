
struct AppContainer {
    struct Overrides {
        var custom: String
    }
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var userID: String

    private var _storage_userID: String? = nil
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var apiClient: APIClient

    private var _storage_apiClient: APIClient? = nil

    // MARK: - Initialization
    init(userID: String, apiClient: APIClient? = nil) {
        self._storage_userID = userID
        self._storage_apiClient = apiClient ?? APIClient()
    }
}