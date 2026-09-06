
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var config: Config
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var request: Request
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var logger: RequestLogger

    // MARK: - Initialization
    init(config: Config, logger: RequestLogger? = nil, request: Request? = nil, _innoDITrace: DITraceContext = .disabled) {
        final class _InnoDIDeferredCell<T>: @unchecked Swift.Sendable {
            private var value: T?
            private var resolver: (() -> T)?

            func storeValue(_ value: T) {
                self.value = value
            }

            func bindResolver(_ resolver: @escaping () -> T) {
                self.resolver = resolver
            }

            func resolve() -> T {
                guard let value else {
                    if let resolver {
                        return resolver()
                    }
                    return InnoDI._innoDITrap("InnoDI codegen invariant violated: deferred dependency resolved before initialization completed.")
                }
                return value
            }
        }
        let _innoDITraceOwner = _InnoDITraceOwner(
            context: _innoDITrace,
            containerType: Self.self
        )
        self._innoDITraceOwner_logger = _innoDITraceOwner
        self._innoDITraceOwner_request = _innoDITraceOwner
        let _innoDILazyCell_request = _InnoDIDeferredCell<Request>()
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
            let _innoDIResolved_logger = { (request: InnoDI.Provider<Request>) in
                RequestLogger(requests: request)
            }(.init {
                    _innoDILazyCell_request.resolve()
                })
            _innoDITraceOwner.finish(.success, span: _innoDITraceSpan_logger)
            self._storage_logger = _innoDIResolved_logger
        }
        self._override_request = request
        _innoDILazyCell_request.bindResolver {
            request ?? { (config: Config) in
                    Request(config: config)
                }(config)
        }
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var logger: RequestLogger? = nil
        var request: Request? = nil
    }

    typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    init(config: Config, _innoDITrace: DITraceContext = .disabled, _ _innoDIApplyOverrides: (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(config: config, logger: _innoDIOverrides.logger, request: _innoDIOverrides.request, _innoDITrace: _innoDITrace)
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