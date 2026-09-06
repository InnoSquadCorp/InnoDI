
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var userID: String
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var apiClient: APIClient
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var viewModel: ViewModel

    // MARK: - Initialization
    init(userID: String, apiClient: APIClient? = nil, viewModel: ViewModel? = nil, _innoDITrace: DITraceContext = .disabled) {
        let _innoDITraceOwner = _InnoDITraceOwner(
            context: _innoDITrace,
            containerType: Self.self
        )
        self._innoDITraceOwner_apiClient = _innoDITraceOwner
        self._innoDITraceOwner_viewModel = _innoDITraceOwner
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
        self._override_viewModel = viewModel
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var apiClient: APIClient? = nil
        var viewModel: ViewModel? = nil
    }

    typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    init(userID: String, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(userID: userID, apiClient: _innoDIOverrides.apiClient, viewModel: _innoDIOverrides.viewModel, _innoDITrace: _innoDITrace)
    }

    // MARK: - withOverrides
    static func withOverrides<OperationResult>(userID: String, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) -> OperationResult) -> OperationResult {
        let _innoDIContainer = Self(userID: userID, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (throws)
    static func withOverrides<OperationResult>(userID: String, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) throws -> OperationResult) throws -> OperationResult {
        let _innoDIContainer = Self(userID: userID, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return try _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async)
    nonisolated(nonsending) static func withOverrides<OperationResult>(userID: String, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
        let _innoDIContainer = Self(userID: userID, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async throws)
    nonisolated(nonsending) static func withOverrides<OperationResult>(userID: String, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
        let _innoDIContainer = Self(userID: userID, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return try await _innoDIOperation(_innoDIContainer)
    }
}