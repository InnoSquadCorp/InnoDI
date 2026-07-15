
struct AppContainer {
    @Swift.MainActor @InnoDI._InnoDIProvideAccessor(recovery: false)
    var userID: String
    @Swift.MainActor @InnoDI._InnoDIProvideAccessor(recovery: false)
    var apiClient: APIClient

    // MARK: - Initialization
    @Swift.MainActor init(userID: String, apiClient: APIClient? = nil) {
        self._storage_userID = userID
        self._storage_apiClient = apiClient ?? APIClient()
    }

    // MARK: - Overrides Builder
    @Swift.MainActor struct Overrides {
        var apiClient: APIClient? = nil
    }

    typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    @Swift.MainActor init(userID: String, _ _innoDIApplyOverrides: @Swift.MainActor (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(userID: userID, apiClient: _innoDIOverrides.apiClient)
    }

    // MARK: - withOverrides
    @Swift.MainActor static func withOverrides<OperationResult>(userID: String, _ _innoDIApplyOverrides: @Swift.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @Swift.MainActor (Self) -> OperationResult) -> OperationResult {
        let _innoDIContainer = Self(userID: userID, _innoDIApplyOverrides)
        return _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (throws)
    @Swift.MainActor static func withOverrides<OperationResult>(userID: String, _ _innoDIApplyOverrides: @Swift.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @Swift.MainActor (Self) throws -> OperationResult) throws -> OperationResult {
        let _innoDIContainer = Self(userID: userID, _innoDIApplyOverrides)
        return try _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async)
    @Swift.MainActor static func withOverrides<OperationResult>(userID: String, _ _innoDIApplyOverrides: @Swift.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @Swift.MainActor (Self) async -> OperationResult) async -> OperationResult {
        let _innoDIContainer = Self(userID: userID, _innoDIApplyOverrides)
        return await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async throws)
    @Swift.MainActor static func withOverrides<OperationResult>(userID: String, _ _innoDIApplyOverrides: @Swift.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @Swift.MainActor (Self) async throws -> OperationResult) async throws -> OperationResult {
        let _innoDIContainer = Self(userID: userID, _innoDIApplyOverrides)
        return try await _innoDIOperation(_innoDIContainer)
    }
}