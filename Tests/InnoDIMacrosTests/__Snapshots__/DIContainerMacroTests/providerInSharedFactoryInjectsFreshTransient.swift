
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

    init(config: Config, logger: RequestLogger? = nil, request: Request? = nil) {
        let _lazyCell_request = _LazyCell<Request>()
        self._storage_config = config
        self._storage_logger = logger ?? { (request: Provider<Request>) in
                RequestLogger(requests: request)
            }(Provider {
                _lazyCell_request.resolve()
            })
        self._override_request = request
        let _lazySelf = self
        _lazyCell_request.bindResolver {
            _lazySelf.request
        }
    }

    struct Overrides {
        var logger: RequestLogger? = nil
        var request: Request? = nil
    }

    init(config: Config, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(config: config, logger: overrides.logger, request: overrides.request)
    }

    static func withOverrides<T>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> T) -> T {
        let container = Self(config: config, applyOverrides)
        return operation(container)
    }

    static func withOverrides<T>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> T) throws -> T {
        let container = Self(config: config, applyOverrides)
        return try operation(container)
    }

    static func withOverrides<T>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> T) async -> T {
        let container = Self(config: config, applyOverrides)
        return await operation(container)
    }

    static func withOverrides<T>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> T) async throws -> T {
        let container = Self(config: config, applyOverrides)
        return try await operation(container)
    }
}