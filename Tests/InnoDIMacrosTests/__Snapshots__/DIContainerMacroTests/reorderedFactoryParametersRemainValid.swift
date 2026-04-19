
struct AppContainer {
    var config: Config {
        get {
            return _storage_config
        }
    }

    private let _storage_config: Config
    var logger: Logger {
        get {
            return _storage_logger
        }
    }

    private let _storage_logger: Logger
    var service: Service {
        get {
            return _storage_service
        }
    }

    private let _storage_service: Service

    init(config: Config, logger: Logger, service: Service? = nil) {
        self._storage_config = config
        self._storage_logger = logger
        self._storage_service = service ?? { (logger: Logger, config: Config) in
                Service(config: config, logger: logger)
            }(self._storage_logger, self._storage_config)
    }
}