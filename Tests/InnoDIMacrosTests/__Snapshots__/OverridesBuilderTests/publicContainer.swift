
public struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var userID: String
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var apiClient: APIClient

    // MARK: - Initialization
    public init(userID: String, apiClient: APIClient? = nil) {
        self._storage_userID = userID
        self._storage_apiClient = apiClient ?? APIClient()
    }

    // MARK: - Overrides Builder
    public struct Overrides {
        public var apiClient: APIClient? = nil
    }

    public typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    public init(userID: String, _ _innoDIApplyOverrides: (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(userID: userID, apiClient: _innoDIOverrides.apiClient)
    }

    // MARK: - withOverrides
    public static func withOverrides<OperationResult>(userID: String, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) -> OperationResult) -> OperationResult {
        let _innoDIContainer = Self(userID: userID, _innoDIApplyOverrides)
        return _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (throws)
    public static func withOverrides<OperationResult>(userID: String, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) throws -> OperationResult) throws -> OperationResult {
        let _innoDIContainer = Self(userID: userID, _innoDIApplyOverrides)
        return try _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async)
    public nonisolated(nonsending) static func withOverrides<OperationResult>(userID: String, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
        let _innoDIContainer = Self(userID: userID, _innoDIApplyOverrides)
        return await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async throws)
    public nonisolated(nonsending) static func withOverrides<OperationResult>(userID: String, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
        let _innoDIContainer = Self(userID: userID, _innoDIApplyOverrides)
        return try await _innoDIOperation(_innoDIContainer)
    }
}