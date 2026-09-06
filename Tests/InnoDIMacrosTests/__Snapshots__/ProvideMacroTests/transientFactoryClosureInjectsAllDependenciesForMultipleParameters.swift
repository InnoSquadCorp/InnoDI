
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var apiClient: APIClient
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var logger: Logger
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var viewModel: ViewModel

    // MARK: - Initialization
    init(apiClient: APIClient, logger: Logger, viewModel: ViewModel? = nil, _innoDITrace: DITraceContext = .disabled) {
        let _innoDITraceOwner = _InnoDITraceOwner(
            context: _innoDITrace,
            containerType: Self.self
        )
        self._innoDITraceOwner_viewModel = _innoDITraceOwner
        self._storage_apiClient = apiClient
        self._storage_logger = logger
        self._override_viewModel = viewModel
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var viewModel: ViewModel? = nil
    }

    typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    init(apiClient: APIClient, logger: Logger, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(apiClient: apiClient, logger: logger, viewModel: _innoDIOverrides.viewModel, _innoDITrace: _innoDITrace)
    }

    // MARK: - withOverrides
    static func withOverrides<OperationResult>(apiClient: APIClient, logger: Logger, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) -> OperationResult) -> OperationResult {
        let _innoDIContainer = Self(apiClient: apiClient, logger: logger, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (throws)
    static func withOverrides<OperationResult>(apiClient: APIClient, logger: Logger, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) throws -> OperationResult) throws -> OperationResult {
        let _innoDIContainer = Self(apiClient: apiClient, logger: logger, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return try _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async)
    nonisolated(nonsending) static func withOverrides<OperationResult>(apiClient: APIClient, logger: Logger, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
        let _innoDIContainer = Self(apiClient: apiClient, logger: logger, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async throws)
    nonisolated(nonsending) static func withOverrides<OperationResult>(apiClient: APIClient, logger: Logger, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
        let _innoDIContainer = Self(apiClient: apiClient, logger: logger, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return try await _innoDIOperation(_innoDIContainer)
    }
}