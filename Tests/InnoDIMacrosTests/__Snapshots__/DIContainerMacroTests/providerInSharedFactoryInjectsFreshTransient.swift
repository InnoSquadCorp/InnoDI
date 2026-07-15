
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var config: Config
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var request: Request
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var logger: RequestLogger

    // MARK: - Initialization
    init(config: Config, logger: RequestLogger? = nil, request: Request? = nil) {
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
        let _innoDILazyCell_request = _InnoDIDeferredCell<Request>()
        self._storage_config = config
        self._storage_logger = logger ?? { (request: Provider<Request>) in
                RequestLogger(requests: request)
            }(.init {
                _innoDILazyCell_request.resolve()
            })
        self._override_request = request
        let _innoDILazySelf = self
        _innoDILazyCell_request.bindResolver {
            _innoDILazySelf.request
        }
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var logger: RequestLogger? = nil
        var request: Request? = nil
    }

    typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    init(config: Config, _ _innoDIApplyOverrides: (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(config: config, logger: _innoDIOverrides.logger, request: _innoDIOverrides.request)
    }

    // MARK: - withOverrides
    static func withOverrides<OperationResult>(config: Config, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) -> OperationResult) -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (throws)
    static func withOverrides<OperationResult>(config: Config, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) throws -> OperationResult) throws -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return try _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async)
    nonisolated(nonsending) static func withOverrides<OperationResult>(config: Config, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async throws)
    nonisolated(nonsending) static func withOverrides<OperationResult>(config: Config, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return try await _innoDIOperation(_innoDIContainer)
    }
}