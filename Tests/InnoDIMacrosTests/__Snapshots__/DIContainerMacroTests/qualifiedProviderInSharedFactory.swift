
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var config: Config

    private var _storage_config: Config? = nil
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var request: Request

    private var _override_request: Request? = nil
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var logger: RequestLogger

    private var _storage_logger: RequestLogger? = nil

    // MARK: - Initialization
    init(config: Config, logger: RequestLogger? = nil, request: Request? = nil) {
        final class _InnoDIDeferredCell<T>: @unchecked Sendable {
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
                    preconditionFailure("InnoDI codegen invariant violated: deferred dependency resolved before initialization completed.")
                }
                return value
            }
        }
        let _lazyCell_request = _InnoDIDeferredCell<Request>()
        self._storage_config = config
        self._storage_logger = logger ?? { (request: InnoDI.Provider<Request>) in
                RequestLogger(requests: request)
            }(InnoDI.Provider {
                _lazyCell_request.resolve()
            })
        self._override_request = request
        let _lazySelf = self
        _lazyCell_request.bindResolver {
            _lazySelf.request
        }
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var logger: RequestLogger? = nil
        var request: Request? = nil
    }

    // MARK: - Convenience Init with Overrides
    init(config: Config, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(config: config, logger: overrides.logger, request: overrides.request)
    }

    // MARK: - withOverrides
    static func withOverrides<OperationResult>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> OperationResult) -> OperationResult {
        let container = Self(config: config, applyOverrides)
        return operation(container)
    }

    // MARK: - withOverrides (throws)
    static func withOverrides<OperationResult>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> OperationResult) throws -> OperationResult {
        let container = Self(config: config, applyOverrides)
        return try operation(container)
    }

    // MARK: - withOverrides (async)
    nonisolated(nonsending) static func withOverrides<OperationResult>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
        let container = Self(config: config, applyOverrides)
        return await operation(container)
    }

    // MARK: - withOverrides (async throws)
    nonisolated(nonsending) static func withOverrides<OperationResult>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
        let container = Self(config: config, applyOverrides)
        return try await operation(container)
    }
}