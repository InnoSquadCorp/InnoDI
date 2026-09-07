
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var config: Config
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var logger: Logger
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var service: Service

    // MARK: - Initialization
    init(config: Config, logger: Logger? = nil, service: Service? = nil, _innoDITrace: DITraceContext = .disabled) {
        let _innoDITraceOwner = _InnoDITraceOwner(
            context: _innoDITrace,
            containerType: Self.self
        )
        self._innoDITraceOwner_logger = _innoDITraceOwner
        self._innoDITraceOwner_service = _innoDITraceOwner
        self._storage_config = config
        if let _innoDIOverride = logger {
            self._storage_logger = _innoDITraceOwner.overridden(
                member: "logger",
                value: _innoDIOverride
            )
        } else {
            let _innoDITraceSpan_logger = _innoDITraceOwner.start(
                member: "logger"
            )
            let _innoDIResolved_logger = Logger()
            _innoDITraceOwner.finish(.success, span: _innoDITraceSpan_logger)
            self._storage_logger = _innoDIResolved_logger
        }
        let _innoDITraceSpan_service = _innoDITraceOwner.start(
            member: "service"
        )
        let _innoDITask_service: _Concurrency.Task<Service, Swift.Never> = .init {
            if let override = service {
                return _innoDITraceOwner.overridden(
                    member: "service",
                    value: override,
                    span: _innoDITraceSpan_service
                )
            }
            return await _innoDITraceOwner.withResolution(
                span: _innoDITraceSpan_service
            ) {
                await { () async in
                    Service()
                }()
            }
        }
        self._storage_task_service = _innoDITask_service
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var logger: Logger? = nil
        var service: Service? = nil
    }

    typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    init(config: Config, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(config: config, logger: _innoDIOverrides.logger, service: _innoDIOverrides.service, _innoDITrace: _innoDITrace)
    }

    // MARK: - withOverrides
    static func withOverrides<OperationResult>(config: Config, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) -> OperationResult) -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (throws)
    static func withOverrides<OperationResult>(config: Config, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) throws -> OperationResult) throws -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return try _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async)
    nonisolated(nonsending) static func withOverrides<OperationResult>(config: Config, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async throws)
    nonisolated(nonsending) static func withOverrides<OperationResult>(config: Config, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDITrace: _innoDITrace, _innoDIApplyOverrides)
        return try await _innoDIOperation(_innoDIContainer)
    }
}