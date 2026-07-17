
struct AppContainer {
    @_Concurrency.MainActor @InnoDI._InnoDIProvideAccessor(recovery: false)
    var userID: String
    @_Concurrency.MainActor @InnoDI._InnoDIProvideAccessor(recovery: false)
    var apiClient: APIClient

    // MARK: - Initialization
    @_Concurrency.MainActor init(userID: String, apiClient: APIClient? = nil) {
        self._storage_userID = userID
        self._storage_apiClient = apiClient ?? APIClient()
    }

    // MARK: - Overrides Builder
    @_Concurrency.MainActor struct Overrides {
        var apiClient: APIClient? = nil
    }

    typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    @_Concurrency.MainActor init(userID: String, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(userID: userID, apiClient: _innoDIOverrides.apiClient)
    }

    // MARK: - withOverrides
    @_Concurrency.MainActor static func withOverrides<OperationResult>(userID: String, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @_Concurrency.MainActor (Self) -> OperationResult) -> OperationResult {
        let _innoDIContainer = Self(userID: userID, _innoDIApplyOverrides)
        return _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (throws)
    @_Concurrency.MainActor static func withOverrides<OperationResult>(userID: String, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @_Concurrency.MainActor (Self) throws -> OperationResult) throws -> OperationResult {
        let _innoDIContainer = Self(userID: userID, _innoDIApplyOverrides)
        return try _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async)
    @_Concurrency.MainActor static func withOverrides<OperationResult>(userID: String, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @_Concurrency.MainActor (Self) async -> OperationResult) async -> OperationResult {
        let _innoDIContainer = Self(userID: userID, _innoDIApplyOverrides)
        return await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async throws)
    @_Concurrency.MainActor static func withOverrides<OperationResult>(userID: String, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @_Concurrency.MainActor (Self) async throws -> OperationResult) async throws -> OperationResult {
        let _innoDIContainer = Self(userID: userID, _innoDIApplyOverrides)
        return try await _innoDIOperation(_innoDIContainer)
    }
}