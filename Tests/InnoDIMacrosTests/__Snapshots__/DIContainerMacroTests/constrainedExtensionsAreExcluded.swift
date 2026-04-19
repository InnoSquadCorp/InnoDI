
struct AppContainer<T> {
    var config: Config {
        get {
            return _storage_config
        }
    }

    private let _storage_config: Config

    init(config: Config) {
        self._storage_config = config
    }
}

extension AppContainer where T: Sendable {
    init(config: Config, debug: Bool) {
        self.init(config: config)
    }
}