
struct AppContainer {
    var config: Config {
        get {
            return _storage_config
        }
    }

    private let _storage_config: Config
    var request: Request {
        get {
            if let override = _override_request {
                return override
            }
            return { (config: Config) in
                    Request(config: config)
                }(self.config)
        }
    }

    private let _override_request: Request?
    var logger: RequestLogger {
        get {
            return _storage_logger
        }
    }

    private let _storage_logger: RequestLogger

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
    static func withOverrides<T>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> T) -> T {
        let container = Self(config: config, applyOverrides)
        return operation(container)
    }

    // MARK: withOverrides (throws)
    static func withOverrides<T>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> T) throws -> T {
        let container = Self(config: config, applyOverrides)
        return try operation(container)
    }

    // MARK: withOverrides (async)
    static func withOverrides<T>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> T) async -> T {
        let container = Self(config: config, applyOverrides)
        return await operation(container)
    }

    // MARK: withOverrides (async throws)
    static func withOverrides<T>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> T) async throws -> T {
        let container = Self(config: config, applyOverrides)
        return try await operation(container)
    }
}