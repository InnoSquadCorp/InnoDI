
struct AppContainer {
    @_Concurrency.MainActor @InnoDI._InnoDIProvideAccessor(recovery: false)
    var userID: String
    @_Concurrency.MainActor @InnoDI._InnoDIProvideAccessor(recovery: false)
    var apiClient: APIClient

    // MARK: - Initialization
    @_Concurrency.MainActor init(userID: String, apiClient: APIClient? = nil, _innoDITrace: DITraceContext = .disabled) {
        let _innoDITraceOwner = _InnoDITraceOwner(
            context: _innoDITrace,
            containerType: Self.self
        )
        self._innoDITraceOwner_apiClient = _innoDITraceOwner
        self._storage_userID = userID
        if let _innoDIOverride = apiClient {
            self._storage_apiClient = _innoDITraceOwner.overridden(
                member: "apiClient",
                value: _innoDIOverride
            )
        } else {
            let _innoDITraceSpan_apiClient = _innoDITraceOwner.start(
                member: "apiClient"
            )
            let _innoDIResolved_apiClient = APIClient()
            _innoDITraceOwner.finish(.success, span: _innoDITraceSpan_apiClient)
            self._storage_apiClient = _innoDIResolved_apiClient
        }
    }

    // MARK: - Overrides Builder
    @_Concurrency.MainActor struct Overrides {
        var apiClient: APIClient? = nil
    }

    typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    @_Concurrency.MainActor init(userID: String, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(userID: userID, apiClient: _innoDIOverrides.apiClient, _innoDITrace: _innoDITrace)
    }

    // MARK: - withOverrides
    @_Concurrency.MainActor static func withOverrides<OperationResult>(userID: String, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @_Concurrency.MainActor (Self) -> OperationResult) -> OperationResult {
        let _innoDIContainer = Self(userID: userID, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (throws)
    @_Concurrency.MainActor static func withOverrides<OperationResult>(userID: String, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @_Concurrency.MainActor (Self) throws -> OperationResult) throws -> OperationResult {
        let _innoDIContainer = Self(userID: userID, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return try _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async)
    @_Concurrency.MainActor static func withOverrides<OperationResult>(userID: String, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @_Concurrency.MainActor (Self) async -> OperationResult) async -> OperationResult {
        let _innoDIContainer = Self(userID: userID, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async throws)
    @_Concurrency.MainActor static func withOverrides<OperationResult>(userID: String, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @_Concurrency.MainActor (Self) async throws -> OperationResult) async throws -> OperationResult {
        let _innoDIContainer = Self(userID: userID, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return try await _innoDIOperation(_innoDIContainer)
    }
}