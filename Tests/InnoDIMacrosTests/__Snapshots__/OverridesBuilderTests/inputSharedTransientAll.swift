
struct AppContainer {
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
    var viewModel: ViewModel {
        get {
            if let override = _override_viewModel {
                return override
            }
            return {
                ViewModel()
            }()
        }
    }

    private let _override_viewModel: ViewModel?

    // MARK: - Initialization
    init(userID: String, apiClient: APIClient? = nil, viewModel: ViewModel? = nil) {
        self._storage_userID = userID
        self._storage_apiClient = apiClient ?? APIClient()
        self._override_viewModel = viewModel
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var apiClient: APIClient? = nil
        var viewModel: ViewModel? = nil
    }

    // MARK: - Convenience Init with Overrides
    init(userID: String, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(userID: userID, apiClient: overrides.apiClient, viewModel: overrides.viewModel)
    }

    // MARK: - withOverrides
    static func withOverrides<OperationResult>(userID: String, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> OperationResult) -> OperationResult {
        let container = Self(userID: userID, applyOverrides)
        return operation(container)
    }

    // MARK: - withOverrides (throws)
    static func withOverrides<OperationResult>(userID: String, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> OperationResult) throws -> OperationResult {
        let container = Self(userID: userID, applyOverrides)
        return try operation(container)
    }

    // MARK: - withOverrides (async)
    static func withOverrides<OperationResult>(userID: String, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> OperationResult) async -> OperationResult {
        let container = Self(userID: userID, applyOverrides)
        return await operation(container)
    }

    // MARK: - withOverrides (async throws)
    static func withOverrides<OperationResult>(userID: String, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> OperationResult) async throws -> OperationResult {
        let container = Self(userID: userID, applyOverrides)
        return try await operation(container)
    }
}