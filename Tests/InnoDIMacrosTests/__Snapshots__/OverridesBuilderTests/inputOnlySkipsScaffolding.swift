
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var userID: String
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var baseURL: String

    // MARK: - Initialization
    init(userID: String, baseURL: String, _innoDITrace: DITraceContext = .disabled) {
        self._storage_userID = userID
        self._storage_baseURL = baseURL
    }

    // MARK: - Overrides Builder
    struct Overrides {
    }

    typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    init(userID: String, baseURL: String, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(userID: userID, baseURL: baseURL, _innoDITrace: _innoDITrace)
    }

    // MARK: - withOverrides
    static func withOverrides<_InnoDIOperationResult>(userID: String, baseURL: String, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) -> _InnoDIOperationResult) -> _InnoDIOperationResult {
        let _innoDIContainer = Self(userID: userID, baseURL: baseURL, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (throws)
    static func withOverrides<_InnoDIOperationResult>(userID: String, baseURL: String, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) throws -> _InnoDIOperationResult) throws -> _InnoDIOperationResult {
        let _innoDIContainer = Self(userID: userID, baseURL: baseURL, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return try _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async)
    nonisolated(nonsending) static func withOverrides<_InnoDIOperationResult>(userID: String, baseURL: String, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async -> _InnoDIOperationResult) async -> _InnoDIOperationResult {
        let _innoDIContainer = Self(userID: userID, baseURL: baseURL, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async throws)
    nonisolated(nonsending) static func withOverrides<_InnoDIOperationResult>(userID: String, baseURL: String, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async throws -> _InnoDIOperationResult) async throws -> _InnoDIOperationResult {
        let _innoDIContainer = Self(userID: userID, baseURL: baseURL, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return try await _innoDIOperation(_innoDIContainer)
    }
}